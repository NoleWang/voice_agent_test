import os
import asyncio
import logging
from typing import Optional, Any
from dotenv import load_dotenv

from livekit.agents import Agent, AgentSession, JobContext, WorkerOptions, cli, RoomInputOptions
from livekit.plugins.aws import stt as aws_stt, tts as aws_tts
from livekit.plugins import aws, silero, noise_cancellation
from livekit import api
import contextlib

load_dotenv(override=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
log = logging.getLogger("echo-agent")


class EchoAgent(Agent):
    def __init__(self) -> None:
        super().__init__(instructions="A simple voice agent that echoes the user.")


def require_env(var: str) -> str:
    val = os.getenv(var, "").strip()
    if not val:
        raise RuntimeError(f"Missing required environment variable: {var}")
    return val


def extract_text(evt: Any) -> str:
    """
    Defensive text extraction across payload shapes:
    - str
    - dicts with 'user_transcript'/'text'/...
    - objects with those attributes
    - STT alternatives arrays
    """
    try:
        # 1) plain string
        if isinstance(evt, str):
            return evt.strip()

        # 2) dict payloads (most LiveKit 'user_transcript' messages)
        if isinstance(evt, dict):
            for key in ("user_transcript", "text", "value", "message"):
                v = evt.get(key)
                if isinstance(v, str) and v.strip():
                    return " ".join(v.split())
            alts = evt.get("alternatives")
            if isinstance(alts, (list, tuple)) and alts:
                first = alts[0]
                if isinstance(first, dict):
                    for k in ("transcript", "text"):
                        t = first.get(k)
                        if isinstance(t, str) and t.strip():
                            return " ".join(t.split())
            return ""

        # 3) object-like payloads
        for key in ("user_transcript", "text", "value", "message"):
            v = getattr(evt, key, None)
            if isinstance(v, str) and v.strip():
                return " ".join(v.split())

        # 4) alternatives attr (e.g., Transcribe)
        alts = getattr(evt, "alternatives", None)
        if isinstance(alts, (list, tuple)) and alts:
            first = alts[0]
            if isinstance(first, dict):
                for k in ("transcript", "text"):
                    t = first.get(k)
                    if isinstance(t, str) and t.strip():
                        return " ".join(t.split())
    except Exception as e:
        log.warning("extract_text error: %r", e)

    return ""


def is_final_like(evt: Any) -> bool:
    """Treat as final when flag is absent."""
    v = evt.get("is_final") if isinstance(evt, dict) else getattr(evt, "is_final", None)
    return True if v is None else bool(v)


class TTSSerialQueue:
    """Serialize session.say() to avoid overlapping speech. Idempotent start/stop."""
    def __init__(self, session: AgentSession):
        self._session = session
        self._q: asyncio.Queue[Optional[str]] = asyncio.Queue()
        self._worker_task: Optional[asyncio.Task] = None
        self._stopped: bool = False

    async def start(self):
        if self._worker_task and not self._worker_task.done():
            return  # already started

        async def _worker():
            try:
                while True:
                    text = await self._q.get()
                    if text is None:
                        break
                    try:
                        await self._session.say(text, allow_interruptions=True)
                    finally:
                        self._q.task_done()
            finally:
                # ensure no pending task_done remains
                while not self._q.empty():
                    self._q.get_nowait()
                    self._q.task_done()

        self._worker_task = asyncio.create_task(_worker())

    async def say(self, text: str):
        if self._stopped:
            return
        if text:
            await self._q.put(text)

    async def stop(self):
        if self._stopped:
            return
        self._stopped = True
        if self._worker_task is None:
            return
        await self._q.put(None)
        try:
            await self._worker_task
        except asyncio.CancelledError:
            self._worker_task.cancel()
            with contextlib.suppress(Exception):
                await self._worker_task


# ---------- Entrypoint ----------
async def entrypoint(ctx: JobContext):
    # Connect early
    await ctx.connect()
    log.info("Connected. Room=%s", ctx.room)

    # AWS regions/creds
    os.environ.setdefault("AWS_REGION", os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "us-east-1")
    require_env("AWS_REGION")

    if not (os.getenv("AWS_ACCESS_KEY_ID") and os.getenv("AWS_SECRET_ACCESS_KEY")):
        log.info("Using AWS default credential chain (no explicit ACCESS_KEY/SECRET set).")

    # Stack: STT (Transcribe) + LLM (Qwen3 via Bedrock plugin) + TTS (Polly)
    stt = aws_stt.STT(language=os.getenv("STT_LANG", "en-US"), region=os.getenv("AWS_REGION"))
    tts = aws_tts.TTS(voice=os.getenv("POLLY_VOICE", "Joanna"), region=os.getenv("AWS_REGION"))
    llm = aws.LLM(model=os.getenv("LLM_MODEL", "qwen.qwen3-coder-30b-a3b-v1:0"), region=os.getenv("AWS_REGION"))

    # VAD + optional noise cancellation
    vad = silero.VAD.load()
    try:
        room_input_opts = RoomInputOptions(noise_cancellation=noise_cancellation.BVC())
    except Exception as e:
        log.warning("Noise cancellation unavailable, proceeding without it: %r", e)
        room_input_opts = RoomInputOptions()

    session = AgentSession(stt=stt, llm=llm, tts=tts, vad=vad)
    agent = EchoAgent()

    # TTS queue
    tts_queue = TTSSerialQueue(session)
    await tts_queue.start()

    last_final = {"text": ""}

    async def handle_transcript(evt: Any):
        if not is_final_like(evt):
            return
        user_text = extract_text(evt)
        if not user_text or user_text == last_final["text"]:
            return
        last_final["text"] = user_text
        try:
            reply = await session.llm.chat([
                {"role": "system", "content": "You are a concise, helpful voice assistant."},
                {"role": "user", "content": user_text},
            ])
            bot_text = reply.get("content") if isinstance(reply, dict) else str(reply)
        except Exception as e:
            log.warning("LLM error, falling back to echo: %r", e)
            bot_text = f"I heard: {user_text}"
        await tts_queue.say(bot_text)

    # Bind transcript events
    session.on("user_transcript", lambda evt: asyncio.create_task(handle_transcript(evt)))
    session.on("transcript",       lambda evt: asyncio.create_task(handle_transcript(evt)))
    session.on("stt_text",         lambda evt: asyncio.create_task(handle_transcript(evt)))

    # Start media/session
    await session.start(agent=agent, room=ctx.room, room_input_options=room_input_opts)
    log.info("Session started: %s", ctx.room)
    await tts_queue.say("Hello, I have joined the room. Please start speaking.")

    # -------- Graceful shutdown logic --------
    stop_event = asyncio.Event()

    def request_stop(*_):
        if not stop_event.is_set():
            stop_event.set()

    # Optional: squelch benign cancel-during-shutdown logs from amazon_transcribe
    def _asyncio_squelch(loop, ctx_):
        exc = ctx_.get("exception")
        msg = str(ctx_.get("message") or "")
        if ("amazon_transcribe" in msg) or (exc and "amazon_transcribe" in repr(exc)):
            return
        loop.default_exception_handler(ctx_)

    loop = asyncio.get_running_loop()
    loop.set_exception_handler(_asyncio_squelch)

    # Signals
    try:
        import signal
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(sig, request_stop)
            except Exception:
                pass
    except Exception:
        pass

    # End call from UI -> room disconnect -> request_stop
    session.on("room_disconnected", lambda *_: request_stop())

    try:
        await stop_event.wait()
    finally:
        # 1) Stop TTS worker
        await tts_queue.stop()

        # 2) Stop STT explicitly before closing media (prevents callbacks into cancelled futures)
        stt_impl = getattr(session, "stt", None)
        stop_stt = getattr(stt_impl, "stop", None) or getattr(stt_impl, "aclose", None)
        if callable(stop_stt):
            with contextlib.suppress(Exception):
                await stop_stt()

        # 3) Close media session
        with contextlib.suppress(Exception):
            await session.aclose()

        # 4) End only this agent or the whole room
        if os.getenv("END_ROOM", "0") != "1":
            await ctx.shutdown(reason="Session ended")
        else:
            lk = api.LiveKitAPI(
                os.getenv("LIVEKIT_URL"),
                os.getenv("LIVEKIT_API_KEY"),
                os.getenv("LIVEKIT_API_SECRET"),
            )
            await lk.room.delete_room(api.DeleteRoomRequest(room=ctx.job.room.name))
            # Room ended for everyone; no ctx.shutdown() needed.


if __name__ == "__main__":
    cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint))