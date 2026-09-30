from __future__ import annotations

import json
import os
import secrets
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import re
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, Property, QSettings, QTimer, QUrl, Signal, Slot, Qt, QEvent
from PySide6.QtGui import QDesktopServices, QGuiApplication, QWindow, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication
from boot_splash import BootSplash

INTEGRATION_VERSION = "0.30.20"
LIVE_COMMANDS = {
    "dock", "launch", "clear", "cancel",
    "combat_mode", "combat_enter", "combat_leave",
    "combat_threat", "combat_powerplant", "combat_best_target", "combat_egress",
    "combat_toggle_pips", "combat_toggle_subsystem",
    "combat_res_high", "combat_res_haz", "combat_res_plot",
    "combat_fighter_1", "combat_fighter_2", "combat_fighter_recall",
    "combat_wing_target_1", "combat_wing_target_2", "combat_wing_target_3",
    "combat_navlock_1", "combat_navlock_2", "combat_navlock_3",
    "combat_firegroup_next",
    "trade_buy", "trade_sell", "trade_start", "trade_pause", "trade_config",
    "trade_route_search", "trade_route_use_index", "trade_best_search", "trade_best_use_index", "trade_learn_recent",
    "station_refuel", "station_repair", "station_rearm",
}
APP_VERSION = "1.0"

NAV_COMMANDS = {"nav_plot", "nav_memory_plot", "nav_memory_set", "nav_memory_capture"}
ELITE_INPUT_COMMANDS = {
    "dock", "launch", "clear",
    "nav_plot", "nav_memory_plot",
    "combat_mode", "combat_enter", "combat_leave", "combat_threat",
    "combat_powerplant", "combat_best_target", "combat_egress",
    "combat_fighter_1", "combat_fighter_2", "combat_fighter_recall",
    "combat_wing_target_1", "combat_wing_target_2", "combat_wing_target_3",
    "combat_navlock_1", "combat_navlock_2", "combat_navlock_3",
    "combat_firegroup_next", "station_refuel", "station_repair", "station_rearm",
    "trade_buy", "trade_sell", "trade_start",
}
RECORD_COMMANDS = {"save_data", "journal", "diagnostic", "cmdr_refresh"}
AI_VOICE_COMMANDS = {
    "mic_test", "hearing_test", "voice_test", "ptt_map",
    "voice_toggle_input_mode", "voice_cycle_level", "voice_cycle_attention", "voice_set_attention",
    "ai_cycle_tool_mode", "ai_toggle_smart_auto", "ai_toggle_launch_rule",
    "ai_approve", "ai_reject", "clear_rules", "ai_usage_reset", "audio_rescan", "sfx_test", "sfx_reset", "voice_set_tuning",
    "setup_preflight", "setup_binds", "setup_api_key_set", "setup_api_key_verify", "setup_setting",
    "control_bind", "control_bind_row", "control_clear", "control_cancel", "control_copy_hotkey", "control_set_hotkey", "control_restore_hotkeys",
    "ui_cue", "wizard_open", "wizard_close", "wizard_music_start", "wizard_music_stop", "wizard_runtime_gate", "wizard_narrate", "page_help_start", "page_help_stop", "ui_context",
}


def _free_local_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def _string(value: Any, fallback: str = "-") -> str:
    text = str(value if value is not None else "").strip()
    return text if text else fallback


def _screen_native_metrics(screen) -> tuple[int, int, float]:
    """Return physical pixel size plus Qt device-pixel ratio for a screen.

    Qt 6 intentionally reports screen geometry in device-independent pixels when
    Windows display scaling is enabled. Multiplying by devicePixelRatio keeps the
    Display page truthful on 2K/4K/5K panels at 125/150/175/200% scaling.
    """
    if screen is None:
        return (0, 0, 1.0)
    try:
        g = screen.geometry()
        dpr = max(0.5, float(screen.devicePixelRatio()))
        return (max(1, round(g.width() * dpr)), max(1, round(g.height() * dpr)), dpr)
    except Exception:
        return (0, 0, 1.0)


def _frozen_runtime_root() -> Path:
    """Return the folder containing the portable executables."""
    return Path(sys.executable).resolve().parent


def _resource_path(relative: str | Path) -> Path:
    """Resolve source-tree and PyInstaller one-file resources consistently."""
    rel = Path(relative)
    if getattr(sys, "frozen", False):
        bundle_root = Path(getattr(sys, "_MEIPASS", _frozen_runtime_root()))
        return bundle_root / rel
    return Path(__file__).resolve().parent.parent / rel


_SINGLE_INSTANCE_HANDLE = None

def _activate_existing_bridge_window() -> None:
    """Best-effort focus of the already-running Bridge on Windows."""
    if os.name != "nt":
        return
    try:
        import ctypes
        from ctypes import wintypes
        user32 = ctypes.WinDLL("user32", use_last_error=True)
        SW_RESTORE = 9
        found = {"hwnd": None}
        EnumProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def callback(hwnd, _lparam):
            if not user32.IsWindowVisible(hwnd):
                return True
            length = int(user32.GetWindowTextLengthW(hwnd) or 0)
            if length <= 0:
                return True
            buf = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buf, length + 1)
            title = str(buf.value or "")
            if title.startswith("Elite AI Bridge v"):
                found["hwnd"] = hwnd
                return False
            return True
        user32.EnumWindows(EnumProc(callback), 0)
        hwnd = found.get("hwnd")
        if hwnd:
            user32.ShowWindow(hwnd, SW_RESTORE)
            user32.SetForegroundWindow(hwnd)
    except Exception:
        pass

def _claim_single_instance() -> bool:
    """Prevent duplicate QML/backend pairs from fighting over global hotkeys."""
    global _SINGLE_INSTANCE_HANDLE
    if os.name != "nt":
        return True
    try:
        import ctypes
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.CreateMutexW.restype = ctypes.c_void_p
        handle = kernel32.CreateMutexW(None, False, "Local\\EliteAIBridge_SingleInstance")
        if not handle:
            return True
        already_exists = int(ctypes.get_last_error() or 0) == 183
        if already_exists:
            try:
                kernel32.CloseHandle(ctypes.c_void_p(handle))
            except Exception:
                pass
            _activate_existing_bridge_window()
            return False
        _SINGLE_INSTANCE_HANDLE = handle
        return True
    except Exception:
        return True


class BackendProcess:
    """Own the hidden v0.12.95 engine process and its loopback adapter."""

    def __init__(self) -> None:
        self.frozen = bool(getattr(sys, "frozen", False))
        if self.frozen:
            self.package_root = _frozen_runtime_root()
            self.backend_dir = self.package_root / "backend"
            self.host_script = None
            self.backend_executable = self.backend_dir / "EliteAIBridgeBackend.exe"
        else:
            self.package_root = Path(__file__).resolve().parent.parent
            self.backend_dir = self.package_root / "backend"
            self.host_script = self.backend_dir / "backend_host.py"
            self.backend_executable = None
        self.port = _free_local_port()
        self.token = secrets.token_urlsafe(32)
        self.process: subprocess.Popen | None = None
        self._log_handle = None

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def start(self) -> None:
        if self.process is not None:
            return
        if self.frozen:
            if self.backend_executable is None or not self.backend_executable.exists():
                raise FileNotFoundError(
                    "Portable backend executable is missing. Keep the backend folder "
                    "beside EliteAIBridge.exe."
                )
        elif self.host_script is None or not self.host_script.exists():
            raise FileNotFoundError(f"Backend host not found: {self.host_script}")

        local_appdata = Path(os.environ.get("LOCALAPPDATA", str(Path.home())))
        log_dir = local_appdata / "EliteAIBridge"
        log_dir.mkdir(parents=True, exist_ok=True)
        # Beta logging is intentionally lightweight, but the stdout log used to
        # append forever. Rotate at 5 MiB so long-running testers cannot slowly
        # accumulate an unbounded file. Keep one previous segment for support.
        log_path = log_dir / "qml_backend.log"
        log_prev = log_dir / "qml_backend.log.1"
        try:
            if log_path.exists() and log_path.stat().st_size > 5 * 1024 * 1024:
                try:
                    log_prev.unlink(missing_ok=True)
                except TypeError:
                    if log_prev.exists():
                        log_prev.unlink()
                log_path.replace(log_prev)
        except Exception:
            pass
        self._log_handle = log_path.open("a", encoding="utf-8", buffering=1)
        self._log_handle.write(
            f"\n[{datetime.now().isoformat(timespec='seconds')}] Starting QML integration {INTEGRATION_VERSION}\n"
        )

        creationflags = 0
        if os.name == "nt":
            creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

        env = os.environ.copy()
        env["ELITE_AI_BRIDGE_QML_HOST"] = "1"
        if self.frozen:
            command = [
                str(self.backend_executable),
                "--port",
                str(self.port),
                "--token",
                self.token,
            ]
        else:
            command = [
                sys.executable,
                str(self.host_script),
                "--port",
                str(self.port),
                "--token",
                self.token,
            ]
        self.process = subprocess.Popen(
            command,
            cwd=str(self.backend_dir),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=self._log_handle,
            stderr=subprocess.STDOUT,
            creationflags=creationflags,
        )

    def request(self, path: str, method: str = "GET", payload: dict[str, Any] | None = None, timeout: float = 0.85) -> dict[str, Any]:
        data = None
        headers = {"X-Bridge-Token": self.token, "Accept": "application/json"}
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base_url + path, data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read()
        result = json.loads(raw.decode("utf-8") or "{}")
        return result if isinstance(result, dict) else {}

    def grant_foreground_permission(self) -> None:
        """Let the hidden .95 child perform its existing focus_elite() step.

        Windows restricts SetForegroundWindow. A click arrives in the QML process,
        while the proven .95 command handler lives in the child process. Granting
        that child foreground permission preserves .95's own focus/verification
        code without moving keyboard injection into QML.
        """
        if os.name != "nt" or self.process is None or self.process.poll() is not None:
            return
        try:
            import ctypes
            ctypes.windll.user32.AllowSetForegroundWindow(int(self.process.pid))
        except Exception:
            # .95 will still perform and verify its normal focus_elite() attempt.
            pass

    def send_command(self, command: str, **extra: Any) -> dict[str, Any]:
        payload = {"command": command}
        payload.update(extra)
        return self.request("/command", method="POST", payload=payload, timeout=1.0)

    def stop(self) -> None:
        """Gracefully stop the backend, then forcibly reap its whole process tree.

        The Bridge backend may own fallback PowerShell/System.Speech workers. A
        normal Popen.terminate() only terminates the backend Python process on
        Windows, which can leave a child process behind after the GUI closes.
        Always try the application-level /shutdown first, then use taskkill /T
        as the final Windows safety net so no backend Python/voice child survives.
        """
        proc = self.process
        self.process = None
        if proc is None:
            return

        pid = int(getattr(proc, "pid", 0) or 0)
        try:
            if proc.poll() is None:
                try:
                    self.request("/shutdown", method="POST", payload={}, timeout=0.45)
                except Exception:
                    pass
                try:
                    proc.wait(timeout=2.5)
                except subprocess.TimeoutExpired:
                    if os.name == "nt" and pid:
                        try:
                            subprocess.run(
                                ["taskkill", "/PID", str(pid), "/T", "/F"],
                                stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL,
                                timeout=5.0,
                                check=False,
                            )
                        except Exception:
                            pass
                    else:
                        try:
                            proc.terminate()
                        except Exception:
                            pass
                    try:
                        proc.wait(timeout=2.0)
                    except subprocess.TimeoutExpired:
                        try:
                            proc.kill()
                        except Exception:
                            pass
                        try:
                            proc.wait(timeout=1.0)
                        except Exception:
                            pass
        finally:
            if self._log_handle is not None:
                try:
                    self._log_handle.close()
                except Exception:
                    pass
                self._log_handle = None


class BridgeViewModel(QObject):
    stateChanged = Signal()
    pulseChanged = Signal()
    clockChanged = Signal()
    commandRequested = Signal(str)
    snapshotArrived = Signal(object)
    transportError = Signal(str)
    displayChanged = Signal()
    suggestionsArrived = Signal(object, str, int)

    def __init__(self, backend: BackendProcess):
        super().__init__()
        self.backend = backend
        self._started_mono = time.monotonic()
        self._last_snapshot_mono = 0.0
        self._consecutive_errors = 0
        self._poll_inflight = False
        self._shutting_down = False
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="QML-Bridge")
        self._suggest_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="QML-EDSM")
        self._suggestion_serial = 0
        self._nav_system_suggestions: list[str] = []
        self._nav_suggestion_status = "TYPE 3+ CHARACTERS"
        self._pulse = 0.0
        self._clock_text = datetime.now().strftime("%I:%M:%S %p").lstrip("0")
        self._state: dict[str, Any] = self._initial_state()
        self._window = None
        self._settings = QSettings("EliteAIBridge", "QMLFrontend")
        # Hold an optimistic Talk Level selection until the backend echoes it back.
        # The UI polls backend state every 250 ms, so without this guard an in-flight
        # stale snapshot can briefly repaint the old choice before persistence finishes.
        self._pending_voice_attention: str | None = None
        self._pending_voice_attention_deadline = 0.0
        # v0.30.28: application-level keyboard capture. QML focus proved unreliable
        # on the real Windows cockpit, so capture before individual QML items can eat it.
        self._keyboard_capture_action = ""
        self._keyboard_capture_label = ""
        self._keyboard_capture_status = "IDLE"
        # v0.30.35 isolated input-learn diagnostics. These never save or alter bindings.
        self._input_test_mode = ""
        self._input_test_status = "READY // NO BINDINGS WILL BE CHANGED"
        self._input_test_controller_baseline = ""
        self._pending_controller_capture = ""
        self._pending_controller_capture_deadline = 0.0

        self.snapshotArrived.connect(self._apply_snapshot)
        self.transportError.connect(self._apply_transport_error)
        self.suggestionsArrived.connect(self._apply_system_suggestions)

        self.animation_timer = QTimer(self)
        self.animation_timer.timeout.connect(self._tick)
        self.animation_timer.start(70)

        self.clock_timer = QTimer(self)
        self.clock_timer.timeout.connect(self._clock_tick)
        self.clock_timer.start(1000)

        # Refresh Elite display compatibility while Bridge is running.
        # DisplaySettings.xml can change when the pilot switches between
        # Borderless/Windowed and exclusive Fullscreen.
        self.overlay_compat_timer = QTimer(self)
        self.overlay_compat_timer.timeout.connect(self.displayChanged.emit)
        self.overlay_compat_timer.start(750)

        self.poll_timer = QTimer(self)
        self.poll_timer.timeout.connect(self._poll_backend)
        self.poll_timer.start(250)
        QTimer.singleShot(25, self._poll_backend)

    @staticmethod
    def _initial_state() -> dict[str, Any]:
        return {
            "integrationVersion": INTEGRATION_VERSION,
            "backendVersion": "0.12.95",
            "connected": False,
            "eliteTelemetryState": "WAITING",
            "commander": "-",
            "ship": "-",
            "shipName": "",
            "shipModel": "-",
            "system": "-",
            "station": "-",
            "gameState": "STARTING",
            "bridgeState": "STARTING ENGINE",
            "bridgeMessage": "Loading Elite AI Bridge v0.12.95...",
            "bridgeLevel": "info",
            "controlOwner": "NONE",
            "commandFeedbackState": "IDLE",
            "commandFeedbackText": "",
            "commandFeedbackSerial": 0,
            "hullPercent": -1,
            "fuelPercent": -1,
            "shieldState": "UNKNOWN",
            "cargoUsed": 0,
            "cargoCapacity": -1,
            "commanderDossierRows": [],
            "commanderCareerRows": [],
            "commanderRecordRows": [],
            "commanderCargoRows": [],
            "commanderCargoTypeCount": 0,
            "commanderCargoSource": "-",
            "commanderLimpetReserve": 0,
            "commanderStolenCargo": 0,
            "commanderSessionRows": [],
            "commanderHistoryAvailable": False,
            "commanderHistoryNote": "OPTIONAL EDDISCOVERY HISTORY NOT LOADED",
            "commanderCreditsSource": "UNKNOWN",
            "tradeRouteBusy": False,
            "tradeRouteStatus": "READY // SELECT COMMODITY AND SEARCH",
            "tradeRouteRows": [],
            "tradeRouteMaxLs": 10000,
            "tradeBestBusy": False,
            "tradeBestStatus": "READY // FIND THE BEST COMMODITY + LOOP",
            "tradeBestRows": [],
            "tradeCommodity": "-",
            "tradeCommodityOptions": [],
            "tradeConfiguredCargo": 0,
            "tradePlannedCargo": 0,
            "tradeCargoAvailable": -1,
            "tradeLatestBuyUnit": 0,
            "tradeLatestSellUnit": 0,
            "tradeEstimatedProfitCycle": 0,
            "tradeEstimatedRemainingProfit": 0,
            "tradeEstimatedTotalProfit": 0,
            "tradeBuySystem": "-",
            "tradeBuyStation": "-",
            "tradeSellSystem": "-",
            "tradeSellStation": "-",
            "tradeLoopEnabled": False,
            "tradeLoopStatus": "STARTING BRIDGE SYSTEMS",
            "tradeLoopLastAction": "-",
            "tradeMarketStation": "-",
            "tradeMarketSystem": "-",
            "tradeMarketTimestamp": "-",
            "tradeMarketRows": 0,
            "tradeMarketBuy": 0,
            "tradeMarketSell": 0,
            "tradeMarketStock": 0,
            "tradeMarketDemand": 0,
            "tradeLedgerRows": [],
            "tradeRealizedProfit": 0,
            "tradePowerRank": 0,
            "tradePowerMerits": 0,
            "tradeLastMerit": "-",
            "pips": "SYS -   ENG -   WEP -",
            "fsdState": "UNKNOWN",
            "gearState": "UNKNOWN",
            "hardpointsState": "UNKNOWN",
            "systemRows": [
                {"label": "ELITE DATA", "value": "STARTING", "level": "info"},
                {"label": "AI / LUNA", "value": "STARTING", "level": "info"},
                {"label": "VOICE / PTT", "value": "STARTING", "level": "info"},
                {"label": "AUDIO OUTPUT", "value": "STARTING", "level": "info"},
                {"label": "CONTROLLERS", "value": "STARTING", "level": "info"},
                {"label": "ELITE BINDINGS", "value": "STARTING", "level": "info"},
                {"label": "DYNAMIC PIPS", "value": "STARTING", "level": "info"},
                {"label": "STATION SERVICES", "value": "STARTING", "level": "info"},
            ],
            "recentEvents": [],
            "alertLabel": "BRIDGE STARTUP",
            "alertValue": "WAIT",
            "alertDetail": "WAITING FOR ELITE DATA",
            "alertLevel": "info",
            "destination": "NO ROUTE",
            "fsdTarget": "-",
            "routeStatus": "WAITING FOR ELITE DATA",
            "routeJumps": -1,
            "nextStarSystem": "-",
            "nextStarClass": "-",
            "nextStarScoopable": None,
            "nextStarText": "UNKNOWN",
            "voiceMode": "READY",
            "pttStatus": "STARTING",
            "lunaStatus": "STARTING",
            "aiCalls": 0,
            "aiInputTokens": 0,
            "aiOutputTokens": 0,
            "aiEstimatedCost": 0.0,
            "aiUsageCalls": 0,
            "aiUsageInputTokens": 0,
            "aiUsageOutputTokens": 0,
            "aiUsageEstimatedCost": 0.0,
            "aiUsageTranscriptionCalls": 0,
            "aiUsageTranscriptionFailures": 0,
            "aiUsageTranscriptionSeconds": 0.0,
            "aiModel": "gpt-5.6-luna",
            "aiApiConfigured": False,
            "aiApiVerified": False,
            "aiApiVerifyStatus": "NOT CONFIGURED",
            "aiApiVerifyDetail": "",
            "bridgeMode": "CORE",
            "setupApiKeyLast4": "",
            "setupPreflightRows": [],
            "setupReady": False,
            "setupLimited": False,
            "eliteBindingsLive": False,
            "eliteBindingsSource": "not found",
            "eliteControlsReady": False,
            "eliteControlReason": "NO ACTIVE ELITE .BINDS PROFILE",
            "setupControlRows": [],
            "controlCaptureAction": "",
            "controlCaptureStatus": "IDLE",
            "controlConflictModalActive": False,
            "controlConflictModalSerial": 0,
            "controlConflictModalCommand": "",
            "controlConflictModalControl": "",
            "controlConflictModalElite": "",
            "setupEliteBindingRows": [],
            "setupCommanderAddress": "Commander",
            "setupAiContext": "",
            "setupAiContextDefault": "",
            "setupAutoRefuel": False,
            "setupAutoRepair": False,
            "setupAutoRearm": False,
            "setupDynamicPips": False,
            "setupAutoPowerPlant": False,
            "setupAutoChaff": False,
            "setupAutoChaffProfile": "MED",
            "setupAiTradeAuto": True,
            "setupAiMissionAuto": True,
            "setupAiTravelAuto": False,
            "aiCopilotStatus": "STARTING",
            "aiCopilotResponse": "Standing by.",
            "aiToolActivity": "No tools used yet.",
            "aiCommsRows": [],
            "pageHelpActive": False,
            "pageHelpPage": -1,
            "pageHelpStep": -1,
            "pageHelpLabel": "-",
            "pageHelpCompletedSerial": 0,
            "pageHelpCompletedPage": -1,
            "uiPageHintSerial": 0,
            "uiPageHint": -1,
            "uiWorkspaceHint": "",
            "aiToolMode": "Ask Before Acting",
            "aiPendingAction": "NONE",
            "aiPendingActionAvailable": False,
            "aiSafetyLevel": "CLEAR",
            "aiSafetyReason": "No active threat.",
            "aiSmartAutoEnabled": False,
            "aiLaunchRuleEnabled": False,
            "aiSessionRuleCount": 0,
            "aiTranscriptionCalls": 0,
            "aiTranscriptionFailures": 0,
            "aiTranscriptionSeconds": 0.0,
            "voiceInputMode": "PTT",
            "voicePttMapping": "KEYBOARD FALLBACK // CTRL+ALT+SHIFT+V",
            "voiceInputDevice": "System Default",
            "voiceOutputDevice": "System Default",
            "voiceEngineMode": "AUTO",
            "voiceName": "F5",
            "voiceNameOptions": ["M1", "M2", "M3", "M4", "M5", "F1", "F2", "F3", "F4", "F5"],
            "voicePitch": "NORMAL",
            "voicePitchOptions": ["VERY DEEP", "DEEP", "NORMAL", "HIGH"],
            "voiceEffect": "BRIDGE",
            "voiceEffectOptions": ["CLEAN", "BRIDGE", "RADIO", "COMMAND", "SYNTH", "METALLIC", "SHIMMER"],
            "voiceEffectStrength": 35,
            "voiceLevel": "MED",
            "voiceAttentionMode": "IMPORTANT",
            "voiceVolume": 50,
            "voiceSpeed": 1.0,
            "voiceMicLevel": 0.0,
            "voiceInputStatus": "Starting voice input...",
            "voiceLastText": "-",
            "voiceEngineStatus": "STARTING",
            "voiceEngineWarming": True,
            "voiceWarmDurationMs": 0,
            "voiceSfxEnabled": True,
            "voiceStartupAudioEnabled": False,
            "audioInputDevices": ["System Default"],
            "audioOutputDevices": ["System Default"],
            "audioDefaultInput": "System Default",
            "audioDefaultOutput": "System Default",
            "audioSfxVolume": 50,
            "audioSfxRows": [],
            "audioSfxSelectedKey": "startup",
            "audioSfxSelectedLabel": "Startup / Bridge online",
            "audioSfxSelectedFile": "startup.wav",
            "audioSfxSelectedSource": "DEFAULT",
            "audioSfxSelectedEnabled": True,
            "audioSfxStatus": "STARTING",
            "audioLastSound": "-",
            "navArmed": False,
            "navStatus": "WAITING FOR NAVIGATION ENGINE",
            "navDestinationInput": "",
            "navMassLock": "UNKNOWN",
            "navMassLockLevel": "info",
            "navRouteValid": False,
            "navRouteSource": "-",
            "navRouteFileConnected": False,
            "navRouteEntries": [],
            "navFlightPlan": [],
            "navHistory": [],
            "navInSystemTargetVisible": False,
            "navInSystemTargetName": "-",
            "navInSystemTargetKind": "-",
            "navInSystemTargetStationType": "",
            "navInSystemTargetConfirmedStation": False,
            "navHomeSystem": "",
            "navBookmark1System": "",
            "navBookmark2System": "",
            "navMemoryCaptureSystem": "-",
            "navMemoryCaptureSource": "CURRENT SYSTEM",
            "colonizationHasProject": False,
            "colonizationStatus": "NO PROJECT",
            "colonizationSystem": "-",
            "colonizationStation": "-",
            "colonizationMarketId": "-",
            "colonizationProgressPercent": 0.0,
            "colonizationLastUpdate": "-",
            "colonizationLastEvent": "-",
            "colonizationRemainingTotal": 0,
            "colonizationCompleteCount": 0,
            "colonizationIncompleteCount": 0,
            "colonizationRequirementRows": [],
            "colonizationNextCommodity": "-",
            "colonizationNextRemaining": 0,
            "colonizationNextAboard": 0,
            "colonizationNextLoadTarget": 0,
            "colonizationCommodityLoads": 0,
            "colonizationProjectLoads": 0,
            "colonizationContributionTotal": 0,
            "colonizationPaceText": "WAITING FOR CONSTRUCTION DEPOT DATA",
            "colonizationClaimStatus": "-",
            "colonizationClaimSystem": "-",
            "colonizationLogRows": [],
            "colonizationProjectRows": [],
            "colonizationCurrentProjectIndex": -1,
            "colonizationDataSource": "ELITE JOURNAL + SAVED PROJECTS",
            "combatActive": False,
            "combatState": "IDLE",
            "combatStatusRows": [],
            "combatSessionRows": [],
            "combatAlertRows": [],
            "combatThreatWarning": "-",
            "combatScanAlertActive": False,
            "combatScanAlertText": "CLEAR",
            "combatSupportRows": [],
            "combatTargetRows": [],
            "combatThreatHistory": [],
            "combatEventHistory": [],
            "combatTargetPresent": False,
            "combatTargetName": "NO TARGET",
            "combatTargetPilot": "-",
            "combatTargetShip": "-",
            "combatTargetLegal": "-",
            "combatTargetFaction": "-",
            "combatTargetRank": "-",
            "combatTargetHullPercent": -1,
            "combatTargetShieldPercent": -1,
            "combatTargetBounty": "-",
            "combatTargetSubsystem": "-",
            "combatTargetSubsystemPercent": -1,
            "combatTargetScanStage": 0,
            "combatTacticalAdvisory": "COMBAT OBSERVER STARTING",
            "combatUnderAttack": False,
            "combatHudMode": "UNKNOWN",
            "combatFireGroup": "-",
            "combatCollectorUpperBound": 0,
            "combatLimpetReserve": 0,
            "combatStolenCargo": 0,
            "combatCrewWagesTotal": 0,
            "combatCommandStatus": "-",
            "combatEgressStatus": "-",
            "combatDynamicPipsEnabled": False,
            "combatDynamicPipsMode": "OFF",
            "combatDynamicPipsStatus": "-",
            "combatAutoSubsystemEnabled": False,
            "combatAutoSubsystemStatus": "-",
            "combatAutoChaffEnabled": False,
            "combatAutoChaffStatus": "-",
            "combatResStatus": "-",
            "combatResBusy": False,
            "combatResRows": [],
            "combatResNearest": "-",
        }

    def _tick(self) -> None:
        self._pulse = (self._pulse + 0.035) % 1.0
        self.pulseChanged.emit()

    def _clock_tick(self) -> None:
        value = datetime.now().strftime("%I:%M:%S %p").lstrip("0")
        if value != self._clock_text:
            self._clock_text = value
            self.clockChanged.emit()

    def _poll_backend(self) -> None:
        if self._shutting_down or self._poll_inflight:
            return
        if self.backend.process is not None and self.backend.process.poll() is not None:
            self._apply_transport_error(f"Backend process exited with code {self.backend.process.returncode}")
            return
        self._poll_inflight = True
        future = self._executor.submit(self.backend.request, "/state")

        def done(fut):
            try:
                snapshot = fut.result()
            except Exception as exc:
                self.transportError.emit(str(exc))
            else:
                self.snapshotArrived.emit(snapshot)
            finally:
                self._poll_inflight = False

        future.add_done_callback(done)

    @Slot(object)
    def _apply_snapshot(self, snapshot: object) -> None:
        if not isinstance(snapshot, dict):
            return

        # setVoiceAttention() updates the UI immediately, while the backend command is
        # delivered asynchronously. A backend poll can therefore return the previous
        # value for one or two frames. Keep the user's latest click authoritative until
        # the backend acknowledges it (or a short timeout expires) so the buttons do not
        # flash back and forth while the setting is being saved.
        snapshot = dict(snapshot)
        pending = self._pending_voice_attention
        if pending:
            incoming = str(snapshot.get("voiceAttentionMode") or "").strip().upper()
            now = time.monotonic()
            if incoming == pending:
                self._pending_voice_attention = None
                self._pending_voice_attention_deadline = 0.0
            elif now < self._pending_voice_attention_deadline:
                snapshot["voiceAttentionMode"] = pending
                snapshot["voiceLevel"] = {"OFF": "LOW", "IMPORTANT": "MED", "MOST": "HIGH"}[pending]
            else:
                # If the backend never acknowledges the selection, stop masking its
                # state so a real save/transport problem remains visible to the pilot.
                self._pending_voice_attention = None
                self._pending_voice_attention_deadline = 0.0

        pending_control = self._pending_controller_capture
        if pending_control:
            incoming_control = str(snapshot.get("controlCaptureAction") or "").strip()
            now = time.monotonic()
            if incoming_control == pending_control:
                # Backend has acknowledged the capture. From here its live state wins.
                self._pending_controller_capture = ""
                self._pending_controller_capture_deadline = 0.0
            elif now < self._pending_controller_capture_deadline:
                snapshot["controlCaptureAction"] = pending_control
                snapshot["controlCaptureStatus"] = "REMAP REQUEST SENT // WAITING FOR CONTROLLER ENGINE"
            else:
                self._pending_controller_capture = ""
                self._pending_controller_capture_deadline = 0.0
                snapshot["controlCaptureStatus"] = "REMAP REQUEST TIMED OUT // BACKEND DID NOT ARM CAPTURE"

        self._state.update(snapshot)
        if self._input_test_mode == "HOTAS":
            raw = str(snapshot.get("controllerLastInput") or "").strip()
            if raw and raw != self._input_test_controller_baseline:
                self._input_test_status = "HOTAS RECEIVED // " + raw
                self._input_test_mode = ""
        self._last_snapshot_mono = time.monotonic()
        self._consecutive_errors = 0
        self.stateChanged.emit()

    @Slot(str)
    def _apply_transport_error(self, message: str) -> None:
        if self._shutting_down:
            return
        self._consecutive_errors += 1
        elapsed = time.monotonic() - self._started_mono
        proc = self.backend.process
        proc_alive = proc is not None and proc.poll() is None

        # A cold first launch can legitimately take substantially longer than a warm
        # restart while the protected .95 engine initializes audio, bindings, journal
        # readers and the HTTP adapter.  Process-alive + no snapshot means STARTING,
        # not OFFLINE.  Only declare a startup failure after a generous 90-second
        # window, or immediately if the backend process actually exits.
        if self._last_snapshot_mono == 0.0 and proc_alive and elapsed < 90.0:
            delayed = elapsed >= 45.0
            self._state.update({
                "connected": False,
                "eliteTelemetryState": "WAITING",
                "bridgeState": "STARTUP DELAYED" if delayed else "STARTING ENGINE",
                "bridgeMessage": "Bridge systems are still starting; connection retries will continue automatically..." if delayed else "Starting Bridge systems...",
                "bridgeLevel": "warn" if delayed else "info",
                "alertLabel": "BRIDGE STARTUP",
                "alertValue": "WAIT",
                "alertDetail": "BRIDGE STARTUP IN PROGRESS // RETRYING AUTOMATICALLY",
                "alertLevel": "warn" if delayed else "info",
            })
        elif self._last_snapshot_mono == 0.0 and proc_alive and elapsed < 120.0:
            self._state.update({
                "connected": False,
                "eliteTelemetryState": "WAITING",
                "bridgeState": "STARTUP DELAYED",
                "bridgeMessage": "Backend initialization is taking unusually long; still retrying automatically...",
                "bridgeLevel": "warn",
                "alertLabel": "BRIDGE STARTUP",
                "alertValue": "DELAYED",
                "alertDetail": "ENGINE PROCESS IS RUNNING // CONNECTION RETRY CONTINUES",
                "alertLevel": "warn",
            })
        elif self._consecutive_errors >= 3:
            self._state.update({
                "connected": False,
                "eliteTelemetryState": "OFFLINE" if not proc_alive else "WAITING",
                "bridgeState": "BRIDGE SYSTEMS OFFLINE",
                "bridgeMessage": _string(message, "Backend connection unavailable"),
                "bridgeLevel": "bad",
                "alertLabel": "BRIDGE LINK",
                "alertValue": "OFFLINE",
                "alertDetail": "BRIDGE SERVICE STOPPED" if not proc_alive else "BRIDGE STARTUP TIMED OUT AFTER 120 SECONDS",
                "alertLevel": "bad",
            })
        self.stateChanged.emit()

    def _set_command_feedback(self, state: str, text: str = "") -> None:
        self._state["commandFeedbackState"] = str(state or "IDLE").upper()
        self._state["commandFeedbackText"] = str(text or "")
        self._state["commandFeedbackSerial"] = int(self._state.get("commandFeedbackSerial", 0) or 0) + 1
        self.stateChanged.emit()

    def _send_command_worker(self, command: str, payload: dict[str, Any] | None = None) -> None:
        cockpit_command = command in ELITE_INPUT_COMMANDS
        label = str(command or "").replace("_", " ").upper()
        if cockpit_command:
            self._set_command_feedback("EXECUTING", label)
        try:
            result = self.backend.send_command(command, **(payload or {}))
            if cockpit_command:
                # Delivery to the authoritative .95 command engine completed.
                # We deliberately do not claim an in-game outcome that telemetry
                # has not verified; the backend's normal state remains authoritative.
                ok = not isinstance(result, dict) or bool(result.get("ok", True))
                detail = ""
                if isinstance(result, dict):
                    detail = str(result.get("message") or result.get("status") or "").strip()
                self._set_command_feedback("COMPLETED" if ok else "FAILED", detail or label)
        except Exception as exc:
            if cockpit_command:
                self._set_command_feedback("FAILED", f"{label} // {exc}")
            self.transportError.emit(f"Command {command!r} was not delivered: {exc}")
        finally:
            if cockpit_command:
                # Briefly retain completion/failure so the overlay can display it,
                # then return to normal backend-driven state.
                time.sleep(0.9)
                self._set_command_feedback("IDLE", "")

    def attach_window(self, window) -> None:
        self._window = window
        try:
            window.screenChanged.connect(self._screen_changed)
        except Exception:
            pass

    def _screen_key(self, screen) -> str:
        if screen is None:
            return ""
        try:
            g = screen.geometry()
            return f"{screen.name()}|{g.x()},{g.y()},{g.width()},{g.height()}"
        except Exception:
            return ""

    def _find_saved_screen(self):
        screens = list(QGuiApplication.screens())
        if not screens:
            return None
        saved_key = str(self._settings.value("display/last_screen", "") or "")
        saved_name = saved_key.split("|", 1)[0] if saved_key else ""
        for screen in screens:
            if self._screen_key(screen) == saved_key:
                return screen
        if saved_name:
            for screen in screens:
                if screen.name() == saved_name:
                    return screen
        return QGuiApplication.primaryScreen() or screens[0]

    def _save_screen(self, screen=None) -> None:
        target = screen
        if target is None and self._window is not None:
            target = self._window.screen()
        key = self._screen_key(target)
        if key:
            self._settings.setValue("display/last_screen", key)
            self._settings.sync()
        self.displayChanged.emit()

    def restore_window_monitor(self) -> None:
        if self._window is None:
            return
        target = self._find_saved_screen()
        if target is None:
            return
        try:
            self._window.setScreen(target)
            g = target.availableGeometry()
            self._window.setPosition(g.x(), g.y())
        except Exception:
            pass
        self._save_screen(target)

    @Slot(object)
    def _screen_changed(self, screen) -> None:
        self._save_screen(screen)

    @Slot()
    def cycleMonitor(self) -> None:
        if self._window is None:
            return
        screens = list(QGuiApplication.screens())
        if len(screens) < 2:
            self._save_screen(self._window.screen())
            return
        current = self._window.screen()
        try:
            index = screens.index(current)
        except ValueError:
            index = -1
        target = screens[(index + 1) % len(screens)]
        try:
            was_maximized = self._window.visibility() == QWindow.Visibility.Maximized
            was_fullscreen = self._window.visibility() == QWindow.Visibility.FullScreen
            self._window.showNormal()
            self._window.setScreen(target)
            g = target.availableGeometry()
            self._window.setPosition(g.x(), g.y())
            if was_fullscreen:
                self._window.showFullScreen()
            elif was_maximized:
                self._window.showMaximized()
        finally:
            self._save_screen(target)

    @Property(bool, notify=displayChanged)
    def firstRunSetupCompleted(self) -> bool:
        value = self._settings.value("setup/wizard_completed", False)
        if isinstance(value, bool):
            return value
        return str(value).strip().lower() in {"1", "true", "yes", "on"}

    @Property(bool, notify=displayChanged)
    def firstRunSetupEnabled(self) -> bool:
        # Wizard completion and system readiness are deliberately separate. A pilot
        # can finish onboarding with missing optional/Elite bindings, then repair
        # those later from Setup without being trapped in the wizard every launch.
        if self._settings.contains("setup/show_first_run"):
            value = self._settings.value("setup/show_first_run", True)
            if isinstance(value, bool):
                return value
            return str(value).strip().lower() not in {"0", "false", "no", "off"}
        return not self.firstRunSetupCompleted

    @Slot(bool)
    def setFirstRunSetupEnabled(self, enabled: bool) -> None:
        # This is a user preference, not a readiness gate. Missing bindings remain
        # visible in Setup/preflight, but must never force the wizard back on.
        self._settings.setValue("setup/show_first_run", 1 if bool(enabled) else 0)
        self._settings.sync()
        self.displayChanged.emit()

    @Slot()
    def markFirstRunSetupCompleted(self) -> None:
        self._settings.setValue("setup/wizard_completed", 1)
        self._settings.setValue("setup/show_first_run", 0)
        self._settings.sync()
        self.displayChanged.emit()

    @Property(bool, notify=displayChanged)
    def startupPreflightEnabled(self) -> bool:
        value = self._settings.value("setup/startup_preflight_enabled", False)
        if isinstance(value, bool):
            return value
        return str(value).strip().lower() not in {"0", "false", "no", "off"}

    @Slot(bool)
    def setStartupPreflightEnabled(self, enabled: bool) -> None:
        self._settings.setValue("setup/startup_preflight_enabled", 1 if bool(enabled) else 0)
        self._settings.sync()
        self.displayChanged.emit()

    @Property(bool, notify=displayChanged)
    def gameOverlayEnabled(self) -> bool:
        value = self._settings.value("display/game_overlay_enabled", True)
        if isinstance(value, bool):
            return value
        return str(value).strip().lower() in {"1", "true", "yes", "on"}

    @Slot(bool)
    def setGameOverlayEnabled(self, enabled: bool) -> None:
        self._settings.setValue("display/game_overlay_enabled", 1 if bool(enabled) else 0)
        self._settings.sync()
        self.displayChanged.emit()

    @Property(str, notify=displayChanged)
    def gameOverlayMode(self) -> str:
        value = str(self._settings.value("display/game_overlay_mode", "ACTIVITY_CHAT") or "ACTIVITY_CHAT").upper()
        return value if value in {"ACTIVITY", "ACTIVITY_CHAT", "CHAT"} else "ACTIVITY_CHAT"

    @Slot(str)
    def setGameOverlayMode(self, mode: str) -> None:
        value = str(mode or "ACTIVITY_CHAT").upper()
        if value not in {"ACTIVITY", "ACTIVITY_CHAT", "CHAT"}:
            value = "ACTIVITY_CHAT"
        self._settings.setValue("display/game_overlay_mode", value)
        self._settings.sync()
        self.displayChanged.emit()

    @Property(str, notify=displayChanged)
    def gameOverlayPosition(self) -> str:
        value = str(self._settings.value("display/game_overlay_position", "RIGHT") or "RIGHT").upper()
        return value if value in {"TOP_LEFT", "TOP_CENTER", "TOP_RIGHT", "LEFT", "RIGHT"} else "TOP_CENTER"

    @Slot(str)
    def setGameOverlayPosition(self, position: str) -> None:
        value = str(position or "RIGHT").upper()
        if value not in {"TOP_LEFT", "TOP_CENTER", "TOP_RIGHT", "LEFT", "RIGHT"}:
            value = "RIGHT"
        self._settings.setValue("display/game_overlay_position", value)
        self._settings.sync()
        self.displayChanged.emit()

    @Property(str, notify=displayChanged)
    def gameOverlaySize(self) -> str:
        value = str(self._settings.value("display/game_overlay_size", "STANDARD") or "STANDARD").upper()
        return value if value in {"SMALL", "STANDARD", "LARGE"} else "STANDARD"

    @Slot(str)
    def setGameOverlaySize(self, size: str) -> None:
        value = str(size or "STANDARD").upper()
        if value not in {"SMALL", "STANDARD", "LARGE"}: value = "STANDARD"
        self._settings.setValue("display/game_overlay_size", value); self._settings.sync(); self.displayChanged.emit()

    @Property(str, notify=displayChanged)
    def gameOverlayLayout(self) -> str:
        value = str(self._settings.value("display/game_overlay_layout", "RIGHT") or "RIGHT").upper()
        return value if value in {"TOP", "LEFT", "RIGHT"} else "TOP"

    @Slot(str)
    def setGameOverlayLayout(self, layout: str) -> None:
        value = str(layout or "RIGHT").upper()
        if value not in {"TOP", "LEFT", "RIGHT"}: value = "RIGHT"
        self._settings.setValue("display/game_overlay_layout", value); self._settings.sync(); self.displayChanged.emit()

    @Property(int, notify=displayChanged)
    def gameOverlayOpacity(self) -> int:
        try: return max(25, min(100, int(self._settings.value("display/game_overlay_opacity", 75))))
        except Exception: return 75

    @Slot(int)
    def setGameOverlayOpacity(self, value: int) -> None:
        self._settings.setValue("display/game_overlay_opacity", max(25, min(100, int(value)))); self._settings.sync(); self.displayChanged.emit()

    @Property(str, notify=displayChanged)
    def eliteOverlayCompatibility(self) -> str:
        # Elite stores the selected presentation mode in DisplaySettings.xml.
        # Treat missing/unreadable config as UNKNOWN rather than falsely warning.
        try:
            cfg = Path(os.environ.get("LOCALAPPDATA", "")) / "Frontier Developments" / "Elite Dangerous" / "Options" / "Graphics" / "DisplaySettings.xml"
            if not cfg.exists(): return "UNKNOWN"
            text = cfg.read_text(encoding="utf-8", errors="ignore")
            def val(tag):
                m = re.search(r"<"+tag+r">\s*([^<]+)\s*</"+tag+r">", text, re.I)
                return m.group(1).strip().lower() if m else ""
            borderless = val("Borderless")
            fullscreen = val("FullScreen")
            if borderless in {"1","true","yes"}: return "READY // BORDERLESS"
            if fullscreen in {"1","true","yes"}: return "CAUTION // ELITE FULLSCREEN DETECTED"
            return "READY // WINDOWED"
        except Exception:
            return "UNKNOWN"

    @Property(bool, notify=displayChanged)
    def liveOrientationEnabled(self) -> bool:
        value = self._settings.value("setup/live_orientation_enabled", False)
        if isinstance(value, bool):
            return value
        return str(value).strip().lower() not in {"0", "false", "no", "off"}

    @Slot(bool)
    def setLiveOrientationEnabled(self, enabled: bool) -> None:
        requested = bool(enabled)
        self._settings.setValue("setup/live_orientation_enabled", 1 if requested else 0)
        self._settings.sync()
        self.displayChanged.emit()

    @Property(bool, notify=displayChanged)
    def liveOrientationCompleted(self) -> bool:
        value = self._settings.value("setup/live_orientation_completed", False)
        if isinstance(value, bool):
            return value
        return str(value).strip().lower() in {"1", "true", "yes", "on"}

    @Slot()
    def markLiveOrientationComplete(self) -> None:
        self._settings.setValue("setup/live_orientation_completed", 1)
        self._settings.sync()
        self.displayChanged.emit()

    @Slot()
    def resetLiveOrientationComplete(self) -> None:
        self._settings.setValue("setup/live_orientation_completed", 0)
        self._settings.sync()
        self.displayChanged.emit()

    @Slot(str)
    def copyTextToClipboard(self, value: str) -> None:
        try:
            QGuiApplication.clipboard().setText(str(value or ""))
        except Exception:
            pass

    @Slot(str)
    def playUiCue(self, cue: str) -> None:
        cue = str(cue or "").strip().lower()
        if cue in {"nav", "confirm", "warn"}:
            self._executor.submit(self._send_command_worker, "ui_cue", {"cue": cue})

    @Slot(int)
    def startWizard(self, step: int) -> None:
        step = max(0, min(6, int(step)))
        self._executor.submit(self._send_command_worker, "wizard_open", {"step": step})

    @Slot()
    def stopWizard(self) -> None:
        self._executor.submit(self._send_command_worker, "wizard_close")

    @Slot(int)
    def startPageHelp(self, page: int) -> None:
        try:
            page = max(0, min(10, int(page)))
        except Exception:
            page = 0
        self._executor.submit(self._send_command_worker, "page_help_start", {"page": page})

    @Slot(int, int)
    def startPageHelpFromStep(self, page: int, start_step: int) -> None:
        try:
            page = max(0, min(10, int(page)))
            start_step = max(0, int(start_step))
        except Exception:
            page, start_step = 0, 0
        self._executor.submit(self._send_command_worker, "page_help_start", {"page": page, "start_step": start_step})

    @Slot(int, int, int)
    def startPageHelpSegment(self, page: int, start_step: int, end_step: int) -> None:
        try:
            page = max(0, min(10, int(page)))
            start_step = max(0, int(start_step))
            end_step = max(start_step, int(end_step))
        except Exception:
            page, start_step, end_step = 0, 0, 0
        self._executor.submit(self._send_command_worker, "page_help_start", {"page": page, "start_step": start_step, "end_step": end_step})

    @Slot()
    def announceOrientationStart(self) -> None:
        self._executor.submit(self._send_command_worker, "orientation_intro")

    @Slot()
    def announceOrientationStopped(self) -> None:
        self._executor.submit(self._send_command_worker, "orientation_stopped")

    @Slot()
    def announceOrientationComplete(self) -> None:
        self._executor.submit(self._send_command_worker, "orientation_complete")

    @Slot()
    def stopPageHelp(self) -> None:
        # STOP HELP is an emergency-style local UX action: clear the visible guide
        # immediately and deliver the stop request on its own thread so a queued poll
        # or long-running command can never delay speech cancellation.
        self._state["pageHelpActive"] = False
        self._state["pageHelpStep"] = -1
        self._state["pageHelpLabel"] = "-"
        self.stateChanged.emit()

        def _urgent_stop():
            try:
                self.backend.request("/command", method="POST", payload={"command": "page_help_stop"}, timeout=0.30)
            except Exception as exc:
                self.transportError.emit(f"Page help stop was not delivered: {exc}")

        threading.Thread(target=_urgent_stop, daemon=True, name="QML-PageHelpStop").start()

    @Slot(int, str)
    def setUiContext(self, page: int, workspace: str) -> None:
        try:
            page = max(0, min(10, int(page)))
        except Exception:
            page = 0
        workspace = str(workspace or "main").strip().lower()[:80]
        self._executor.submit(self._send_command_worker, "ui_context", {"page": page, "workspace": workspace})

    @Slot(bool)
    def setWizardAudioActive(self, active: bool) -> None:
        self._executor.submit(self._send_command_worker, "wizard_music_start" if active else "wizard_music_stop")

    @Slot(bool)
    def setWizardRuntimePaused(self, active: bool) -> None:
        self._executor.submit(self._send_command_worker, "wizard_runtime_gate", {"active": bool(active)})

    @Slot()
    def narrateWizardPage1(self) -> None:
        self._executor.submit(self._send_command_worker, "wizard_narrate_page_1")

    @Slot()
    def narrateWizardPage2(self) -> None:
        self._executor.submit(self._send_command_worker, "wizard_narrate_page_2")

    @Slot()
    def narrateWizardPage3(self) -> None:
        self._executor.submit(self._send_command_worker, "wizard_narrate_page_3")

    @Slot()
    def narrateWizardPage4(self) -> None:
        self._executor.submit(self._send_command_worker, "wizard_narrate_page_4")

    @Slot()
    def narrateWizardPage5(self) -> None:
        self._executor.submit(self._send_command_worker, "wizard_narrate_page_5")

    @Slot()
    def narrateWizardPage6(self) -> None:
        self._executor.submit(self._send_command_worker, "wizard_narrate_page_6")

    @Slot()
    def narrateWizardPage7(self) -> None:
        self._executor.submit(self._send_command_worker, "wizard_narrate_page_7")

    @Slot(int)
    def narrateWizardStep(self, step: int) -> None:
        # Compatibility path for older QML only. v0.29.61 uses seven no-argument
        # page commands so the page identity cannot be lost in QVariant/int marshalling.
        step = max(0, min(6, int(step)))
        self._executor.submit(self._send_command_worker, f"wizard_narrate_page_{step + 1}")

    @Slot(str)
    def openExternalHelp(self, target: str) -> None:
        target = str(target or "").strip().lower()
        if target == "chatgpt_api_help":
            prompt = (
                "Show me simple step-by-step instructions for creating an OpenAI API key. "
                "Explain any OpenAI account or API billing setup required, where to create the key, "
                "how to keep it private, and where to check API usage. Once the key is created, tell me "
                "to copy it and paste it into the program I am using. Do not provide programming instructions, "
                "API integration code, application-editing instructions, or ask me to paste the secret key into ChatGPT."
            )
            try:
                QGuiApplication.clipboard().setText(prompt)
            except Exception:
                pass
            # ChatGPT does not currently document a guaranteed external prefill deep-link.
            # Try the common q= form, while keeping the prompt on the clipboard as a
            # reliable fallback if the web UI ignores the query parameter.
            url = "https://chatgpt.com/?q=" + urllib.parse.quote(prompt)
            QDesktopServices.openUrl(QUrl(url))
            return
        urls = {
            "api_keys": "https://platform.openai.com/api-keys",
            "api_billing": "https://platform.openai.com/settings/organization/billing/overview",
            "api_quickstart": "https://developers.openai.com/api/docs/quickstart",
        }
        url = urls.get(target)
        if url:
            QDesktopServices.openUrl(QUrl(url))

    @Slot()
    def openSupportPage(self) -> None:
        """Open the public Elite AI Bridge support page in the user's default browser."""
        QDesktopServices.openUrl(QUrl("https://ko-fi.com/eliteaibridge"))

    @Property(str, notify=displayChanged)
    def activeMonitorLabel(self) -> str:
        screen = self._window.screen() if self._window is not None else self._find_saved_screen()
        if screen is None:
            return "UNKNOWN"
        try:
            width, height, _ = _screen_native_metrics(screen)
            name = screen.name() or "DISPLAY"
            return f"{name}  {width}x{height}"
        except Exception:
            return "DISPLAY"

    @Property(str, notify=displayChanged)
    def activeMonitorName(self) -> str:
        screen = self._window.screen() if self._window is not None else self._find_saved_screen()
        try:
            return (screen.name() or "DISPLAY") if screen is not None else "UNKNOWN"
        except Exception:
            return "DISPLAY"

    @Property(str, notify=displayChanged)
    def activeMonitorResolution(self) -> str:
        screen = self._window.screen() if self._window is not None else self._find_saved_screen()
        try:
            if screen is None:
                return "UNKNOWN"
            width, height, _ = _screen_native_metrics(screen)
            return f"{width} × {height}"
        except Exception:
            return "UNKNOWN"

    @Property(str, notify=displayChanged)
    def activeMonitorDpiScale(self) -> str:
        screen = self._window.screen() if self._window is not None else self._find_saved_screen()
        try:
            if screen is None:
                return "UNKNOWN"
            _, _, dpr = _screen_native_metrics(screen)
            return f"{round(dpr * 100)}%"
        except Exception:
            return "UNKNOWN"

    @Property(str, notify=displayChanged)
    def activeMonitorLogicalResolution(self) -> str:
        screen = self._window.screen() if self._window is not None else self._find_saved_screen()
        try:
            if screen is None:
                return "UNKNOWN"
            g = screen.geometry()
            return f"{g.width()} × {g.height()}"
        except Exception:
            return "UNKNOWN"

    @Property(str, notify=displayChanged)
    def displayMode(self) -> str:
        try:
            if self._window is None:
                return "UNKNOWN"
            vis = self._window.visibility()
            if vis == QWindow.Visibility.FullScreen:
                return "FULLSCREEN"
            if vis == QWindow.Visibility.Maximized:
                return "MAXIMIZED"
            return "WINDOWED"
        except Exception:
            return "UNKNOWN"

    @Property(int, notify=displayChanged)
    def monitorCount(self) -> int:
        return len(QGuiApplication.screens())

    @Slot()
    def maximizeBridge(self) -> None:
        try:
            if self._window is not None:
                self._window.showMaximized()
                self._save_screen(self._window.screen())
        finally:
            self.displayChanged.emit()

    @Slot()
    def toggleFullScreen(self) -> None:
        try:
            if self._window is None:
                return
            if self._window.visibility() == QWindow.Visibility.FullScreen:
                self._window.showMaximized()
            else:
                self._window.showFullScreen()
            self._save_screen(self._window.screen())
        finally:
            self.displayChanged.emit()

    @Slot()
    def resetDisplaySettings(self) -> None:
        try:
            self._settings.remove("display/last_screen")
            self._settings.sync()
            screens = QGuiApplication.screens()
            if self._window is not None and screens:
                screen = QGuiApplication.primaryScreen() or screens[0]
                self._window.setScreen(screen)
                geom = screen.availableGeometry()
                self._window.setPosition(geom.x(), geom.y())
                self._window.showMaximized()
        except Exception:
            pass
        self.displayChanged.emit()

    @Slot(str)
    def requestCommand(self, command: str) -> None:
        command = str(command or "").strip().lower()
        self.commandRequested.emit(command)
        if command in ELITE_INPUT_COMMANDS and not self.eliteControlsReady:
            return
        if command in LIVE_COMMANDS:
            # This call happens on the QML/UI thread that received the click.
            # It grants the child permission to execute .95's existing focus_elite()
            # behavior; QML itself never sends Elite keyboard input.
            self.backend.grant_foreground_permission()
            self._executor.submit(self._send_command_worker, command)
        elif command in RECORD_COMMANDS:
            # Commander record actions are local Bridge operations. They never
            # need cockpit focus or send Elite keypresses.
            self._executor.submit(self._send_command_worker, command)
        elif command in AI_VOICE_COMMANDS:
            # AI/voice settings and tests are Bridge-local.  The locked .95 engine
            # remains authoritative for preferences, capture, TTS and approvals.
            self._executor.submit(self._send_command_worker, command)

    @Slot(str)
    def selectSfxEvent(self, key: str) -> None:
        key = str(key or "").strip().lower()
        if not key:
            return
        self._executor.submit(self._send_command_worker, "sfx_select", {"key": key})

    @Slot(str, bool)
    def setSfxEventEnabled(self, key: str, enabled: bool) -> None:
        key = str(key or "").strip().lower()
        if not key:
            return
        self._executor.submit(self._send_command_worker, "sfx_set_enabled", {"key": key, "enabled": bool(enabled)})

    @Slot(str, str)
    def importSfxFile(self, key: str, fileUrl: str) -> None:
        key = str(key or "").strip().lower()
        if not key:
            return
        value = str(fileUrl or "").strip()
        try:
            local_path = QUrl(value).toLocalFile() if value.lower().startswith("file:") else value
        except Exception:
            local_path = value
        if not local_path:
            return
        self._executor.submit(self._send_command_worker, "sfx_import_path", {"key": key, "path": local_path})

    @Slot(str)
    def testSfxEvent(self, key: str) -> None:
        key = str(key or "").strip().lower()
        if key:
            self._executor.submit(self._send_command_worker, "sfx_test", {"key": key})

    @Slot(str)
    def resetSfxEvent(self, key: str) -> None:
        key = str(key or "").strip().lower()
        if key:
            self._executor.submit(self._send_command_worker, "sfx_reset", {"key": key})

    @Slot(str, int)
    def setAudioLevel(self, bus: str, value: int) -> None:
        bus = str(bus or "").strip().lower()
        try: amount = max(0, min(100, int(value)))
        except Exception: return
        if bus not in {"voice", "sfx"}:
            return
        self._executor.submit(self._send_command_worker, "audio_set_level", {"bus": bus, "value": amount})

    @Slot(str, str)
    def setAudioDevice(self, kind: str, device: str) -> None:
        kind = str(kind or "").strip().lower()
        device = str(device or "System Default").strip() or "System Default"
        if kind not in {"input", "output"}:
            return
        self._executor.submit(self._send_command_worker, "audio_set_device", {"kind": kind, "device": device})

    @Slot(str, str)
    def setVoiceTuning(self, field: str, value: str) -> None:
        field = str(field or "").strip().lower()
        if field not in {"name", "pitch", "effect"}:
            return
        self._executor.submit(self._send_command_worker, "voice_set_tuning", {"field": field, "value": str(value or "")})

    @Slot(str, float)
    def setVoiceTuningNumber(self, field: str, value: float) -> None:
        field = str(field or "").strip().lower()
        if field not in {"effect_strength", "speed"}:
            return
        try:
            amount = float(value)
        except Exception:
            return
        self._executor.submit(self._send_command_worker, "voice_set_tuning", {"field": field, "value": amount})

    @Slot(str)
    def saveApiKey(self, value: str) -> None:
        value = str(value or "").strip()
        if value:
            self._executor.submit(self._send_command_worker, "setup_api_key_set", {"value": value})

    @Slot(str)
    def beginInputLearnTest(self, mode: str) -> None:
        mode = str(mode or "").strip().upper()
        if mode not in {"KEYBOARD", "HOTAS"}:
            return
        self._input_test_mode = mode
        if mode == "HOTAS":
            self._input_test_controller_baseline = str(self._get("controllerLastInput", "") or "").strip()
            self._input_test_status = "HOTAS TEST ARMED // PRESS ONE BUTTON OR HAT // NOTHING WILL BE SAVED"
        else:
            self._input_test_status = "KEYBOARD TEST ARMED // PRESS A KEY COMBINATION // NOTHING WILL BE SAVED"
        self.stateChanged.emit()

    @Slot()
    def cancelInputLearnTest(self) -> None:
        self._input_test_mode = ""
        self._input_test_status = "TEST CANCELLED // NO BINDINGS CHANGED"
        self.stateChanged.emit()

    @Property(str, notify=stateChanged)
    def inputTestMode(self): return self._input_test_mode

    @Property(str, notify=stateChanged)
    def inputTestStatus(self): return self._input_test_status

    def _control_row_identity(self, row_index: int):
        rows = list(self._get("setupControlRows", []) or [])
        try:
            row = rows[int(row_index)]
        except Exception:
            return "", ""
        if not isinstance(row, dict):
            return "", ""
        # Resolve identity in Python. QML never supplies/saves the command id.
        action = str(row.get("id") or row.get("commandId") or "").strip()
        label = str(row.get("label") or action or "").strip()
        return action, label

    @Slot(int)
    def beginBridgeHotkeyCaptureRow(self, row_index: int) -> None:
        action, label = self._control_row_identity(row_index)
        self.beginBridgeHotkeyCapture(action, label)

    @Slot(int)
    def bindBridgeControlRow(self, row_index: int) -> None:
        try:
            row_index = int(row_index)
        except Exception:
            row_index = -1
        self._state["controlCaptureStatus"] = f"REMAP CLICKED // ROW {row_index} // BACKEND RESOLVING COMMAND"
        self.stateChanged.emit()
        self._executor.submit(self._send_command_worker, "control_bind_row", {"row_index": row_index})

    @Slot(int)
    def beginBridgeHotkeyCaptureRowSafe(self, row_index: int) -> None:
        try:
            row_index = int(row_index)
        except Exception:
            row_index = -1
        rows = list(self._get("setupControlRows", []) or [])
        if not (0 <= row_index < len(rows)):
            self._keyboard_capture_status = f"KEYBOARD REMAP FAILED // INVALID ROW {row_index}"
            self.stateChanged.emit()
            return
        row = rows[row_index] if isinstance(rows[row_index], dict) else {}
        action = str(row.get("commandId") or row.get("id") or "").strip()
        label = str(row.get("label") or action).strip()
        if not action:
            self._keyboard_capture_status = f"KEYBOARD REMAP FAILED // ROW {row_index} HAS NO COMMAND"
            self.stateChanged.emit()
            return
        self.beginBridgeHotkeyCapture(action, label)

    @Slot(int)
    def clearBridgeControlRow(self, row_index: int) -> None:
        try:
            row_index = int(row_index)
        except Exception:
            row_index = -1
        self._state["controlCaptureStatus"] = f"CLEAR CLICKED // ROW {row_index} // BACKEND RESOLVING COMMAND"
        self.stateChanged.emit()
        self._executor.submit(self._send_command_worker, "control_clear_row", {"row_index": row_index})

    @Slot(str)
    @Slot(str, str)
    def beginBridgeHotkeyCapture(self, action: str, label: str) -> None:
        self._keyboard_capture_action = str(action or "").strip()
        self._keyboard_capture_label = str(label or action or "").strip()
        self._keyboard_capture_status = "WAITING FOR KEYBOARD INPUT" if self._keyboard_capture_action else "IDLE"
        self.stateChanged.emit()
        if self._keyboard_capture_action:
            self._executor.submit(self._send_command_worker, "control_keyboard_capture_begin", {"action": self._keyboard_capture_action})

    @Slot()
    def cancelBridgeHotkeyCapture(self) -> None:
        self._keyboard_capture_action = ""
        self._keyboard_capture_label = ""
        self._keyboard_capture_status = "CANCELLED"
        self.stateChanged.emit()
        self._executor.submit(self._send_command_worker, "control_keyboard_capture_end", {})

    def eventFilter(self, watched, event):
        if self._input_test_mode == "KEYBOARD" and event.type() == QEvent.Type.KeyPress:
            key = int(event.key())
            if key == int(Qt.Key.Key_Escape):
                self.cancelInputLearnTest(); return True
            modifiers_only = {int(Qt.Key.Key_Control), int(Qt.Key.Key_Alt), int(Qt.Key.Key_Shift), int(Qt.Key.Key_Meta)}
            if key in modifiers_only:
                return True
            text = str(event.text() or "").strip().upper()
            if not text:
                text = f"KEY {key}"
            parts=[]; mods=event.modifiers()
            if mods & Qt.KeyboardModifier.ControlModifier: parts.append("Ctrl")
            if mods & Qt.KeyboardModifier.AltModifier: parts.append("Alt")
            if mods & Qt.KeyboardModifier.ShiftModifier: parts.append("Shift")
            if mods & Qt.KeyboardModifier.MetaModifier: parts.append("Win")
            parts.append(text)
            self._input_test_status = "KEYBOARD RECEIVED // " + "+".join(parts)
            self._input_test_mode = ""
            self.stateChanged.emit(); return True
        if self._keyboard_capture_action and event.type() == QEvent.Type.KeyPress:
            key = int(event.key())
            if key == int(Qt.Key.Key_Escape):
                self.cancelBridgeHotkeyCapture()
                return True
            modifiers_only = {int(Qt.Key.Key_Control), int(Qt.Key.Key_Alt), int(Qt.Key.Key_Shift), int(Qt.Key.Key_Meta)}
            if key in modifiers_only:
                return True
            # Convert Qt keys to the Windows virtual-key values used by the existing
            # BridgeGlobalHotkeys implementation.  This deliberately supports navigation,
            # function and keypad keys as well as printable A-Z/0-9 shortcuts.
            keypad = bool(event.modifiers() & Qt.KeyboardModifier.KeypadModifier)
            if int(Qt.Key.Key_A) <= key <= int(Qt.Key.Key_Z):
                name = chr(ord('A') + key - int(Qt.Key.Key_A)); vk = ord(name)
            elif int(Qt.Key.Key_0) <= key <= int(Qt.Key.Key_9):
                digit = key - int(Qt.Key.Key_0)
                name = (f"Num {digit}" if keypad else str(digit)); vk = (0x60 + digit if keypad else ord(str(digit)))
            else:
                special = {
                    int(Qt.Key.Key_PageUp): ("Page Up", 0x21),
                    int(Qt.Key.Key_PageDown): ("Page Down", 0x22),
                    int(Qt.Key.Key_End): ("End", 0x23),
                    int(Qt.Key.Key_Home): ("Home", 0x24),
                    int(Qt.Key.Key_Left): ("Left", 0x25),
                    int(Qt.Key.Key_Up): ("Up", 0x26),
                    int(Qt.Key.Key_Right): ("Right", 0x27),
                    int(Qt.Key.Key_Down): ("Down", 0x28),
                    int(Qt.Key.Key_Insert): ("Insert", 0x2D),
                    int(Qt.Key.Key_Delete): ("Delete", 0x2E),
                    int(Qt.Key.Key_Space): ("Space", 0x20),
                    int(Qt.Key.Key_Tab): ("Tab", 0x09),
                    int(Qt.Key.Key_Backspace): ("Backspace", 0x08),
                    int(Qt.Key.Key_Return): ("Enter", 0x0D),
                    int(Qt.Key.Key_Enter): ("Num Enter", 0x0D),
                }
                if int(Qt.Key.Key_F1) <= key <= int(Qt.Key.Key_F24):
                    n = key - int(Qt.Key.Key_F1) + 1; name = f"F{n}"; vk = 0x70 + n - 1
                elif key in special:
                    name, vk = special[key]
                else:
                    self._keyboard_capture_status = f"UNSUPPORTED KEY {key}"
                    self.stateChanged.emit()
                    return True
            parts=[]
            mods=event.modifiers()
            if mods & Qt.KeyboardModifier.ControlModifier: parts.append("Ctrl")
            if mods & Qt.KeyboardModifier.AltModifier: parts.append("Alt")
            if mods & Qt.KeyboardModifier.ShiftModifier: parts.append("Shift")
            if mods & Qt.KeyboardModifier.MetaModifier: parts.append("Win")
            parts.append(name)
            display="+".join(parts)
            action=self._keyboard_capture_action
            self._keyboard_capture_action=""
            self._keyboard_capture_status=f"RAW KEYBOARD // {display} // SAVING"
            self.stateChanged.emit()
            self._executor.submit(self._send_command_worker, "control_set_hotkey", {"action":action,"display":display,"vk":vk})
            return True
        return super().eventFilter(watched, event)

    @Property(bool, notify=stateChanged)
    def keyboardCaptureActive(self): return bool(self._keyboard_capture_action)

    @Property(str, notify=stateChanged)
    def keyboardCaptureAction(self): return self._keyboard_capture_action

    @Property(str, notify=stateChanged)
    def keyboardCaptureStatus(self): return self._keyboard_capture_status

    def setVoiceAttention(self, value: str) -> None:
        value = str(value or "").strip().upper()
        if value in {"OFF", "IMPORTANT", "MOST"}:
            # Optimistic UI update: choosing a talk level must feel immediate. Keep the
            # choice pinned briefly so the 250 ms state poll cannot repaint a stale
            # backend value while the asynchronous save command is still in flight.
            self._pending_voice_attention = value
            self._pending_voice_attention_deadline = time.monotonic() + 2.0
            self._state["voiceAttentionMode"] = value
            self._state["voiceLevel"] = {"OFF": "LOW", "IMPORTANT": "MED", "MOST": "HIGH"}[value]
            self.stateChanged.emit()
            self._executor.submit(self._send_command_worker, "voice_set_attention", {"value": value})

    @Slot(str, bool)
    def setSetupBool(self, name: str, value: bool) -> None:
        self._executor.submit(self._send_command_worker, "setup_setting", {"name": str(name or ""), "value": bool(value)})

    @Slot(str, str)
    def setSetupValue(self, name: str, value: str) -> None:
        self._executor.submit(self._send_command_worker, "setup_setting", {"name": str(name or ""), "value": str(value or "")})

    @Slot(str)
    def bindBridgeControl(self, action: str) -> None:
        action = str(action or "").strip()
        if not action:
            self._state["controlCaptureStatus"] = "REMAP FAILED // EMPTY COMMAND ID"
            self.stateChanged.emit()
            return
        self._pending_controller_capture = action
        self._pending_controller_capture_deadline = time.monotonic() + 3.0
        self._state["controlCaptureAction"] = action
        self._state["controlCaptureStatus"] = "REMAP CLICKED // ARMING CONTROLLER CAPTURE"
        self.stateChanged.emit()
        self._executor.submit(self._send_command_worker, "control_bind", {"action": action})

    @Slot(str)
    def clearBridgeControl(self, action: str) -> None:
        self._executor.submit(self._send_command_worker, "control_clear", {"action": str(action or "")})

    @Slot(str)
    def copyBridgeHotkey(self, action: str) -> None:
        self._executor.submit(self._send_command_worker, "control_copy_hotkey", {"action": str(action or "")})

    @Slot(str, str, int)
    def setBridgeHotkey(self, action: str, display: str, vk: int) -> None:
        self._executor.submit(self._send_command_worker, "control_set_hotkey", {"action": str(action or ""), "display": str(display or ""), "vk": int(vk)})

    @Slot()
    def restoreBridgeHotkeys(self) -> None:
        self._executor.submit(self._send_command_worker, "control_restore_hotkeys", {})

    @Slot(str, str, str, str, str, str, str)
    def saveTradeProfile(self, commodity: str, cargo: str, buySystem: str, buyStation: str, sellSystem: str, sellStation: str, runLength: str) -> None:
        payload = {
            "commodity": str(commodity or "").strip(),
            "cargo": str(cargo or "").strip(),
            "buy_system": str(buySystem or "").strip(),
            "buy_station": str(buyStation or "").strip(),
            "sell_system": str(sellSystem or "").strip(),
            "sell_station": str(sellStation or "").strip(),
            "run_length": str(runLength or "CONTINUOUS").strip(),
        }
        self.commandRequested.emit("trade_config")
        self._executor.submit(self._send_command_worker, "trade_config", payload)

    @Slot(str, str, str, str, str, str, str)
    def startTradeRun(self, commodity: str, cargo: str, buySystem: str, buyStation: str, sellSystem: str, sellStation: str, runLength: str) -> None:
        payload = {
            "commodity": str(commodity or "").strip(),
            "cargo": str(cargo or "").strip(),
            "buy_system": str(buySystem or "").strip(),
            "buy_station": str(buyStation or "").strip(),
            "sell_system": str(sellSystem or "").strip(),
            "sell_station": str(sellStation or "").strip(),
            "run_length": str(runLength or "CONTINUOUS").strip(),
        }
        self.commandRequested.emit("trade_start")
        self.backend.grant_foreground_permission()
        self._executor.submit(self._send_command_worker, "trade_start", payload)

    @Slot(str, str, str, str)
    def searchTradeRoutes(self, commodity: str, maxLy: str, maxLs: str, minRuns: str) -> None:
        payload = {
            "commodity": str(commodity or "").strip(),
            "max_ly": str(maxLy or "100").strip(),
            "max_ls": str(maxLs or "10000").strip(),
            "min_runs": str(minRuns or "5").strip(),
        }
        self.commandRequested.emit("trade_route_search")
        self._executor.submit(self._send_command_worker, "trade_route_search", payload)

    @Slot(int)
    def useTradeRouteIndex(self, index: int) -> None:
        try:
            idx = int(index)
        except Exception:
            return
        if idx < 0:
            return
        self.commandRequested.emit("trade_route_use_index")
        self._executor.submit(self._send_command_worker, "trade_route_use_index", {"index": idx})

    @Slot(str, str, str, str, str, str)
    def searchBestTrade(self, maxStartLy: str, maxLegLy: str, maxLs: str, minRuns: str, legality: str, rareMode: str) -> None:
        payload = {
            "max_start_ly": str(maxStartLy or "100").strip(),
            "max_leg_ly": str(maxLegLy or "100").strip(),
            "max_ls": str(maxLs or "10000").strip(),
            "min_runs": str(minRuns or "5").strip(),
            "legality": str(legality or "LEGAL ONLY").strip(),
            "rare_mode": str(rareMode or "EXCLUDE").strip(),
        }
        self.commandRequested.emit("trade_best_search")
        self._executor.submit(self._send_command_worker, "trade_best_search", payload)

    @Slot(int)
    def useBestTradeIndex(self, index: int) -> None:
        try:
            idx = int(index)
        except Exception:
            return
        if idx < 0:
            return
        self.commandRequested.emit("trade_best_use_index")
        self._executor.submit(self._send_command_worker, "trade_best_use_index", {"index": idx})

    @Slot(int)
    def useColonizationProjectIndex(self, index: int) -> None:
        try:
            idx = int(index)
        except Exception:
            return
        if idx < 0:
            return
        self.commandRequested.emit("colonization_project_use_index")
        self._executor.submit(self._send_command_worker, "colonization_project_use_index", {"index": idx})

    @Slot(str, int, str, str, str)
    def searchColonizationSupply(self, commodity: str, quantity: int, maxLy: str, maxLs: str, minRuns: str) -> None:
        commodity = str(commodity or "").strip()
        if not commodity:
            return
        try:
            qty = max(1, int(quantity))
        except Exception:
            qty = 1
        payload = {
            "commodity": commodity,
            "quantity": str(qty),
            "max_ly": str(maxLy or "100").strip(),
            "max_ls": str(maxLs or "10000").strip(),
            "min_runs": str(minRuns or "1").strip(),
        }
        self.commandRequested.emit("colonization_find_supply")
        self._executor.submit(self._send_command_worker, "colonization_find_supply", payload)

    @Slot(int)
    def plotResIndex(self, index: int) -> None:
        try:
            idx = int(index)
        except Exception:
            return
        if idx < 0:
            return
        self.commandRequested.emit("combat_res_plot_index")
        self.backend.grant_foreground_permission()
        self._executor.submit(self._send_command_worker, "combat_res_plot_index", {"index": idx})

    @Slot(str)
    def plotRoute(self, destination: str) -> None:
        destination = str(destination or "").strip()
        if not destination:
            return
        self.commandRequested.emit("nav_plot")
        self.backend.grant_foreground_permission()
        self._executor.submit(self._send_command_worker, "nav_plot", {"destination": destination})

    @Slot(str)
    def plotMemory(self, slot: str) -> None:
        slot = str(slot or "").strip().lower()
        if slot not in {"home", "bookmark1", "bookmark2"}:
            return
        self.commandRequested.emit("nav_memory_plot")
        self.backend.grant_foreground_permission()
        self._executor.submit(self._send_command_worker, "nav_memory_plot", {"slot": slot})

    @Slot(str, str)
    def setNavigationMemory(self, slot: str, destination: str) -> None:
        slot = str(slot or "").strip().lower()
        if slot not in {"home", "bookmark1", "bookmark2"}:
            return
        destination = str(destination or "").strip()
        self.commandRequested.emit("nav_memory_set")
        self._executor.submit(self._send_command_worker, "nav_memory_set", {"slot": slot, "destination": destination})

    @Slot(str)
    def captureNavigationMemory(self, slot: str) -> None:
        slot = str(slot or "").strip().lower()
        if slot not in {"home", "bookmark1", "bookmark2"}:
            return
        self.commandRequested.emit("nav_memory_capture")
        self._executor.submit(self._send_command_worker, "nav_memory_capture", {"slot": slot})

    def _local_system_candidates(self, prefix: str) -> list[str]:
        names: list[str] = []
        for value in (
            self.system, self.destination, self.fsdTarget,
            self.navHomeSystem, self.navBookmark1System, self.navBookmark2System,
        ):
            value = str(value or "").strip()
            if value and value not in {"-", "NO ROUTE"}:
                names.append(value)
        for row in list(self._get("navRouteEntries", []) or []):
            if isinstance(row, dict):
                value = str(row.get("system") or "").strip()
                if value and value not in {"-", "MORE"} and not value.endswith(" MORE"):
                    names.append(value)
        folded = prefix.casefold()
        seen = set()
        result = []
        for name in names:
            key = name.casefold()
            if key in seen or not key.startswith(folded):
                continue
            seen.add(key)
            result.append(name)
        return result[:5]

    @Slot(str)
    def requestSystemSuggestions(self, prefix: str) -> None:
        prefix = str(prefix or "").strip()
        self._suggestion_serial += 1
        serial = self._suggestion_serial
        local = self._local_system_candidates(prefix) if prefix else []
        if len(prefix) < 3:
            self._nav_system_suggestions = local
            self._nav_suggestion_status = "TYPE 3+ CHARACTERS"
            self.stateChanged.emit()
            return
        self._nav_system_suggestions = local
        self._nav_suggestion_status = "SEARCHING EDSM..."
        self.stateChanged.emit()

        def worker():
            names = list(local)
            status = "EDSM OFFLINE"
            try:
                query = urllib.parse.urlencode({"systemName": prefix})
                req = urllib.request.Request(
                    "https://www.edsm.net/api-v1/systems?" + query,
                    headers={"Accept": "application/json", "User-Agent": "Elite-AI-Bridge-QML/0.29.4"},
                )
                with urllib.request.urlopen(req, timeout=2.2) as response:
                    raw = response.read(4_000_000)
                payload = json.loads(raw.decode("utf-8", errors="replace") or "[]")
                if isinstance(payload, list):
                    existing = {name.casefold() for name in names}
                    for row in payload:
                        if not isinstance(row, dict):
                            continue
                        name = str(row.get("name") or "").strip()
                        if not name or not name.casefold().startswith(prefix.casefold()):
                            continue
                        key = name.casefold()
                        if key in existing:
                            continue
                        existing.add(key)
                        names.append(name)
                        if len(names) >= 5:
                            break
                    status = f"EDSM // {len(names)} MATCH{'ES' if len(names) != 1 else ''}" if names else "EDSM // NO MATCH"
                else:
                    status = "EDSM // NO MATCH"
            except Exception:
                if names:
                    status = f"LOCAL // {len(names)} MATCH{'ES' if len(names) != 1 else ''}"
            return names[:5], status, serial

        future = self._suggest_executor.submit(worker)
        def done(fut):
            try:
                names, status, result_serial = fut.result()
                self.suggestionsArrived.emit(names, status, result_serial)
            except Exception:
                self.suggestionsArrived.emit(local, "EDSM OFFLINE", serial)
        future.add_done_callback(done)

    @Slot(object, str, int)
    def _apply_system_suggestions(self, names: object, status: str, serial: int) -> None:
        if serial != self._suggestion_serial:
            return
        self._nav_system_suggestions = [str(x) for x in list(names or [])[:5] if str(x).strip()]
        self._nav_suggestion_status = str(status or "")
        self.stateChanged.emit()

    @Slot()
    def exitBridge(self) -> None:
        """Flush pending preferences/backend writes, then leave through one exit path."""
        # A normal Windows title-bar close can arrive immediately after a settings
        # click. Setup commands use the single command executor, so drain it before
        # stopping the backend. This makes EXIT, the Windows X and Alt+F4 equivalent.
        self.shutdown()
        app = QGuiApplication.instance()
        if app is not None:
            app.quit()

    @Slot()
    def shutdown(self) -> None:
        if self._shutting_down:
            return
        self._shutting_down = True
        self.poll_timer.stop()
        try:
            self.clock_timer.stop()
        except Exception:
            pass
        try:
            self.overlay_compat_timer.stop()
        except Exception:
            pass
        try:
            self._settings.sync()
        except Exception:
            pass
        try:
            # Do not cancel queued setup/voice/display writes during shutdown. The
            # executor is single-threaded, so waiting here preserves their order and
            # guarantees they reach the backend before /shutdown persists engine state.
            self._executor.shutdown(wait=True, cancel_futures=False)
        except Exception:
            pass
        try:
            self._suggest_executor.shutdown(wait=True, cancel_futures=True)
        except Exception:
            pass
        try:
            self.backend.stop()
        except Exception:
            pass

    def _get(self, key: str, fallback: Any = None) -> Any:
        return self._state.get(key, fallback)

    @Property(bool, notify=stateChanged)
    def connected(self): return bool(self._get("connected", False))

    @Property(str, notify=stateChanged)
    def commander(self): return _string(self._get("commander"))

    @Property(str, notify=stateChanged)
    def ship(self): return _string(self._get("ship"))

    @Property(str, notify=stateChanged)
    def shipName(self): return _string(self._get("shipName"), "")

    @Property(str, notify=stateChanged)
    def shipModel(self): return _string(self._get("shipModel"), "-")

    @Property(str, notify=stateChanged)
    def system(self): return _string(self._get("system"))

    @Property(str, notify=stateChanged)
    def station(self): return _string(self._get("station"))

    @Property(str, notify=stateChanged)
    def gameState(self): return _string(self._get("gameState"), "STARTING")

    @Property(str, notify=stateChanged)
    def bridgeState(self): return _string(self._get("bridgeState"), "STARTING ENGINE")

    @Property(str, notify=stateChanged)
    def bridgeMessage(self): return _string(self._get("bridgeMessage"), "-")

    @Property(str, notify=stateChanged)
    def bridgeLevel(self): return _string(self._get("bridgeLevel"), "info")

    @Property(str, notify=stateChanged)
    def controlOwner(self): return _string(self._get("controlOwner"), "NONE")

    @Property(str, notify=stateChanged)
    def commandFeedbackState(self): return _string(self._get("commandFeedbackState"), "IDLE")

    @Property(str, notify=stateChanged)
    def commandFeedbackText(self): return _string(self._get("commandFeedbackText"), "")

    @Property(float, notify=pulseChanged)
    def pulse(self): return self._pulse

    @Property(str, notify=clockChanged)
    def localTime(self): return self._clock_text

    @Property(int, notify=stateChanged)
    def hullPercent(self): return int(self._get("hullPercent", -1) or 0) if self._get("hullPercent", -1) is not None else -1

    @Property(int, notify=stateChanged)
    def fuelPercent(self): return int(self._get("fuelPercent", -1) or 0) if self._get("fuelPercent", -1) is not None else -1

    @Property(str, notify=stateChanged)
    def shieldState(self): return _string(self._get("shieldState"), "UNKNOWN")

    @Property(int, notify=stateChanged)
    def cargoUsed(self):
        try: return int(self._get("cargoUsed", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def cargoCapacity(self):
        try: return int(self._get("cargoCapacity", -1))
        except Exception: return -1

    @Property(str, notify=stateChanged)
    def cargoText(self):
        if _string(self._get("eliteTelemetryState"), "WAITING") != "CONNECTED":
            return "UNKNOWN"
        cap = self.cargoCapacity
        return f"{self.cargoUsed:,} / {cap:,} T" if cap >= 0 else f"{self.cargoUsed:,} T"

    @Property(str, notify=stateChanged)
    def pips(self): return _string(self._get("pips"), "SYS -   ENG -   WEP -")

    @Property(str, notify=stateChanged)
    def fsdState(self): return _string(self._get("fsdState"), "UNKNOWN")

    @Property(str, notify=stateChanged)
    def gearState(self): return _string(self._get("gearState"), "UNKNOWN")

    @Property(str, notify=stateChanged)
    def hardpointsState(self): return _string(self._get("hardpointsState"), "UNKNOWN")

    @Property('QVariantList', notify=stateChanged)
    def commanderDossierRows(self): return list(self._get("commanderDossierRows", []) or [])

    @Property('QVariantList', notify=stateChanged)
    def commanderCareerRows(self): return list(self._get("commanderCareerRows", []) or [])

    @Property('QVariantList', notify=stateChanged)
    def commanderRecordRows(self): return list(self._get("commanderRecordRows", []) or [])

    @Property('QVariantList', notify=stateChanged)
    def commanderCargoRows(self): return list(self._get("commanderCargoRows", []) or [])

    @Property(int, notify=stateChanged)
    def commanderCargoTypeCount(self):
        try: return int(self._get("commanderCargoTypeCount", 0) or 0)
        except Exception: return 0

    @Property(str, notify=stateChanged)
    def commanderCargoSource(self): return _string(self._get("commanderCargoSource"), "-")

    @Property(int, notify=stateChanged)
    def commanderLimpetReserve(self):
        try: return int(self._get("commanderLimpetReserve", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def commanderStolenCargo(self):
        try: return int(self._get("commanderStolenCargo", 0) or 0)
        except Exception: return 0

    @Property('QVariantList', notify=stateChanged)
    def commanderSessionRows(self): return list(self._get("commanderSessionRows", []) or [])

    @Property(bool, notify=stateChanged)
    def commanderHistoryAvailable(self): return bool(self._get("commanderHistoryAvailable", False))

    @Property(str, notify=stateChanged)
    def commanderHistoryNote(self): return _string(self._get("commanderHistoryNote"), "OPTIONAL EDDISCOVERY HISTORY NOT LOADED")

    @Property(str, notify=stateChanged)
    def commanderCreditsSource(self): return _string(self._get("commanderCreditsSource"), "UNKNOWN")

    @Property(list, notify=stateChanged)
    def systemRows(self): return list(self._get("systemRows", []) or [])

    @Property(str, notify=stateChanged)
    def eliteTelemetryState(self):
        return _string(self._get("eliteTelemetryState"), "OFFLINE").upper()

    @Property(bool, notify=stateChanged)
    def eliteTelemetryConnected(self):
        return self.eliteTelemetryState == "CONNECTED"

    @Property(bool, notify=stateChanged)
    def eliteControlsReady(self):
        return bool(self._get("eliteControlsReady", False))

    @Property(str, notify=stateChanged)
    def eliteControlReason(self):
        return _string(self._get("eliteControlReason"), "NO ACTIVE ELITE .BINDS PROFILE")

    @Property(list, notify=stateChanged)
    def recentEvents(self): return list(self._get("recentEvents", []) or [])

    @Property(str, notify=stateChanged)
    def alertLabel(self): return _string(self._get("alertLabel"), "NO ACTIVE ALERTS")

    @Property(str, notify=stateChanged)
    def alertValue(self): return _string(self._get("alertValue"), "CLEAR")

    @Property(str, notify=stateChanged)
    def alertDetail(self): return _string(self._get("alertDetail"), "-")

    @Property(str, notify=stateChanged)
    def alertLevel(self): return _string(self._get("alertLevel"), "info")

    @Property(str, notify=stateChanged)
    def destination(self): return _string(self._get("destination"), "NO ROUTE")

    @Property(str, notify=stateChanged)
    def fsdTarget(self): return _string(self._get("fsdTarget"), "-")

    @Property(str, notify=stateChanged)
    def routeStatus(self): return _string(self._get("routeStatus"), "NO ROUTE PLOTTED")

    @Property(int, notify=stateChanged)
    def routeJumps(self):
        try: return int(self._get("routeJumps", -1))
        except Exception: return -1

    @Property(str, notify=stateChanged)
    def nextStarSystem(self): return _string(self._get("nextStarSystem"), "-")

    @Property(str, notify=stateChanged)
    def nextStarClass(self): return _string(self._get("nextStarClass"), "-")

    @Property(str, notify=stateChanged)
    def nextStarText(self): return _string(self._get("nextStarText"), "UNKNOWN")

    @Property(bool, notify=stateChanged)
    def nextStarScoopable(self): return bool(self._get("nextStarScoopable", False))

    @Property(bool, notify=stateChanged)
    def nextStarScoopableKnown(self): return self._get("nextStarScoopable", None) is not None

    @Property(str, notify=stateChanged)
    def voiceMode(self): return _string(self._get("voiceMode"), "READY")

    @Property(str, notify=stateChanged)
    def voiceEngineStatus(self): return _string(self._get("voiceEngineStatus"), "STARTING")

    @Property(bool, notify=stateChanged)
    def voiceEngineWarming(self): return bool(self._get("voiceEngineWarming", False))

    @Property(int, notify=stateChanged)
    def voiceWarmDurationMs(self):
        try: return int(self._get("voiceWarmDurationMs", 0) or 0)
        except Exception: return 0

    @Property(bool, notify=stateChanged)
    def wizardNarrationActive(self): return bool(self._get("wizardNarrationActive", False))

    @Property(str, notify=stateChanged)
    def pttStatus(self): return _string(self._get("pttStatus"), "STARTING")

    @Property(str, notify=stateChanged)
    def lunaStatus(self): return _string(self._get("lunaStatus"), "STARTING")

    @Property(int, notify=stateChanged)
    def aiCalls(self):
        try: return int(self._get("aiCalls", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def aiInputTokens(self):
        try: return int(self._get("aiInputTokens", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def aiOutputTokens(self):
        try: return int(self._get("aiOutputTokens", 0) or 0)
        except Exception: return 0

    @Property(str, notify=stateChanged)
    def aiEstimatedCostText(self):
        try: return f"${float(self._get('aiEstimatedCost', 0.0) or 0.0):.4f}"
        except Exception: return "$0.0000"

    @Property(int, notify=stateChanged)
    def aiUsageCalls(self):
        try: return int(self._get("aiUsageCalls", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def aiUsageInputTokens(self):
        try: return int(self._get("aiUsageInputTokens", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def aiUsageOutputTokens(self):
        try: return int(self._get("aiUsageOutputTokens", 0) or 0)
        except Exception: return 0

    @Property(str, notify=stateChanged)
    def aiUsageEstimatedCostText(self):
        try: return f"${float(self._get('aiUsageEstimatedCost', 0.0) or 0.0):.4f}"
        except Exception: return "$0.0000"

    @Property(int, notify=stateChanged)
    def aiUsageTranscriptionCalls(self):
        try: return int(self._get("aiUsageTranscriptionCalls", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def aiUsageTranscriptionFailures(self):
        try: return int(self._get("aiUsageTranscriptionFailures", 0) or 0)
        except Exception: return 0

    @Property(str, notify=stateChanged)
    def aiUsageTranscriptionSecondsText(self):
        try: return f"{float(self._get('aiUsageTranscriptionSeconds', 0.0) or 0.0):.1f} S"
        except Exception: return "0.0 S"

    @Property(int, notify=stateChanged)
    def aiMeterSegments(self):
        # Cosmetic activity meter, now driven by real request count rather than a fixed prototype value.
        return max(0, min(12, self.aiCalls))

    @Property(str, notify=stateChanged)
    def aiModel(self): return _string(self._get("aiModel"), "gpt-5.6-luna")

    @Property(bool, notify=stateChanged)
    def aiApiConfigured(self): return bool(self._get("aiApiConfigured", False))
    @Property(bool, notify=stateChanged)
    def aiApiVerified(self): return bool(self._get("aiApiVerified", False))
    @Property(str, notify=stateChanged)
    def aiApiVerifyStatus(self): return _string(self._get("aiApiVerifyStatus"), "NOT CONFIGURED")
    @Property(str, notify=stateChanged)
    def aiApiVerifyDetail(self): return _string(self._get("aiApiVerifyDetail"), "")
    @Property(str, notify=stateChanged)
    def bridgeMode(self): return _string(self._get("bridgeMode"), "CORE")

    @Property(str, notify=stateChanged)
    def setupApiKeyLast4(self): return _string(self._get("setupApiKeyLast4"), "")
    @Property('QVariantList', notify=stateChanged)
    def setupPreflightRows(self): return list(self._get("setupPreflightRows", []) or [])
    @Property(bool, notify=stateChanged)
    def setupReady(self): return bool(self._get("setupReady", False))
    @Property(bool, notify=stateChanged)
    def setupLimited(self): return bool(self._get("setupLimited", False))
    @Property(bool, notify=stateChanged)
    def eliteBindingsLive(self): return bool(self._get("eliteBindingsLive", False))
    @Property(str, notify=stateChanged)
    def eliteBindingsSource(self): return _string(self._get("eliteBindingsSource"), "not found")
    @Property('QVariantList', notify=stateChanged)
    def setupControlRows(self): return list(self._get("setupControlRows", []) or [])

    @Property(str, notify=stateChanged)
    def controlCaptureAction(self): return str(self._get("controlCaptureAction", "") or "")

    @Property(str, notify=stateChanged)
    def controlCaptureStatus(self): return _string(self._get("controlCaptureStatus"), "IDLE")
    @Property(bool, notify=stateChanged)
    def controlConflictModalActive(self): return bool(self._get("controlConflictModalActive", False))
    @Property(str, notify=stateChanged)
    def controlConflictModalCommand(self): return _string(self._get("controlConflictModalCommand"), "")
    @Property(str, notify=stateChanged)
    def controlConflictModalControl(self): return _string(self._get("controlConflictModalControl"), "")
    @Property(str, notify=stateChanged)
    def controlConflictModalElite(self): return _string(self._get("controlConflictModalElite"), "")

    @Slot()
    def acknowledgeControlConflict(self) -> None:
        # Optimistic close prevents the next 250 ms poll from making ACKNOWLEDGE feel sticky.
        self._state["controlConflictModalActive"] = False
        self.stateChanged.emit()
        self._executor.submit(self._send_command_worker, "control_conflict_ack", {})
    @Property('QVariantList', notify=stateChanged)
    def setupEliteBindingRows(self): return list(self._get("setupEliteBindingRows", []) or [])
    @Property(str, notify=stateChanged)
    def setupCommanderAddress(self): return _string(self._get("setupCommanderAddress"), "Commander")
    @Property(str, notify=stateChanged)
    def setupAiContext(self): return _string(self._get("setupAiContext"), "")
    @Property(str, notify=stateChanged)
    def setupAiContextDefault(self): return _string(self._get("setupAiContextDefault"), "")
    @Property(bool, notify=stateChanged)
    def setupAutoRefuel(self): return bool(self._get("setupAutoRefuel", False))
    @Property(bool, notify=stateChanged)
    def setupAutoRepair(self): return bool(self._get("setupAutoRepair", False))
    @Property(bool, notify=stateChanged)
    def setupAutoRearm(self): return bool(self._get("setupAutoRearm", False))
    @Property(bool, notify=stateChanged)
    def setupDynamicPips(self): return bool(self._get("setupDynamicPips", False))
    @Property(bool, notify=stateChanged)
    def setupAutoPowerPlant(self): return bool(self._get("setupAutoPowerPlant", False))
    @Property(bool, notify=stateChanged)
    def setupAutoChaff(self): return bool(self._get("setupAutoChaff", False))
    @Property(str, notify=stateChanged)
    def setupAutoChaffProfile(self): return _string(self._get("setupAutoChaffProfile"), "MED")
    @Property(bool, notify=stateChanged)
    def setupAiTradeAuto(self): return bool(self._get("setupAiTradeAuto", True))
    @Property(bool, notify=stateChanged)
    def setupAiMissionAuto(self): return bool(self._get("setupAiMissionAuto", True))
    @Property(bool, notify=stateChanged)
    def setupAiTravelAuto(self): return bool(self._get("setupAiTravelAuto", False))

    @Property(str, notify=stateChanged)
    def aiCopilotStatus(self): return _string(self._get("aiCopilotStatus"), "-")

    @Property(str, notify=stateChanged)
    def aiCopilotResponse(self): return _string(self._get("aiCopilotResponse"), "-")

    @Property(str, notify=stateChanged)
    def aiToolActivity(self): return _string(self._get("aiToolActivity"), "-")

    @Property(list, notify=stateChanged)
    def aiCommsRows(self): return list(self._get("aiCommsRows", []) or [])

    @Property(bool, notify=stateChanged)
    def pageHelpActive(self): return bool(self._get("pageHelpActive", False))

    @Property(int, notify=stateChanged)
    def pageHelpPage(self):
        try: return int(self._get("pageHelpPage", -1))
        except Exception: return -1

    @Property(int, notify=stateChanged)
    def pageHelpStep(self):
        try: return int(self._get("pageHelpStep", -1))
        except Exception: return -1

    @Property(str, notify=stateChanged)
    def pageHelpLabel(self): return _string(self._get("pageHelpLabel"), "-")

    @Property(int, notify=stateChanged)
    def pageHelpCompletedSerial(self):
        try: return int(self._get("pageHelpCompletedSerial", 0))
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def pageHelpCompletedPage(self):
        try: return int(self._get("pageHelpCompletedPage", -1))
        except Exception: return -1

    @Property(int, notify=stateChanged)
    def uiPageHintSerial(self):
        try: return int(self._get("uiPageHintSerial", 0))
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def uiPageHint(self):
        try: return int(self._get("uiPageHint", -1))
        except Exception: return -1

    @Property(str, notify=stateChanged)
    def uiWorkspaceHint(self): return str(self._get("uiWorkspaceHint", "") or "")

    @Property(str, notify=stateChanged)
    def aiToolMode(self): return _string(self._get("aiToolMode"), "Ask Before Acting")

    @Property(str, notify=stateChanged)
    def aiPendingAction(self): return _string(self._get("aiPendingAction"), "NONE")

    @Property(bool, notify=stateChanged)
    def aiPendingActionAvailable(self): return bool(self._get("aiPendingActionAvailable", False))

    @Property(str, notify=stateChanged)
    def aiSafetyLevel(self): return _string(self._get("aiSafetyLevel"), "CLEAR")

    @Property(str, notify=stateChanged)
    def aiSafetyReason(self): return _string(self._get("aiSafetyReason"), "No active threat.")

    @Property(bool, notify=stateChanged)
    def aiSmartAutoEnabled(self): return bool(self._get("aiSmartAutoEnabled", False))

    @Property(bool, notify=stateChanged)
    def aiLaunchRuleEnabled(self): return bool(self._get("aiLaunchRuleEnabled", False))

    @Property(int, notify=stateChanged)
    def aiSessionRuleCount(self):
        try: return int(self._get("aiSessionRuleCount", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def aiTranscriptionCalls(self):
        try: return int(self._get("aiTranscriptionCalls", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def aiTranscriptionFailures(self):
        try: return int(self._get("aiTranscriptionFailures", 0) or 0)
        except Exception: return 0

    @Property(str, notify=stateChanged)
    def aiTranscriptionSecondsText(self):
        try: return f"{float(self._get('aiTranscriptionSeconds', 0.0) or 0.0):.1f} S"
        except Exception: return "0.0 S"

    @Property(str, notify=stateChanged)
    def voiceInputMode(self): return _string(self._get("voiceInputMode"), "PTT")

    @Property(str, notify=stateChanged)
    def voicePttMapping(self): return _string(self._get("voicePttMapping"), "KEYBOARD FALLBACK // CTRL+ALT+SHIFT+V")

    @Property(str, notify=stateChanged)
    def voiceInputDevice(self): return _string(self._get("voiceInputDevice"), "System Default")

    @Property(str, notify=stateChanged)
    def voiceOutputDevice(self): return _string(self._get("voiceOutputDevice"), "System Default")

    @Property(str, notify=stateChanged)
    def voiceEngineMode(self): return _string(self._get("voiceEngineMode"), "AUTO")

    @Property(str, notify=stateChanged)
    def voiceName(self): return _string(self._get("voiceName"), "-")

    @Property(list, notify=stateChanged)
    def voiceNameOptions(self): return list(self._get("voiceNameOptions", []) or [])

    @Property(str, notify=stateChanged)
    def voicePitch(self): return _string(self._get("voicePitch"), "NORMAL")

    @Property(list, notify=stateChanged)
    def voicePitchOptions(self): return list(self._get("voicePitchOptions", []) or [])

    @Property(str, notify=stateChanged)
    def voiceEffect(self): return _string(self._get("voiceEffect"), "BRIDGE")

    @Property(list, notify=stateChanged)
    def voiceEffectOptions(self): return list(self._get("voiceEffectOptions", []) or [])

    @Property(int, notify=stateChanged)
    def voiceEffectStrength(self):
        try: return max(0, min(100, int(self._get("voiceEffectStrength", 35) or 35)))
        except Exception: return 35

    @Property(float, notify=stateChanged)
    def voiceSpeed(self):
        try: return float(self._get("voiceSpeed", 1.0) or 1.0)
        except Exception: return 1.0

    @Property(str, notify=stateChanged)
    def voiceLevel(self): return _string(self._get("voiceLevel"), "MED")

    @Property(str, notify=stateChanged)
    def voiceAttentionMode(self): return _string(self._get("voiceAttentionMode"), "IMPORTANT")

    @Property(int, notify=stateChanged)
    def voiceVolume(self):
        try: return int(self._get("voiceVolume", 0) or 0)
        except Exception: return 0

    @Property(str, notify=stateChanged)
    def voiceSpeedText(self):
        try: return f"{float(self._get('voiceSpeed', 1.0) or 1.0):.2f}X"
        except Exception: return "1.00X"

    @Property(float, notify=stateChanged)
    def voiceMicLevel(self):
        try: return max(0.0, min(1.0, float(self._get("voiceMicLevel", 0.0) or 0.0)))
        except Exception: return 0.0

    @Property(int, notify=stateChanged)
    def voiceMicSegments(self): return max(0, min(12, int(round(self.voiceMicLevel * 12))))

    @Property(str, notify=stateChanged)
    def voiceInputStatus(self): return _string(self._get("voiceInputStatus"), "-")

    @Property(str, notify=stateChanged)
    def voiceLastText(self): return _string(self._get("voiceLastText"), "-")

    @Property(bool, notify=stateChanged)
    def voiceSfxEnabled(self): return bool(self._get("voiceSfxEnabled", False))

    @Property(bool, notify=stateChanged)
    def voiceStartupAudioEnabled(self): return bool(self._get("voiceStartupAudioEnabled", False))

    @Property('QVariantList', notify=stateChanged)
    def audioInputDevices(self): return list(self._get("audioInputDevices", ["System Default"]) or ["System Default"])

    @Property('QVariantList', notify=stateChanged)
    def audioOutputDevices(self): return list(self._get("audioOutputDevices", ["System Default"]) or ["System Default"])

    @Property(str, notify=stateChanged)
    def audioDefaultInput(self): return _string(self._get("audioDefaultInput"), "System Default")

    @Property(str, notify=stateChanged)
    def audioDefaultOutput(self): return _string(self._get("audioDefaultOutput"), "System Default")

    @Property(int, notify=stateChanged)
    def audioSfxVolume(self):
        try: return max(0, min(100, int(self._get("audioSfxVolume", 50) or 0)))
        except Exception: return 50

    @Property('QVariantList', notify=stateChanged)
    def audioSfxRows(self): return list(self._get("audioSfxRows", []) or [])

    @Property(str, notify=stateChanged)
    def audioSfxSelectedKey(self): return _string(self._get("audioSfxSelectedKey"), "startup")

    @Property(str, notify=stateChanged)
    def audioSfxSelectedLabel(self): return _string(self._get("audioSfxSelectedLabel"), "Startup / Bridge online")

    @Property(str, notify=stateChanged)
    def audioSfxSelectedFile(self): return _string(self._get("audioSfxSelectedFile"), "startup.wav")

    @Property(str, notify=stateChanged)
    def audioSfxSelectedSource(self): return _string(self._get("audioSfxSelectedSource"), "DEFAULT")

    @Property(bool, notify=stateChanged)
    def audioSfxSelectedEnabled(self): return bool(self._get("audioSfxSelectedEnabled", True))

    @Property(str, notify=stateChanged)
    def audioSfxStatus(self): return _string(self._get("audioSfxStatus"), "-")

    @Property(str, notify=stateChanged)
    def audioLastSound(self): return _string(self._get("audioLastSound"), "-")

    @Property(bool, notify=stateChanged)
    def navArmed(self): return bool(self._get("navArmed", False))

    @Property(str, notify=stateChanged)
    def navStatus(self): return _string(self._get("navStatus"), "NAVIGATION STANDBY")

    @Property(str, notify=stateChanged)
    def navDestinationInput(self): return _string(self._get("navDestinationInput"), "") if self._get("navDestinationInput", "") else ""

    @Property(str, notify=stateChanged)
    def navMassLock(self): return _string(self._get("navMassLock"), "UNKNOWN")

    @Property(str, notify=stateChanged)
    def navMassLockLevel(self): return _string(self._get("navMassLockLevel"), "info")

    @Property(bool, notify=stateChanged)
    def navRouteValid(self): return bool(self._get("navRouteValid", False))

    @Property(str, notify=stateChanged)
    def navRouteSource(self): return _string(self._get("navRouteSource"), "-")

    @Property(bool, notify=stateChanged)
    def navRouteFileConnected(self): return bool(self._get("navRouteFileConnected", False))

    @Property(list, notify=stateChanged)
    def navRouteEntries(self): return list(self._get("navRouteEntries", []) or [])

    @Property(list, notify=stateChanged)
    def navFlightPlan(self): return list(self._get("navFlightPlan", []) or [])

    @Property(list, notify=stateChanged)
    def navHistory(self): return list(self._get("navHistory", []) or [])

    @Property(bool, notify=stateChanged)
    def navInSystemTargetVisible(self): return bool(self._get("navInSystemTargetVisible", False))

    @Property(str, notify=stateChanged)
    def navInSystemTargetName(self): return _string(self._get("navInSystemTargetName"), "-")

    @Property(str, notify=stateChanged)
    def navInSystemTargetKind(self): return _string(self._get("navInSystemTargetKind"), "-")

    @Property(str, notify=stateChanged)
    def navInSystemTargetStationType(self): return _string(self._get("navInSystemTargetStationType"), "") if self._get("navInSystemTargetStationType", "") else ""

    @Property(bool, notify=stateChanged)
    def navInSystemTargetConfirmedStation(self): return bool(self._get("navInSystemTargetConfirmedStation", False))

    @Property(str, notify=stateChanged)
    def navHomeSystem(self): return _string(self._get("navHomeSystem"), "") if self._get("navHomeSystem", "") else ""

    @Property(str, notify=stateChanged)
    def navBookmark1System(self): return _string(self._get("navBookmark1System"), "") if self._get("navBookmark1System", "") else ""

    @Property(str, notify=stateChanged)
    def navBookmark2System(self): return _string(self._get("navBookmark2System"), "") if self._get("navBookmark2System", "") else ""

    @Property(str, notify=stateChanged)
    def navMemoryCaptureSystem(self): return _string(self._get("navMemoryCaptureSystem"), "-")

    @Property(str, notify=stateChanged)
    def navMemoryCaptureSource(self): return _string(self._get("navMemoryCaptureSource"), "CURRENT SYSTEM")

    @Property(bool, notify=stateChanged)
    def colonizationHasProject(self): return bool(self._get("colonizationHasProject", False))

    @Property(str, notify=stateChanged)
    def colonizationStatus(self): return _string(self._get("colonizationStatus"), "NO PROJECT")

    @Property(str, notify=stateChanged)
    def colonizationSystem(self): return _string(self._get("colonizationSystem"), "-")

    @Property(str, notify=stateChanged)
    def colonizationStation(self): return _string(self._get("colonizationStation"), "-")

    @Property(str, notify=stateChanged)
    def colonizationMarketId(self): return _string(self._get("colonizationMarketId"), "-")

    @Property(float, notify=stateChanged)
    def colonizationProgressPercent(self): return float(self._get("colonizationProgressPercent", 0.0) or 0.0)

    @Property(str, notify=stateChanged)
    def colonizationLastUpdate(self): return _string(self._get("colonizationLastUpdate"), "-")

    @Property(str, notify=stateChanged)
    def colonizationLastEvent(self): return _string(self._get("colonizationLastEvent"), "-")

    @Property(int, notify=stateChanged)
    def colonizationRemainingTotal(self): return int(self._get("colonizationRemainingTotal", 0) or 0)

    @Property(int, notify=stateChanged)
    def colonizationCompleteCount(self): return int(self._get("colonizationCompleteCount", 0) or 0)

    @Property(int, notify=stateChanged)
    def colonizationIncompleteCount(self): return int(self._get("colonizationIncompleteCount", 0) or 0)

    @Property('QVariantList', notify=stateChanged)
    def colonizationRequirementRows(self): return list(self._get("colonizationRequirementRows", []) or [])

    @Property(str, notify=stateChanged)
    def colonizationNextCommodity(self): return _string(self._get("colonizationNextCommodity"), "-")

    @Property(int, notify=stateChanged)
    def colonizationNextRemaining(self): return int(self._get("colonizationNextRemaining", 0) or 0)

    @Property(int, notify=stateChanged)
    def colonizationNextAboard(self): return int(self._get("colonizationNextAboard", 0) or 0)

    @Property(int, notify=stateChanged)
    def colonizationNextLoadTarget(self): return int(self._get("colonizationNextLoadTarget", 0) or 0)

    @Property(int, notify=stateChanged)
    def colonizationCommodityLoads(self): return int(self._get("colonizationCommodityLoads", 0) or 0)

    @Property(int, notify=stateChanged)
    def colonizationProjectLoads(self): return int(self._get("colonizationProjectLoads", 0) or 0)

    @Property(int, notify=stateChanged)
    def colonizationContributionTotal(self): return int(self._get("colonizationContributionTotal", 0) or 0)

    @Property(str, notify=stateChanged)
    def colonizationPaceText(self): return _string(self._get("colonizationPaceText"), "WAITING FOR CONSTRUCTION DEPOT DATA")

    @Property(str, notify=stateChanged)
    def colonizationClaimStatus(self): return _string(self._get("colonizationClaimStatus"), "-")

    @Property(str, notify=stateChanged)
    def colonizationClaimSystem(self): return _string(self._get("colonizationClaimSystem"), "-")

    @Property('QVariantList', notify=stateChanged)
    def colonizationLogRows(self): return list(self._get("colonizationLogRows", []) or [])

    @Property('QVariantList', notify=stateChanged)
    def colonizationProjectRows(self): return list(self._get("colonizationProjectRows", []) or [])

    @Property(int, notify=stateChanged)
    def colonizationCurrentProjectIndex(self): return int(self._get("colonizationCurrentProjectIndex", -1) if self._get("colonizationCurrentProjectIndex", -1) is not None else -1)

    @Property(str, notify=stateChanged)
    def colonizationDataSource(self): return _string(self._get("colonizationDataSource"), "ELITE JOURNAL + SAVED PROJECTS")

    @Property(bool, notify=stateChanged)
    def tradeRouteBusy(self): return bool(self._get("tradeRouteBusy", False))

    @Property(str, notify=stateChanged)
    def tradeRouteStatus(self): return _string(self._get("tradeRouteStatus"), "READY // SELECT COMMODITY AND SEARCH")

    @Property('QVariantList', notify=stateChanged)
    def tradeRouteRows(self): return list(self._get("tradeRouteRows", []) or [])

    @Property(int, notify=stateChanged)
    def tradeRouteMaxLs(self): return int(self._get("tradeRouteMaxLs", 10000) or 10000)

    @Property(bool, notify=stateChanged)
    def tradeBestBusy(self): return bool(self._get("tradeBestBusy", False))

    @Property(str, notify=stateChanged)
    def tradeBestStatus(self): return _string(self._get("tradeBestStatus"), "READY // FIND THE BEST COMMODITY + LOOP")

    @Property('QVariantList', notify=stateChanged)
    def tradeBestRows(self): return list(self._get("tradeBestRows", []) or [])

    @Property(str, notify=stateChanged)
    def tradeCommodity(self): return _string(self._get("tradeCommodity"), "-")

    @Property('QVariantList', notify=stateChanged)
    def tradeCommodityOptions(self): return list(self._get("tradeCommodityOptions", []) or [])

    @Property(int, notify=stateChanged)
    def tradeConfiguredCargo(self): return int(self._get("tradeConfiguredCargo", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradePlannedCargo(self): return int(self._get("tradePlannedCargo", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeCargoAvailable(self): return int(self._get("tradeCargoAvailable", -1) if self._get("tradeCargoAvailable", -1) is not None else -1)

    @Property(int, notify=stateChanged)
    def tradeLatestBuyUnit(self): return int(self._get("tradeLatestBuyUnit", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeLatestSellUnit(self): return int(self._get("tradeLatestSellUnit", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeEstimatedProfitCycle(self): return int(self._get("tradeEstimatedProfitCycle", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeEstimatedRemainingProfit(self): return int(self._get("tradeEstimatedRemainingProfit", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeEstimatedTotalProfit(self): return int(self._get("tradeEstimatedTotalProfit", 0) or 0)

    @Property(str, notify=stateChanged)
    def tradeBuySystem(self): return _string(self._get("tradeBuySystem"), "-")

    @Property(str, notify=stateChanged)
    def tradeBuyStation(self): return _string(self._get("tradeBuyStation"), "-")

    @Property(str, notify=stateChanged)
    def tradeSellSystem(self): return _string(self._get("tradeSellSystem"), "-")

    @Property(str, notify=stateChanged)
    def tradeSellStation(self): return _string(self._get("tradeSellStation"), "-")

    @Property(bool, notify=stateChanged)
    def tradeLoopEnabled(self): return bool(self._get("tradeLoopEnabled", False))

    @Property(str, notify=stateChanged)
    def tradeLoopStatus(self): return _string(self._get("tradeLoopStatus"), "-")

    @Property(str, notify=stateChanged)
    def tradeLoopLastAction(self): return _string(self._get("tradeLoopLastAction"), "-")

    @Property(str, notify=stateChanged)
    def tradeMarketStation(self): return _string(self._get("tradeMarketStation"), "-")

    @Property(str, notify=stateChanged)
    def tradeMarketSystem(self): return _string(self._get("tradeMarketSystem"), "-")

    @Property(str, notify=stateChanged)
    def tradeMarketTimestamp(self): return _string(self._get("tradeMarketTimestamp"), "-")

    @Property(int, notify=stateChanged)
    def tradeMarketRows(self): return int(self._get("tradeMarketRows", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeMarketBuy(self): return int(self._get("tradeMarketBuy", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeMarketSell(self): return int(self._get("tradeMarketSell", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeMarketStock(self): return int(self._get("tradeMarketStock", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeMarketDemand(self): return int(self._get("tradeMarketDemand", 0) or 0)

    @Property('QVariantList', notify=stateChanged)
    def tradeLedgerRows(self): return list(self._get("tradeLedgerRows", []) or [])

    @Property(int, notify=stateChanged)
    def tradeRealizedProfit(self): return int(self._get("tradeRealizedProfit", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradePowerRank(self): return int(self._get("tradePowerRank", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradePowerMerits(self): return int(self._get("tradePowerMerits", 0) or 0)

    @Property(str, notify=stateChanged)
    def tradeLastMerit(self): return _string(self._get("tradeLastMerit"), "-")

    @Property(str, notify=stateChanged)
    def tradeRunLength(self): return _string(self._get("tradeRunLength"), "CONTINUOUS")

    @Property(int, notify=stateChanged)
    def tradeRunTargetCycles(self): return int(self._get("tradeRunTargetCycles", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeRunCompletedCycles(self): return int(self._get("tradeRunCompletedCycles", 0) or 0)

    @Property(int, notify=stateChanged)
    def tradeRunRemainingCycles(self): return int(self._get("tradeRunRemainingCycles", -1) if self._get("tradeRunRemainingCycles", -1) is not None else -1)

    @Property(bool, notify=stateChanged)
    def combatActive(self): return bool(self._get("combatActive", False))

    @Property(str, notify=stateChanged)
    def combatState(self): return _string(self._get("combatState"), "IDLE")

    @Property(list, notify=stateChanged)
    def combatStatusRows(self): return list(self._get("combatStatusRows", []) or [])

    @Property(list, notify=stateChanged)
    def combatSessionRows(self): return list(self._get("combatSessionRows", []) or [])

    @Property(list, notify=stateChanged)
    def combatAlertRows(self): return list(self._get("combatAlertRows", []) or [])

    @Property(str, notify=stateChanged)
    def combatThreatWarning(self): return _string(self._get("combatThreatWarning"), "-")

    @Property(bool, notify=stateChanged)
    def combatScanAlertActive(self): return bool(self._get("combatScanAlertActive", False))

    @Property(str, notify=stateChanged)
    def combatScanAlertText(self): return _string(self._get("combatScanAlertText"), "CLEAR")

    @Property(list, notify=stateChanged)
    def combatSupportRows(self): return list(self._get("combatSupportRows", []) or [])

    @Property(list, notify=stateChanged)
    def combatTargetRows(self): return list(self._get("combatTargetRows", []) or [])

    @Property(list, notify=stateChanged)
    def combatThreatHistory(self): return list(self._get("combatThreatHistory", []) or [])

    @Property(list, notify=stateChanged)
    def combatEventHistory(self): return list(self._get("combatEventHistory", []) or [])

    @Property(bool, notify=stateChanged)
    def combatTargetPresent(self): return bool(self._get("combatTargetPresent", False))

    @Property(str, notify=stateChanged)
    def combatTargetName(self): return _string(self._get("combatTargetName"), "NO TARGET")

    @Property(str, notify=stateChanged)
    def combatTargetPilot(self): return _string(self._get("combatTargetPilot"), "-")

    @Property(str, notify=stateChanged)
    def combatTargetShip(self): return _string(self._get("combatTargetShip"), "-")

    @Property(str, notify=stateChanged)
    def combatTargetLegal(self): return _string(self._get("combatTargetLegal"), "-")

    @Property(str, notify=stateChanged)
    def combatTargetFaction(self): return _string(self._get("combatTargetFaction"), "-")

    @Property(str, notify=stateChanged)
    def combatTargetRank(self): return _string(self._get("combatTargetRank"), "-")

    @Property(int, notify=stateChanged)
    def combatTargetHullPercent(self):
        try: return int(self._get("combatTargetHullPercent", -1))
        except Exception: return -1

    @Property(int, notify=stateChanged)
    def combatTargetShieldPercent(self):
        try: return int(self._get("combatTargetShieldPercent", -1))
        except Exception: return -1

    @Property(str, notify=stateChanged)
    def combatTargetBounty(self): return _string(self._get("combatTargetBounty"), "-")

    @Property(str, notify=stateChanged)
    def combatTargetSubsystem(self): return _string(self._get("combatTargetSubsystem"), "-")

    @Property(int, notify=stateChanged)
    def combatTargetSubsystemPercent(self):
        try: return int(self._get("combatTargetSubsystemPercent", -1))
        except Exception: return -1

    @Property(int, notify=stateChanged)
    def combatTargetScanStage(self):
        try: return int(self._get("combatTargetScanStage", 0) or 0)
        except Exception: return 0

    @Property(str, notify=stateChanged)
    def combatTacticalAdvisory(self): return _string(self._get("combatTacticalAdvisory"), "COMBAT OBSERVER STANDING BY")

    @Property(bool, notify=stateChanged)
    def combatUnderAttack(self): return bool(self._get("combatUnderAttack", False))

    @Property(str, notify=stateChanged)
    def combatHudMode(self): return _string(self._get("combatHudMode"), "UNKNOWN")

    @Property(str, notify=stateChanged)
    def combatFireGroup(self): return _string(self._get("combatFireGroup"), "-")

    @Property(int, notify=stateChanged)
    def combatCollectorUpperBound(self):
        try: return int(self._get("combatCollectorUpperBound", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def combatLimpetReserve(self):
        try: return int(self._get("combatLimpetReserve", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def combatStolenCargo(self):
        try: return int(self._get("combatStolenCargo", 0) or 0)
        except Exception: return 0

    @Property(int, notify=stateChanged)
    def combatCrewWagesTotal(self):
        try: return int(self._get("combatCrewWagesTotal", 0) or 0)
        except Exception: return 0

    @Property(str, notify=stateChanged)
    def combatCommandStatus(self): return _string(self._get("combatCommandStatus"), "-")

    @Property(str, notify=stateChanged)
    def combatEgressStatus(self): return _string(self._get("combatEgressStatus"), "-")

    @Property(bool, notify=stateChanged)
    def combatDynamicPipsEnabled(self): return bool(self._get("combatDynamicPipsEnabled", False))

    @Property(str, notify=stateChanged)
    def combatDynamicPipsMode(self): return _string(self._get("combatDynamicPipsMode"), "OFF")

    @Property(str, notify=stateChanged)
    def combatDynamicPipsStatus(self): return _string(self._get("combatDynamicPipsStatus"), "-")

    @Property(bool, notify=stateChanged)
    def combatAutoSubsystemEnabled(self): return bool(self._get("combatAutoSubsystemEnabled", False))

    @Property(str, notify=stateChanged)
    def combatAutoSubsystemStatus(self): return _string(self._get("combatAutoSubsystemStatus"), "-")

    @Property(bool, notify=stateChanged)
    def combatAutoChaffEnabled(self): return bool(self._get("combatAutoChaffEnabled", False))

    @Property(str, notify=stateChanged)
    def combatAutoChaffStatus(self): return _string(self._get("combatAutoChaffStatus"), "-")

    @Property(str, notify=stateChanged)
    def combatResStatus(self): return _string(self._get("combatResStatus"), "-")

    @Property(bool, notify=stateChanged)
    def combatResBusy(self): return bool(self._get("combatResBusy", False))

    @Property('QVariantList', notify=stateChanged)
    def combatResRows(self): return list(self._get("combatResRows", []) or [])

    @Property(str, notify=stateChanged)
    def combatResNearest(self): return _string(self._get("combatResNearest"), "-")

    @Property(list, notify=stateChanged)
    def navSystemSuggestions(self): return list(self._nav_system_suggestions)

    @Property(str, notify=stateChanged)
    def navSuggestionStatus(self): return self._nav_suggestion_status

    @Property(str, notify=stateChanged)
    def navJumpsText(self):
        jumps = self.routeJumps
        return "--" if jumps < 0 else str(jumps)

    @Property(str, notify=stateChanged)
    def navRouteState(self):
        if not self.navArmed:
            return "OFF"
        return "ACTIVE" if self.destination != "NO ROUTE" else "READY"

    @Slot(str, result=str)
    def levelColor(self, level: str) -> str:
        return {
            "ok": "#2aff80",
            "warn": "#d6a540",
            "bad": "#ff493e",
            "info": "#506454",
        }.get(str(level or "").lower(), "#506454")


if __name__ == "__main__":
    # Keep fractional Windows DPI factors (125/150/175/200%) exact. Qt 6 already
    # renders in device-independent pixels; PassThrough prevents coarse rounding
    # from making the cockpit jump in size between 2K, 4K and 5K displays.
    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough
    )

    if not _claim_single_instance():
        print("Elite AI Bridge is already running. Activated the existing window.", file=sys.stderr)
        raise SystemExit(0)

    # BootSplash is a QWidget, so the application object must be QApplication,
    # not QGuiApplication. QApplication is still a QGuiApplication subclass,
    # so the existing QML/GUI behavior remains compatible.
    app = QApplication(sys.argv)
    app.setApplicationName(f"Elite AI Bridge v{APP_VERSION}")
    app_icon = _resource_path(Path("assets") / "Elite_AI_Bridge.ico")
    if app_icon.exists():
        app.setWindowIcon(QIcon(str(app_icon)))

    # The CRT boot screen is deliberately created before the backend and heavy
    # QML scene. It gives the pilot immediate visual feedback while the real
    # application initializes underneath it.
    boot_settings = QSettings("EliteAIBridge", "QMLFrontend")
    screens = list(QGuiApplication.screens())
    boot_screen = QGuiApplication.primaryScreen() or (screens[0] if screens else None)
    saved_key = str(boot_settings.value("display/last_screen", "") or "")
    saved_name = saved_key.split("|", 1)[0] if saved_key else ""
    for candidate in screens:
        try:
            g = candidate.geometry()
            key = f"{candidate.name()}|{g.x()},{g.y()},{g.width()},{g.height()}"
            if saved_key and key == saved_key:
                boot_screen = candidate
                break
        except Exception:
            pass
    else:
        if saved_name:
            for candidate in screens:
                try:
                    if candidate.name() == saved_name:
                        boot_screen = candidate
                        break
                except Exception:
                    pass

    boot_art = _resource_path(Path("frontend") / "assets" / "elite_ai_bridge_boot_sequence.png")
    splash = BootSplash(boot_screen, boot_art)
    splash.showFullScreen()
    splash.raise_()
    app.processEvents()

    backend = BackendProcess()
    try:
        backend.start()
    except Exception as exc:
        print(f"Failed to start backend: {exc}", file=sys.stderr)

    vm = BridgeViewModel(backend)
    app.installEventFilter(vm)
    app.aboutToQuit.connect(vm.shutdown)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("bridge", vm)
    qml_file = _resource_path(Path("frontend") / "qml" / "Main.qml")
    engine.load(QUrl.fromLocalFile(str(qml_file)))
    if not engine.rootObjects():
        splash.close()
        vm.shutdown()
        raise SystemExit(2)

    window = engine.rootObjects()[0]
    vm.attach_window(window)
    vm.restore_window_monitor()
    window.showMaximized()
    splash.set_main_window(window)

    def boot_ready() -> bool:
        try:
            if not bool(vm.connected):
                return False
            if bool(vm.voiceEngineWarming):
                return False
            return True
        except Exception:
            return False

    splash.set_ready_probe(boot_ready)

    # The main window is already visible behind the CRT screen. Keep the boot
    # animation alive until the Bridge has actually connected and the voice engine
    # has finished its warm-up, but never trap a degraded startup behind the splash.
    def keep_splash_on_top():
        if splash.isVisible() and window.isVisible():
            splash.raise_()

    splash_stack_timer = QTimer()
    splash_stack_timer.setInterval(250)
    splash_stack_timer.timeout.connect(keep_splash_on_top)
    # BootSplash uses WA_DeleteOnClose. Stop the timer before Qt destroys the
    # widget so a queued timeout cannot call methods on a deleted C++ object.
    splash.destroyed.connect(splash_stack_timer.stop)
    splash_stack_timer.start()

    exit_code = app.exec()
    splash_stack_timer.stop()
    # aboutToQuit normally performs this cleanup. Calling it again is safe because
    # BridgeViewModel.shutdown() is idempotent and guarantees the backend process,
    # timers and worker pools are not left holding the extracted application folder.
    vm.shutdown()
    raise SystemExit(exit_code)
