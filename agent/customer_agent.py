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
        # Load initial profile, but note that bootstrap payload will overwrite dispute data
        self._load_bootstrap_profile()
        log.info("🔍 Agent initialized. Initial dispute: merchant=%s, amount=%s, last4=%s", 
                 self.dispute.merchant, self.dispute.amount, self.dispute.last4)
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
            dynamic_payload = self._load_dynamic_payload()
            if dynamic_payload:
                self._apply_bootstrap(dynamic_payload)
                log.info("CustomerLLMAgent: loaded dynamic payload from UserData")
                return

        if candidate is None:
            allow_test = os.getenv("ALLOW_TEST_PROFILE", "0").strip().lower() in {"1", "true", "yes"}
            if allow_test:
                p = Path(__file__).with_name("test_profile.json")
                if p.exists():
                    candidate = p

        if candidate is None:
            log.warning(
                "No profile JSON found. Provide PROFILE_JSON, or ensure UserData/profile.json + dispute_*.json, or put test_profile.json next to customer_agent.py"
            )
            return

        try:
            data = json.loads(candidate.read_text(encoding="utf-8"))
            self._apply_bootstrap(data)
            log.info("CustomerLLMAgent: loaded profile from %s", candidate)
        except Exception as e:
            log.exception("Failed to load profile JSON: %s", e)

    def _load_dynamic_payload(self) -> Optional[Dict[str, Any]]:
        user_data_root = self._resolve_user_data_root()
        if user_data_root is None:
            return None

        user_folder = self._resolve_user_folder(user_data_root)
        if user_folder is None:
            return None

        profile_payload = self._load_profile_payload(user_folder)
        dispute_payload = self._load_latest_dispute_payload(user_folder)

        if not profile_payload and not dispute_payload:
            return None

        payload: Dict[str, Any] = {}
        if profile_payload:
            payload["profile"] = profile_payload
        if dispute_payload:
            payload["dispute"] = dispute_payload
        return payload

    def _resolve_user_data_root(self) -> Optional[Path]:
        explicit_root = os.getenv("VOICE_AGENT_USERDATA_DIR", "").strip()
        if explicit_root:
            root = Path(explicit_root).expanduser()
            if root.exists():
                return root
            log.warning("VOICE_AGENT_USERDATA_DIR not found: %s", root)

        simulator_root = self._find_simulator_user_data_root()
        if simulator_root is not None:
            return simulator_root

        repo_root = Path(__file__).resolve().parents[1]
        repo_user_data = repo_root / "iOS" / "VoiceAgent" / "UserData"
        if self._latest_payload_mtime(repo_user_data) is not None:
            return repo_user_data

        return None

    def _find_simulator_user_data_root(self) -> Optional[Path]:
        simulator_root = Path.home() / "Library" / "Developer" / "CoreSimulator" / "Devices"
        if not simulator_root.exists():
            return None

        user_data_dirs = list(
            simulator_root.glob(
                "*/data/Containers/Data/Application/*/Documents/UserData"
            )
        )
        if not user_data_dirs:
            return None

        candidates = [
            (user_data_dir, self._latest_payload_mtime(user_data_dir))
            for user_data_dir in user_data_dirs
        ]
        candidates = [(path, mtime) for path, mtime in candidates if mtime is not None]
        if not candidates:
            return None

        latest_dir = max(candidates, key=lambda item: item[1])[0]
        log.info("🔍 Using simulator UserData folder: %s", latest_dir)
        return latest_dir

    def _latest_payload_mtime(self, user_data_root: Path) -> Optional[float]:
        if not user_data_root.exists():
            return None

        json_files = [
            p
            for p in user_data_root.rglob("*.json")
            if not p.name.startswith(".")
        ]
        if not json_files:
            return None

        return max(p.stat().st_mtime for p in json_files)

    def _resolve_user_folder(self, user_data_root: Path) -> Optional[Path]:
        preferred_user = os.getenv("VOICE_AGENT_USER", "").strip()
        if preferred_user:
            candidate = user_data_root / preferred_user
            if candidate.exists():
                return candidate
            log.warning("VOICE_AGENT_USER folder not found: %s", candidate)

        user_dirs = [p for p in user_data_root.iterdir() if p.is_dir()]
        if not user_dirs:
            return None

        if len(user_dirs) == 1:
            return user_dirs[0]

        profile_files = [d / "profile.json" for d in user_dirs if (d / "profile.json").exists()]
        if profile_files:
            latest_profile = max(profile_files, key=lambda p: p.stat().st_mtime)
            return latest_profile.parent

        return max(user_dirs, key=lambda p: p.stat().st_mtime)

    def _load_profile_payload(self, user_folder: Path) -> Dict[str, Any]:
        profile_file = user_folder / "profile.json"
        if not profile_file.exists():
            return {}

        data = self._read_json(profile_file)
        if not isinstance(data, dict):
            return {}

        return self._normalize_profile(data)

    def _load_latest_dispute_payload(self, user_folder: Path) -> Dict[str, Any]:
        dispute_files = [
            p
            for p in user_folder.rglob("*.json")
            if p.name != "profile.json" and not p.name.startswith(".")
        ]
        if not dispute_files:
            log.info("🔍 No dispute files found in %s", user_folder)
            return {}

        latest_file = max(dispute_files, key=lambda p: p.stat().st_mtime)
        log.info("🔍 Loading latest dispute file: %s (mtime: %s)", latest_file.name, latest_file.stat().st_mtime)
        data = self._read_json(latest_file)
        if not isinstance(data, dict):
            return {}

        dispute_payload = data.get("dispute") if "dispute" in data else data
        if not isinstance(dispute_payload, dict):
            return {}

        profile_payload = data.get("profile")
        if isinstance(profile_payload, dict):
            normalized_profile = self._normalize_profile(profile_payload)
            if normalized_profile:
                self.profile.first_name = normalized_profile.get("first_name", self.profile.first_name)
                self.profile.last_name = normalized_profile.get("last_name", self.profile.last_name)
                self.profile.email = normalized_profile.get("email", self.profile.email)
                self.profile.address = normalized_profile.get("address", self.profile.address)
                self.profile.phone = normalized_profile.get("phone", self.profile.phone)

        log.info("🔍 Loaded dispute from file: merchant=%s, amount=%s, last4=%s", 
                 dispute_payload.get("merchant", ""), dispute_payload.get("amount", 0), 
                 dispute_payload.get("last4", ""))
        return dispute_payload

    def _normalize_profile(self, data: Dict[str, Any]) -> Dict[str, Any]:
        profile = data.get("profile") if "profile" in data else data
        if not isinstance(profile, dict):
            return {}

        return {
            "first_name": profile.get("first_name") or profile.get("firstName") or "",
            "last_name": profile.get("last_name") or profile.get("lastName") or "",
            "email": profile.get("email") or "",
            "address": profile.get("address") or "",
            "phone": profile.get("phone") or profile.get("phoneNumber") or "",
        }

    @staticmethod
    def _read_json(path: Path) -> Optional[Dict[str, Any]]:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception as e:
            log.warning("Failed to read JSON %s: %s", path, e)
            return None

    def _apply_bootstrap(self, data: Dict[str, Any]) -> None:
        prof = self._normalize_profile(data)
        disp = self._normalize_dispute(data)

        if prof:
            self.profile.first_name = str(prof.get("first_name", "") or "")
            self.profile.last_name = str(prof.get("last_name", "") or "")
            self.profile.email = str(prof.get("email", "") or "")
            self.profile.address = str(prof.get("address", "") or "")
            self.profile.phone = str(prof.get("phone", "") or "")

        if disp:
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

    def apply_runtime_payload(self, data: Dict[str, Any]) -> None:
        log.info("🔄 Applying runtime payload")
        log.info("🔄 Payload structure: %s", json.dumps(data, indent=2, default=str))
        log.info("🔄 BEFORE apply: merchant=%s, amount=%s, last4=%s", 
                 self.dispute.merchant, self.dispute.amount, self.dispute.last4)
        self._apply_bootstrap(data)
        log.info("✅ AFTER apply: merchant=%s, amount=%s, currency=%s, last4=%s, reason=%s", 
                 self.dispute.merchant, self.dispute.amount, self.dispute.currency, 
                 self.dispute.last4, self.dispute.reason[:50] if self.dispute.reason else "")

    def resolve_tool_value_sync(self, name: str) -> Optional[str]:
        """
        Synchronous version of resolve_tool_value for use in sync contexts.
        """
        log.info("🔍 Resolving tool (sync): %s (merchant=%s, amount=%s)", name, self.dispute.merchant, self.dispute.amount)
        values = {
            "get_full_name": self._as_sentence("full_name", self.profile.full_name),
            "get_first_name": self._as_sentence("first_name", self.profile.first_name),
            "get_last_name": self._as_sentence("last_name", self.profile.last_name),
            "get_email": self._as_sentence("email", self.profile.email),
            "get_address": self._as_sentence("address", self.profile.address),
            "get_phone": self._as_sentence("phone", self.profile.phone),
            "get_last4": self._as_sentence("last4", self.dispute.last4),
            "get_txn_date": self._as_sentence("txn_date", self.dispute.txn_date),
            "get_amount": self._as_sentence(
                "amount",
                f"{self.dispute.amount:.2f}" if self.dispute.amount is not None and self.dispute.amount > 0 else "",
            ),
            "get_currency": self._as_sentence("currency", self.dispute.currency),
            "get_merchant": self._as_sentence("merchant", self.dispute.merchant),
            "get_reason": self._as_sentence("reason", self.dispute.reason),
            "get_summary": self._as_sentence("summary", self.dispute.summary),
        }
        result = values.get(name)
        if result:
            log.info("✅ Tool %s resolved to (sync): %s", name, result[:100])
        else:
            log.warning("⚠️ Tool %s not found in resolver map", name)
        return result

    async def resolve_tool_value(self, name: str) -> Optional[str]:
        """
        Resolve tool values directly without invoking the LiveKit tool wrapper.
        Used by RoomIO when the model emits tool tags as plain text.
        """
        # Delegate to sync version since we don't do any async work
        return self.resolve_tool_value_sync(name)

    def _normalize_dispute(self, data: Dict[str, Any]) -> Dict[str, Any]:
        dispute = data.get("dispute") if "dispute" in data else data
        if not isinstance(dispute, dict):
            log.warning("⚠️ _normalize_dispute: dispute is not a dict, got: %r", type(dispute))
            return {}

        # Handle both snake_case (from JSON encoding) and camelCase (direct dict access)
        # Also check top-level keys in case dispute data is at root level
        # iOS sends JSON with CodingKeys, so it should be snake_case, but handle both
        normalized = {
            "summary": dispute.get("summary") or data.get("summary") or "",
            "amount": dispute.get("amount") or data.get("amount") or 0.0,
            "currency": dispute.get("currency") or data.get("currency") or "USD",
            "merchant": dispute.get("merchant") or dispute.get("merchantName") or data.get("merchant") or data.get("Merchant") or "",
            "txn_date": dispute.get("txn_date") or dispute.get("txnDate") or data.get("txn_date") or data.get("txnDate") or "",
            "reason": dispute.get("reason") or data.get("reason") or data.get("Reason") or "",
            "last4": dispute.get("last4") or dispute.get("lastFour") or data.get("last4") or data.get("Last4") or "",
        }
        log.info("🔍 _normalize_dispute: input keys=%s, result merchant=%s, amount=%s, last4=%s", 
                 list(dispute.keys()) if isinstance(dispute, dict) else "N/A",
                 normalized["merchant"], normalized["amount"], normalized["last4"])
        return normalized

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
