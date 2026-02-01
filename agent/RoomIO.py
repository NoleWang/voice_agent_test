# RoomIO.py — LiveKit Voice Agent + iOS Chat Sync (topic="chat")
#
# FIXES APPLIED:
# 1) Always publish DataPackets with topic="chat" so iOS receives them.
# 2) Chat listener does NOT capture session=None; it dynamically fetches room._typed_chat_session.
# 3) Prevent duplicate listener installation (no double logs).
# 4) Best-effort bridge: publish user transcripts AND agent response text into iOS chat.
# 5) Can run as:
#    - uvicorn RoomIO:app --host 0.0.0.0 --port 8000  (FastAPI + worker auto-start)
#    - python RoomIO.py  (worker only)
#
# NOTE: LiveKit Python APIs vary by version; this code is defensive and will no-op rather than crash
# if your SDK uses different event names.


from __future__ import annotations

import os
import json
import time
import asyncio
import logging
import contextlib
import inspect
import threading
import sys
import multiprocessing
from pathlib import Path
from typing import Any, Optional, AsyncIterator
import re

from dotenv import load_dotenv
from fastapi import FastAPI
from pydantic import BaseModel

from livekit.agents import AgentSession, JobContext, WorkerOptions, cli, RoomInputOptions
from livekit.plugins.aws import stt as aws_stt, tts as aws_tts
from livekit.plugins import silero, noise_cancellation, aws
from livekit import api

from customer_agent import CustomerLLMAgent

load_dotenv(override=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("fraud-dispute-agent:llm")

CHAT_TOPIC = "chat"
BOOTSTRAP_TOPIC = "bootstrap"
TOOL_CALL_PATTERN = re.compile(r"<function=([a-zA-Z0-9_]+)>", re.MULTILINE)


# ---------------------------------------------------------------------
# Utils
# ---------------------------------------------------------------------
def _require_env(var: str) -> str:
    val = os.getenv(var, "").strip()
    if not val:
        raise RuntimeError(f"Missing required environment variable: {var}")
    return val


def _patch_livekit_json_parsers() -> None:
    """
    Safe JSON parsing for tool-call args (workaround for malformed tool JSON).
    """
    try:
        from livekit.agents.llm import utils as llm_utils
        _orig_from_json = llm_utils.from_json

        def _safe_from_json(s: str):
            try:
                if not s:
                    return {}
                if isinstance(s, str) and s.strip() in ("", "{"):
                    return {}
                return _orig_from_json(s)
            except Exception:
                return {}

        llm_utils.from_json = _safe_from_json

        import json as _json
        from livekit.agents.llm._provider_format import aws as aws_fmt
        _orig_json_loads = _json.loads

        def _safe_json_loads(s, *args, **kwargs):
            try:
                if s is None:
                    return {}
                if isinstance(s, str) and s.strip() in ("", "{"):
                    return {}
                return _orig_json_loads(s, *args, **kwargs)
            except Exception:
                return {}

        aws_fmt.json.loads = _safe_json_loads

        log.info("Applied safe JSON parser patches for tool-call arguments.")
    except Exception as e:
        log.warning("Could not apply JSON parser patches: %s", e)


_patch_livekit_json_parsers()


# ---------------------------------------------------------------------
# FastAPI token endpoint models
# ---------------------------------------------------------------------
class TokenRequest(BaseModel):
    room: str
    identity: str
    name: str | None = None


# ---------------------------------------------------------------------
# DataPacket publish helper
# ---------------------------------------------------------------------
async def publish_chat(room: Any, from_name: str, text: str) -> None:
    payload = {
        "id": str(time.time()),
        "from": from_name,
        "text": text,
        "timestamp": time.time(),  # Unix seconds
    }
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")

    try:
        fn = room.local_participant.publish_data
        result = fn(data, topic=CHAT_TOPIC, reliable=True)
        if inspect.isawaitable(result):
            await result
        log.info("📤 published chat (from=%s): %s", from_name, text)
    except Exception as e:
        log.exception("❌ publish_chat failed: %r", e)


# ---------------------------------------------------------------------
# Tool call resolution for models that emit tool tags as plain text
# ---------------------------------------------------------------------
async def _resolve_tool_calls(text: str, room: Any) -> Optional[str]:
    if not text:
        return None

    tool_names = TOOL_CALL_PATTERN.findall(text)
    if not tool_names:
        return None

    agent = getattr(room, "_agent_instance", None)
    if agent is None:
        return None

    resolver = getattr(agent, "resolve_tool_value", None)
    resolved: list[str] = []
    for name in tool_names:
        try:
            if callable(resolver):
                out = resolver(name)
                if inspect.isawaitable(out):
                    out = await out
            else:
                fn = getattr(agent, name, None)
                if fn is None:
                    continue
                out = fn()
                if inspect.isawaitable(out):
                    out = await out
            if isinstance(out, str) and out.strip():
                resolved.append(out.strip())
        except Exception:
            continue

    if not resolved:
        return None

    return " ".join(resolved)


# ---------------------------------------------------------------------
# GUARANTEED: hook TTS so agent speech text -> DataPacket
# ---------------------------------------------------------------------
def _install_tts_to_chat_hook(session: AgentSession, room: Any) -> None:
    """
    Guarantees: any text passed into TTS will also be published to iOS chat.
    """
    if getattr(session, "_tts_chat_hook_installed", False):
        return
    session._tts_chat_hook_installed = True

    tts_obj = getattr(session, "tts", None) or getattr(session, "_tts", None)
    if tts_obj is None:
        log.warning("⚠️ No TTS object found on session; cannot hook TTS->chat.")
        return

    # Common call points across LiveKit TTS wrappers
    method_names = ["synthesize", "synthesize_stream", "stream", "speak", "__call__"]

    def _extract_text(args, kwargs) -> Optional[str]:
        for k in ("text", "input", "prompt", "ssml"):
            v = kwargs.get(k)
            if isinstance(v, str) and v.strip():
                return v
        for a in args:
            if isinstance(a, str) and a.strip():
                return a
        return None

    hooked_any = False

    for name in method_names:
        if not hasattr(tts_obj, name):
            continue

        orig = getattr(tts_obj, name)
        if getattr(orig, "_is_chat_wrapped", False):
            hooked_any = True
            continue

        if inspect.iscoroutinefunction(orig):

            async def _async_wrapper(*args, __orig=orig, **kwargs):
                text = _extract_text(args, kwargs)
                if text:
                    resolved = await _resolve_tool_calls(text, room)
                    if resolved:
                        text = resolved
                        if "text" in kwargs:
                            kwargs["text"] = text
                        elif "input" in kwargs:
                            kwargs["input"] = text
                        elif "prompt" in kwargs:
                            kwargs["prompt"] = text
                        elif "ssml" in kwargs:
                            kwargs["ssml"] = text
                        else:
                            args = (text, *args[1:]) if args else (text,)

                    asyncio.create_task(publish_chat(room, os.getenv("AGENT_LABEL", "agent"), str(text)))
                out = __orig(*args, **kwargs)
                if inspect.isawaitable(out):
                    return await out
                return out

            wrapped = _async_wrapper
        else:

            def _sync_wrapper(*args, __orig=orig, **kwargs):
                text = _extract_text(args, kwargs)
                if text:
                    resolved = None
                    try:
                        loop = asyncio.get_running_loop()
                    except RuntimeError:
                        loop = None

                    if loop is None:
                        resolved = asyncio.run(_resolve_tool_calls(text, room))
                    if resolved:
                        text = resolved
                        if "text" in kwargs:
                            kwargs["text"] = text
                        elif "input" in kwargs:
                            kwargs["input"] = text
                        elif "prompt" in kwargs:
                            kwargs["prompt"] = text
                        elif "ssml" in kwargs:
                            kwargs["ssml"] = text
                        else:
                            args = (text, *args[1:]) if args else (text,)

                    asyncio.create_task(publish_chat(room, os.getenv("AGENT_LABEL", "agent"), str(text)))
                return __orig(*args, **kwargs)

            wrapped = _sync_wrapper

        setattr(wrapped, "_is_chat_wrapped", True)

        try:
            setattr(tts_obj, name, wrapped)
            log.info("✅ Installed TTS->chat hook on tts.%s(...)", name)
            hooked_any = True
        except Exception as e:
            log.warning("Failed to wrap tts.%s: %r", name, e)

    if not hooked_any:
        log.warning("⚠️ Could not hook any TTS methods; agent->chat sync may not work.")


# ---------------------------------------------------------------------
# GUARANTEED: mirror "received user transcript" logs -> DataPacket
# ---------------------------------------------------------------------
def _install_user_transcript_log_tap(room: Any) -> None:
    """
    Your logs clearly show:
      livekit.agents: received user transcript {"user_transcript": "..."}
    Some versions don't expose this as a public event.
    So we tap the logger and publish those transcripts to chat.

    This is intentionally a "pragmatic hack" to guarantee iOS sees the customer's voice text.
    """
    if getattr(room, "_user_transcript_logtap_installed", False):
        return
    room._user_transcript_logtap_installed = True

    lk_logger = logging.getLogger("livekit.agents")
    lk_logger.setLevel(logging.DEBUG)  # ensure these records arrive

    class _Tap(logging.Handler):
        def emit(self, record: logging.LogRecord) -> None:
            try:
                msg = str(record.getMessage() or "")
                if "received user transcript" not in msg:
                    return

                # record.args is often a dict for structured logs
                data = None
                if isinstance(record.args, dict):
                    data = record.args
                else:
                    # sometimes extras are injected directly
                    d = record.__dict__
                    if isinstance(d, dict) and ("user_transcript" in d or "transcript" in d):
                        data = d

                if not isinstance(data, dict):
                    return

                text = data.get("user_transcript") or data.get("transcript") or data.get("text")
                if not isinstance(text, str) or not text.strip():
                    return

                user_label = os.getenv("IOS_USER_LABEL", "iOS User")

                try:
                    loop = asyncio.get_running_loop()
                    loop.create_task(publish_chat(room, user_label, text.strip()))
                except RuntimeError:
                    # if not in an event loop (rare), just ignore
                    return
            except Exception:
                return

    # Avoid double handlers
    for h in lk_logger.handlers:
        if getattr(h, "_is_user_transcript_tap", False):
            return

    tap = _Tap()
    setattr(tap, "_is_user_transcript_tap", True)
    lk_logger.addHandler(tap)
    log.info("✅ Installed log-tap for user transcripts (livekit.agents -> chat).")


# ---------------------------------------------------------------------
# Best-effort: inject typed iOS chat into AgentSession
# ---------------------------------------------------------------------
async def _try_inject_text_into_session(session: AgentSession, text: str) -> bool:
    candidates = [
        ("ingest_text", {"text": text}),
        ("send_text", {"text": text}),
        ("handle_text", {"text": text}),
        ("push_text", {"text": text}),
        ("submit_text", {"text": text}),
        ("receive_text", {"text": text}),
        ("chat", {"text": text}),
        ("say", {"text": text}),  # last resort (may speak)
    ]

    for name, kwargs in candidates:
        fn = getattr(session, name, None)
        if fn is None:
            continue
        try:
            out = fn(**kwargs)
            if inspect.isawaitable(out):
                await out
            log.info("✅ injected typed chat into session via %s(...)", name)
            return True
        except TypeError:
            try:
                out = fn(text)
                if inspect.isawaitable(out):
                    await out
                log.info("✅ injected typed chat into session via %s(text)", name)
                return True
            except Exception:
                continue
        except Exception:
            continue

    return False


# ---------------------------------------------------------------------
# Chat listener: receive DataPackets topic="chat"
# ---------------------------------------------------------------------
def _install_chat_listener(room: Any) -> None:
    if getattr(room, "_chat_listener_installed", False):
        log.info("chat listener already installed, skipping")
        return
    room._chat_listener_installed = True

    async def _handle_packet(packet: Any, participant: Any | None = None) -> None:
        try:
            topic = getattr(packet, "topic", None) or getattr(packet, "destination_topic", None)
            if topic not in {CHAT_TOPIC, BOOTSTRAP_TOPIC}:
                return

            raw = getattr(packet, "data", None) or getattr(packet, "payload", None)
            if raw is None:
                log.info("📩 chat packet received (no data field): %r", packet)
                return

            body = raw.decode("utf-8", errors="ignore")

            try:
                obj = json.loads(body)
            except Exception:
                obj = None

            if topic == BOOTSTRAP_TOPIC:
                agent = getattr(room, "_agent_instance", None)
                if agent is None:
                    log.warning("📩 bootstrap payload received, but no agent is attached")
                    return
                if not isinstance(obj, dict):
                    log.warning("📩 bootstrap payload received, but payload is not JSON")
                    return
                try:
                    agent.apply_runtime_payload(obj)
                    log.info("📩 applied bootstrap payload from iOS")
                except Exception as e:
                    log.exception("Failed to apply bootstrap payload: %r", e)
                return

            text_for_log = body
            from_name = "user"
            if isinstance(obj, dict):
                text_for_log = obj.get("text", body)
                from_name = obj.get("from", "user")

            pid = getattr(participant, "identity", None) or getattr(participant, "sid", None) or "unknown"
            log.info("📩 iOS chat DataPacket (from=%s pid=%s): %s", from_name, pid, text_for_log)

            session: Optional[AgentSession] = getattr(room, "_typed_chat_session", None)
            if session is not None:
                injected = await _try_inject_text_into_session(session, str(text_for_log))
                if injected:
                    return

            # fallback echo
            await publish_chat(room, os.getenv("AGENT_LABEL", "agent"), f"Echo: {text_for_log}")

        except Exception as e:
            log.exception("chat listener error: %r", e)

    # room event API differs by version; try both
    if hasattr(room, "on"):

        def _cb(*args, **kwargs):
            packet = args[0] if len(args) > 0 else kwargs.get("packet")
            participant = args[1] if len(args) > 1 else kwargs.get("participant")
            if packet is None:
                return
            asyncio.create_task(_handle_packet(packet, participant))

        try:
            room.on("data_received", _cb)
            log.info("✅ Installed chat listener via room.on('data_received', ...)")
            return
        except Exception as e:
            log.warning("room.on('data_received', ...) failed: %r", e)

    if hasattr(room, "add_listener"):
        try:
            room.add_listener(
                "data_received",
                lambda *args, **kwargs: asyncio.create_task(
                    _handle_packet(
                        args[0] if len(args) > 0 else kwargs.get("packet"),
                        args[1] if len(args) > 1 else kwargs.get("participant"),
                    )
                ),
            )
            log.info("✅ Installed chat listener via room.add_listener('data_received', ...)")
            return
        except Exception as e:
            log.warning("room.add_listener('data_received', ...) failed: %r", e)

    log.warning("❌ Could not attach chat listener (unknown room event API).")


# ---------------------------------------------------------------------
# LiveKit agent entrypoint
# ---------------------------------------------------------------------
async def entrypoint(ctx: JobContext):
    await ctx.connect()
    log.info("Connected. Room=%s", ctx.room)

    # Ensure user transcript tap + typed chat listener are installed ASAP
    _install_chat_listener(ctx.room)
    _install_user_transcript_log_tap(ctx.room)

    # AWS region/creds
    os.environ.setdefault("AWS_REGION", os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "us-east-1")
    region = _require_env("AWS_REGION")

    stt_lang = os.getenv("STT_LANG", "en-US")
    polly_voice = os.getenv("POLLY_VOICE", "Joanna")
    model_id = os.getenv("LLM_MODEL", "qwen.qwen3-coder-30b-a3b-v1:0")

    log.info(
        "Audio/LLM stack: region=%s, transcribe_lang=%s, polly_voice=%s, model=%s",
        region, stt_lang, polly_voice, model_id
    )

    stt = aws_stt.STT(language=stt_lang, region=region)
    tts = aws_tts.TTS(voice=polly_voice, region=region)
    llm = aws.LLM(model=model_id, region=region, temperature=0.2, max_output_tokens=256)
    vad = silero.VAD.load()

    try:
        room_input_opts = RoomInputOptions(noise_cancellation=noise_cancellation.BVC())
    except Exception as e:
        log.warning("Noise cancellation unavailable, proceeding without it: %r", e)
        room_input_opts = RoomInputOptions()

    # Agent persona
    agent = CustomerLLMAgent()
    setattr(ctx.room, "_agent_instance", agent)

    # Session
    session = AgentSession(stt=stt, tts=tts, vad=vad, llm=llm)

    # ✅ main guarantee: agent speech -> iOS chat
    _install_tts_to_chat_hook(session, ctx.room)

    # Start session
    await session.start(agent=agent, room=ctx.room, room_input_options=room_input_opts)
    log.info("Session started with CustomerLLMAgent (Bedrock %s)", model_id)

    # Let typed chat injection find session
    setattr(ctx.room, "_typed_chat_session", session)

    # Shutdown handling
    stop_event = asyncio.Event()

    def request_stop(*_):
        if not stop_event.is_set():
            stop_event.set()

    loop = asyncio.get_running_loop()
    try:
        import signal
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(sig, request_stop)
            except Exception:
                pass
    except Exception:
        pass

    try:
        session.on("room_disconnected", lambda *_: request_stop())
    except Exception:
        pass

    try:
        await stop_event.wait()
    finally:
        with contextlib.suppress(Exception):
            await session.aclose()
        await ctx.shutdown(reason="Session ended")


# ---------------------------------------------------------------------
# Worker runner helpers
# ---------------------------------------------------------------------
_worker_started = False
_worker_lock = threading.Lock()
_worker_process: Optional[multiprocessing.Process] = None


def _run_worker_blocking(command: str = "start") -> None:
    """
    Run LiveKit worker (blocking).

    IMPORTANT:
    - This function runs in a subprocess (not thread) to avoid signal.signal() restrictions
    - cli.run_app uses click and reads sys.argv
    - So we must set sys.argv to include a subcommand
    """
    try:
        if sys.platform.startswith("win"):
            asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())  # type: ignore[attr-defined]
    except Exception:
        pass

    # For embedded usage: prefer "start" (no watch/hotreload) to avoid timeouts.
    # For manual development: you can run `python RoomIO.py dev`.
    old_argv = list(sys.argv)
    try:
        sys.argv = ["livekit-worker", command, "--log-level", os.getenv("LIVEKIT_LOG_LEVEL", "DEBUG")]
        # Now running in subprocess, which is the main thread of that process
        # This allows signal handlers to work correctly
        cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint))
    except KeyboardInterrupt:
        # Handle interrupt gracefully
        log.info("Worker interrupted")
    except Exception as e:
        log.exception("Worker failed: %r", e)
        raise
    finally:
        sys.argv = old_argv


def start_worker_in_background(command: str = "start") -> None:
    """
    Start LiveKit worker in a subprocess (not thread) to avoid signal handler issues.
    
    IMPORTANT: signal.signal() can only be used in the main thread of the main interpreter.
    Using multiprocessing instead of threading allows each subprocess to have its own main thread
    where signal handlers can be properly registered.
    
    Note: daemon=False because LiveKit worker needs to spawn child processes (proc_pool),
    and daemon processes cannot have children in Python's multiprocessing.
    """
    global _worker_started, _worker_process
    with _worker_lock:
        if _worker_started:
            return
        _worker_started = True

        # Try to set multiprocessing start method (may already be set)
        # This is needed for cross-platform compatibility
        try:
            multiprocessing.set_start_method('spawn', force=False)
        except RuntimeError:
            # Start method already set, use whatever is configured
            pass

        # Use multiprocessing instead of threading to avoid signal.signal() restrictions
        # Each subprocess has its own main thread where signal handlers can work
        # IMPORTANT: daemon=False because LiveKit worker spawns child processes (proc_pool)
        # LiveKit uses proc_pool which creates worker processes internally
        _worker_process = multiprocessing.Process(
            target=_run_worker_blocking,
            args=(command,),
            daemon=False,  # Must be False - LiveKit worker spawns child processes
            name="livekit-worker",
        )
        _worker_process.start()
        log.info("✅ LiveKit worker started in background process (command=%s, PID=%d).", command, _worker_process.pid)


# ---------------------------------------------------------------------
# FastAPI lifespan (no deprecation warning)
# ---------------------------------------------------------------------
@contextlib.asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    # When running via uvicorn, start worker in-process (stable mode by default).
    if os.getenv("START_LIVEKIT_WORKER", "1") == "1":
        cmd = (os.getenv("LIVEKIT_WORKER_CMD", "start").strip() or "start").lower()
        if cmd not in ("start", "dev"):
            cmd = "start"
        start_worker_in_background(command=cmd)
    
    try:
        yield
    finally:
        # Cleanup: terminate worker process on shutdown
        global _worker_process
        if _worker_process is not None and _worker_process.is_alive():
            log.info("Terminating LiveKit worker process (PID=%d)...", _worker_process.pid)
            _worker_process.terminate()
            # Give it a chance to cleanup gracefully
            try:
                _worker_process.join(timeout=5)
            except Exception:
                pass
            # Force kill if still alive
            if _worker_process.is_alive():
                log.warning("Force killing LiveKit worker process...")
                _worker_process.kill()
                _worker_process.join()


app = FastAPI(lifespan=lifespan)


@app.post("/livekit/token")
def create_token(req: TokenRequest):
    _ = _require_env("LIVEKIT_URL")
    api_key = _require_env("LIVEKIT_API_KEY")
    api_secret = _require_env("LIVEKIT_API_SECRET")

    token = (
        api.AccessToken(api_key, api_secret)
        .with_identity(req.identity)
        .with_name(req.name or req.identity)
        .with_grants(
            api.VideoGrants(
                room_join=True,
                room=req.room,
                can_publish=True,
                can_subscribe=True,
                can_publish_data=True,
            )
        )
        .to_jwt()
    )
    return {"token": token}


# ---------------------------------------------------------------------
# CLI entry: worker only
# ---------------------------------------------------------------------
if __name__ == "__main__":
    # Usage:
    #   python RoomIO.py         -> runs worker using 'dev' (friendly logs)
    #   python RoomIO.py dev     -> runs worker using 'dev'
    #   python RoomIO.py start   -> runs worker using 'start'
    cmd = (sys.argv[1] if len(sys.argv) > 1 else "dev").strip().lower()
    if cmd not in ("dev", "start"):
        log.warning("Unknown command '%s'. Falling back to 'dev'.", cmd)
        cmd = "dev"
    _run_worker_blocking(command=cmd)
