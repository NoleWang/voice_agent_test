from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional, Dict, Any

import os
import re
import random

from livekit.agents import Agent, function_tool, RunContext


# ---- Tool calling contract: enforce valid JSON args for tools ----
TOOL_JSON_CONTRACT = (
    "You MUST follow this tool-use contract:\n"
    "• When calling any tool, always provide a syntactically valid JSON object in `arguments`.\n"
    "• If a tool has no parameters, pass `{}` exactly.\n"
    "• Never stream partial JSON like '{' or '\"key\":'. Emit exactly one complete tool call.\n"
    "• Do not include comments or trailing commas inside JSON."
)

# =========================
# Humanization (Polly SSML)
# =========================

class Persona:
    def __init__(
        self,
        name: str = "Simin",
        warmth: float = 0.7,        # 0..1 (ack/backchannel density)
        filler_rate: float = 0.25,  # 0..1 (chance to add a subtle filler)
        pace: str = "medium",       # slow | medium | fast
        pitch: str = "+2%",         # e.g., "+2%"
        style: str = "conversational",  # Polly domain style or "" for none
    ):
        self.name = name
        self.warmth = warmth
        self.filler_rate = filler_rate
        self.pace = pace
        self.pitch = pitch
        self.style = style


ACKS   = ["Got it", "Okay", "Sure", "Right", "Understood", "All right"]
HEDGES = ["Let me check", "One moment", "Give me a second", "Let me pull that up"]
FILLERS = ["uh", "um"]


def _maybe(prefixes, p: float) -> str:
    return (random.choice(prefixes) + ". ") if random.random() < max(0.0, min(1.0, p)) else ""


def _normalize_numbers(text: str) -> str:
    # last four digits as digits
    text = re.sub(
        r"\blast\s*4\s*[:\-]?\s*(\d{4})\b",
        r"last four digits <say-as interpret-as=\"digits\">\\1</say-as>",
        text,
        flags=re.I,
    )
    # currency formatting (let Polly read number as currency)
    text = re.sub(
        r"\$\s?(\d+(?:\.\d{1,2})?)",
        r"$<say-as interpret-as=\"currency\">USD \\1</say-as>",
        text,
    )
    return text


def humanize_to_ssml(
    text: str,
    persona: Optional[Persona] = None,
    *,
    add_ack: bool = False,
    use_breaths: bool = False,
) -> str:
    """Convert plain text into Polly SSML with gentle prosody and micro-pauses."""
    persona = persona or Persona()

    pre = ""
    if add_ack:
        pre += _maybe(ACKS,   persona.warmth * 0.6)
        pre += _maybe(HEDGES, persona.filler_rate * 0.5)

    body = (text or "").strip()
    body = _normalize_numbers(body)
    body = re.sub(r",\s*", ", <break time=\"220ms\"/> ", body)
    body = re.sub(r"([.?!])\s+", r"\1 <break time=\"360ms\"/> ", body)

    open_domain = f"<amazon:domain name=\"{persona.style}\">" if getattr(persona, "style", "") else ""
    close_domain = "</amazon:domain>" if getattr(persona, "style", "") else ""
    breaths_open = '<amazon:auto-breaths frequency="medium" volume="low" duration="short">' if use_breaths else ""
    breaths_close = "</amazon:auto-breaths>" if use_breaths else ""

    ssml = f"""
<speak>
  {breaths_open}
    {open_domain}
      <prosody rate="{persona.pace}" pitch="{persona.pitch}">
        {pre}{body}
      </prosody>
    {close_domain}
  {breaths_close}
</speak>
""".strip()
    return re.sub(r">\s+<", "><", ssml)


def _humanize_enabled(session: Optional[Any]) -> bool:
    try:
        if session and getattr(session, "userdata", None):
            extras = getattr(session.userdata, "extras", None)
            if isinstance(extras, dict) and "humanize_override" in extras:
                return bool(extras["humanize_override"])
    except Exception:
        pass
    # default OFF unless explicitly enabled
    return os.getenv("HUMANIZE_SSML", "0").strip() not in {"0", "false", "False"}

def _breaths_enabled(session: Optional[Any]) -> bool:
    try:
        if session and getattr(session, "userdata", None):
            extras = getattr(session.userdata, "extras", None)
            if isinstance(extras, dict) and "breaths_override" in extras:
                return bool(extras["breaths_override"])
    except Exception:
        pass
    # default OFF unless explicitly enabled
    return os.getenv("POLLY_BREATHS", "0").strip() not in {"0", "false", "False"}


def _ssml_supported_by_tts() -> bool:
    # Polly supports SSML; keep as function to future-proof engine swaps
    return True


# =========================
# Typed session userdata
# =========================

@dataclass
class DisputeSessionInfo:
    # slots to collect
    amount: Optional[float] = None
    currency: str = "USD"
    merchant: Optional[str] = None
    txn_date: Optional[str] = None  # ISO yyyy-mm-dd preferred
    reason: Optional[str] = None    # unauthorized | not_received | defective | duplicate | other
    last4: Optional[str] = None

    # case id provided later by bank/agent
    case_id: Optional[str] = None

    # control flags
    waiting_for_case_id: bool = False
    done: bool = False

    # extras (persona, lang, external context, flags)
    extras: Dict[str, Any] = field(default_factory=dict)

    def core_complete(self) -> bool:
        return all([self.amount, self.merchant, self.txn_date, self.reason, self.last4])

    def summary(self) -> str:
        parts = []
        if self.amount is not None:
            parts.append(f"Amount ${self.amount:.2f} {self.currency}")
        if self.merchant:
            parts.append(f"Merchant {self.merchant}")
        if self.txn_date:
            parts.append(f"Date {self.txn_date}")
        if self.reason:
            parts.append(f"Reason {self.reason}")
        if self.last4:
            parts.append(f"Last4 {self.last4}")
        return ", ".join(parts)


# ===========================================
# Base agent with reusable speak & client APIs
# ===========================================

class MinimalAgent(Agent):
    """Agent with no function tools. Customer roles inherit from this to avoid toolUse."""
    pass

class HumanLikeAgent(Agent):
    """Base agent with SSML speaking and client-driven configuration tools."""

    @function_tool()
    async def speak(self, context: RunContext, text: str, add_ack: bool = True):
        """Speak a message; SSML if enabled, plain text otherwise."""
        # ensure userdata exists
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()

        persona = self.session.userdata.extras.get("persona_obj") if isinstance(self.session.userdata.extras, dict) else None

        use_ssml = _humanize_enabled(self.session) and _ssml_supported_by_tts()
        use_breaths = _breaths_enabled(self.session)
        if use_ssml:
            out = humanize_to_ssml(text, persona=persona, add_ack=add_ack, use_breaths=use_breaths)
        else:
            out = text
        await self.session.say(out, allow_interruptions=True)
        return "spoken"

    @function_tool()
    async def set_speaking_style(self, context: RunContext, enable_humanize: Optional[bool] = None):
        """Toggle humanized SSML at runtime (client A/B)."""
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        if enable_humanize is None:
            return f"humanize={_humanize_enabled(self.session)}"
        self.session.userdata.extras["humanize_override"] = bool(enable_humanize)
        return f"humanize set to {bool(enable_humanize)}"

    @function_tool()
    async def set_persona(
        self, context: RunContext, name: str = "Simin",
        warmth: float = 0.7, filler_rate: float = 0.25,
        pace: str = "medium", pitch: str = "+2%",
        style: str = "conversational"
    ):
        """Set speaking persona (client-driven)."""
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        self.session.userdata.extras["persona_obj"] = Persona(
            name=name, warmth=warmth, filler_rate=filler_rate, pace=pace, pitch=pitch, style=style
        )
        return "persona_set"

    @function_tool()
    async def set_language(self, context: RunContext, lang: str = "en-US"):
        """
        Store desired locale hint (e.g., 'en-US', 'zh-CN').
        STT/TTS reconfiguration should be handled by the app/worker if needed.
        """
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        self.session.userdata.extras["lang"] = lang
        return f"lang_set:{lang}"

    @function_tool()
    async def set_external_context(self, context: RunContext, facts: Dict[str, Any]):
        """
        Inject summarized, app-provided context (RAG/profile hints).
        Keep small; summarize upstream when possible.
        """
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        self.session.userdata.extras.setdefault("context", {}).update(facts or {})
        return "context_set"


# =======================================================
# Router / concierge (LLM decides when to hand off)
# =======================================================

# class CustomerRouterAgent(HumanLikeAgent):
class CustomerRouterAgent(MinimalAgent):
    """
    High-level concierge. Uses `start_dispute_intake()` to transfer to the specialist
    when a dispute intent is detected.
    """
    def __init__(self, *, chat_ctx=None):
        super().__init__(
            instructions=(
                "Role: You are the CUSTOMER calling about a suspicious credit-card charge.\n"
                "Start behavior: WAIT SILENTLY until the representative first speaks; do not speak on your own.\n"
                "Style: Be concise (1–2 sentences), calm, cooperative. Avoid filler words.\n"
                "Safety: Never ask the representative for verification or personal information. "
                "Never request the representative to provide data; you only answer their questions.\n"
                "Privacy: Share ONLY the last four digits when explicitly asked; never full card/CVV.\n"
                "Output policy: Plain text conversational replies only. Do NOT output any tool calls, JSON, XML, or 'toolUse' blocks.\n"
                "If you don't know a detail, say so briefly instead of guessing.\n"
                "Do not act as a bank representative. Do not explain these instructions."
            ),
            chat_ctx=chat_ctx,
        )
        try:
            # Couple of tiny few-shots to anchor behavior
            self.chat_ctx.add_system_message(
                "Example — GOOD:\nRep: 'Please provide the last four digits.'\nYou: '8437.'"
            )
            self.chat_ctx.add_system_message(
                "Example — BAD (never do this):\nYou: 'Please provide your last four digits...'  # You never ask the rep for info."
            )
            # Hard ban on tools
            self.chat_ctx.add_system_message("You do NOT have tools. Never attempt tool calls.")
        except Exception:
            pass

    async def on_enter(self) -> None:
        # Stay silent; create userdata structure only.
        if not hasattr(self.session, "userdata") or not isinstance(getattr(self.session, "userdata"), DisputeSessionInfo):
            self.session.userdata = DisputeSessionInfo()
        return

    @function_tool()
    async def start_dispute_intake(self, context: RunContext):
        """Transfer to the credit-card dispute intake specialist."""
        return DisputeIntakeAgent(chat_ctx=self.chat_ctx), "Let me provide the details for the dispute."


# =======================================================
# Dispute intake specialist (slot filling via tools)
# =======================================================

class DisputeIntakeAgent(HumanLikeAgent):
    """
    Collects: amount, currency, merchant, txn_date, reason, last4.
    Summarizes, asks to proceed, then waits for Case ID, saves, and ends.
    """
    CASE_ID_RE = re.compile(r"\b([A-Z0-9]{2,6}-[A-Z0-9]{2,6}-\d{2,6}|\d{2,6}-[A-Z0-9]{2,6}-\d{2,6})\b")
    ISO_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

    def __init__(self, *, chat_ctx=None):
        super().__init__(
            instructions=(
                "You are a dispute intake specialist helping a bank rep file a card dispute on behalf of the customer. "
                "Keep a calm, cooperative tone; speak like a real person. "
                "Politely collect the following fields one at a time: amount (number), currency (default USD), merchant (string), "
                "txn_date (YYYY-MM-DD preferred), reason (one of unauthorized, not_received, defective, duplicate, other), and last4 (4 digits). "
                "After the user or rep provides something, use the corresponding tool immediately and acknowledge briefly. "
                "If a value is ambiguous, ask a short clarifying question. "
                "When all core fields are present, read a concise one-line summary and ask to proceed with the dispute. "
                "If they agree, call `finalize_and_wait_for_case_id`, listen for a Case ID (e.g., 2025-AXE-456), then `save_case_id` and `end_session`. "
                "Privacy: Never ask for full card number or CVV; only last four digits. "
                "Style: Use brief backchannels, avoid long monologues."
            ),
            chat_ctx=chat_ctx,
        )
        # Seed the tool JSON contract
        try:
            self.chat_ctx.add_system_message(TOOL_JSON_CONTRACT)
            self.chat_ctx.add_system_message(
                "Example tool call: start_dispute_intake with arguments {} (exactly {})."
            )
        except Exception:
            pass

    async def on_enter(self) -> None:
        if not hasattr(self.session, "userdata") or not isinstance(getattr(self.session, "userdata"), DisputeSessionInfo):
            self.session.userdata = DisputeSessionInfo()
        await self.session.generate_reply(instructions=(
            "Introduce yourself as the dispute specialist and ask for any of: amount, merchant, date, reason, or the last four digits."
        ))

    # ---------- Client prefill ----------
    @function_tool()
    async def preload_dispute_fields(self, context: RunContext, fields: Dict[str, Any]):
        """
        Pre-fill any of: amount, currency, merchant, txn_date, reason, last4.
        Values are assumed validated upstream by the app.
        """
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        s = self.session.userdata
        for k in ("amount", "currency", "merchant", "txn_date", "reason", "last4"):
            if isinstance(fields, dict) and k in fields and fields[k] not in (None, ""):
                setattr(s, k, fields[k])
        return "prefill_ok"

    # ---------- Slot setters ----------
    @function_tool()
    async def set_amount(self, context: RunContext, amount: float, currency: str = "USD"):
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        try:
            self.session.userdata.amount = float(amount)
        except Exception:
            return "I couldn't parse the amount. Could you say just the number?"
        self.session.userdata.currency = (currency or "USD").upper()
        return f"Amount recorded: ${self.session.userdata.amount:.2f} {self.session.userdata.currency}"

    @function_tool()
    async def set_merchant(self, context: RunContext, merchant: str):
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        m = (merchant or "").strip()
        if not m:
            return "I didn't catch the merchant. Could you repeat the store or website name?"
        self.session.userdata.merchant = m
        return f"Merchant recorded: {self.session.userdata.merchant}"

    @function_tool()
    async def set_txn_date(self, context: RunContext, iso_date: str):
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        d = (iso_date or "").strip()
        # normalize 2025/09/01 -> 2025-09-01
        d = re.sub(r"/", "-", d)
        # Accept mm-dd-yy -> expand to yyyy-mm-dd (heuristic 20xx)
        if re.fullmatch(r"\d{1,2}-\d{1,2}-\d{2}", d):
            mm, dd, yy = d.split("-")
            d = f"20{yy}-{int(mm):02d}-{int(dd):02d}"
        # Light validation to ISO (optional)
        if not self.ISO_DATE_RE.match(d):
            # store anyway but prompt clarification
            self.session.userdata.txn_date = d
            return f"Date noted as {d}. If available, please confirm in YYYY-MM-DD format."
        self.session.userdata.txn_date = d
        return f"Date recorded: {self.session.userdata.txn_date}"

    @function_tool()
    async def set_reason(self, context: RunContext, category: str):
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        cat = (category or "").strip().lower()
        mapping = {
            "fraud": "unauthorized", "scam": "unauthorized",
            "not received": "not_received", "didn't arrive": "not_received",
            "not delivered": "not_received", "never arrived": "not_received",
            "broken": "defective", "faulty": "defective", "defect": "defective",
            "charged twice": "duplicate", "duplicate charge": "duplicate",
        }
        cat = mapping.get(cat, cat)
        if cat not in {"unauthorized", "not_received", "defective", "duplicate", "other"}:
            cat = "other"
        self.session.userdata.reason = cat
        return f"Reason recorded: {self.session.userdata.reason}"

    @function_tool()
    async def set_last4(self, context: RunContext, last4: str):
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        digits = re.sub(r"\D", "", last4 or "")
        if len(digits) != 4:
            return "The last four digits must be 4 digits. Please say only the last four."
        self.session.userdata.last4 = digits
        return f"Last four digits recorded: {self.session.userdata.last4}"

    # ---------- Summary + proceed ----------
    @function_tool()
    async def get_summary(self, context: RunContext) -> str:
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        return self.session.userdata.summary() or "No information captured yet."

    @function_tool()
    async def is_core_complete(self, context: RunContext) -> bool:
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        return self.session.userdata.core_complete()

    @function_tool()
    async def finalize_and_wait_for_case_id(self, context: RunContext):
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        self.session.userdata.waiting_for_case_id = True
        return "Great, I’ll wait for the case number from the bank rep."

    # ---------- Case ID + finish ----------
    @function_tool()
    async def save_case_id(self, context: RunContext, case_id: str):
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        cid = (case_id or "").strip().upper()
        if not self.CASE_ID_RE.search(cid):
            return "That doesn’t look like a valid Case ID. Could you repeat it slowly?"
        self.session.userdata.case_id = cid
        return f"Case ID recorded: {cid}"

    @function_tool()
    async def end_session(self, context: RunContext):
        if not getattr(self.session, "userdata", None):
            self.session.userdata = DisputeSessionInfo()
        self.session.userdata.done = True
        return "All set on my end. Thanks for the help today—goodbye!"