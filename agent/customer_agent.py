from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

from livekit.agents import Agent, RunContext, function_tool

log = logging.getLogger(__name__)
if not log.handlers:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )


@dataclass
class Profile:
    first_name: str = ""
    last_name: str = ""
    email: str = ""
    address: str = ""
    phone: str = ""

    @property
    def full_name(self) -> str:
        f = (self.first_name or "").strip()
        l = (self.last_name or "").strip()
        if f and l:
            return f"{f} {l}"
        return f or l or ""


@dataclass
class Dispute:
    last4: str = ""
    txn_date: str = ""
    amount: float = 0.0
    currency: str = "USD"
    merchant: str = ""
    reason: str = ""
    summary: str = ""


class CustomerLLMAgent(Agent):
    """
    Persona that acts as the CUSTOMER (cardholder).
    Exposes zero-argument tools so tool calls never need JSON arguments.
    """

    def __init__(self) -> None:
        super().__init__(instructions=self._system_prompt())
        self.profile: Profile = Profile()
        self.dispute: Dispute = Dispute()
        self._load_bootstrap_profile()
        self._did_opening_line = False

    def _system_prompt(self) -> str:
        return (
            "ROLE:\n"
            "- You are the CUSTOMER (cardholder). You never act as bank staff.\n"
            "- You never say you are an AI. You speak in first person as the caller.\n\n"
            "ALLOWED BEHAVIOR:\n"
            "- Answer ONLY what the bank asks. If the bank doesn't ask a question, keep replies minimal.\n"
            "- Do NOT ask follow-up questions. Do NOT guide the process. Do NOT say you'll proceed, open tickets, or take actions.\n"
            "- When the bank asks for identity or dispute info, call the EXACT zero-argument tool and return ONLY that value as a short sentence.\n"
            "- If a requested item is missing, say: \"I don't have that on file.\" DO NOT invent.\n\n"
            "STRICT OUTPUT RULES:\n"
            "1) Never ask questions. (No question marks.)\n"
            "2) Never use bank-rep phrasing like: \"Could you provide\", \"I'll proceed\", \"I will now\", \"let me\", \"we can\", \"I'll process\".\n"
            "3) Keep answers to ONE short sentence.\n"
            "4) Never add extra commentary after answering a request.\n\n"
            "TOOLS YOU MAY CALL (no arguments):\n"
            "- get_full_name, get_first_name, get_last_name, get_email, get_address, get_phone\n"
            "- get_last4, get_txn_date, get_amount, get_currency, get_merchant, get_reason, get_summary\n\n"
            "EXAMPLES (obey strictly):\n"
            "Bank: \"Hello, how can I help you?\"\n"
            "You: \"Hi, I'm calling about a charge I don't recognize on my credit card.\"\n"
            "(Then wait. Do NOT ask any questions.)\n\n"
            "Bank: \"May I have your last and first name, please?\"\n"
            "You: (call get_last_name, get_first_name) Return two short sentences, each with the value.\n"
            "OK: \"My last name is Wang. My first name is Simin.\"\n"
            "NOT OK: \"Could you also confirm your email?\" (You must never ask.)\n\n"
            "Bank: \"What's the merchant and amount?\"\n"
            "You: (call get_merchant, get_amount) e.g., \"The merchant is BestBuy. The amount is $150.00.\"\n"
        )

    # ------------------------
    # Bootstrap profile loading
    # ------------------------
    def _load_bootstrap_profile(self) -> None:
        profile_path = os.getenv("PROFILE_JSON", "").strip()
        candidate: Optional[Path] = None

        if profile_path:
            p = Path(profile_path)
            if p.exists():
                candidate = p
            else:
                log.warning("PROFILE_JSON path not found: %s", p)

        if candidate is None:
            p = Path(__file__).with_name("test_profile.json")
            if p.exists():
                candidate = p

        if candidate is None:
            log.warning(
                "No profile JSON found. Provide PROFILE_JSON or put test_profile.json next to customer_agent.py"
            )
            return

        try:
            data = json.loads(candidate.read_text(encoding="utf-8"))
            self._apply_bootstrap(data)
            log.info("CustomerLLMAgent: loaded profile from %s", candidate)
        except Exception as e:
            log.exception("Failed to load profile JSON: %s", e)

    def _apply_bootstrap(self, data: Dict[str, Any]) -> None:
        prof = data.get("profile") or {}
        disp = data.get("dispute") or {}

        self.profile.first_name = str(prof.get("first_name", "") or "")
        self.profile.last_name = str(prof.get("last_name", "") or "")
        self.profile.email = str(prof.get("email", "") or "")
        self.profile.address = str(prof.get("address", "") or "")
        self.profile.phone = str(prof.get("phone", "") or "")

        self.dispute.last4 = str(disp.get("last4", "") or "")
        self.dispute.txn_date = str(disp.get("txn_date", "") or "")

        try:
            amt = disp.get("amount", 0.0)
            self.dispute.amount = float(amt) if amt is not None else 0.0
        except Exception:
            self.dispute.amount = 0.0

        self.dispute.currency = str(disp.get("currency", "USD") or "USD")
        self.dispute.merchant = str(disp.get("merchant", "") or "")
        self.dispute.reason = str(disp.get("reason", "") or "")
        self.dispute.summary = str(disp.get("summary", "") or "")

    # -------------------------
    # Helper: sentence rendering
    # -------------------------
    @staticmethod
    def _as_sentence(key: str, value: str) -> str:
        if not value:
            return "I don't have that on file."
        labels = {
            "email": "email address",
            "last4": "last four digits",
            "txn_date": "transaction date",
            "full_name": "full name",
            "first_name": "first name",
            "last_name": "last name",
        }
        label = labels.get(key, key.replace("_", " "))
        return f"My {label} is {value}."

    # -----------------
    # Zero-arg getters
    # -----------------
    @function_tool
    async def get_full_name(self) -> str:
        return self._as_sentence("full_name", self.profile.full_name)

    @function_tool
    async def get_first_name(self) -> str:
        return self._as_sentence("first_name", self.profile.first_name)

    @function_tool
    async def get_last_name(self) -> str:
        return self._as_sentence("last_name", self.profile.last_name)

    @function_tool
    async def get_email(self) -> str:
        return self._as_sentence("email", self.profile.email)

    @function_tool
    async def get_address(self) -> str:
        return self._as_sentence("address", self.profile.address)

    @function_tool
    async def get_phone(self) -> str:
        return self._as_sentence("phone", self.profile.phone)

    @function_tool
    async def get_last4(self) -> str:
        return self._as_sentence("last4", self.dispute.last4)

    @function_tool
    async def get_txn_date(self) -> str:
        return self._as_sentence("txn_date", self.dispute.txn_date)

    @function_tool
    async def get_amount(self) -> str:
        # Format nicely; if amount is 0 but genuinely missing you should store None in JSON instead.
        val = f"{self.dispute.amount:.2f}" if self.dispute.amount is not None else ""
        return self._as_sentence("amount", val)

    @function_tool
    async def get_currency(self) -> str:
        return self._as_sentence("currency", self.dispute.currency)

    @function_tool
    async def get_merchant(self) -> str:
        return self._as_sentence("merchant", self.dispute.merchant)

    @function_tool
    async def get_reason(self) -> str:
        return self._as_sentence("reason", self.dispute.reason)

    @function_tool
    async def get_summary(self) -> str:
        return self._as_sentence("summary", self.dispute.summary)

    # Optional updater tool
    @function_tool
    async def start_dispute_intake(self) -> str:
        return "intake_started"

    async def on_start(self, ctx: Optional[RunContext] = None) -> None:
        # Keep empty for maximum compatibility across SDK versions.
        # (If you later want a single proactive opening line, we can add it once we confirm the correct API hook.)
        pass

    async def on_stop(self, ctx: Optional[RunContext] = None) -> None:
        pass