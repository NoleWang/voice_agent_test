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
import uuid
import secrets
import sqlite3

from dotenv import load_dotenv
from fastapi import FastAPI
from pydantic import BaseModel

from livekit.agents import AgentSession, JobContext, WorkerOptions, cli, RoomInputOptions
from livekit.plugins.aws import stt as aws_stt, tts as aws_tts
from livekit.plugins import silero, noise_cancellation, aws
from livekit import api, rtc

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
ROOM_PREFIX = os.getenv("SESSION_ROOM_PREFIX", "case-")
SIP_LOBBY_ROOM = os.getenv("SIP_LOBBY_ROOM", "sip-lobby")
SESSION_CODE_LEN = int(os.getenv("SESSION_CODE_LEN", "6"))
SESSION_CODE_TTL_SEC = int(os.getenv("SESSION_CODE_TTL_SEC", "900"))
SESSION_STORE_PATH = os.getenv("SESSION_STORE_PATH", "/tmp/livekit_session_codes.sqlite3")


class SessionCodeStore:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._db_path = SESSION_STORE_PATH
        self._ensure_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self._db_path, timeout=5)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS session_codes (
                    code TEXT PRIMARY KEY,
                    room TEXT NOT NULL,
                    expires_at REAL NOT NULL,
                    created_at REAL NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS session_rooms (
                    room TEXT PRIMARY KEY,
                    expires_at REAL NOT NULL,
                    created_at REAL NOT NULL
                )
                """
            )
            conn.execute("CREATE INDEX IF NOT EXISTS idx_session_codes_expires ON session_codes(expires_at)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_session_rooms_expires ON session_rooms(expires_at)")
            conn.commit()

    def _cleanup(self, conn: sqlite3.Connection, now: float) -> None:
        conn.execute("DELETE FROM session_codes WHERE expires_at <= ?", (now,))
        conn.execute("DELETE FROM session_rooms WHERE expires_at <= ?", (now,))

    def generate_code(self) -> str:
        rng = secrets.SystemRandom()
        return "".join(str(rng.randrange(10)) for _ in range(SESSION_CODE_LEN))

    def create(self, room: str) -> str:
        now = time.time()
        expires_at = now + SESSION_CODE_TTL_SEC
        with self._lock:
            with self._connect() as conn:
                self._cleanup(conn, now)
                conn.execute(
                    """
                    INSERT INTO session_rooms(room, expires_at, created_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(room) DO UPDATE SET
                        expires_at=excluded.expires_at,
                        created_at=excluded.created_at
                    """,
                    (room, expires_at, now),
                )
                for _ in range(50):
                    code = self.generate_code()
                    try:
                        conn.execute(
                            "INSERT INTO session_codes(code, room, expires_at, created_at) VALUES (?, ?, ?, ?)",
                            (code, room, expires_at, now),
                        )
                        conn.commit()
                        return code
                    except sqlite3.IntegrityError:
                        continue
        raise RuntimeError("Unable to allocate unique session code")

    def resolve(self, code: str) -> Optional[str]:
        now = time.time()
        with self._lock:
            with self._connect() as conn:
                self._cleanup(conn, now)
                row = conn.execute(
                    "SELECT room, expires_at FROM session_codes WHERE code = ?",
                    (code,),
                ).fetchone()
                conn.execute("DELETE FROM session_codes WHERE code = ?", (code,))
                conn.commit()
        if row is None:
            return None
        if float(row["expires_at"]) <= now:
            return None
        return str(row["room"])

    def latest_room(self) -> Optional[str]:
        now = time.time()
        with self._lock:
            with self._connect() as conn:
                self._cleanup(conn, now)
                row = conn.execute(
                    """
                    SELECT room
                    FROM session_rooms
                    WHERE expires_at > ?
                    ORDER BY created_at DESC
                    LIMIT 1
                    """,
                    (now,),
                ).fetchone()
        return None if row is None else str(row["room"])


_session_codes = SessionCodeStore()


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


class SessionRequest(BaseModel):
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
def _resolve_tool_calls_sync(text: str, room: Any) -> Optional[str]:
    """Synchronous version of tool call resolution for use in sync contexts."""
    if not text:
        return None

    tool_names = TOOL_CALL_PATTERN.findall(text)
    if not tool_names:
        return None

    agent = getattr(room, "_agent_instance", None)
    if agent is None:
        log.warning("⚠️ No agent instance found for tool call resolution")
        return None

    # Try to use synchronous resolver first
    sync_resolver = getattr(agent, "resolve_tool_value_sync", None)
    if sync_resolver and callable(sync_resolver):
        resolved: list[str] = []
        for name in tool_names:
            try:
                out = sync_resolver(name)
                if isinstance(out, str) and out.strip():
                    resolved.append(out.strip())
                elif out:
                    log.warning("⚠️ Tool %s returned non-string: %r", name, out)
            except Exception as e:
                log.warning("Failed to resolve tool %s: %r", name, e)
                continue
        
        if resolved:
            result = " ".join(resolved)
            log.info("✅ Resolved %d tool(s) synchronously: %s", len(tool_names), result[:100])
            return result

    # Fallback: try async resolver if available
    resolver = getattr(agent, "resolve_tool_value", None)
    if resolver and callable(resolver):
        resolved: list[str] = []
        for name in tool_names:
            try:
                out = resolver(name)
                # If it's a coroutine, we can't await it in sync context
                if inspect.isawaitable(out):
                    log.warning("⚠️ Tool %s resolver is async, cannot resolve synchronously", name)
                    continue
                if isinstance(out, str) and out.strip():
                    resolved.append(out.strip())
            except Exception as e:
                log.warning("Failed to resolve tool %s: %r", name, e)
                continue
        
        if resolved:
            result = " ".join(resolved)
            log.info("✅ Resolved %d tool(s) (sync fallback): %s", len(tool_names), result[:100])
            return result

    log.warning("⚠️ No tools resolved from: %s", text[:100])
    return None


async def _resolve_tool_calls(text: str, room: Any) -> Optional[str]:
    if not text:
        return None

    tool_names = TOOL_CALL_PATTERN.findall(text)
    if not tool_names:
        return None

    agent = getattr(room, "_agent_instance", None)
    if agent is None:
        log.warning("⚠️ No agent instance found for tool call resolution")
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
                    log.warning("⚠️ Tool function %s not found on agent", name)
                    continue
                out = fn()
                if inspect.isawaitable(out):
                    out = await out
            if isinstance(out, str):
                if out.strip():
                    resolved.append(out.strip())
                else:
                    log.warning("⚠️ Tool %s returned empty string", name)
            else:
                log.warning("⚠️ Tool %s returned non-string: %r", name, out)
        except Exception as e:
            log.warning("Failed to resolve tool %s: %r", name, e)
            continue

    if not resolved:
        log.warning("⚠️ No tools resolved from: %s", text[:100])
        return None

    result = " ".join(resolved)
    log.info("✅ Resolved %d tool(s): %s", len(tool_names), result[:100])
    return result


# ---------------------------------------------------------------------
# Helper: clean tool call tags from text
# ---------------------------------------------------------------------
def _clean_tool_call_tags(text: str) -> str:
    """Remove any remaining tool call tags from text before TTS."""
    if not text:
        return text
    # Remove tool call patterns like <function=name> or </function> or <tool_call>...</tool_call>
    cleaned = TOOL_CALL_PATTERN.sub("", text)
    cleaned = re.sub(r"</?function[^>]*>", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"</?tool_call[^>]*>", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"<function[^>]*>.*?</function>", "", cleaned, flags=re.IGNORECASE | re.DOTALL)
    cleaned = re.sub(r"<tool_call[^>]*>.*?</tool_call>", "", cleaned, flags=re.IGNORECASE | re.DOTALL)
    return cleaned.strip()


# ---------------------------------------------------------------------
# Hook session.say() to filter tool calls
# ---------------------------------------------------------------------
def _install_session_say_hook(session: AgentSession, room: Any) -> None:
    """
    Hook session.say() directly to filter tool call tags before TTS.
    This catches all paths where the agent speaks, not just TTS methods.
    """
    if getattr(session, "_say_hook_installed", False):
        return
    session._say_hook_installed = True

    orig_say = getattr(session, "say", None)
    if orig_say is None:
        log.warning("⚠️ session.say() not found; cannot hook")
        return

    async def _filtered_say(text: str, *args, **kwargs):
        """Filter tool call tags from text before speaking."""
        if not isinstance(text, str):
            return await orig_say(text, *args, **kwargs)
        
        original_text = text
        
        # Check if text contains tool calls
        has_tool_calls = bool(TOOL_CALL_PATTERN.search(text))
        
        if has_tool_calls:
            # First try to resolve tool calls
            resolved = await _resolve_tool_calls(text, room)
            if resolved:
                text = resolved
                log.info("🔧 Resolved tool calls: %s -> %s", original_text[:100], text[:100])
            else:
                # If resolution failed, clean tags but log warning
                cleaned = _clean_tool_call_tags(text)
                log.warning("⚠️ Tool call resolution failed, cleaned tags: %s -> %s", original_text[:100], cleaned[:100] if cleaned else "(empty)")
                text = cleaned
        else:
            # No tool calls, just clean any stray tags
            cleaned = _clean_tool_call_tags(text)
            if cleaned != text:
                log.info("🧹 Cleaned stray tool call tags: %s -> %s", text[:100], cleaned[:100])
            text = cleaned
        
        # Only speak if there's actual content left
        if text and text.strip():
            return await orig_say(text, *args, **kwargs)
        else:
            log.warning("⚠️ Filtered out empty text (was: %s)", original_text[:100])
            return None

    try:
        setattr(session, "say", _filtered_say)
        log.info("✅ Installed session.say() hook to filter tool calls")
    except Exception as e:
        log.warning("Failed to hook session.say(): %r", e)


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
                    # First try to resolve tool calls
                    resolved = await _resolve_tool_calls(text, room)
                    if resolved:
                        text = resolved
                    else:
                        # If no resolution, clean any remaining tool call tags
                        text = _clean_tool_call_tags(text)
                    
                    # Update the appropriate parameter
                    if text and text.strip():
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

                        # Publish to chat only if we have actual content
                        asyncio.create_task(publish_chat(room, os.getenv("AGENT_LABEL", "agent"), str(text)))
                    else:
                        log.warning("⚠️ Not publishing empty text to chat")
                out = __orig(*args, **kwargs)
                if inspect.isawaitable(out):
                    return await out
                return out

            wrapped = _async_wrapper
        else:

            def _sync_wrapper(*args, __orig=orig, **kwargs):
                text = _extract_text(args, kwargs)
                if text:
                    log.debug("🔍 Sync wrapper received text: %s", text[:200])
                    resolved = None
                    has_tool_calls = bool(TOOL_CALL_PATTERN.search(text))
                    
                    if has_tool_calls:
                        log.info("🔧 Sync wrapper detected tool calls in text: %s", text[:200])
                        # Try synchronous resolution first (preferred for sync context)
                        try:
                            resolved = _resolve_tool_calls_sync(text, room)
                            if resolved:
                                log.info("✅ Sync wrapper resolved tool calls synchronously: %s", resolved[:100])
                        except Exception as e:
                            log.warning("⚠️ Synchronous tool call resolution failed: %r", e)
                            resolved = None
                        
                        # If sync resolution failed, try async (only if no loop is running)
                        if not resolved:
                            try:
                                loop = asyncio.get_running_loop()
                                # There's a running loop, we can't use asyncio.run
                                # Try to use the sync resolver which should work
                                log.warning("⚠️ Sync resolution failed but loop is running, cannot use async")
                            except RuntimeError:
                                # No running loop, we can create a new one for async resolution
                                try:
                                    resolved = asyncio.run(_resolve_tool_calls(text, room))
                                    if resolved:
                                        log.info("✅ Sync wrapper resolved tool calls via async (new loop): %s", resolved[:100])
                                except Exception as e:
                                    log.warning("⚠️ Failed to resolve tool calls in new loop: %r", e)
                    
                    if resolved:
                        text = resolved
                        log.info("✅ Sync wrapper using resolved text: %s", text[:100])
                    else:
                        # If no resolution, clean any remaining tool call tags
                        cleaned = _clean_tool_call_tags(text)
                        if cleaned != text:
                            log.info("🧹 Sync wrapper cleaned tool call tags: %s -> %s", text[:100], cleaned[:100] if cleaned else "(empty)")
                        text = cleaned
                    
                    if text and text.strip():
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

                        # Publish to chat only if we have actual content
                        try:
                            loop = asyncio.get_running_loop()
                            if loop:
                                asyncio.create_task(publish_chat(room, os.getenv("AGENT_LABEL", "agent"), str(text)))
                        except RuntimeError:
                            # No loop, can't publish async - this is OK, the async wrapper will handle it
                            pass
                    else:
                        log.warning("⚠️ Not publishing empty text to chat (sync wrapper). Original: %s", text[:200] if text else "(empty)")
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

            raw = getattr(packet, "data", None) or getattr(packet, "payload", None)
            if raw is None:
                log.info("📩 chat packet received (no data field): %r", packet)
                return

            body = raw.decode("utf-8", errors="ignore")

            try:
                obj = json.loads(body)
            except Exception:
                obj = None

            normalized_topic = (topic or "").strip()
            inferred_topic = normalized_topic
            if not inferred_topic:
                if isinstance(obj, dict):
                    if "text" in obj or "message" in obj:
                        inferred_topic = CHAT_TOPIC
                    elif any(
                        key in obj
                        for key in (
                            "profile",
                            "dispute",
                            "summary",
                            "amount",
                            "currency",
                            "merchant",
                            "reason",
                            "last4",
                            "txn_date",
                        )
                    ):
                        inferred_topic = BOOTSTRAP_TOPIC
                if not inferred_topic:
                    inferred_topic = CHAT_TOPIC
            elif inferred_topic not in {CHAT_TOPIC, BOOTSTRAP_TOPIC}:
                return

            if inferred_topic == BOOTSTRAP_TOPIC:
                agent = getattr(room, "_agent_instance", None)
                if not isinstance(obj, dict):
                    log.warning("📩 bootstrap payload received, but payload is not JSON")
                    return
                try:
                    if agent is None:
                        # Stash until agent is attached.
                        setattr(room, "_pending_bootstrap_payload", obj)
                        log.warning("📩 bootstrap payload received, but no agent is attached (stashed).")
                        return
                    log.info("📩 Received bootstrap payload with keys: %s", list(obj.keys()))
                    if "dispute" in obj and isinstance(obj["dispute"], dict):
                        log.info("📩 Bootstrap dispute data: merchant=%s, amount=%s, last4=%s", 
                                obj["dispute"].get("merchant", ""), obj["dispute"].get("amount", 0),
                                obj["dispute"].get("last4", ""))
                    agent.apply_runtime_payload(obj)
                    log.info("📩 ✅ Successfully applied bootstrap payload from iOS")
                except Exception as e:
                    log.exception("❌ Failed to apply bootstrap payload: %r", e)
                return

            text_for_log = body
            from_name = "user"
            if isinstance(obj, dict):
                text_for_log = obj.get("text", body)
                from_name = obj.get("from", "user")

            pid = getattr(participant, "identity", None) or getattr(participant, "sid", None) or "unknown"
            log.info("📩 iOS chat DataPacket (from=%s pid=%s): %s", from_name, pid, text_for_log)

            # Prevent feedback loops:
            # - ignore packets sent by this local participant
            # - ignore packets explicitly marked as agent messages
            local_identity = (
                getattr(getattr(room, "local_participant", None), "identity", None)
                or getattr(getattr(room, "local_participant", None), "sid", None)
            )
            from_name_norm = str(from_name or "").strip().lower()
            agent_label_norm = (os.getenv("AGENT_LABEL", "agent") or "agent").strip().lower()
            pid_norm = str(pid or "").strip().lower()
            local_identity_norm = str(local_identity or "").strip().lower()

            if local_identity_norm and pid_norm == local_identity_norm:
                log.debug("Skipping local self-sent chat packet (pid=%s)", pid)
                return

            if from_name_norm in {"agent", agent_label_norm} or pid_norm.startswith("agent-"):
                log.debug("Skipping agent-originated chat packet to avoid loop (from=%s pid=%s)", from_name, pid)
                return

            # Operator override: typed chat from iOS (explicitly marked) should be spoken by the agent.
            ios_user_label_norm = (os.getenv("IOS_USER_LABEL", "iOS User") or "iOS User").strip().lower()
            allow_override = bool(obj and isinstance(obj, dict) and obj.get("override") is True)
            if from_name_norm == ios_user_label_norm and allow_override:
                def _is_primary_agent(room: Any) -> bool:
                    local = getattr(getattr(room, "local_participant", None), "identity", None)
                    if isinstance(local, bytes):
                        local_id = local.decode("utf-8", errors="ignore")
                    else:
                        local_id = str(local or "")

                    agent_ids: list[str] = []
                    remote = getattr(room, "remote_participants", None)
                    if isinstance(remote, dict):
                        for p in remote.values():
                            rid = getattr(p, "identity", None) or getattr(p, "sid", None) or ""
                            if isinstance(rid, bytes):
                                rid = rid.decode("utf-8", errors="ignore")
                            rid = str(rid)
                            if rid.startswith("agent-"):
                                agent_ids.append(rid)

                    if local_id.startswith("agent-"):
                        agent_ids.append(local_id)

                    if not agent_ids:
                        return True
                    return local_id == sorted(set(agent_ids))[0]

                if not _is_primary_agent(room):
                    log.debug("Operator override ignored on non-primary agent.")
                    return

                session: Optional[AgentSession] = getattr(room, "_typed_chat_session", None)
                if session is not None and hasattr(session, "say"):
                    try:
                        await session.say(str(text_for_log))
                        log.info("✅ operator override: session.say(...)")
                        return
                    except Exception as e:
                        log.warning("Operator override speak failed: %r", e)

                # Fallback: at least show as agent in chat if no session is ready.
                await publish_chat(room, os.getenv("AGENT_LABEL", "agent"), str(text_for_log))
                log.info("✅ operator override: published chat only (no session)")
                return

            session: Optional[AgentSession] = getattr(room, "_typed_chat_session", None)
            if session is not None:
                injected = await _try_inject_text_into_session(session, str(text_for_log))
                if injected:
                    return

            # No fallback echo; avoids duplicate/noisy chat messages.
            log.info("No typed-chat injection API available; message not echoed.")

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
def _get_room_name(ctx: JobContext) -> str:
    try:
        job_room = getattr(getattr(ctx, "job", None), "room", None)
        name = getattr(job_room, "name", None)
        if isinstance(name, str) and name:
            return name
    except Exception:
        pass
    try:
        name = getattr(getattr(ctx, "room", None), "name", None)
        if isinstance(name, str) and name:
            return name
    except Exception:
        pass
    return ""


async def _safe_ctx_shutdown(ctx: JobContext, reason: str) -> None:
    """
    Compatibility wrapper: some SDK versions expose ctx.shutdown as sync, others async.
    """
    try:
        maybe = ctx.shutdown(reason=reason)
        if inspect.isawaitable(maybe):
            await maybe
    except Exception as e:
        log.warning("ctx.shutdown failed (reason=%s): %r", reason, e)


def _parse_dtmf_event(*args, **kwargs) -> tuple[Optional[str], Optional[str]]:
    digit = None
    participant = None
    participant_identity = None

    def _maybe_set_digit(val: Any) -> None:
        nonlocal digit
        if isinstance(val, str) and len(val) >= 1 and digit is None:
            digit = val[0]

    def _maybe_set_participant(val: Any) -> None:
        nonlocal participant
        if val is None:
            return
        if hasattr(val, "identity") or hasattr(val, "sid"):
            participant = val

    for arg in args:
        if isinstance(arg, dict):
            _maybe_set_digit(arg.get("digit") or arg.get("dtmf") or arg.get("tone"))
            _maybe_set_participant(arg.get("participant"))
            participant_identity = (
                participant_identity
                or arg.get("participant_identity")
                or arg.get("participant_id")
                or arg.get("participant_sid")
                or arg.get("identity")
                or arg.get("sid")
            )
        else:
            _maybe_set_digit(
                arg if isinstance(arg, str) else (
                    getattr(arg, "digit", None)
                    or getattr(arg, "dtmf", None)
                    or getattr(arg, "tone", None)
                )
            )
            _maybe_set_participant(arg)
            participant_identity = (
                participant_identity
                or getattr(arg, "participant_identity", None)
                or getattr(arg, "participant_id", None)
                or getattr(arg, "participant_sid", None)
                or getattr(arg, "identity", None)
                or getattr(arg, "sid", None)
            )

    _maybe_set_digit(kwargs.get("digit") or kwargs.get("dtmf") or kwargs.get("tone"))
    _maybe_set_participant(kwargs.get("participant"))
    participant_identity = (
        participant_identity
        or kwargs.get("participant_identity")
        or kwargs.get("participant_id")
        or kwargs.get("participant_sid")
        or kwargs.get("identity")
        or kwargs.get("sid")
    )

    if participant_identity is None and participant is not None:
        participant_identity = getattr(participant, "identity", None) or getattr(participant, "sid", None)

    if isinstance(participant_identity, bytes):
        participant_identity = participant_identity.decode("utf-8", errors="ignore")

    return digit, participant_identity


async def _move_participant(lk: api.LiveKitAPI, from_room: str, identity: str, to_room: str) -> bool:
    room_svc = getattr(lk, "room", None) or getattr(lk, "room_service", None)
    req_cls = getattr(api, "MoveParticipantRequest", None)
    if room_svc is None or req_cls is None:
        log.warning("MoveParticipant not available in this LiveKit API version.")
        return False

    req = None
    for key in ("to_room", "destination_room", "target_room", "room_to", "new_room"):
        try:
            req = req_cls(room=from_room, identity=identity, **{key: to_room})
            break
        except Exception:
            continue

    # Some SDK/proto versions only accept positional init + setattr style.
    if req is None:
        try:
            req = req_cls(room=from_room, identity=identity)
            for key in ("to_room", "destination_room", "target_room", "room_to", "new_room"):
                try:
                    setattr(req, key, to_room)
                    break
                except Exception:
                    continue
        except Exception:
            req = None

    if req is None:
        log.warning("MoveParticipantRequest signature mismatch; cannot move participant.")
        return False

    for method in ("move_participant", "transfer_participant"):
        fn = getattr(room_svc, method, None)
        if callable(fn):
            try:
                await fn(req)
                return True
            except Exception as e:
                log.warning("Move participant via %s failed: %r", method, e)
                return False

    log.warning("Room service does not support move/transfer participant.")
    return False


async def _ensure_agent_dispatched_to_room(lk: api.LiveKitAPI, room_name: str) -> bool:
    """
    Ensure an agent job is dispatched to `room_name` so the conversation entrypoint runs.
    """
    dispatch_svc = getattr(lk, "agent_dispatch", None)
    create_req_cls = getattr(api, "CreateAgentDispatchRequest", None)
    list_req_cls = getattr(api, "ListAgentDispatchRequest", None)
    if dispatch_svc is None or create_req_cls is None:
        log.warning("Agent dispatch API unavailable; cannot dispatch room '%s'.", room_name)
        return False

    try:
        if list_req_cls is not None and hasattr(dispatch_svc, "list_dispatch"):
            listed = await dispatch_svc.list_dispatch(list_req_cls(room=room_name))
            existing = list(getattr(listed, "agent_dispatches", []) or [])
            if existing:
                log.info("Agent dispatch already exists for room '%s' (%d dispatch(es)).", room_name, len(existing))
                return True
    except Exception as e:
        log.warning("Failed to list agent dispatches for room '%s': %r", room_name, e)

    agent_name = (os.getenv("LIVEKIT_AGENT_NAME", "") or os.getenv("AGENT_NAME", "")).strip()
    metadata = json.dumps({"source": "sip-router", "room": room_name})
    kwargs: dict[str, Any] = {"room": room_name, "metadata": metadata}
    if agent_name:
        kwargs["agent_name"] = agent_name

    try:
        req = create_req_cls(**kwargs)
    except Exception:
        req = create_req_cls(room=room_name)
        if agent_name:
            with contextlib.suppress(Exception):
                setattr(req, "agent_name", agent_name)
        with contextlib.suppress(Exception):
            setattr(req, "metadata", metadata)

    create_fn = getattr(dispatch_svc, "create_dispatch", None)
    if not callable(create_fn):
        log.warning("Agent dispatch service missing create_dispatch for room '%s'.", room_name)
        return False

    try:
        out = await create_fn(req)
        dispatch_id = getattr(out, "id", None) or getattr(out, "dispatch_id", None)
        log.info("Created agent dispatch for room '%s' (dispatch_id=%s, agent_name=%s).", room_name, dispatch_id, agent_name or "<any>")
        return True
    except Exception as e:
        log.warning("Failed to create agent dispatch for room '%s': %r", room_name, e)
        return False


async def _room_has_agent_participant(lk: api.LiveKitAPI, room_name: str) -> bool:
    room_svc = getattr(lk, "room", None) or getattr(lk, "room_service", None)
    req_cls = getattr(api, "ListParticipantsRequest", None)
    if room_svc is None or req_cls is None:
        return False

    list_fn = getattr(room_svc, "list_participants", None)
    if not callable(list_fn):
        return False

    try:
        out = await list_fn(req_cls(room=room_name))
        participants = list(getattr(out, "participants", []) or [])
        for p in participants:
            state_val = getattr(p, "state", None)
            state_name = str(getattr(state_val, "name", state_val)).upper()
            if state_name and state_name not in {"JOINED", "ACTIVE"}:
                continue
            pid = (
                getattr(p, "identity", None)
                or getattr(p, "sid", None)
                or ""
            )
            pid_norm = str(pid).strip().lower()
            if pid_norm.startswith("agent-"):
                return True
    except Exception as e:
        log.warning("Failed to inspect participants for room '%s': %r", room_name, e)
    return False


async def _dispatch_if_needed_after_move(
    lk: api.LiveKitAPI, room_name: str, dispatched_rooms: set[str]
) -> None:
    if room_name in dispatched_rooms:
        return

    # Optional guard: skip explicit dispatch when an active agent is already present.
    # Default is ON to avoid duplicate agents when auto-dispatch already occurred.
    skip_if_agent_present = os.getenv("SKIP_EXPLICIT_DISPATCH_IF_AGENT_PRESENT", "1").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    if skip_if_agent_present:
        await asyncio.sleep(1.0)
        if await _room_has_agent_participant(lk, room_name):
            log.info("Room '%s' already has an agent participant; explicit dispatch skipped.", room_name)
            return

    dispatched_ok = await _ensure_agent_dispatched_to_room(lk, room_name)
    if dispatched_ok:
        dispatched_rooms.add(room_name)


async def _run_sip_router(ctx: JobContext) -> None:
    log.info("SIP router connected. Room=%s", ctx.room)

    api_key = _require_env("LIVEKIT_API_KEY")
    api_secret = _require_env("LIVEKIT_API_SECRET")
    livekit_url = _require_env("LIVEKIT_URL")

    lk = api.LiveKitAPI(livekit_url, api_key, api_secret)
    buffers: dict[str, str] = {}
    moved_participants: set[str] = set()
    dispatched_rooms: set[str] = set()
    fallback_scheduled: set[str] = set()

    def _safe_repr(val: Any, limit: int = 300) -> str:
        try:
            raw = repr(val)
        except Exception:
            raw = "<unreprable>"
        return raw if len(raw) <= limit else raw[:limit] + "...(truncated)"

    async def _route_code(code: str, participant_id: str) -> None:
        code = code.strip()
        if len(code) != SESSION_CODE_LEN:
            log.info("Ignoring code with wrong length: '%s'", code)
            return
        dest_room = _session_codes.resolve(code)
        if not dest_room:
            log.info("Invalid/expired code '%s' for participant %s", code, participant_id)
            return
        from_room = getattr(ctx.room, "name", SIP_LOBBY_ROOM)
        ok = await _move_participant(lk, from_room, participant_id, dest_room)
        log.info("Move participant %s -> %s (ok=%s)", participant_id, dest_room, ok)
        if ok:
            moved_participants.add(str(participant_id))
            await _dispatch_if_needed_after_move(lk, dest_room, dispatched_rooms)

    async def _handle_dtmf(*args, **kwargs) -> None:
        log.info("DTMF callback fired. args=%s kwargs=%s", _safe_repr(args), _safe_repr(kwargs))
        digit, participant_id = _parse_dtmf_event(*args, **kwargs)
        log.info("DTMF parsed. digit=%s participant=%s", digit, participant_id)
        if not digit or not participant_id:
            log.warning("DTMF parse incomplete; ignored event.")
            return

        if digit == "*":
            buffers[participant_id] = ""
            log.info("DTMF reset buffer for participant=%s", participant_id)
            return

        if digit == "#":
            code = buffers.get(participant_id, "")
            buffers[participant_id] = ""
            log.info("DTMF submit for participant=%s code='%s'", participant_id, code)
            await _route_code(code, participant_id)
            return

        if digit.isdigit():
            buf = buffers.get(participant_id, "") + digit
            log.info("DTMF digit for participant=%s buffer='%s'", participant_id, buf)
            if len(buf) >= SESSION_CODE_LEN:
                code = buf[:SESSION_CODE_LEN]
                buffers[participant_id] = ""
                log.info("DTMF auto-submit for participant=%s code='%s'", participant_id, code)
                await _route_code(code, participant_id)
            else:
                buffers[participant_id] = buf

    def _participant_identity(val: Any) -> Optional[str]:
        if val is None:
            return None
        cand = (
            getattr(val, "identity", None)
            or getattr(val, "sid", None)
            or getattr(val, "participant_identity", None)
        )
        if isinstance(cand, bytes):
            cand = cand.decode("utf-8", errors="ignore")
        if cand is None:
            return None
        return str(cand)

    async def _fallback_move_participant(participant_id: str) -> None:
        if participant_id in moved_participants:
            return
        # Give DTMF a short chance first; fallback only if no code was entered.
        await asyncio.sleep(6)
        if participant_id in moved_participants:
            return
        latest_room = _session_codes.latest_room()
        if not latest_room:
            log.warning("No active case room found for SIP fallback move.")
            return
        from_room = getattr(ctx.room, "name", SIP_LOBBY_ROOM)
        ok = await _move_participant(lk, from_room, participant_id, latest_room)
        log.info("Fallback move participant %s -> %s (ok=%s)", participant_id, latest_room, ok)
        if ok:
            moved_participants.add(str(participant_id))
            await _dispatch_if_needed_after_move(lk, latest_room, dispatched_rooms)

    def _schedule_fallback(participant_id: Optional[str]) -> None:
        if not participant_id:
            return
        pid = str(participant_id)
        if pid in fallback_scheduled or pid in moved_participants:
            return
        fallback_scheduled.add(pid)
        asyncio.create_task(_fallback_move_participant(pid))

    async def _handle_participant_connected(*args, **kwargs) -> None:
        participant = None
        if args:
            participant = args[0]
        participant = kwargs.get("participant", participant)
        pid = _participant_identity(participant)
        if not pid:
            pid = (
                kwargs.get("participant_identity")
                or kwargs.get("participant_id")
                or kwargs.get("participant_sid")
            )
            if pid is not None:
                pid = str(pid)
        log.info("Participant-connected callback in lobby. participant=%s", pid)
        _schedule_fallback(pid)

    def _attach_listener(event_name: str) -> None:
        if hasattr(ctx.room, "on"):
            try:
                ctx.room.on(event_name, lambda *a, **k: asyncio.create_task(_handle_dtmf(*a, **k)))
                log.info("✅ DTMF listener attached via room.on('%s')", event_name)
                return
            except Exception as e:
                log.warning("room.on('%s') failed: %r", event_name, e)

        if hasattr(ctx.room, "add_listener"):
            try:
                ctx.room.add_listener(
                    event_name,
                    lambda *a, **k: asyncio.create_task(_handle_dtmf(*a, **k)),
                )
                log.info("✅ DTMF listener attached via room.add_listener('%s')", event_name)
            except Exception as e:
                log.warning("room.add_listener('%s') failed: %r", event_name, e)

    _attach_listener("sip_dtmf_received")
    _attach_listener("dtmf_received")

    def _attach_participant_listener(event_name: str) -> None:
        if hasattr(ctx.room, "on"):
            try:
                ctx.room.on(event_name, lambda *a, **k: asyncio.create_task(_handle_participant_connected(*a, **k)))
                log.info("✅ Participant listener attached via room.on('%s')", event_name)
                return
            except Exception as e:
                log.warning("room.on('%s') failed: %r", event_name, e)
        if hasattr(ctx.room, "add_listener"):
            try:
                ctx.room.add_listener(
                    event_name,
                    lambda *a, **k: asyncio.create_task(_handle_participant_connected(*a, **k)),
                )
                log.info("✅ Participant listener attached via room.add_listener('%s')", event_name)
            except Exception as e:
                log.warning("room.add_listener('%s') failed: %r", event_name, e)

    _attach_participant_listener("participant_connected")
    _attach_participant_listener("participant_joined")

    async def _poll_existing_participants() -> None:
        # Some SDK builds don't emit participant join events reliably for SIP.
        for _ in range(30):  # ~30 seconds
            try:
                remote = getattr(ctx.room, "remote_participants", None)
                if isinstance(remote, dict):
                    for p in remote.values():
                        _schedule_fallback(_participant_identity(p))
            except Exception:
                pass
            await asyncio.sleep(1)

    asyncio.create_task(_poll_existing_participants())

    stop_event = asyncio.Event()

    def request_stop(*_):
        if not stop_event.is_set():
            stop_event.set()

    try:
        ctx.room.on("room_disconnected", lambda *_: request_stop())
    except Exception:
        pass

    try:
        await stop_event.wait()
    finally:
        await _safe_ctx_shutdown(ctx, reason="SIP router ended")


async def _run_conversation(ctx: JobContext) -> None:
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

    # SIP participants can present audio tracks as SOURCE_UNKNOWN on some SDK versions.
    # If we only accept SOURCE_MICROPHONE, the agent may ignore bank-side speech.
    try:
        track_source = getattr(rtc, "TrackSource", None)
        accepted_sources = []
        if track_source is not None:
            for src_name in ("SOURCE_MICROPHONE", "SOURCE_UNKNOWN"):
                src_val = getattr(track_source, src_name, None)
                if src_val is not None:
                    accepted_sources.append(src_val)

        if accepted_sources:
            applied = False
            for attr_name in ("accepted_sources", "accepted_audio_sources", "audio_sources"):
                if hasattr(room_input_opts, attr_name):
                    setattr(room_input_opts, attr_name, accepted_sources)
                    applied = True
                    log.info("Room input accepted sources configured via '%s': %s", attr_name, accepted_sources)
                    break

            if not applied:
                # Fallback for versions that only accept constructor kwargs.
                try:
                    room_input_opts = RoomInputOptions(
                        noise_cancellation=getattr(room_input_opts, "noise_cancellation", None),
                        accepted_sources=accepted_sources,
                    )
                    log.info("Room input accepted sources configured via constructor: %s", accepted_sources)
                except Exception as e:
                    log.warning("Could not set accepted sources for room input options: %r", e)
    except Exception as e:
        log.warning("Failed to configure SIP-compatible accepted sources: %r", e)

    # Agent persona
    agent = CustomerLLMAgent()
    setattr(ctx.room, "_agent_instance", agent)
    pending_bootstrap = getattr(ctx.room, "_pending_bootstrap_payload", None)
    if isinstance(pending_bootstrap, dict):
        try:
            log.info("📩 Applying stashed bootstrap payload after agent attach.")
            agent.apply_runtime_payload(pending_bootstrap)
            setattr(ctx.room, "_pending_bootstrap_payload", None)
        except Exception as e:
            log.warning("Failed to apply stashed bootstrap payload: %r", e)

    # Session
    session = AgentSession(stt=stt, tts=tts, vad=vad, llm=llm)

    # ✅ Filter tool calls from session.say() before TTS
    _install_session_say_hook(session, ctx.room)

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
        await _safe_ctx_shutdown(ctx, reason="Session ended")


async def entrypoint(ctx: JobContext):
    await ctx.connect()
    room_name = _get_room_name(ctx)
    if not room_name:
        room_name = getattr(getattr(ctx, "room", None), "name", "") or ""

    if room_name == SIP_LOBBY_ROOM:
        await _run_sip_router(ctx)
        return

    if room_name.startswith(ROOM_PREFIX):
        await _run_conversation(ctx)
        return

    log.info("Room '%s' not handled by this agent. Shutting down.", room_name)
    await _safe_ctx_shutdown(ctx, reason="Room not handled")


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
    raw_port = (os.getenv("LIVEKIT_WORKER_PORT", "0") or "0").strip()
    try:
        worker_port = int(raw_port)
    except Exception:
        log.warning("Invalid LIVEKIT_WORKER_PORT='%s', falling back to 0.", raw_port)
        worker_port = 0
    try:
        sys.argv = ["livekit-worker", command, "--log-level", os.getenv("LIVEKIT_LOG_LEVEL", "DEBUG")]
        # Now running in subprocess, which is the main thread of that process
        # This allows signal handlers to work correctly
        log.info("Starting LiveKit worker (command=%s, http_port=%d)", command, worker_port)
        cli.run_app(WorkerOptions(entrypoint_fnc=entrypoint, port=worker_port))
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
    return {"token": token, "url": os.getenv("LIVEKIT_URL")}


@app.post("/livekit/session")
def create_session(req: SessionRequest):
    livekit_url = _require_env("LIVEKIT_URL")
    api_key = _require_env("LIVEKIT_API_KEY")
    api_secret = _require_env("LIVEKIT_API_SECRET")

    room = f"{ROOM_PREFIX}{uuid.uuid4().hex[:10]}"
    code = _session_codes.create(room)

    token = (
        api.AccessToken(api_key, api_secret)
        .with_identity(req.identity)
        .with_name(req.name or req.identity)
        .with_grants(
            api.VideoGrants(
                room_join=True,
                room=room,
                can_publish=True,
                can_subscribe=True,
                can_publish_data=True,
            )
        )
        .to_jwt()
    )
    return {
        "room": room,
        "code": code,
        "token": token,
        "url": livekit_url,
        "expires_in": SESSION_CODE_TTL_SEC,
    }


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
