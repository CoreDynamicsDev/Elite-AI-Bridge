"""Headless host for the known-good Elite AI Bridge v0.12.95 engine.

The legacy engine remains the authority for journal/status parsing, bindings,
automation, AI/voice/audio, and cockpit-command arbitration.  This module only
publishes a read-only snapshot for the QML frontend and queues explicit command
requests back onto the Tk/Bridge thread.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
import copy
import hashlib
import json
import math
import os
import queue
import shutil
import subprocess
import sys
import re
import threading
import time
import zipfile
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from types import MethodType
from pathlib import Path

# Portable releases carry the Supertonic model beside the backend executable.
# Point Supertonic at that bundled cache before the protected engine imports it.
# Development/source runs keep using the normal per-user Supertonic cache.
if getattr(sys, "frozen", False):
    _portable_root = Path(sys.executable).resolve().parent
    _portable_supertonic = _portable_root / "supertonic3"
    if _portable_supertonic.is_dir():
        os.environ["SUPERTONIC_CACHE_DIR"] = str(_portable_supertonic)
        os.environ["ELITE_BRIDGE_BUNDLED_SUPERTONIC"] = "1"

import EliteAIBridge_v0_12_95 as legacy

# QML copilot guidance policy. The locked engine keeps its original prompt; this
# adapter adds a simple intent rule so beginner help opens the relevant Bridge
# page/tour instead of interrogating the pilot for operational parameters.
try:
    legacy.AI_TOOL_INSTRUCTIONS += """

Elite AI Bridge QML guidance rules:
- Speak and write in English unless the commander explicitly asks you to use another language. Never switch languages because of a transcription mistake, garbled phrase, accent, or uncertain wording. If speech is unclear, ask a short clarification in English.
- Natural talk-density commands are direct settings, not questions. Phrases such as "talk less", "be less chatty", "shorter answers", "keep it brief", "less commentary", or "be less verbose" mean reduce the public talk level one step. "Talk more", "more commentary", "more detail", or "be more talkative" mean increase it one step. Explicit Quiet/Low, Balanced/Medium, and Talkative/High requests map to the matching public talk profile. Do not ask the commander to distinguish voice level from verbosity when this intent is clear.
- Bridge setting changes must happen in the background. Never open Setup, AI & Voice, Audio, or another page merely because set_bridge_setting was used. Keep the commander on the page they were already viewing unless they explicitly ask to open/show a page.
- First distinguish NAVIGATION, GUIDANCE, and ACTION. Plain navigation such as "show me the combat screen", "open Combat", or "go to Trade" means make that Bridge page visible only. Use show_bridge_workspace with guide=false and do not start Page Help, change Elite HUD mode, or execute any cockpit action.
- GUIDANCE requires explicit help/teaching language such as "show me how", "help me", "teach me", "explain", or "walk me through". For GUIDANCE, use show_bridge_workspace with guide=true. Do not ask for market radius, cargo, jump range, RES radius, or other task parameters merely to explain where a feature is or how to use it.
- Broad guidance such as 'help me with trade' should open that module and play its normal beginner tour. Specific guidance such as 'how do I use Best Trade' may open the matching workspace and play its focused saved help segment.
- Only run search/action tools when the commander actually asks you to DO the task, for example 'find me a High RES' or 'search for a trade'.
- For explicit cockpit-state requests such as night vision, lights, landing gear, cargo scoop, hardpoints, flight assist, silent running, or Combat/Analysis HUD mode, use set_cockpit_control. Never invent a raw key. Bridge resolves the active Elite keyboard binding and verifies the resulting Status.json state.
- For throttle presets and one-shot cockpit commands, use perform_cockpit_action. Examples: "half speed" or "50 percent throttle" = throttle_50; "full speed" = throttle_100; "all stop" = throttle_0; boost, chaff, heat sink, shield cell, targeting, fire-group cycling, radar range, maps, FSD/supercruise, wing orders, and fighter orders also use perform_cockpit_action. Bridge always resolves the commander's CURRENT Elite .binds entry at execution time.
- For direct distributor requests such as "full power to shields", "power to weapons", "full engines", or "balance pips", use set_power_distribution. A direct pilot PIP request temporarily overrides Dynamic PIPs so automation does not fight the commander. "Resume Auto Pips" clears that manual override and re-enables Dynamic PIPs if needed.
- When the commander says "find the best target", use find_best_target. This is a two-pass survey, not a full scan of every contact: first cycle a bounded full target list and record early ship type plus any legal status Elite already knows, then rank all observed candidates and cycle again to reacquire the winner. CLEAN contacts are invalid and must be skipped; WANTED contacts are preferred. Do not stop at the first Python/Anaconda.
- When the commander is DOCKED, plain departure language such as "launch", "take off", "depart", "leave the station", or "get us out of here" means Auto Launch now. Do not ask whether the commander means launch when docked.
- "Clear and jump" means run Clear Station + FSD now. Only phrases that explicitly say automatic/automatically/after launch/session rule should change the Clear + Jump After Launch setting.
- In supercruise with an SCO-capable FSD, "SCO", "engage SCO", "overcharge", or "supercruise overcharge" means perform the sco cockpit action, which uses the commander's CURRENT UseBoostJuice binding.
- If the commander asks whether a cockpit command is available, or asks for an uncommon bound control, use get_cockpit_bindings to inspect the active Elite preset rather than guessing. If it returns a READY exact Elite action that is not covered by perform_cockpit_action, use perform_elite_binding with that exact action name.
- Never substitute a guessed physical key for an Elite action. If the active preset has no keyboard Primary/Secondary binding for a supported action, say that voice execution needs a keyboard binding for that Elite action.
- When guide=true, keep your spoken answer to one short sentence because the Bridge will immediately speak the saved beginner explanation.
- In spoken wording, do not say the acronym RES by itself. Say "Resource Extraction Site" instead. On-screen labels may still say RES Finder, High RES, or Haz RES.
"""
except Exception:
    pass

# QML integration policy extension: Python-class targets should use the proven
# .95 auto Power Plant selector when the pilot explicitly enables it.  The
# legacy engine source stays byte-for-byte unchanged.
try:
    legacy.AUTO_POWERPLANT_HEAVY_SHIP_KEYS.update({"python", "pythonmkii", "pythonmk2"})
except Exception:
    pass

# v0.30.08 Auto Chaff retune. The former MED behavior becomes HIGH; MED moves
# to the former LOW behavior, and LOW becomes deliberately more conservative.
# The protected engine remains unchanged; only the integration runtime table is adjusted.
try:
    legacy.AUTO_CHAFF_PROFILES.update({
        "LOW": {"min_combat_seconds": 70.0, "attack_window_seconds": 120.0, "min_attacks": 3, "cooldown_seconds": 50.0},
        "MED": {"min_combat_seconds": 45.0, "attack_window_seconds": 90.0, "min_attacks": 2, "cooldown_seconds": 35.0},
        "HIGH": {"min_combat_seconds": 25.0, "attack_window_seconds": 45.0, "min_attacks": 1, "cooldown_seconds": 25.0},
    })
except Exception:
    pass

# Human-readable names for safe state-aware cockpit controls exposed by the QML adapter.
try:
    legacy.BindingsManager.DISPLAY_NAMES.update({
        "NightVisionToggle": "Night Vision",
        "ShipSpotLightToggle": "Ship Lights",
        "ToggleCargoScoop": "Cargo Scoop Toggle",
        "ToggleFlightAssist": "Flight Assist Toggle",
        "SilentRunningToggle": "Silent Running Toggle",
    })
except Exception:
    pass

# v0.30.08 retains the generic cockpit command registry introduced in v0.30.03. Smart AI interprets natural speech
# into one semantic command; Bridge then resolves the CURRENT Elite .binds entry
# and sends that binding. No physical key is hard-coded here. Stateful toggles stay
# in _qml_cockpit_control_specs() so they can be verified before/after execution.
COCKPIT_ACTIONS = {
    # Throttle presets
    "throttle_reverse_100": {"action": "SetSpeedMinus100", "label": "Reverse throttle 100%", "spoken": "Reverse throttle full."},
    "throttle_reverse_75": {"action": "SetSpeedMinus75", "label": "Reverse throttle 75%", "spoken": "Reverse throttle seventy five percent."},
    "throttle_reverse_50": {"action": "SetSpeedMinus50", "label": "Reverse throttle 50%", "spoken": "Reverse throttle fifty percent."},
    "throttle_reverse_25": {"action": "SetSpeedMinus25", "label": "Reverse throttle 25%", "spoken": "Reverse throttle twenty five percent."},
    "throttle_0": {"action": "SetSpeedZero", "label": "Throttle 0%", "spoken": "Throttle zero."},
    "throttle_25": {"action": "SetSpeed25", "label": "Throttle 25%", "spoken": "Throttle twenty five percent."},
    "throttle_50": {"action": "SetSpeed50", "label": "Throttle 50%", "spoken": "Throttle fifty percent."},
    "throttle_75": {"action": "SetSpeed75", "label": "Throttle 75%", "spoken": "Throttle seventy five percent."},
    "throttle_100": {"action": "SetSpeed100", "label": "Throttle 100%", "spoken": "Full throttle."},
    "reverse_throttle_toggle": {"action": "ToggleReverseThrottleInput", "label": "Reverse throttle toggle", "spoken": "Reverse throttle toggled."},

    # Flight / navigation
    "boost": {"action": "UseBoostJuice", "label": "Boost", "spoken": "Boost."},
    "sco": {"action": "UseBoostJuice", "label": "Supercruise Overcharge", "spoken": "Supercruise overcharge."},
    "supercruise_overcharge": {"action": "UseBoostJuice", "label": "Supercruise Overcharge", "spoken": "Supercruise overcharge."},
    "fsd_toggle": {"action": "HyperSuperCombination", "label": "FSD / Hyper-Supercruise", "spoken": "Frame shift command sent."},
    "supercruise": {"action": "Supercruise", "label": "Supercruise", "spoken": "Supercruise command sent."},
    "hyperspace": {"action": "Hyperspace", "label": "Hyperspace", "spoken": "Hyperspace command sent."},
    "orbit_lines_toggle": {"action": "OrbitLinesToggle", "label": "Orbit lines", "spoken": "Orbit lines toggled."},
    "target_next_route_system": {"action": "TargetNextRouteSystem", "label": "Next route system", "spoken": "Next route system targeted."},
    "galaxy_map": {"action": "GalaxyMapOpen", "label": "Galaxy Map", "spoken": "Galaxy map."},
    "system_map": {"action": "SystemMapOpen", "label": "System Map", "spoken": "System map."},
    "fss": {"action": "ExplorationFSSEnter", "label": "Full Spectrum Scanner", "spoken": "Full Spectrum Scanner."},

    # Targeting / combat support. Weapon-fire bindings are intentionally excluded.
    "target_under_reticle": {"action": "SelectTarget", "label": "Target under reticle", "spoken": "Target selected."},
    "target_next": {"action": "CycleNextTarget", "label": "Next target", "spoken": "Next target."},
    "target_previous": {"action": "CyclePreviousTarget", "label": "Previous target", "spoken": "Previous target."},
    "target_highest_threat": {"action": "SelectHighestThreat", "label": "Highest threat", "spoken": "Highest threat targeted."},
    "target_next_hostile": {"action": "CycleNextHostileTarget", "label": "Next hostile target", "spoken": "Next hostile."},
    "target_previous_hostile": {"action": "CyclePreviousHostileTarget", "label": "Previous hostile target", "spoken": "Previous hostile."},
    "subsystem_next": {"action": "CycleNextSubsystem", "label": "Next subsystem", "spoken": "Next subsystem."},
    "subsystem_previous": {"action": "CyclePreviousSubsystem", "label": "Previous subsystem", "spoken": "Previous subsystem."},
    "fire_group_next": {"action": "CycleFireGroupNext", "label": "Next fire group", "spoken": "Next fire group."},
    "fire_group_previous": {"action": "CycleFireGroupPrevious", "label": "Previous fire group", "spoken": "Previous fire group."},
    "heat_sink": {"action": "DeployHeatSink", "label": "Heat sink", "spoken": "Heat sink deployed."},
    "shield_cell": {"action": "UseShieldCell", "label": "Shield cell", "spoken": "Shield cell activated."},
    "chaff": {"action": "FireChaffLauncher", "label": "Chaff", "spoken": "Chaff deployed."},
    "field_neutralizer": {"action": "TriggerFieldNeutraliser", "label": "Shutdown field neutralizer", "spoken": "Field neutralizer triggered."},
    "radar_range_up": {"action": "RadarIncreaseRange", "label": "Increase radar range", "spoken": "Radar range increased."},
    "radar_range_down": {"action": "RadarDecreaseRange", "label": "Decrease radar range", "spoken": "Radar range decreased."},

    # Wing / fighter controls
    "wingman_1": {"action": "TargetWingman0", "label": "Wingman 1", "spoken": "Wingman one targeted."},
    "wingman_2": {"action": "TargetWingman1", "label": "Wingman 2", "spoken": "Wingman two targeted."},
    "wingman_3": {"action": "TargetWingman2", "label": "Wingman 3", "spoken": "Wingman three targeted."},
    "targets_target": {"action": "SelectTargetsTarget", "label": "Target's target", "spoken": "Target's target selected."},
    "wing_nav_lock": {"action": "WingNavLock", "label": "Wing nav lock", "spoken": "Wing nav lock toggled."},
    "fighter_recall": {"action": "OrderRequestDock", "label": "Fighter recall / dock", "spoken": "Fighter recall sent."},
    "fighter_defensive": {"action": "OrderDefensiveBehaviour", "label": "Fighter defensive", "spoken": "Fighter defensive order sent."},
    "fighter_aggressive": {"action": "OrderAggressiveBehaviour", "label": "Fighter aggressive", "spoken": "Fighter aggressive order sent."},
    "fighter_focus_target": {"action": "OrderFocusTarget", "label": "Fighter focus target", "spoken": "Fighter focus target order sent."},
    "fighter_hold_fire": {"action": "OrderHoldFire", "label": "Fighter hold fire", "spoken": "Fighter hold fire order sent."},
    "fighter_hold_position": {"action": "OrderHoldPosition", "label": "Fighter hold position", "spoken": "Fighter hold position order sent."},
    "fighter_follow": {"action": "OrderFollow", "label": "Fighter follow", "spoken": "Fighter follow order sent."},

    # Panels / utility
    "panel_left": {"action": "FocusLeftPanel", "label": "Left panel", "spoken": "Left panel."},
    "panel_comms": {"action": "FocusCommsPanel", "label": "Comms panel", "spoken": "Comms panel."},
    "panel_quick_comms": {"action": "QuickCommsPanel", "label": "Quick comms", "spoken": "Quick comms."},
    "panel_radar": {"action": "FocusRadarPanel", "label": "Role panel", "spoken": "Role panel."},
    "panel_right": {"action": "FocusRightPanel", "label": "Right panel", "spoken": "Right panel."},
    "colonization_module": {"action": "TriggerColonisationModule", "label": "Colonization module", "spoken": "Colonization module command sent."},
}

# Never expose blind destructive/fire controls through the generic AI binding path.
COCKPIT_PROTECTED_ELITE_ACTIONS = {
    "PrimaryFire", "SecondaryFire", "EjectAllCargo",
}

# Generic execution can cover additional one-shot ship controls discovered from
# the live preset, but these action shapes are deliberately not blind-tapped.
COCKPIT_CONTEXTUAL_OR_HOLD_ACTIONS = {
    "UIFocus", "UI_Up", "UI_Down", "UI_Left", "UI_Right", "UI_Select", "UI_Back", "UI_Toggle",
    "ForwardKey", "BackwardKey", "UpThrustButton", "ToggleButtonUpInput",
    "ChargeECM", "ExplorationFSSDiscoveryScan",
}
COCKPIT_BLOCKED_ACTION_PREFIXES = ("Humanoid", "Cam", "FreeCam", "VanityCamera")

# v0.30.08 Bridge-owned runtime controls exposed to Smart AI. These are
# application settings/toggles, not Elite keybinds. The registry keeps the AI
# vocabulary aligned with the switches shown in QML so status questions and
# explicit on/off requests use one source of truth.
BRIDGE_AI_SETTING_NAMES = [
    "dynamic_pips_enabled",
    "auto_subsystem_enabled",
    "auto_chaff_enabled",
    "auto_chaff_profile",
    "smart_auto_ai_enabled",
    "ai_trade_commentary_enabled",
    "ai_mission_commentary_enabled",
    "ai_travel_commentary_enabled",
    "auto_refuel_enabled",
    "auto_repair_enabled",
    "auto_rearm_enabled",
    "clear_and_jump_after_launch",
    "voice_level",
    "voice_volume",
    "voice_speed",
    "sfx_enabled",
    "sfx_volume",
    "startup_sound_enabled",
    "voice_attention_mode",
    "voice_input_mode",
]

try:
    legacy.BindingsManager.DISPLAY_NAMES.update({
        spec["action"]: spec["label"] for spec in COCKPIT_ACTIONS.values()
    })
except Exception:
    pass

# QML-only UI audio extensions. Keep the locked .95 engine source untouched.
# The former startup sound is now wizard music and only plays while the guided
# setup overlay is visible. Navigation deliberately replaces music with a cue,
# then narrates the destination page after that cue finishes.
try:
    legacy.SFX_SPECS["startup"]["label"] = "Wizard / guided setup music"
    legacy.SFX_SPECS["startup"]["priority"] = 10
    legacy.SFX_SPECS.update({
        "ui_nav": {"label": "UI navigation beep", "file": "ui_nav.wav", "priority": 20},
        "ui_confirm": {"label": "UI confirmation chirp", "file": "ui_confirm.wav", "priority": 25},
        "ui_warning": {"label": "UI warning tone", "file": "ui_warning.wav", "priority": 30},
    })
    legacy.SFX_LABEL_TO_KEY.clear()
    legacy.SFX_LABEL_TO_KEY.update({row["label"]: key for key, row in legacy.SFX_SPECS.items()})
except Exception:
    pass

# Wizard speech needs hard interruption when the pilot presses Back/Next. The locked
# v0.12.95 Supertonic worker plays through a blocking RawOutputStream, so generic
# sounddevice.stop() cannot reliably stop it. Wrap only the voice worker's PCM player
# with the engine's existing stop_event hook; all non-voice audio keeps its normal path.
_WIZARD_VOICE_INTERRUPT = threading.Event()
_WIZARD_VOICE_CONTEXT = threading.local()
_ORIGINAL_PCM_WAV_PLAYER = legacy._play_pcm_wav_blocking

def _qml_interruptible_pcm_wav_player(path, device_name="System Default", stop_event=None):
    event = stop_event
    if event is None and threading.current_thread().name == "EliteBridge-Voice":
        event = getattr(_WIZARD_VOICE_CONTEXT, "cancel", _WIZARD_VOICE_INTERRUPT)
    return _ORIGINAL_PCM_WAV_PLAYER(path, device_name, stop_event=event)

legacy._play_pcm_wav_blocking = _qml_interruptible_pcm_wav_player

# Supertonic uses WinSound when sounddevice is unavailable. Cancel stale jobs
# on that path too, without changing the legacy engine's choice of backend.
if os.name == "nt":
    import winsound
    _ORIGINAL_WINSOUND_PLAYER = winsound.PlaySound

    def _qml_winsound_player(sound, flags):
        if threading.current_thread().name == "EliteBridge-Voice":
            cancel = getattr(_WIZARD_VOICE_CONTEXT, "cancel", _WIZARD_VOICE_INTERRUPT)
            if sound is not None and cancel.is_set():
                return
        return _ORIGINAL_WINSOUND_PLAYER(sound, flags)

    winsound.PlaySound = _qml_winsound_player

class QmlSFXManager(legacy.BridgeSFXManager):
    """Reuse legacy settings/files, but expose completion and serialize streams."""
    _output_lock = threading.Lock()

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._play_thread = None
        self.wait_for_voice = None

    def is_playing(self):
        return self._play_thread is not None and self._play_thread.is_alive()

    def play(self, key, *, force=False, allow_disabled=False):
        key = str(key or "").strip().lower()
        spec = legacy.SFX_SPECS.get(key)
        if not spec or not self.enabled or self.volume <= 0:
            return False
        if not allow_disabled and not self.enabled_by_key.get(key, True):
            self.last_error = f"{spec['label']} is disabled"
            return False
        source, _ = self.source_for(key)
        if not source.is_file():
            self.last_error = f"Missing sound: {source.name}"
            return False
        with self._lock:
            if not force and self.is_playing() and int(spec.get("priority", 0)) < self.current_priority:
                self.drop_count += 1
                return False
            self.stop()
            stopper = self._play_stop = threading.Event()
            generation = self._play_generation
            device = self.output_device
            self.last_error = ""
            self.last_sound = spec["label"]
            self.last_file = source.name
            self.current_priority = int(spec.get("priority", 0))
            self.status = "PLAYING"

            def play_audio():
                try:
                    while self.wait_for_voice is not None and self.wait_for_voice():
                        if stopper.wait(0.02):
                            return
                    # A replacement waits for the old stream to close, not a WAV estimate.
                    with self._output_lock:
                        if stopper.is_set():
                            return
                        playback = self._scaled_path(source)
                        if stopper.is_set():
                            return
                        self.current_until_mono = time.monotonic() + self._wav_duration(playback)
                        if legacy.SOUNDDEVICE_AVAILABLE:
                            legacy._play_pcm_wav_blocking(playback, device, stopper)
                        else:
                            import winsound
                            winsound.PlaySound(str(playback), winsound.SND_FILENAME | winsound.SND_NODEFAULT)
                except Exception as exc:
                    if generation == self._play_generation:
                        self.last_error = str(exc)
                finally:
                    if generation == self._play_generation:
                        self.current_until_mono = 0.0
                        self.current_priority = -1
                        self.status = f"SFX failed: {self.last_error}" if self.last_error else "READY"

            self._play_thread = threading.Thread(target=play_audio, daemon=True, name="EliteBridge-SFX")
            self._play_thread.start()
            self.play_count += 1
            return True

    def tick(self):
        # Configuration refreshes and estimated durations are not completion events.
        if self.is_playing():
            self.status = "PLAYING"
        elif self.status == "PLAYING":
            self.status = f"SFX failed: {self.last_error}" if self.last_error else "READY"


legacy.BridgeSFXManager = QmlSFXManager


class QmlVoiceWorker(legacy.VoiceSpeechWorker):
    """QML voice worker with cancellable speech and fast cold-start warm-up."""

    @staticmethod
    def _bridge_pronunciation_text(text):
        """Small spoken-only lexicon for Elite names the local TTS misreads."""
        spoken = str(text or "")
        # Supertonic can read Sidewinder as "side wind er". This spelling keeps
        # the visible UI/chat untouched while steering speech toward SIDE-WINE-DER.
        spoken = re.sub(r"\bsidewinder\b", "side wine der", spoken, flags=re.IGNORECASE)
        # Product/provider names need deterministic local-TTS pronunciation. Keep
        # visible UI text canonical and alter only the speech payload.
        spoken = re.sub(r"\bOpenAI\b", "Open ay eye", spoken, flags=re.IGNORECASE)
        # Expand common initialisms globally so Supertonic never tries to turn
        # them into words. OpenAI is handled first to avoid a partial match.
        spoken = re.sub(r"\bAPI\b", "ay pee eye", spoken, flags=re.IGNORECASE)
        spoken = re.sub(r"\bAI\b", "ay eye", spoken, flags=re.IGNORECASE)
        # Elite distance units: expand only standalone units after a number.
        # Keep singular grammar for exactly 1 and plural for every other value.
        def _distance_unit(match):
            raw = match.group(1)
            unit = match.group(2).lower()
            try:
                singular = float(raw.replace(",", "")) == 1.0
            except Exception:
                singular = False
            if unit == "ly":
                return f"{raw} light year" if singular else f"{raw} light years"
            return f"{raw} light second" if singular else f"{raw} light seconds"
        spoken = re.sub(r"(?<![\w.])(\d[\d,]*(?:\.\d+)?)\s*(LY|LS)\b", _distance_unit, spoken, flags=re.IGNORECASE)
        spoken = re.sub(r"\bElite\b", "E leet", spoken, flags=re.IGNORECASE)
        return spoken

    def __init__(self):
        super().__init__()
        self._qml_neural_warm_state = "IDLE"
        self._qml_neural_warm_started_mono = 0.0
        self._qml_neural_warm_ready_mono = 0.0
        self._qml_neural_warm_duration_ms = 0
        self._qml_neural_warm_error = ""

    def config_snapshot(self):
        cfg = super().config_snapshot()
        cfg["_wizard_cancel"] = _WIZARD_VOICE_INTERRUPT
        return cfg

    def _prewarm_supertonic(self):
        """Warm only the neural path needed for first speech.

        The protected .95 worker also pre-warmed the optional pitch-DSP path by
        importing librosa during startup. In a frozen Windows build that import can
        dominate cold start even though the OOBE default pitch is NORMAL. The QML
        release therefore loads Supertonic, resolves the selected voice style and
        runs one tiny inference, but defers optional pitch-DSP loading until a pilot
        actually selects a non-normal pitch.
        """
        cfg = self.config_snapshot()
        engine = self._clean_engine(cfg.get("engine"))
        if engine not in ("AUTO", "SUPERTONIC") or not self.supertonic_available():
            self._qml_neural_warm_state = "FALLBACK"
            return
        started = time.monotonic()
        self._qml_neural_warm_started_mono = started
        self._qml_neural_warm_state = "INITIALIZING"
        self.status = "WARMING • Bridge neural voice"
        try:
            print("[VOICE] Supertonic cold-start warm-up begin", flush=True)
            tts = self._load_supertonic()
            voice = str(cfg.get("voice") or "M1").upper()
            if voice not in self.SUPER_VOICES:
                voice = "M1"
            style = self._super_style_cache.get(voice)
            if style is None:
                style = tts.get_voice_style(voice_name=voice)
                self._super_style_cache[voice] = style
            self.status = f"WARMING • Supertonic {voice}"
            # Pay the ONNX first-inference cost with the shortest useful utterance.
            # Do NOT import/warm librosa here; NORMAL pitch needs no pitch DSP.
            warm_wav, _ = tts.synthesize(
                text="Ready.",
                voice_style=style,
                lang="en",
                total_steps=5,
                speed=1.2,
            )
            # Character processing is lightweight (NumPy only) and is safe to warm
            # when the selected preset actually uses it.
            effect = str(cfg.get("effect") or "CLEAN").upper()
            effect_strength = int(round(self._clamp(cfg.get("effect_strength"), 0, 100, 0)))
            if effect != "CLEAN" and effect_strength > 0:
                try:
                    self._apply_voice_character(warm_wav, effect, effect_strength)
                except Exception:
                    pass
            elapsed_ms = int(round((time.monotonic() - started) * 1000.0))
            self._qml_neural_warm_duration_ms = elapsed_ms
            self._qml_neural_warm_ready_mono = time.monotonic()
            self._qml_neural_warm_state = "READY"
            self.status = f"READY • Supertonic {voice} warmed"
            print(f"[VOICE] Supertonic cold-start warm-up ready in {elapsed_ms} ms", flush=True)
        except Exception as exc:
            elapsed_ms = int(round((time.monotonic() - started) * 1000.0))
            self._qml_neural_warm_duration_ms = elapsed_ms
            self._qml_neural_warm_error = str(exc)
            self._qml_neural_warm_state = "FALLBACK"
            self._supertonic_import_error = str(exc)
            self.last_error = str(exc)
            self.status = "READY • Supertonic unavailable; Windows fallback armed"
            print(f"[VOICE] Supertonic warm-up failed after {elapsed_ms} ms: {exc}", flush=True)

    def _speak_supertonic(self, text, cfg):
        self._qml_speech_active = True
        cancel = cfg.get("_wizard_cancel", _WIZARD_VOICE_INTERRUPT)
        _WIZARD_VOICE_CONTEXT.cancel = cancel
        spoken_text = self._bridge_pronunciation_text(text)
        try:
            if not cancel.is_set():
                return super()._speak_supertonic(spoken_text, cfg)
        finally:
            if cancel.is_set():
                self.status = "READY • cancelled wizard speech"
            self._qml_speech_active = False

    def _start_windows_process(self, cfg):
        """Persistent System.Speech worker with completion acknowledgements.

        The protected .95 worker intentionally stays untouched. QML's adapter owns
        this richer protocol so the SPEAKING state reflects real playback time.
        """
        if os.name != "nt":
            raise RuntimeError("Windows system voice unavailable on this OS.")
        exe = shutil.which("powershell.exe") or shutil.which("powershell")
        if not exe:
            raise RuntimeError("Windows PowerShell was not found.")
        volume = int(round(self._clamp(cfg.get("volume"), 0, 100, 80)))
        rate = self._windows_rate_from_speed(cfg.get("speed"))
        voice = str(cfg.get("voice") or "System Default").strip()
        select_line = ""
        if voice and voice not in ("System Default", *self.SUPER_VOICES):
            select_line = f"try {{ $voice.SelectVoice('{self._ps_single_quote(voice)}') }} catch {{ }}\n"
        script = f"""Add-Type -AssemblyName System.Speech
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voice.Volume = {volume}
$voice.Rate = {rate}
{select_line}[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
while (($line = [Console]::In.ReadLine()) -ne $null) {{
    if ($line -eq '__ELITE_BRIDGE_VOICE_EXIT__') {{ break }}
    if ([string]::IsNullOrWhiteSpace($line)) {{ continue }}
    try {{
        $voice.Speak($line)
        [Console]::Out.WriteLine('__ELITE_BRIDGE_VOICE_DONE__')
    }} catch {{
        [Console]::Out.WriteLine('__ELITE_BRIDGE_VOICE_ERROR__')
    }}
    [Console]::Out.Flush()
}}
try {{ $voice.Dispose() }} catch {{ }}
"""
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        self._windows_process = subprocess.Popen(
            [exe, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", errors="replace", bufsize=1, creationflags=flags,
        )
        self._windows_process_config = (volume, rate, voice)

    def _stop_windows_process(self):
        """Stop the fallback TTS worker and wait until it is truly gone.

        Wizard page changes may arrive while System.Speech is inside a blocking
        Speak() call.  The legacy helper terminated PowerShell but did not wait
        for process exit, allowing the next wizard page to start a second speech
        worker while the old one was still unwinding.  That race produced a brief
        SPEAKING lamp with no audible narration on fresh Windows PCs.
        """
        proc = self._windows_process
        self._windows_process = None
        self._windows_process_config = None
        if proc is None:
            return
        try:
            if proc.poll() is None and proc.stdin:
                proc.stdin.write("__ELITE_BRIDGE_VOICE_EXIT__\n")
                proc.stdin.flush()
        except Exception:
            pass
        try:
            if proc.poll() is None:
                proc.terminate()
        except Exception:
            pass
        forced = False
        try:
            proc.wait(timeout=0.35)
        except Exception:
            forced = True
            try:
                proc.kill()
            except Exception:
                pass
            try:
                proc.wait(timeout=0.25)
            except Exception:
                pass
        try:
            if proc.stdin:
                proc.stdin.close()
        except Exception:
            pass
        try:
            if proc.stdout:
                proc.stdout.close()
        except Exception:
            pass
        print(f"[VOICE] Windows fallback process stopped // forced={forced}", flush=True)

    def _speak_windows(self, text, cfg, fallback_reason=""):
        self._qml_speech_active = True
        cancel = cfg.get("_wizard_cancel", _WIZARD_VOICE_INTERRUPT)
        spoken_text = self._bridge_pronunciation_text(text)
        started = time.monotonic()
        try:
            if cancel.is_set():
                return None
            volume = int(round(self._clamp(cfg.get("volume"), 0, 100, 80)))
            rate = self._windows_rate_from_speed(cfg.get("speed"))
            voice = str(cfg.get("voice") or "System Default").strip()
            if voice in self.SUPER_VOICES:
                voice = "System Default"
            desired = (volume, rate, voice)
            if (
                self._windows_process is None
                or self._windows_process.poll() is not None
                or not self._windows_process.stdin
                or self._windows_process_config != desired
            ):
                self._stop_windows_process()
                cfg2 = dict(cfg)
                cfg2["voice"] = voice
                self._start_windows_process(cfg2)

            prefix = "FALLBACK • " if fallback_reason else ""
            self.status = f"{prefix}SPEAKING • Windows {voice}"
            self._notify_speech_start(spoken_text, f"Windows {voice}")
            print(f"[VOICE] Windows fallback playback start // chars={len(spoken_text)}", flush=True)
            proc = self._windows_process
            if proc is None or proc.poll() is not None or not proc.stdin:
                if cancel.is_set():
                    return None
                raise RuntimeError("Windows System.Speech worker disappeared before playback.")
            proc.stdin.write(spoken_text + "\n")
            proc.stdin.flush()

            marker = ""
            if proc.stdout:
                marker = str(proc.stdout.readline() or "").strip()
            if cancel.is_set():
                self._stop_windows_process()
                self.status = "READY • cancelled wizard speech"
                return None
            if marker == "__ELITE_BRIDGE_VOICE_ERROR__":
                raise RuntimeError("Windows System.Speech failed to play the utterance.")
            if marker != "__ELITE_BRIDGE_VOICE_DONE__":
                raise RuntimeError("Windows System.Speech ended without a completion acknowledgement.")

            self.last_backend = f"Windows {voice}"
            if fallback_reason:
                self.status = f"READY • Windows fallback • {fallback_reason}"
            else:
                self.status = f"READY • Windows {voice}"
            print(f"[VOICE] Windows fallback playback complete // {time.monotonic()-started:.2f}s", flush=True)
            return None
        except Exception as exc:
            self.last_error = str(exc)
            print(f"[VOICE] Windows fallback playback FAILED // {exc}", flush=True)
            raise
        finally:
            if cancel.is_set():
                self._stop_windows_process()
                self.status = "READY • cancelled wizard speech"
            self._qml_speech_active = False


legacy.VoiceSpeechWorker = QmlVoiceWorker

INTEGRATION_VERSION = "0.30.20"
BACKEND_VERSION = "0.12.95"

# Commands below inject Elite controls and therefore require the pilot's real
# active .binds profile. Search/configuration/diagnostic commands remain usable
# on a clean PC so Bridge never locks the user out of the interface.
ELITE_CONTROL_COMMANDS = {
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


def _sfx_display_filename(key: str, source, custom: bool) -> str:
    """Show the user's original WAV filename even though managed copies are key-prefixed."""
    if not source:
        return "-"
    name = Path(source).name
    prefix = f"{str(key)}__"
    if custom and name.startswith(prefix):
        return name[len(prefix):] or name
    return name


def _managed_sfx_target_name(key: str, source: Path) -> str:
    """Create a collision-safe managed filename while retaining the original name for display."""
    original = Path(source).name or f"{key}.wav"
    safe = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', original).strip().strip('.')
    if not safe.lower().endswith('.wav'):
        safe += '.wav'
    if not safe:
        safe = f"{key}.wav"
    return f"{key}__{safe}"

NAV_MEMORY_DEFAULTS = {"home": "", "bookmark1": "", "bookmark2": ""}
_NAV_MEMORY_LOCK = threading.Lock()

# Adapter-owned trade run plan.  The .95 engine remains a two-endpoint loop
# engine; the QML adapter adds an optional finite cycle target around it.
TRADE_RUN_DEFAULT = "CONTINUOUS"

# Stable baseline commodity catalog for the non-editable Trade selector.
# Current market/journal commodity names are merged into this list at runtime
# so newly-added Elite commodities can appear without accepting arbitrary text.
TRADE_COMMODITY_BASE = [
    "Agronomic Treatment", "Algae", "Aluminium", "Animal Meat", "Aquaponic Systems",
    "Articulation Motors", "Basic Medicines", "Bauxite", "Beer", "Bertrandite",
    "Biowaste", "Building Fabricators", "Ceramic Composites", "Clothing", "Cobalt",
    "Coffee", "Computer Components", "Consumer Technology", "Copper", "Crop Harvesters",
    "Domestic Appliances", "Evacuation Shelter", "Fish", "Food Cartridges", "Gallite",
    "Gallium", "Gold", "Grain", "H.E. Suits", "Hydrogen Fuel", "Indite", "Indium",
    "Insulating Membrane", "Land Enrichment Systems", "Leather", "Liquor", "Lithium",
    "Marine Equipment", "Medical Diagnostic Equipment", "Micro Controllers", "Mineral Extractors",
    "Non-Lethal Weapons", "Palladium", "Performance Enhancers", "Personal Weapons",
    "Polymers", "Power Generators", "Progenitor Cells", "Reactive Armour", "Robotics",
    "Semiconductors", "Silver", "Superconductors", "Synthetic Fabrics", "Tea",
    "Titanium", "Tobacco", "Tritium", "Uraninite", "Water", "Wine"
]



def _install_strong_elite_focus(app):
    """Integration-only foreground helper for QML-triggered cockpit commands.

    Windows often refuses a plain SetForegroundWindow after the user clicks the
    QML dashboard.  Keep .95 untouched, but replace this one KeySender method
    with a stronger Win32 handoff that locates EliteDangerous64.exe, restores
    the window, temporarily attaches input queues, and verifies the result.
    """
    if os.name != "nt":
        return

    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    SW_RESTORE = 9
    SW_SHOW = 5
    HWND_TOPMOST = -1
    HWND_NOTOPMOST = -2
    SWP_NOMOVE = 0x0002
    SWP_NOSIZE = 0x0001
    SWP_SHOWWINDOW = 0x0040

    EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

    def _window_title(hwnd):
        n = user32.GetWindowTextLengthW(hwnd)
        buf = ctypes.create_unicode_buffer(max(1, n + 1))
        user32.GetWindowTextW(hwnd, buf, len(buf))
        return buf.value

    def _exe_name_for_hwnd(hwnd):
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if not pid.value:
            return ""
        hproc = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid.value)
        if not hproc:
            return ""
        try:
            size = wintypes.DWORD(32768)
            buf = ctypes.create_unicode_buffer(size.value)
            if not kernel32.QueryFullProcessImageNameW(hproc, 0, buf, ctypes.byref(size)):
                return ""
            return Path(buf.value).name.lower()
        finally:
            kernel32.CloseHandle(hproc)

    def _find_elite_hwnd():
        hits = []
        @EnumWindowsProc
        def cb(hwnd, _lparam):
            if not user32.IsWindowVisible(hwnd):
                return True
            title = _window_title(hwnd)
            exe = _exe_name_for_hwnd(hwnd)
            title_l = title.lower()
            if exe == "elitedangerous64.exe" or ("elite - dangerous" in title_l and "launcher" not in title_l):
                hits.append((hwnd, title, exe))
                return False
            return True
        user32.EnumWindows(cb, 0)
        return hits[0] if hits else (None, "", "")

    def _is_process_elevated(pid):
        # Best-effort only.  If token inspection fails, return None rather than
        # inventing an admin/elevation diagnosis.
        TOKEN_QUERY = 0x0008
        TokenElevation = 20
        hproc = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not hproc:
            return None
        token = wintypes.HANDLE()
        try:
            if not ctypes.windll.advapi32.OpenProcessToken(hproc, TOKEN_QUERY, ctypes.byref(token)):
                return None
            elevation = wintypes.DWORD()
            ret_len = wintypes.DWORD()
            if not ctypes.windll.advapi32.GetTokenInformation(token, TokenElevation, ctypes.byref(elevation), ctypes.sizeof(elevation), ctypes.byref(ret_len)):
                return None
            return bool(elevation.value)
        finally:
            if token.value:
                kernel32.CloseHandle(token)
            kernel32.CloseHandle(hproc)

    def strong_focus(self):
        hwnd, title, exe = _find_elite_hwnd()
        if not hwnd:
            raise RuntimeError("EliteDangerous64.exe game window was not found.")

        # Restore/show first so foreground activation has a real top-level target.
        user32.ShowWindow(hwnd, SW_RESTORE)
        user32.ShowWindow(hwnd, SW_SHOW)

        fg = user32.GetForegroundWindow()
        current_tid = kernel32.GetCurrentThreadId()
        target_tid = user32.GetWindowThreadProcessId(hwnd, None)
        fg_tid = user32.GetWindowThreadProcessId(fg, None) if fg else 0
        attached_target = False
        attached_fg = False
        try:
            if target_tid and target_tid != current_tid:
                attached_target = bool(user32.AttachThreadInput(current_tid, target_tid, True))
            if fg_tid and fg_tid != current_tid and fg_tid != target_tid:
                attached_fg = bool(user32.AttachThreadInput(current_tid, fg_tid, True))

            # The topmost pulse is intentionally momentary.  It avoids leaving
            # Elite permanently topmost but helps Windows honor the activation.
            user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
            user32.SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
            user32.BringWindowToTop(hwnd)
            user32.SetActiveWindow(hwnd)
            user32.SetForegroundWindow(hwnd)
            user32.SetFocus(hwnd)
        finally:
            if attached_fg:
                user32.AttachThreadInput(current_tid, fg_tid, False)
            if attached_target:
                user32.AttachThreadInput(current_tid, target_tid, False)

        for _ in range(15):
            time.sleep(0.06)
            if user32.GetForegroundWindow() == hwnd:
                self.last_window_title = title
                return title or exe or "EliteDangerous64.exe"

        # If foreground failed, check for the common UIPI/admin mismatch so the
        # cockpit status can give the pilot a useful reason.
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        elite_admin = _is_process_elevated(pid.value) if pid.value else None
        bridge_admin = None
        try:
            bridge_admin = bool(ctypes.windll.shell32.IsUserAnAdmin())
        except Exception:
            pass
        if elite_admin is True and bridge_admin is False:
            raise RuntimeError("Elite is running elevated (Administrator) while Bridge is not. Run both at the same privilege level.")
        raise RuntimeError("Windows refused to bring Elite to the foreground after restore/activation attempts.")

    app.key_sender.focus_elite = MethodType(strong_focus, app.key_sender)


def _install_combat_intent_overrides(app):
    """Integration-only combat-intent policy layered around untouched v0.12.95.

    Escape/interdiction always wins over combat intent.  Entering the QML Combat
    page is an explicit pilot signal that permits the COMBAT distributor profile;
    UnderAttack by itself no longer forces WEP-heavy PIPs.
    """
    app._qml_combat_intent_active = False

    def desired(self):
        s = self.state_data
        if self.egress_phase != "IDLE":
            return None
        if s.flag("Docked") or s.flag("Supercruise") or s.flag("FSD Jump"):
            return None
        if not s.flag("In Main Ship"):
            return None
        if self.station_safety_pips_active or s.flag("FSD Mass Locked"):
            return "STATION_SAFETY"

        # Survival wins.  During an interdiction, or immediately afterward while
        # Elite still reports danger, bias ENG rather than treating damage as
        # proof the pilot wants to fight.
        now_wall = time.time()
        last_interdiction = float(getattr(s, "last_interdiction", 0.0) or 0.0)
        recent_interdiction = bool(last_interdiction and (now_wall - last_interdiction) < 30.0)
        if s.flag("Being Interdicted") or (recent_interdiction and s.flag("In Danger")):
            return "EGRESS"

        # Explicit Combat-tab intent is stronger evidence than generic damage.
        if bool(getattr(self, "_qml_combat_intent_active", False)):
            return "COMBAT"
        if s.wanted_target_prearmed():
            return "COMBAT"

        now = time.monotonic()
        recovery_age = now - float(getattr(s, "combat_last_end_mono", 0.0) or 0.0)
        if (not s.flag("Shields Up")) or (
            getattr(s, "combat_last_end_mono", 0.0)
            and recovery_age < legacy.DYNAMIC_PIP_POST_COMBAT_RECOVERY_SECONDS
        ):
            return "RECOVERY"
        if s.flag("Hardpoints"):
            return "WEAPONS"
        return "CRUISE"

    app._dynamic_pips_desired_mode = MethodType(desired, app)


def _combat_enter(app):
    # Page navigation is visual only. Merely opening Combat must not change Elite
    # HUD mode or seize the distributor. Hardpoints/telemetry still drive normal
    # automation, and explicit cockpit commands remain available separately.
    app._qml_combat_intent_active = False
    try:
        app._dynamic_pips_log("COMBAT PAGE VISIBLE | no cockpit side effects")
    except Exception:
        pass


def _combat_leave(app):
    # Leaving the page is also visual only. Do not reset Dynamic PIPs state,
    # because that could cause a needless distributor command after navigation.
    app._qml_combat_intent_active = False
    try:
        app._dynamic_pips_log("COMBAT PAGE HIDDEN | no cockpit side effects")
    except Exception:
        pass


def _nav_memory_path() -> Path:
    root = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "EliteAIBridge"
    root.mkdir(parents=True, exist_ok=True)
    return root / "qml_navigation_memories.json"


def _sanitize_nav_memory_value(value: Any) -> str:
    text = str(value if value is not None else "").strip()
    if len(text) > 160 or any(ord(ch) < 32 for ch in text):
        return ""
    return text


def _load_nav_memories() -> dict[str, str]:
    values = dict(NAV_MEMORY_DEFAULTS)
    path = _nav_memory_path()
    with _NAV_MEMORY_LOCK:
        try:
            raw = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
            if isinstance(raw, dict):
                for key in values:
                    cleaned = _sanitize_nav_memory_value(raw.get(key, values[key]))
                    values[key] = cleaned
        except Exception:
            pass
    return values


def _save_nav_memory(slot: str, system: str) -> dict[str, str]:
    slot = str(slot or "").strip().lower()
    if slot not in NAV_MEMORY_DEFAULTS:
        raise ValueError(f"unknown navigation memory slot: {slot}")
    cleaned = _sanitize_nav_memory_value(system)
    values = _load_nav_memories()
    values[slot] = cleaned
    path = _nav_memory_path()
    with _NAV_MEMORY_LOCK:
        path.write_text(json.dumps(values, ensure_ascii=False, indent=2), encoding="utf-8")
    return values



def _valid_text(value: Any, fallback: str = "-") -> str:
    text = str(value if value is not None else "").strip()
    return text if text and text != "None" else fallback


def _fmt_commander_cr(value: Any, fallback: str = "-") -> str:
    try:
        return f"{int(round(float(value))):,} CR"
    except Exception:
        return fallback


def _commander_event_counts(lines: list[str]) -> dict[str, int]:
    """Count adapter-session journal events from the existing display log.

    StateData only appends non-seed events to event_log, which makes this a
    useful honest Bridge-session ledger without modifying the .95 parser.
    """
    counts = {"jumps": 0, "dockings": 0, "trade_sales": 0, "bounties": 0}
    for raw in lines:
        line = str(raw or "")
        if re.search(r"\s{2}FSDJump(?:\s{2}|$)", line):
            counts["jumps"] += 1
        if re.search(r"\s{2}Docked(?:\s{2}|$)", line):
            counts["dockings"] += 1
        if re.search(r"\s{2}MarketSell(?:\s{2}|$)", line):
            counts["trade_sales"] += 1
        if re.search(r"\s{2}Bounty(?:\s{2}|$)", line):
            counts["bounties"] += 1
    return counts


def _colonization_project_records(state) -> list[dict[str, Any]]:
    """Return cached colonization projects newest-first without changing .95 state."""
    rows: list[dict[str, Any]] = []
    projects = getattr(state, "colonization_projects", {}) or {}
    if not isinstance(projects, dict):
        return rows
    for raw in projects.values():
        if not isinstance(raw, dict):
            continue
        resources = raw.get("resources") or []
        remaining = 0
        complete_count = 0
        total_count = 0
        for item in resources if isinstance(resources, list) else []:
            if not isinstance(item, dict):
                continue
            try:
                required = max(0, int(item.get("RequiredAmount", 0) or 0))
            except Exception:
                required = 0
            try:
                provided = max(0, int(item.get("ProvidedAmount", 0) or 0))
            except Exception:
                provided = 0
            left = max(0, required - provided)
            remaining += left
            total_count += 1
            if left <= 0:
                complete_count += 1
        try:
            progress_pct = max(0.0, min(100.0, float(raw.get("progress", 0) or 0) * 100.0))
        except Exception:
            progress_pct = 0.0
        status = "COMPLETE" if bool(raw.get("complete", False)) else ("FAILED" if bool(raw.get("failed", False)) else "ACTIVE")
        try:
            market_id = int(raw.get("market_id"))
        except Exception:
            continue
        rows.append({
            "marketId": market_id,
            "system": _valid_text(raw.get("system"), "-"),
            "station": _valid_text(raw.get("station"), "-"),
            "progressPct": progress_pct,
            "remaining": remaining,
            "completeCount": complete_count,
            "commodityCount": total_count,
            "status": status,
            "timestamp": _valid_text(raw.get("timestamp"), "-"),
        })
    rows.sort(key=lambda row: str(row.get("timestamp") or ""), reverse=True)
    return rows


def _pct(value: Any) -> int:
    try:
        return max(0, min(100, int(round(float(value) * 100.0))))
    except Exception:
        return -1


def _recent_fighter_context(app) -> dict[str, Any]:
    """Best-effort fighter/crew context from the commander's recent journals.

    Elite does not expose every NPC-crew/fighter prerequisite in Status.json, so
    this helper deliberately reports only what the journal can prove. It is used
    for clear QML feedback and never changes the locked .95 engine.
    """
    result = {
        "has_fighter_hangar": None,
        "active_npc_crew": None,
        "active_crew_name": "",
        "fighter_active": False,
        "last_fighter_event": "",
    }
    try:
        journal_dir = Path(getattr(legacy, "JOURNAL_DIR"))
        files = sorted(journal_dir.glob("Journal.*.log"), key=lambda q: q.stat().st_mtime)[-16:]
        crew_roles: dict[str, str] = {}
        fired: set[str] = set()
        latest_loadout = None
        fighter_active = False
        last_fighter_event = ""
        for jf in files:
            try:
                for line in jf.read_text(encoding="utf-8", errors="replace").splitlines():
                    try:
                        e = json.loads(line)
                    except Exception:
                        continue
                    ev = str(e.get("event") or "")
                    if ev == "Loadout":
                        latest_loadout = e
                    elif ev in {"CrewHire", "CrewAssign", "CrewFire"}:
                        key = str(e.get("CrewID") or e.get("Name") or "").strip()
                        if not key:
                            continue
                        if ev == "CrewFire":
                            fired.add(key); crew_roles.pop(key, None)
                        elif ev == "CrewAssign":
                            fired.discard(key); crew_roles[key] = str(e.get("Role") or "").strip()
                        else:
                            fired.discard(key); crew_roles.setdefault(key, "Inactive")
                    elif ev in {"LaunchFighter", "CrewLaunchFighter"}:
                        fighter_active = True; last_fighter_event = ev
                    elif ev in {"DockFighter", "FighterDestroyed"}:
                        fighter_active = False; last_fighter_event = ev
            except Exception:
                continue
        if latest_loadout is not None:
            modules = latest_loadout.get("Modules") or []
            has = False
            for mod in modules:
                if not isinstance(mod, dict):
                    continue
                item = str(mod.get("Item") or "").casefold().replace("_", "")
                if "fighterbay" in item or "fighterhangar" in item:
                    has = True; break
            result["has_fighter_hangar"] = has
        active = [(k, role) for k, role in crew_roles.items() if k not in fired and role.casefold() == "active"]
        if crew_roles or fired:
            result["active_npc_crew"] = bool(active)
            if active:
                result["active_crew_name"] = active[-1][0]
        result["fighter_active"] = bool(fighter_active or app.state_data.flag("In Fighter"))
        result["last_fighter_event"] = last_fighter_event
    except Exception:
        pass
    return result


def _fighter_deploy_preflight(app, fighter_number: int) -> bool:
    s = app.state_data
    if s.flag("Docked") or s.flag("Supercruise") or s.flag("FSD Jump"):
        app.native_command_status = f"Deploy Fighter {fighter_number}: BLOCKED // NORMAL-SPACE FLIGHT REQUIRED."
        try:
            app.voice_engine.say("I can't deploy a fighter right now.")
        except Exception:
            pass
        return False
    ctx = _recent_fighter_context(app)
    if ctx.get("has_fighter_hangar") is False:
        app.native_command_status = f"Deploy Fighter {fighter_number}: BLOCKED // NO FIGHTER HANGAR FOUND IN LAST LOADOUT."
        try:
            app.voice_engine.say("No fighter hangar is available.")
        except Exception:
            pass
        return False
    if ctx.get("fighter_active"):
        app.native_command_status = f"Deploy Fighter {fighter_number}: BLOCKED // A FIGHTER IS ALREADY DEPLOYED."
        try:
            app.voice_engine.say("A fighter is already deployed.")
        except Exception:
            pass
        return False
    crew_state = ctx.get("active_npc_crew")
    if crew_state is False:
        app.native_command_status = f"Deploy Fighter {fighter_number}: BLOCKED // NO ACTIVE NPC CREW ASSIGNED."
        try:
            app.voice_engine.say("No active crew member assigned.")
        except Exception:
            pass
        return False
    if crew_state is not True:
        # Elite's journal does not always expose a trustworthy current crew state.
        # Keep pilot-facing feedback short instead of narrating journal limitations.
        app.native_command_status = f"Deploy Fighter {fighter_number}: BLOCKED // CREW STATUS UNCONFIRMED."
        try:
            app.voice_engine.say("I can't deploy a fighter right now.")
        except Exception:
            pass
        return False
    return True


def _fighter_recall_preflight(app) -> bool:
    ctx = _recent_fighter_context(app)
    if not ctx.get("fighter_active"):
        app.native_command_status = "Recall Fighter: BLOCKED // NO ACTIVE FIGHTER CONFIRMED BY JOURNAL."
        return False
    return True


def _wing_preflight(app, label: str) -> bool:
    if not app.state_data.flag("In Wing"):
        app.native_command_status = f"{label}: BLOCKED // NOT CURRENTLY IN A WING / TEAM."
        return False
    return True


def _event_stamp_local_12h(stamp: str) -> str:
    """Format the legacy event recorder's already-local clock as 12-hour time.

    Elite journal timestamps start as UTC, but v0.12.95's fmt_time() converts them
    to the Windows machine's local timezone before writing state_data.event_log.
    Do not apply another timezone offset here. Doing so double-converts the clock.
    """
    if not stamp or stamp == "--:--":
        return stamp
    try:
        parts = [int(part) for part in stamp.split(":")]
        hour, minute = parts[0], parts[1]
        second = parts[2] if len(parts) > 2 else 0
        suffix = "AM" if hour < 12 else "PM"
        hour12 = hour % 12 or 12
        if len(parts) > 2:
            return f"{hour12}:{minute:02d}:{second:02d} {suffix}"
        return f"{hour12}:{minute:02d} {suffix}"
    except Exception:
        return stamp


def _event_rows(lines: list[str], limit: int = 5) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for raw in list(lines or [])[-limit:][::-1]:
        text = _valid_text(raw, "")
        if not text:
            continue
        m = re.match(r"^(\d{1,2}:\d{2}(?::\d{2})?)\s{2,}(.*)$", text)
        if m:
            stamp, body = _event_stamp_local_12h(m.group(1)), m.group(2)
        else:
            stamp, body = "--:--", text
        normalized = body.replace("  |  ", " // ").replace(" | ", " // ")
        event_name, sep, summary = normalized.partition(" // ")
        rows.append({
            "time": stamp,
            "event": event_name.strip(),
            "summary": summary.strip() if sep else "",
            "text": normalized,
        })
    return rows




def _nav_history_rows(lines: list[str], limit: int = 6) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for raw in list(lines or [])[-limit:][::-1]:
        line = _valid_text(raw, "")
        if not line:
            continue
        m = re.match(r"^(\d{1,2}:\d{2}(?::\d{2})?)\s{2,}(.*)$", line)
        if m:
            stamp = _event_stamp_local_12h(m.group(1))
            body = m.group(2).strip()
        else:
            stamp = "--:--"
            body = line
        rows.append({"time": stamp, "text": body})
    return rows

def _append_qml_nav_trip_line(app: legacy.BridgeApp, text: str) -> None:
    """Append a QML-only trip-log line without changing the .95 engine's nav history."""
    body = str(text or "").strip()
    if not body:
        return
    history = getattr(app, "_qml_nav_trip_history", None)
    if not isinstance(history, list):
        history = []
        setattr(app, "_qml_nav_trip_history", history)
    line = f"{time.strftime('%H:%M:%S')}  {body}"
    if history and history[-1] == line:
        return
    history.append(line)
    if len(history) > 120:
        del history[:-120]


def _mirror_native_nav_history(app: legacy.BridgeApp) -> None:
    """Mirror new .95 nav-action lines into the richer QML trip log."""
    history = getattr(app, "_qml_nav_trip_history", None)
    if not isinstance(history, list):
        history = []
        setattr(app, "_qml_nav_trip_history", history)
    seen = getattr(app, "_qml_nav_action_seen_counts", None)
    if not isinstance(seen, dict):
        seen = {}
        setattr(app, "_qml_nav_action_seen_counts", seen)
    current_counts: dict[str, int] = {}
    for raw in list(getattr(app, "nav_history", []) or []):
        line = str(raw or "").strip()
        if not line:
            continue
        current_counts[line] = current_counts.get(line, 0) + 1
        if current_counts[line] > int(seen.get(line, 0) or 0):
            history.append(line)
    for line, count in current_counts.items():
        seen[line] = max(int(seen.get(line, 0) or 0), count)
    if len(history) > 120:
        del history[:-120]


def _station_target_kind(station_type: str, confirmed_station: bool) -> str:
    low = str(station_type or "").strip().casefold().replace("_", " ")
    if "outpost" in low or "asteroid" in low:
        return "OUTPOST"
    if "settlement" in low or "surface" in low:
        return "SETTLEMENT"
    if "carrier" in low:
        return "CARRIER"
    if confirmed_station:
        return "STARPORT"
    return "IN-SYSTEM TARGET"


def _status_in_system_target(
    s: legacy.EliteState,
    status: dict[str, Any],
    current_system: str,
    route_destination: str,
    fsd_target: str,
) -> dict[str, Any]:
    """Project Status.json Destination conservatively into an in-system endpoint.

    Status.json can expose a named navigation destination after the hyperspace
    route itself is exhausted.  We show a station-specific symbol only when the
    journal has corroborating station knowledge; otherwise the same endpoint is
    honestly labelled IN-SYSTEM TARGET rather than guessing a station type.
    """
    dest = status.get("Destination") if isinstance(status, dict) else None
    if not isinstance(dest, dict):
        return {"visible": False, "name": "-", "kind": "-", "stationType": "", "confirmedStation": False}

    name = _valid_text(
        dest.get("Name_Localised") or dest.get("Name") or dest.get("StationName") or dest.get("BodyName"),
        "",
    )
    if not name:
        return {"visible": False, "name": "-", "kind": "-", "stationType": "", "confirmedStation": False}

    system_names = {
        str(value).strip().casefold()
        for value in (current_system, route_destination, fsd_target)
        if str(value or "").strip() not in ("", "-", "NO ROUTE")
    }
    if name.casefold() in system_names:
        return {"visible": False, "name": "-", "kind": "-", "stationType": "", "confirmedStation": False}

    confirmed_station = False
    station_type = str(dest.get("StationType") or dest.get("StationType_Localised") or "").strip()
    if station_type:
        confirmed_station = True
    # Prefer metadata learned from this commander's own journal.
    for meta in list(getattr(s, "station_metadata", {}).values()):
        if not isinstance(meta, dict):
            continue
        if str(meta.get("station") or "").strip().casefold() != name.casefold():
            continue
        confirmed_station = True
        if str(meta.get("system") or "").strip().casefold() == str(current_system or "").strip().casefold():
            station_type = str(meta.get("station_type") or "")
            break
        if not station_type:
            station_type = str(meta.get("station_type") or "")

    # Mission destination fields and station event state corroborate names even
    # when StationType has not yet been observed in this journal.
    known_station_names = {
        str(value).strip().casefold()
        for value in (
            getattr(s, "station", ""),
            getattr(s, "market_station", ""),
            getattr(s, "last_docking_station", ""),
            getattr(s, "colonization_current_station", ""),
        )
        if str(value or "").strip() not in ("", "-")
    }
    for mission in list(getattr(s, "missions", {}).values()):
        if isinstance(mission, dict):
            value = str(mission.get("DestinationStation") or "").strip()
            if value:
                known_station_names.add(value.casefold())
    if name.casefold() in known_station_names:
        confirmed_station = True

    kind = _station_target_kind(station_type, confirmed_station)
    return {
        "visible": True,
        "name": name,
        "kind": kind,
        "stationType": station_type,
        "confirmedStation": confirmed_station,
    }


def _update_qml_nav_trip_log(
    app: legacy.BridgeApp,
    current_system: str,
    destination: str,
    fsd_target: str,
    route_jumps: int | None,
    in_system_target: dict[str, Any],
    docked: bool,
    station: str,
    docking_revision: int,
    docking_event: str,
    docking_station: str,
) -> None:
    """Record real travel progress for the QML Route Log.

    This is integration-layer presentation state only. It never sends cockpit
    input and it does not modify the known-good .95 engine source.
    """
    _mirror_native_nav_history(app)
    state = {
        "system": current_system,
        "destination": destination,
        "fsdTarget": fsd_target,
        "jumps": route_jumps,
        "targetName": str(in_system_target.get("name") or "-") if in_system_target.get("visible") else "-",
        "targetKind": str(in_system_target.get("kind") or "IN-SYSTEM TARGET"),
        "docked": bool(docked),
        "station": station,
        "dockingRevision": int(docking_revision or 0),
        "dockingEvent": docking_event,
        "dockingStation": docking_station,
    }
    previous = getattr(app, "_qml_nav_trip_state", None)
    if not isinstance(previous, dict):
        if current_system not in ("", "-"):
            _append_qml_nav_trip_line(app, f"NAV TRACKING // {current_system}")
        if destination not in ("", "-", "NO ROUTE"):
            suffix = "" if route_jumps is None else f" // {route_jumps} JUMP{'S' if route_jumps != 1 else ''} REMAINING"
            _append_qml_nav_trip_line(app, f"ROUTE ACTIVE // {destination}{suffix}")
        if in_system_target.get("visible"):
            _append_qml_nav_trip_line(app, f"{state['targetKind']} TARGET // {state['targetName']}")
        if docked and station not in ("", "-", "IN FLIGHT"):
            _append_qml_nav_trip_line(app, f"DOCKED // {station}")
        setattr(app, "_qml_nav_trip_state", state)
        return

    system_changed = state["system"] != previous.get("system") and state["system"] not in ("", "-")
    if system_changed:
        suffix = "" if route_jumps is None else f" // {route_jumps} JUMP{'S' if route_jumps != 1 else ''} REMAINING"
        _append_qml_nav_trip_line(app, f"ARRIVED // {state['system']}{suffix}")
        if fsd_target not in ("", "-", state["system"]):
            _append_qml_nav_trip_line(app, f"NEXT // {fsd_target}")

    if state["destination"] != previous.get("destination"):
        if state["destination"] in ("", "-", "NO ROUTE"):
            _append_qml_nav_trip_line(app, "ROUTE CLEARED")
        else:
            suffix = "" if route_jumps is None else f" // {route_jumps} JUMP{'S' if route_jumps != 1 else ''} REMAINING"
            _append_qml_nav_trip_line(app, f"ROUTE TARGET // {state['destination']}{suffix}")
    elif not system_changed and route_jumps != previous.get("jumps") and route_jumps is not None:
        _append_qml_nav_trip_line(app, f"ROUTE UPDATED // {route_jumps} JUMP{'S' if route_jumps != 1 else ''} REMAINING")

    if state["targetName"] != previous.get("targetName"):
        if state["targetName"] not in ("", "-"):
            _append_qml_nav_trip_line(app, f"{state['targetKind']} TARGET // {state['targetName']}")
        elif previous.get("targetName") not in (None, "", "-"):
            _append_qml_nav_trip_line(app, "IN-SYSTEM TARGET CLEARED")

    if state["dockingRevision"] != int(previous.get("dockingRevision", 0) or 0) and state["dockingEvent"] not in ("", "-"):
        docking_labels = {
            "DockingRequested": "DOCKING REQUESTED",
            "DockingGranted": "DOCKING GRANTED",
            "DockingDenied": "DOCKING DENIED",
            "DockingCancelled": "DOCKING CANCELLED",
        }
        label = docking_labels.get(state["dockingEvent"], str(state["dockingEvent"]).replace("Docking", "DOCKING ").upper())
        where = state["dockingStation"] if state["dockingStation"] not in ("", "-") else state["targetName"]
        _append_qml_nav_trip_line(app, f"{label} // {where}" if where not in ("", "-") else label)

    if state["docked"] != bool(previous.get("docked")):
        if state["docked"]:
            at = state["station"] if state["station"] not in ("", "-", "IN FLIGHT") else state["targetName"]
            _append_qml_nav_trip_line(app, f"DOCKED // {at}" if at not in ("", "-") else "DOCKED")
        else:
            from_station = previous.get("station") or "-"
            _append_qml_nav_trip_line(app, f"LAUNCHED // {from_station}" if from_station not in ("", "-", "IN FLIGHT") else "LAUNCHED")

    setattr(app, "_qml_nav_trip_state", state)

def _level_color_name(level: str) -> str:
    return level if level in {"ok", "warn", "bad", "info"} else "info"


_ELITE_PROCESS_CACHE = {"checked": 0.0, "running": None}

def _elite_process_running():
    """Return True/False on Windows, None when process probing is unavailable.

    Elite leaves Journal/Status files behind after exit, so file presence alone cannot
    represent a live game connection. Cache tasklist briefly to keep snapshot polling cheap.
    """
    if os.name != "nt":
        return None
    now = time.monotonic()
    if now - float(_ELITE_PROCESS_CACHE.get("checked", 0.0) or 0.0) < 1.25:
        return _ELITE_PROCESS_CACHE.get("running")
    running = False
    try:
        proc = subprocess.run(
            ["tasklist", "/FO", "CSV", "/NH"],
            capture_output=True, text=True, timeout=2.0, check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        low = (proc.stdout or "").casefold()
        running = "elitedangerous64.exe" in low or "elitedangerous.exe" in low
    except Exception:
        running = None
    _ELITE_PROCESS_CACHE["checked"] = now
    _ELITE_PROCESS_CACHE["running"] = running
    return running


def build_live_snapshot(app: legacy.BridgeApp) -> dict[str, Any]:
    """Build a JSON-safe Live-page view of the *existing* Bridge state.

    This function does not send game input and does not mutate automation state.
    It runs on the Bridge/Tk thread.
    """
    # Keep the dashboard's route display synchronized with Elite even when the
    # pilot plots manually in the Galaxy Map.  This calls the existing .95
    # NavRoute.json watcher; it does not duplicate route parsing or send input.
    try:
        app.poll_navroute_file()
    except Exception:
        pass

    s = app.state_data
    st = s.status or {}

    ship_model = _valid_text(s.ship)
    ship_name = _valid_text(getattr(s, "ship_name", ""), "")
    ship_display = ship_model
    if ship_name:
        ship_display = f"{ship_name} // {ship_model}"

    if s.flag("Docked"):
        game_state = "DOCKED"
    elif s.flag("Supercruise"):
        game_state = "SUPERCRUISE"
    elif s.flag("FSD Charging"):
        game_state = "FSD CHARGING"
    elif s.flag("FSD Jump"):
        game_state = "FSD JUMP"
    else:
        game_state = "NORMAL FLIGHT"

    if getattr(app, "egress_phase", "IDLE") != "IDLE":
        bridge_state = "EMERGENCY EGRESS"
        bridge_message = _valid_text(getattr(app, "egress_status", ""), "Emergency sequence active.")
        bridge_level = "bad"
        control_owner = "EMERGENCY_EGRESS"
    elif getattr(app, "native_command_busy", False):
        bridge_state = _valid_text(getattr(app, "native_command_name", ""), "COMMAND RUNNING").upper()
        bridge_message = _valid_text(getattr(app, "native_command_status", ""), "Bridge owns cockpit controls.")
        bridge_level = "warn"
        control_owner = _valid_text(getattr(app, "native_command_name", ""), "NATIVE_COMMAND")
    elif getattr(app, "station_automation_busy", False):
        bridge_state = "SHIP SERVICES"
        bridge_message = _valid_text(getattr(app, "station_automation_status", ""), "Station maintenance running.")
        bridge_level = "warn"
        control_owner = "STATION_AUTOMATION"
    elif getattr(app, "voice_input_recording", False):
        bridge_state = "LISTENING"
        bridge_message = "PTT active. Listening for your command."
        bridge_level = "ok"
        control_owner = "NONE"
    elif getattr(app, "copilot_busy", False):
        bridge_state = "AI THINKING"
        bridge_message = "Bridge is processing your request."
        bridge_level = "warn"
        control_owner = "NONE"
    elif "SPEAKING" in str(getattr(app.voice_engine, "status", "")).upper():
        bridge_state = "AI SPEAKING"
        bridge_message = _valid_text(getattr(app.voice_engine, "status", ""), "Voice output active.")
        bridge_level = "ok"
        control_owner = "NONE"
    else:
        bridge_state = "IDLE"
        bridge_message = "Ready for your command, Commander."
        bridge_level = "ok"
        control_owner = "NONE"

    hull_percent = _pct(getattr(s, "hull_health", None))

    fuel_percent = -1
    fuel = st.get("Fuel")
    if isinstance(fuel, dict) and fuel.get("FuelMain") is not None:
        try:
            fmain = float(fuel.get("FuelMain") or 0.0)
            cap = float(getattr(s, "fuel_capacity_main", 0.0) or 0.0)
            if cap > 0:
                fuel_percent = max(0, min(100, int(round(fmain / cap * 100.0))))
        except Exception:
            pass

    pips = st.get("Pips")
    if isinstance(pips, list) and len(pips) >= 3:
        try:
            pips_text = f"SYS {pips[0]/2:g}   ENG {pips[1]/2:g}   WEP {pips[2]/2:g}"
        except Exception:
            pips_text = "SYS -   ENG -   WEP -"
    else:
        pips_text = "SYS -   ENG -   WEP -"

    if s.flag("FSD Charging"):
        fsd_state = "CHARGING"
    elif s.flag("FSD Cooldown"):
        fsd_state = "COOLDOWN"
    elif s.flag("FSD Mass Locked"):
        fsd_state = "MASS LOCKED"
    elif s.flag("FSD Jump"):
        fsd_state = "JUMP"
    else:
        fsd_state = "READY / IDLE"

    # A live Elite connection cannot be inferred from Journal/Status file presence
    # because both files remain after the game exits. On Windows, use the actual
    # Elite process as the authoritative outer gate and the existing telemetry
    # health as the readiness gate inside that session.
    telemetry_ok = bool(s.journal_connected and s.status_connected)
    elite_process = _elite_process_running()
    last_elite_event = str(getattr(s, "last_event", "") or "").strip().upper()
    if elite_process is False or last_elite_event == "SHUTDOWN":
        elite_telemetry_state = "OFFLINE"
        telemetry_ok = False
    elif elite_process is True:
        elite_telemetry_state = "CONNECTED" if telemetry_ok else "WAITING"
    else:
        elite_telemetry_state = "CONNECTED" if telemetry_ok else "OFFLINE"

    # Never turn missing telemetry into plausible ship state. Status flags default
    # to false, which previously made a clean PC look like a real ship in normal
    # flight with shields down, gear up and hardpoints retracted. Only live Elite
    # telemetry may produce those values.
    elite_live = elite_telemetry_state == "CONNECTED"
    if not elite_live:
        game_state = "ELITE OFFLINE" if elite_telemetry_state == "OFFLINE" else "WAITING FOR ELITE"
        fsd_state = "UNKNOWN"
        hull_percent = -1
        fuel_percent = -1
        pips_text = "SYS -   ENG -   WEP -"

    ai_key_value = str(os.environ.get("OPENAI_API_KEY") or "")
    ai_key = bool(ai_key_value)
    qml_host = getattr(app, "_qml_host", None)
    setup_overrides = getattr(qml_host, "setup_overrides", {}) if qml_host is not None else {}
    stored_mode = str((setup_overrides or {}).get("bridge_mode") or "").strip().upper()
    bridge_mode = stored_mode if stored_mode in ("CORE", "COPILOT") else ("COPILOT" if ai_key else "CORE")
    verified_fp = str((setup_overrides or {}).get("api_verified_fingerprint") or "").strip().lower()
    ai_api_verified = bool(ai_key_value and verified_fp and verified_fp == _api_key_fingerprint(ai_key_value))
    ai_verify_status = str(getattr(app, "_ai_api_verify_status", "VERIFIED" if ai_api_verified else ("KEY SAVED // VERIFY REQUIRED" if ai_key else "NOT CONFIGURED")) or "")
    ai_verify_detail = str(getattr(app, "_ai_api_verify_detail", "" if ai_api_verified else ("Verify the saved key before enabling AI Co-Pilot." if ai_key else "Enter an OpenAI API key to continue with AI Co-Pilot.")) or "")
    setup_preflight_rows, setup_ready, setup_limited = _setup_preflight_rows(app)
    setup_elite_rows = _setup_elite_rows(app)
    setup_control_rows = _setup_control_rows(app)
    ptt_binding = (getattr(app, "controller_bindings", {}) or {}).get("push_to_talk")
    ptt_mapped = isinstance(ptt_binding, dict)
    registered_hotkeys = set(getattr(getattr(app, "bridge_hotkeys", None), "registered", set()) or set())
    ptt_keyboard_ready = "push_to_talk" in registered_hotkeys
    ptt_ready = ptt_mapped or ptt_keyboard_ready
    audio_ok = bool(legacy.SOUNDDEVICE_AVAILABLE and getattr(app, "audio_output_device_var", None))
    try:
        controller_ok = bool(app.controller_manager.devices_snapshot())
    except Exception:
        controller_ok = False
    try:
        elite_binding_rows_raw, missing_bindings = app._setup_elite_binding_rows()
    except Exception:
        elite_binding_rows_raw, missing_bindings = [], ["unknown"]
    try:
        live_elite_bindings = bool(app._qml_live_elite_bindings())
    except Exception:
        live_elite_bindings = False
    if not live_elite_bindings:
        missing_bindings = [str(row[0]) for row in elite_binding_rows_raw] or ["Elite bindings profile"]
    dynamic_pips = bool(app.dynamic_pips_var.get())
    services_on = any((bool(app.auto_refuel_var.get()), bool(app.auto_repair_var.get()), bool(app.auto_rearm_var.get())))
    copilot_mode = bridge_mode == "COPILOT"

    system_rows = [
        {"label": "ELITE DATA", "value": elite_telemetry_state, "level": "ok" if elite_telemetry_state == "CONNECTED" else "warn"},
        {
            "label": "AI / VOICE",
            "value": ("THINKING" if app.copilot_busy else ("READY" if ai_api_verified else "CHECK API")) if copilot_mode else "OFF",
            "level": ("warn" if app.copilot_busy else ("ok" if ai_api_verified else "warn")) if copilot_mode else "info",
        },
        {
            "label": "VOICE / PTT",
            "value": ("LISTENING" if app.voice_input_recording else ("READY" if ptt_ready else "CHECK PTT")) if copilot_mode else "OFF",
            "level": ("ok" if ptt_ready else "warn") if copilot_mode else "info",
        },
        {"label": "AUDIO OUTPUT", "value": "READY" if audio_ok else "CHECK", "level": "ok" if audio_ok else "warn"},
        {"label": "CONTROLLERS", "value": "DETECTED" if controller_ok else "CHECK", "level": "ok" if controller_ok else "warn"},
        {
            "label": "ELITE BINDINGS",
            "value": "OK" if live_elite_bindings and not missing_bindings else (f"{len(missing_bindings)} MISSING" if live_elite_bindings else "NOT DETECTED"),
            "level": "ok" if live_elite_bindings and not missing_bindings else "warn",
        },
        {"label": "DYNAMIC PIPS", "value": "ACTIVE" if dynamic_pips else "OFF", "level": "ok" if dynamic_pips else "info"},
        {"label": "STATION SERVICES", "value": "READY" if services_on else "OFF", "level": "ok" if services_on else "info"},
    ]

    alerts: list[str] = []
    alert_level = "ok"
    if s.flag("Being Interdicted"):
        alerts.append("INTERDICTION IN PROGRESS")
        alert_level = "bad"
    if time.time() - float(getattr(s, "last_under_attack", 0.0) or 0.0) < 15:
        alerts.append("RECENT HOSTILE FIRE")
        alert_level = "bad"
    if s.flag("Overheating"):
        alerts.append("SHIP OVERHEATING")
        alert_level = "bad"
    if s.flag("Low Fuel"):
        alerts.append("LOW FUEL")
        if alert_level != "bad":
            alert_level = "warn"
    if s.flag("FSD Mass Locked") and not s.flag("Docked"):
        alerts.append("FSD MASS LOCKED")
        if alert_level != "bad":
            alert_level = "warn"

    if alerts:
        alert_label = "ACTIVE ALERTS"
        alert_value = str(len(alerts))
        alert_detail = " // ".join(alerts[:3])
    else:
        alert_label = "NO ACTIVE ALERTS"
        alert_value = "CLEAR"
        safety_reason = _valid_text(getattr(app, "safety_last_reason", ""), "Safety watch nominal")
        alert_detail = safety_reason.upper()

    destination = _valid_text(getattr(s, "nav_route_destination", "-"))
    target = _valid_text(getattr(s, "nav_target_system", "-"))
    if destination in ("", "-"):
        destination = target if target not in ("", "-") else "NO ROUTE"

    # Prefer the authoritative NavRoute.json route list for the jump count.
    # FSDTarget.RemainingJumpsInRoute can lag behind a manually replotted route,
    # which made the QML JUMPS readout appear stuck on a smaller single digit.
    try:
        route_upcoming = list(app._travel_upcoming_route_entries() or [])
    except Exception:
        route_upcoming = []

    route_jumps = None
    if destination != "NO ROUTE" and bool(getattr(s, "nav_route_file_connected", False)) and route_upcoming:
        route_jumps = len(route_upcoming)
    if route_jumps is None:
        route_jumps = getattr(s, "nav_target_remaining_jumps", None)
    if route_jumps is None and destination != "NO ROUTE":
        try:
            route_jumps = max(0, int(getattr(s, "nav_route_len", 0) or 0) - 1)
        except Exception:
            route_jumps = None
    if destination == "NO ROUTE":
        route_status = "NO ROUTE PLOTTED"
    elif route_jumps is None:
        route_status = "ROUTE ARMED"
    else:
        route_status = f"ROUTE ARMED  //  {route_jumps} JUMP{'S' if route_jumps != 1 else ''}"

    next_star_class = _valid_text(getattr(s, "nav_target_star_class", "-"))
    next_star_scoopable: bool | None = None
    next_star_system = target
    try:
        upcoming = app._travel_scoopability_lookahead_rows(limit=1)
    except Exception:
        upcoming = []
    if upcoming:
        next_star_system = _valid_text(upcoming[0].get("system"), target)
        next_star_class = _valid_text(upcoming[0].get("star_class"))
        next_star_scoopable = bool(upcoming[0].get("scoopable"))
    elif next_star_class not in ("", "-"):
        next_star_scoopable = bool(app._travel_star_is_scoopable(next_star_class))

    if next_star_class in ("", "-"):
        next_star_text = "UNKNOWN"
    else:
        scoop = "SCOOPABLE" if next_star_scoopable else "NOT SCOOPABLE"
        next_star_text = f"{next_star_class}-CLASS  //  {scoop}"

    speaking = "SPEAKING" in str(getattr(app.voice_engine, "status", "")).upper()
    listening = bool(getattr(app, "voice_input_recording", False))
    try:
        always_thread = getattr(app, "always_listen_thread", None)
        always_active = (
            str(getattr(app.voice_input_mode_var, "get", lambda: "PTT")() or "PTT").strip().upper() == "ALWAYS LISTEN"
            and bool(always_thread and always_thread.is_alive())
        )
    except Exception:
        always_active = False
    try:
        ptt_capture_active = str(app.controller_manager.capture_snapshot() or "") == "push_to_talk"
    except Exception:
        ptt_capture_active = False
    voice_mode = "SPEAKING" if speaking else ("LISTENING" if listening else ("ALWAYS LISTEN" if always_active else "READY"))
    ptt_status = "MAPPING" if ptt_capture_active else ("LISTENING" if listening else ("READY" if ptt_ready else "NOT READY"))
    luna_status = "THINKING" if app.copilot_busy else ("TALKING" if speaking else ("READY" if ai_key else "NO KEY"))

    try:
        estimated_cost = (
            float(app.ai_input_tokens or 0) / 1_000_000 * legacy.AI_INPUT_PER_MILLION
            + float(app.ai_output_tokens or 0) / 1_000_000 * legacy.AI_OUTPUT_PER_MILLION
        )
    except Exception:
        estimated_cost = 0.0

    # AI + Voice page state.  These values are read directly from the locked .95
    # engine so QML never carries a second preference/state machine.
    try:
        ptt_mapping = (
            f"{ptt_binding.get('device_name')} // {legacy.BridgeControllerManager.binding_label(ptt_binding)}"
            if ptt_mapped else ("KEYBOARD / STREAM DECK // CTRL+ALT+SHIFT+V" if ptt_keyboard_ready else "PTT SHORTCUT NOT READY")
        )
    except Exception:
        ptt_mapping = "MAPPED" if ptt_mapped else ("KEYBOARD / STREAM DECK // CTRL+ALT+SHIFT+V" if ptt_keyboard_ready else "PTT SHORTCUT NOT READY")
    voice_input_mode = _valid_text(getattr(app.voice_input_mode_var, "get", lambda: "PTT")(), "PTT").upper()
    voice_input_device = _valid_text(getattr(app.voice_input_device_var, "get", lambda: "System Default")(), "System Default")
    audio_output_device = _valid_text(getattr(app.audio_output_device_var, "get", lambda: "System Default")(), "System Default")
    voice_engine_mode = _valid_text(getattr(app.voice_engine_mode_var, "get", lambda: "AUTO")(), "AUTO").upper()
    voice_name = _valid_text(getattr(app.voice_name_var, "get", lambda: "-")(), "-")
    voice_pitch = _valid_text(getattr(app.voice_pitch_var, "get", lambda: "NORMAL")(), "NORMAL").upper()
    voice_effect = _valid_text(getattr(app.voice_effect_var, "get", lambda: "BRIDGE")(), "BRIDGE").upper()
    try:
        voice_effect_strength = max(0, min(100, int(round(float(app.voice_effect_strength_var.get() or 0)))))
    except Exception:
        voice_effect_strength = 35
    try:
        if voice_engine_mode in ("AUTO", "SUPERTONIC"):
            voice_name_options = list(legacy.VoiceSpeechWorker.SUPER_VOICES)
        else:
            voice_name_options = list(app.voice_engine.windows_voice_names()) or ["System Default"]
    except Exception:
        voice_name_options = list(legacy.VoiceSpeechWorker.SUPER_VOICES)
    voice_pitch_options = list(legacy.VoiceSpeechWorker.PITCH_PRESETS)
    voice_effect_options = list(legacy.VoiceSpeechWorker.EFFECT_PRESETS)
    voice_level = _valid_text(getattr(app.voice_level_var, "get", lambda: "MED")(), "MED").upper()
    voice_attention = _valid_text(getattr(app.voice_attention_mode_var, "get", lambda: "IMPORTANT")(), "IMPORTANT").upper()
    try:
        voice_volume = int(round(float(app.voice_volume_var.get() or 0)))
    except Exception:
        voice_volume = 0
    try:
        voice_speed = float(app.voice_speed_var.get() or 1.0)
    except Exception:
        voice_speed = 1.0
    try:
        voice_mic_level = max(0.0, min(1.0, float(getattr(app, "voice_input_level", 0.0) or 0.0)))
    except Exception:
        voice_mic_level = 0.0
    voice_input_status = _valid_text(getattr(app, "voice_input_status", "-"), "-")
    try:
        control_capture_action = str(app.controller_manager.capture_snapshot() or "")
        control_capture_status = str(app.controller_manager.status or "-")
    except Exception:
        control_capture_action = ""
        control_capture_status = "CONTROLLER LISTENER UNAVAILABLE"
    voice_last_text = _valid_text(getattr(app, "voice_input_last_text", "-"), "-")
    voice_engine_status = _valid_text(getattr(app.voice_engine, "status", "STARTING"), "STARTING")
    voice_engine_warming = bool(
        str(getattr(app.voice_engine, "_qml_neural_warm_state", "") or "").upper() == "INITIALIZING"
        or voice_engine_status.upper().startswith(("LOADING", "WARMING"))
    )
    try:
        voice_warm_duration_ms = int(getattr(app.voice_engine, "_qml_neural_warm_duration_ms", 0) or 0)
    except Exception:
        voice_warm_duration_ms = 0
    ai_tool_mode = _valid_text(getattr(app.ai_tool_mode_var, "get", lambda: "Ask Before Acting")(), "Ask Before Acting")
    ai_copilot_status = _valid_text(getattr(app, "copilot_status", "-"), "-")
    ai_copilot_response = _valid_text(getattr(app, "copilot_response", "-"), "-")
    ai_tool_activity = _valid_text(getattr(app, "copilot_tool_activity", "-"), "-")

    # Persistent cockpit transcript. Keep this intentionally short so the left-rail
    # AI COMMS display remains useful at a glance rather than becoming a full chat app.
    ai_comms_rows = []
    try:
        raw_messages = list(getattr(app, "copilot_messages", []) or [])[-8:]
        for msg in raw_messages:
            if not isinstance(msg, dict):
                continue
            role = str(msg.get("role") or "").strip().lower()
            text = " ".join(str(msg.get("content") or "").replace("\r", " ").replace("\n", " ").split()).strip()
            if not text:
                continue
            ai_comms_rows.append({
                "speaker": "CMDR" if role == "user" else "BRIDGE",
                "text": text[:420],
            })
        # While Luna is thinking, show the newest spoken/typed request immediately,
        # even though the legacy conversation deque is only committed on completion.
        if bool(getattr(app, "copilot_busy", False)):
            pending_prompt = " ".join(str(getattr(app, "copilot_last_prompt", "") or "").replace("\r", " ").replace("\n", " ").split()).strip()
            if pending_prompt and (not ai_comms_rows or ai_comms_rows[-1].get("text") != pending_prompt):
                ai_comms_rows.append({"speaker": "CMDR", "text": pending_prompt[:420]})
            ai_comms_rows.append({"speaker": "BRIDGE", "text": "Working on that now..."})
        ai_comms_rows = ai_comms_rows[-6:]
    except Exception:
        ai_comms_rows = []

    pending_action = getattr(app, "copilot_pending_action", None)
    if isinstance(pending_action, dict):
        pending_type = str(pending_action.get("type") or "ACTION").replace("_", " ").upper()
        pending_target = str(pending_action.get("system") or pending_action.get("command") or "").strip()
        ai_pending_text = pending_type + (f" // {pending_target}" if pending_target else "")
    else:
        ai_pending_text = "NONE"
    ai_safety_level = _valid_text(getattr(app, "safety_last_level", "CLEAR"), "CLEAR").upper()
    ai_safety_reason = _valid_text(getattr(app, "safety_last_reason", "No active threat."), "No active threat.")
    ai_smart_auto = bool(getattr(app.ai_auto_var, "get", lambda: False)())
    ai_launch_rule = bool((getattr(app, "session_rules", {}) or {}).get("clear_and_jump_after_auto_launch", False))
    try:
        ai_transcription_calls = int(getattr(app, "voice_transcription_calls", 0) or 0)
        ai_transcription_failures = int(getattr(app, "voice_transcription_failures", 0) or 0)
        ai_transcription_seconds = float(getattr(app, "voice_transcription_audio_seconds", 0.0) or 0.0)
    except Exception:
        ai_transcription_calls = 0
        ai_transcription_failures = 0
        ai_transcription_seconds = 0.0
    ai_session_rule_count = sum(1 for enabled in (getattr(app, "session_rules", {}) or {}).values() if enabled)
    ai_api_configured = bool(ai_key)
    sfx_enabled = bool(getattr(app.sfx_enabled_var, "get", lambda: False)())
    startup_audio_enabled = bool((getattr(app, "sfx_event_enabled", {}) or {}).get("startup", True))
    try:
        sfx_volume = max(0, min(100, int(round(float(app.sfx_volume_var.get() or 0)))))
    except Exception:
        sfx_volume = 50
    audio_input_devices = list(getattr(app, "audio_input_devices", None) or ["System Default"])
    audio_output_devices = list(getattr(app, "audio_output_devices", None) or ["System Default"])
    if "System Default" not in audio_input_devices:
        audio_input_devices.insert(0, "System Default")
    if "System Default" not in audio_output_devices:
        audio_output_devices.insert(0, "System Default")
    audio_default_input = _valid_text(getattr(app, "audio_default_input", "System Default"), "System Default")
    audio_default_output = _valid_text(getattr(app, "audio_default_output", "System Default"), "System Default")
    try:
        selected_sfx_key = app._sfx_selected_key()
    except Exception:
        selected_sfx_key = "startup"
    if selected_sfx_key not in legacy.SFX_SPECS:
        selected_sfx_key = "startup"
    selected_spec = legacy.SFX_SPECS.get(selected_sfx_key) or legacy.SFX_SPECS["startup"]
    selected_source, selected_custom = app.sfx_manager.source_for(selected_sfx_key)
    selected_sfx_file = _sfx_display_filename(selected_sfx_key, selected_source, selected_custom) if selected_source else str(selected_spec.get("file") or "-")
    selected_sfx_source = "CUSTOM" if selected_custom else "DEFAULT"
    selected_sfx_enabled = bool((getattr(app, "sfx_event_enabled", {}) or {}).get(selected_sfx_key, True))
    audio_sfx_rows = []
    for sfx_key, spec in legacy.SFX_SPECS.items():
        source, custom = app.sfx_manager.source_for(sfx_key)
        audio_sfx_rows.append({
            "key": sfx_key,
            "label": str(spec.get("label") or sfx_key).upper(),
            "file": _sfx_display_filename(sfx_key, source, custom) if source else str(spec.get("file") or "-"),
            "source": "CUSTOM" if custom else "DEFAULT",
            "enabled": bool((getattr(app, "sfx_event_enabled", {}) or {}).get(sfx_key, True)),
        })
    audio_sfx_status = _valid_text(getattr(app.sfx_manager, "status", "-"), "-")
    audio_last_sound = _valid_text(getattr(app.sfx_manager, "last_sound", "-"), "-")

    # Navigation page state comes directly from the proven .95 route engine.
    nav_armed = bool(getattr(app, "nav_armed", False)) and bool(live_elite_bindings)
    nav_status = _valid_text(getattr(app, "nav_status", ""), "Navigation standing by.")
    if not live_elite_bindings:
        nav_status = "ELITE BINDINGS REQUIRED // NAVIGATION COCKPIT COMMANDS DISABLED"
    # The QML destination editor owns its in-progress typing.  The backend value
    # exposed here represents live plotted-route truth, not the legacy Tk entry.
    nav_input = "" if destination == "NO ROUTE" else destination

    nav_mass_lock = "LOCKED" if s.flag("FSD Mass Locked") else "CLEAR"
    nav_mass_lock_level = "bad" if nav_mass_lock == "LOCKED" else "ok"
    nav_route_valid = bool(
        destination != "NO ROUTE"
        and (getattr(s, "nav_route_file_connected", False) or target not in ("", "-"))
    )
    nav_route_source = _valid_text(getattr(s, "nav_route_source", "-"))
    if nav_route_source in ("", "-") and target not in ("", "-"):
        nav_route_source = "FSDTarget"
    nav_route_file_connected = bool(getattr(s, "nav_route_file_connected", False))

    # Current route truth belongs in the NAV COMPUTER status area.  Historical
    # plot failures remain visible in ROUTE LOG instead of masking a later route
    # that the pilot plotted manually in Elite.
    if nav_route_valid and not bool(getattr(app, "native_command_busy", False)):
        jump_text = "" if route_jumps is None else f"  //  {route_jumps} JUMP{'S' if route_jumps != 1 else ''}"
        nav_status = f"ROUTE LIVE  //  {destination}{jump_text}  //  {nav_route_source}"

    upcoming = route_upcoming
    nav_route_entries: list[dict[str, Any]] = []
    current_system = _valid_text(s.system)
    current_star_class = "-"
    current_scoopable = None
    try:
        for route_row in list(getattr(app, "travel_route_entries", []) or []):
            if str(route_row.get("system") or "").strip().casefold() == current_system.casefold():
                current_star_class = _valid_text(route_row.get("star_class"), "-")
                current_scoopable = route_row.get("scoopable")
                break
    except Exception:
        pass
    if current_system not in ("", "-"):
        nav_route_entries.append({
            "system": current_system,
            "starClass": current_star_class,
            "scoopable": bool(current_scoopable) if current_scoopable is not None else None,
            "kind": "CURRENT",
        })

    # Keep the route map readable on very long routes. Show the first five
    # upcoming jumps, a continuation marker, and the final destination.
    # The exact total remains in routeJumps and can exceed 1000.
    display_upcoming = list(upcoming)
    if len(display_upcoming) > 7:
        hidden_count = max(1, len(display_upcoming) - 6)
        display_upcoming = (
            display_upcoming[:5]
            + [{
                "system": f"{hidden_count} MORE",
                "star_class": "-",
                "scoopable": None,
                "kind": "ELLIPSIS",
                "hidden_count": hidden_count,
            }]
            + display_upcoming[-1:]
        )

    for row in display_upcoming:
        if not isinstance(row, dict):
            continue
        row_kind = str(row.get("kind") or "").upper()
        if row_kind == "ELLIPSIS":
            nav_route_entries.append({
                "system": _valid_text(row.get("system"), "MORE"),
                "starClass": "-",
                "scoopable": None,
                "kind": "ELLIPSIS",
                "hiddenCount": int(row.get("hidden_count") or 0),
            })
            continue
        star_class = _valid_text(row.get("star_class"), "-")
        system_name = _valid_text(row.get("system"), "-")
        if system_name in ("", "-"):
            continue
        nav_route_entries.append({
            "system": system_name,
            "starClass": star_class,
            "scoopable": bool(row.get("scoopable")) if row.get("scoopable") is not None else None,
            "kind": "NEXT" if len(nav_route_entries) == 1 else ("DESTINATION" if row is display_upcoming[-1] else "ROUTE"),
        })

    # If travel metadata is not populated yet, still expose the FSD target truthfully.
    if len(nav_route_entries) <= 1 and target not in ("", "-") and target != current_system:
        nav_route_entries.append({
            "system": target,
            "starClass": next_star_class,
            "scoopable": next_star_scoopable,
            "kind": "NEXT",
        })

    in_system_target = _status_in_system_target(s, st, current_system, destination, target)

    nav_flight_plan: list[dict[str, str]] = []
    if destination == "NO ROUTE":
        nav_flight_plan.append({"step": "01", "text": f"CURRENT // {current_system}", "level": "info"})
        nav_flight_plan.append({"step": "02", "text": "AWAIT ROUTE", "level": "warn"})
    else:
        nav_flight_plan.append({"step": "01", "text": f"CURRENT // {current_system}", "level": "info"})
        if target not in ("", "-"):
            nav_flight_plan.append({"step": "02", "text": f"NEXT // {target}", "level": "ok"})
        if destination not in ("", "-") and destination != target:
            nav_flight_plan.append({"step": f"{len(nav_flight_plan)+1:02d}", "text": f"DEST // {destination}", "level": "ok"})
        if route_jumps is not None:
            nav_flight_plan.append({
                "step": f"{len(nav_flight_plan)+1:02d}",
                "text": f"{route_jumps} JUMP{'S' if route_jumps != 1 else ''} REMAINING",
                "level": "info",
            })
    if in_system_target.get("visible"):
        nav_flight_plan.append({
            "step": f"{len(nav_flight_plan)+1:02d}",
            "text": f"{in_system_target.get('kind', 'IN-SYSTEM TARGET')} // {in_system_target.get('name', '-')}",
            "level": "ok",
        })
    nav_flight_plan = nav_flight_plan[:4]

    if elite_live:
        station_display = "IN FLIGHT" if _valid_text(s.station) == "-" else _valid_text(s.station)
    else:
        station_display = "-"
    _update_qml_nav_trip_log(
        app,
        current_system=current_system,
        destination=destination,
        fsd_target=target,
        route_jumps=route_jumps,
        in_system_target=in_system_target,
        docked=bool(s.flag("Docked")),
        station=station_display,
        docking_revision=int(getattr(s, "docking_revision", 0) or 0),
        docking_event=_valid_text(getattr(s, "last_docking_event", "-")),
        docking_station=_valid_text(getattr(s, "last_docking_station", "-")),
    )

    nav_memories = _load_nav_memories()
    nav_memory_capture_system = destination if nav_route_valid and destination != "NO ROUTE" else current_system
    nav_memory_capture_source = "PLOTTED TARGET" if nav_route_valid and destination != "NO ROUTE" else "CURRENT SYSTEM"

    # Combat page state is projected from the existing v0.12.95 combat observer
    # and native-command engine.  Do not invent telemetry that Elite does not
    # expose (for example, arbitrary nearby-contact ranges or weapon capacitor %).
    combat_elapsed = float(s.combat_elapsed_seconds() or 0.0)
    try:
        combat_elapsed_text = app._combat_format_duration(combat_elapsed)
    except Exception:
        combat_elapsed_text = "0:00:00"
    combat_cr = int(getattr(s, "combat_bounty_cr", 0) or 0) + int(getattr(s, "combat_bond_cr", 0) or 0)
    combat_cr_hr = int(combat_cr * 3600.0 / combat_elapsed) if combat_elapsed >= 30 else 0
    under_attack_recent = bool(getattr(s, "last_under_attack", 0.0) and (time.time() - float(s.last_under_attack)) < 10.0)
    target_present = _valid_text(getattr(s, "target", "-")) not in ("", "-")
    target_hull_pct = _pct(getattr(s, "target_hull", None))
    target_shield_pct = _pct(getattr(s, "target_shield", None))
    target_subsystem_pct = _pct(getattr(s, "target_subsystem_health", None))
    target_scan_stage = int(getattr(s, "target_scan_stage", 0) or 0)
    target_legal = _valid_text(getattr(s, "target_legal", "-"))
    target_bounty = getattr(s, "target_bounty", None)
    if target_bounty is None:
        target_bounty_text = "-"
    else:
        try:
            target_bounty_text = f"{int(target_bounty):,} CR"
        except Exception:
            target_bounty_text = str(target_bounty)

    combat_command_status = _valid_text(getattr(app, "native_command_status", "-"))
    combat_command_upper = combat_command_status.upper()
    # Fighter failures stay pilot-facing and concise. Technical journal limitations
    # belong in diagnostics, not in the combat command rack.
    if "DEPLOY FIGHTER" in combat_command_upper and "NO LAUNCHFIGHTER CONFIRMATION" in combat_command_upper:
        combat_command_status = "Deploy Fighter: I can't deploy a fighter right now."

    if getattr(app, "native_command_busy", False):
        combat_advisory = _valid_text(getattr(app, "native_command_status", ""), "Combat command running.")
    elif target_present and target_scan_stage >= 3:
        combat_advisory = _valid_text(s.current_target_intel(), "FULL TARGET SCAN COMPLETE")
    elif target_present:
        combat_advisory = f"TARGET ACQUIRED // SCAN STAGE {target_scan_stage}/3 // WAITING FOR FULL INTEL"
    elif under_attack_recent:
        combat_advisory = "UNDER ATTACK // NO SHIP TARGET CURRENTLY LOCKED"
    else:
        combat_advisory = "NO SHIP TARGET LOCKED // COMBAT OBSERVER STANDING BY"

    fire_group_raw = st.get("FireGroup")
    try:
        fire_group_text = f"GROUP {int(fire_group_raw) + 1}"
    except Exception:
        fire_group_text = "-"

    hull_level = "bad" if hull_percent >= 0 and hull_percent < 35 else ("warn" if hull_percent >= 0 and hull_percent < 70 else "ok")
    if elite_live:
        combat_status_rows = [
            {"label": "HULL", "value": "-" if hull_percent < 0 else f"{hull_percent}%", "level": hull_level},
            {"label": "SHIELDS", "value": "UP" if s.flag("Shields Up") else "DOWN", "level": "ok" if s.flag("Shields Up") else "bad"},
            {"label": "HEAT", "value": "OVERHEATING" if s.flag("Overheating") else "NORMAL", "level": "bad" if s.flag("Overheating") else "ok"},
            {"label": "POWER", "value": pips_text, "level": "info"},
            {"label": "UNDER ATTACK", "value": "YES" if under_attack_recent else "NO", "level": "bad" if under_attack_recent else "ok"},
            {"label": "HARDPOINTS", "value": "DEPLOYED" if s.flag("Hardpoints") else "RETRACTED", "level": "warn" if s.flag("Hardpoints") else "ok"},
            {"label": "HUD MODE", "value": "ANALYSIS" if s.flag("Analysis Mode") else "COMBAT", "level": "warn" if s.flag("Analysis Mode") else "ok"},
            {"label": "FIRE GROUP", "value": fire_group_text, "level": "info"},
            {"label": "MASS LOCK", "value": "YES" if s.flag("FSD Mass Locked") else "NO", "level": "warn" if s.flag("FSD Mass Locked") else "ok"},
        ]
    else:
        combat_status_rows = [
            {"label": label, "value": "UNKNOWN", "level": "info"}
            for label in ("HULL", "SHIELDS", "HEAT", "POWER", "UNDER ATTACK", "HARDPOINTS", "HUD MODE", "FIRE GROUP", "MASS LOCK")
        ]

    combat_session_rows = [
        {"label": "SESSION", "value": f"{combat_elapsed_text} / {int(s.combat_encounters or 0)} ENCOUNTER(S)", "level": "info"},
        {"label": "BOUNTIES", "value": f"{int(s.combat_bounty_kills or 0):,} / {int(s.combat_bounty_cr or 0):,} CR", "level": "ok"},
        {"label": "BONDS", "value": f"{int(s.combat_bond_kills or 0):,} / {int(s.combat_bond_cr or 0):,} CR", "level": "info"},
        {"label": "CR / HR", "value": "-" if combat_elapsed < 30 else f"{combat_cr_hr:,} CR/HR", "level": "info"},
    ]

    stolen_aboard = int(s.stolen_cargo_count() or 0)
    collector_upper = max(0, int(getattr(s, "collector_launches_upper_bound", 0) or 0))
    limpet_reserve = max(0, int(s.limpet_reserve_count() or 0))
    crew_alert_active = bool(
        _valid_text(getattr(s, "crew_pay_alert_text", "-")) not in ("", "-")
        and time.monotonic() <= float(getattr(s, "crew_pay_alert_expires_mono", 0.0) or 0.0)
    )
    crew_value = _valid_text(getattr(s, "crew_last_wage", "-"), "NO WAGE EVENT OBSERVED")
    # Predictive threat warning. v0.12.95 already classifies hostile NPC chat and
    # pirate/interdiction chatter. The QML adapter exposes that signal and adds a
    # one-shot Smart-Auto voice trigger without changing the locked engine.
    try:
        hostile_chat = app._combat_hostile_chat_active() or "-"
    except Exception:
        hostile_chat = _valid_text(getattr(app, "combat_hostile_chat_text", "-"))
    try:
        interdiction_alert = app._interdiction_active_alert() or "-"
    except Exception:
        interdiction_alert = _valid_text(getattr(app, "interdiction_alert_text", "-"))
    hostile_sender = _valid_text(getattr(app, "combat_hostile_chat_sender", "-"))
    threat_warning = hostile_chat if hostile_chat not in ("", "-") else interdiction_alert
    if hostile_chat not in ("", "-"):
        # v0.30.08 semantic episode suppression. The locked engine quite correctly
        # treats different pirate lines as different messages, but for speech they
        # are usually the same threat episode. Warn once per sender/episode instead
        # of letting paraphrased NPC chatter produce several nearly-identical calls.
        sender_key = hostile_sender.casefold() if hostile_sender not in ("", "-") else "unknown-hostile"
        now_mono = time.monotonic()
        by_sender = getattr(app, "_qml_hostile_voice_by_sender", None)
        if not isinstance(by_sender, dict):
            by_sender = {}
            app._qml_hostile_voice_by_sender = by_sender
        last_mono = float(by_sender.get(sender_key, 0.0) or 0.0)
        if (now_mono - last_mono) >= 75.0:
            by_sender[sender_key] = now_mono
            try:
                app.queue_ai_trigger(
                    f"Safety: {hostile_chat}", 99, "hostile_chat", 0, 20
                )
            except Exception:
                pass

    # Elite does not provide a universal Status.json 'being scanned' bit. In
    # practice authority/NPC scan notices arrive through ReceiveText, so watch
    # only recent ReceiveText summaries for explicit scan language. Keep the
    # alert short-lived and de-duplicate it so repeated journal refreshes do not
    # chatter.
    scan_phrases = (
        "scan detected", "ship scan", "cargo scan", "commencing scan",
        "scanning your ship", "scanning your vessel", "submit to scan",
        "hold position for scan", "scan in progress",
    )
    latest_scan_line = None
    for line in reversed(list(getattr(s, "event_log", []) or [])[-80:]):
        low = str(line).casefold()
        if "receivetext" not in low:
            continue
        if any(phrase in low for phrase in scan_phrases):
            latest_scan_line = str(line)
            break
    if latest_scan_line and getattr(app, "_qml_last_scan_signature", None) != latest_scan_line:
        app._qml_last_scan_signature = latest_scan_line
        app._qml_scan_alert_text = "SHIP SCAN DETECTED"
        app._qml_scan_alert_until = time.monotonic() + 14.0
        try:
            app.queue_ai_trigger(
                "Safety: your ship is being scanned", 96, "ship_scan", 0, 15
            )
        except Exception:
            pass
    scan_active = bool(
        getattr(app, "_qml_scan_alert_until", 0.0)
        and time.monotonic() <= float(getattr(app, "_qml_scan_alert_until", 0.0) or 0.0)
    )
    scan_alert_text = _valid_text(getattr(app, "_qml_scan_alert_text", "SHIP SCAN DETECTED")) if scan_active else "CLEAR"

    combat_alert_rows = [
        {"label": "THREAT WATCH", "value": threat_warning if threat_warning not in ("", "-") else "NO HOSTILE CHAT", "level": "bad" if threat_warning not in ("", "-") else "ok"},
        {"label": "SHIP SCAN", "value": scan_alert_text, "level": "warn" if scan_active else "ok"},
        {"label": "STOLEN CARGO", "value": f"{stolen_aboard} ABOARD" if stolen_aboard else "NONE DETECTED", "level": "bad" if stolen_aboard else "ok"},
        {"label": "COLLECTORS", "value": s.collector_deployment_text(), "level": "warn" if collector_upper else "ok"},
        {"label": "CREW PAY", "value": crew_value, "level": "warn" if crew_alert_active or int(getattr(s, "crew_wages_total", 0) or 0) else "info"},
    ]

    try:
        chaff_remaining = max(0, int(app._auto_chaff_known_remaining()))
    except Exception:
        chaff_remaining = 0
    heat_sink_rec = (getattr(s, "utility_ammo", {}) or {}).get("heat_sink") or {}
    try:
        heat_sink_remaining = max(0, int(heat_sink_rec.get("total", 0) or 0))
    except Exception:
        heat_sink_remaining = 0
    fighter_event = _valid_text(getattr(s, "last_fighter_event", "-"), "NONE OBSERVED")
    if fighter_event != "NONE OBSERVED" and _valid_text(getattr(s, "last_fighter_event_time", "-")) not in ("", "-"):
        fighter_event = f"{fighter_event} @ {_event_stamp_local_12h(str(s.last_fighter_event_time))}"
    combat_support_rows = [
        {"label": "COLLECTOR COUNT", "value": f"UP TO {collector_upper} DEPLOYED", "level": "warn" if collector_upper else "ok"},
        {"label": "LIMPET RESERVE", "value": f"{limpet_reserve}", "level": "warn" if limpet_reserve < 3 else "ok"},
        {"label": "FIGHTER", "value": fighter_event, "level": "info"},
        {"label": "CHAFF", "value": f"~{chaff_remaining} EST. REMAINING", "level": "warn" if chaff_remaining <= 1 else "ok"},
        {"label": "HEAT SINK", "value": f"{heat_sink_remaining} LAST-KNOWN", "level": "warn" if heat_sink_remaining <= 1 else "ok"},
    ]

    dynamic_pips_enabled = bool(getattr(app, "dynamic_pips_var", None).get()) if getattr(app, "dynamic_pips_var", None) is not None else False
    auto_subsystem_enabled = bool(getattr(app, "auto_powerplant_var", None).get()) if getattr(app, "auto_powerplant_var", None) is not None else False
    auto_chaff_enabled = bool(getattr(app, "auto_chaff_var", None).get()) if getattr(app, "auto_chaff_var", None) is not None else False
    # QML RES browser: up to 50 results, hard-limited to 10,000 LS from arrival.
    # .95 already asks INTRA for this limit; repeating it here protects the UI
    # from stale/cached rows and keeps plotted indices consistent with the list.
    res_results = list(getattr(app, "res_search_results", []) or [])
    res_rows = []
    for source_index, row in enumerate(res_results):
        try:
            ly = float(row.get("distance_ly", -1))
        except Exception:
            ly = -1
        try:
            res_ls = float(row.get("res_ls", -1))
        except Exception:
            res_ls = -1
        if res_ls < 0 or res_ls > 10000.0:
            continue
        res_rows.append({
            "sourceIndex": source_index,
            "type": _valid_text(row.get("type"), "RES"),
            "system": _valid_text(row.get("system"), "-"),
            "body": _valid_text(row.get("body"), "-"),
            "distanceLy": "-" if ly < 0 else f"{ly:.1f}",
            "distanceLs": f"{res_ls:,.0f}",
            "resLs": res_ls,
            "support": _valid_text(row.get("support_quality"), "-"),
        })
        if len(res_rows) >= 50:
            break
    if res_rows:
        r0 = res_rows[0]
        res_nearest = f"{r0['type']} // {r0['system']} // {r0['body']} // {r0['distanceLy']} LY // {r0['distanceLs']} LS"
    else:
        res_nearest = "-"

    combat_target_rows = [
        {"label": "VESSEL", "value": _valid_text(getattr(s, "target_ship", "-")) if target_present else "NO TARGET", "level": "info"},
        {"label": "PILOT", "value": _valid_text(getattr(s, "target_pilot", "-")) if target_present else "-", "level": "info"},
        {"label": "FACTION", "value": _valid_text(getattr(s, "target_faction", "-")) if target_present else "-", "level": "info"},
        {"label": "STATUS", "value": target_legal if target_present else "-", "level": "bad" if target_legal.casefold() == "wanted" else "ok"},
        {"label": "BOUNTY", "value": target_bounty_text if target_present else "-", "level": "warn" if target_bounty not in (None, 0) else "info"},
        {"label": "SUBSYSTEM", "value": _valid_text(getattr(s, "target_subsystem", "-")) if target_present else "-", "level": "warn" if target_present and _valid_text(getattr(s, "target_subsystem", "-")) not in ("", "-") else "info"},
        {"label": "SCAN", "value": f"STAGE {target_scan_stage}/3" if target_present else "-", "level": "ok" if target_scan_stage >= 3 else ("warn" if target_present else "info")},
    ]

    # Trade page adapter state.  These values are sourced from the proven .95
    # market/trade-loop/ledger state instead of hard-coded prototype figures.
    try:
        trade_cfg = app._trade_loop_config()
    except Exception:
        trade_cfg = {
            "commodity": str(getattr(getattr(app, "trade_loop_commodity_var", None), "get", lambda: "-")() or "-"),
            "cargo": 0,
            "buy_system": "-", "buy_station": "-",
            "sell_system": "-", "sell_station": "-",
        }
    try:
        configured_cargo = int(trade_cfg.get("cargo") or 0)
    except Exception:
        configured_cargo = 0
    trade_commodity = _valid_text(trade_cfg.get("commodity"), "-")
    market_items = list(getattr(s, "market_items", []) or [])
    trade_market_rows = len(market_items)
    trade_market_station = _valid_text(getattr(s, "market_station", "-"), "-")
    trade_market_system = _valid_text(getattr(s, "market_system", "-"), "-")
    trade_market_timestamp = _valid_text(getattr(s, "market_timestamp", "-"), "-")
    configured_market = None
    try:
        wanted_key = legacy.market_commodity_key(trade_commodity)
        for mi in market_items:
            key = legacy.market_commodity_key(mi.get("Name_Localised") or mi.get("Name"))
            if key == wanted_key:
                configured_market = mi
                break
    except Exception:
        configured_market = None

    def _trade_int(value, default=0):
        try:
            return int(value or 0)
        except Exception:
            return default

    trade_market_buy = _trade_int((configured_market or {}).get("BuyPrice"), 0)
    trade_market_sell = _trade_int((configured_market or {}).get("SellPrice"), 0)
    trade_market_stock = _trade_int((configured_market or {}).get("Stock"), 0)
    trade_market_demand = _trade_int((configured_market or {}).get("Demand"), 0)

    ship_cargo_used = _trade_int(getattr(s, "cargo_count", 0), 0)
    raw_capacity = getattr(s, "cargo_capacity", None)
    try:
        ship_cargo_capacity = max(0, int(float(raw_capacity))) if raw_capacity is not None else -1
    except Exception:
        ship_cargo_capacity = -1
    ship_cargo_available = max(0, ship_cargo_capacity - ship_cargo_used) if ship_cargo_capacity >= 0 else -1
    trade_planned_cargo = ship_cargo_capacity if ship_cargo_capacity > 0 else max(0, configured_cargo)

    # Only expose known/observed commodity names to QML.  This keeps the
    # selector typo-proof while still learning newer Elite commodities from
    # Market.json and the live trade ledger.
    commodity_names = {str(x).strip() for x in TRADE_COMMODITY_BASE if str(x).strip()}
    if trade_commodity not in ("", "-"):
        commodity_names.add(trade_commodity)
    for mi in market_items:
        name = _valid_text(mi.get("Name_Localised") or mi.get("Name"), "")
        if name:
            commodity_names.add(name)

    ledger = getattr(s, "trade_ledger", None)
    ledger_rows_raw = list(getattr(ledger, "rows", []) or [])
    trade_ledger_rows = []
    for row in reversed(ledger_rows_raw[-20:]):
        profit = row.get("profit")
        margin = row.get("margin_pct")
        trade_ledger_rows.append({
            "time": _valid_text(row.get("time"), "-"),
            "type": _valid_text(row.get("type"), "-"),
            "commodity": _valid_text(row.get("commodity"), "-"),
            "qty": _trade_int(row.get("qty"), 0),
            "unit": _trade_int(row.get("unit"), 0),
            "profit": None if profit is None else _trade_int(profit, 0),
            "margin": "-" if margin is None else f"{float(margin):.1f}%",
            "system": _valid_text(row.get("system"), "-"),
            "station": _valid_text(row.get("station"), "-"),
        })
    trade_realized_profit = _trade_int(getattr(ledger, "total_realized_profit", 0), 0)
    trade_known_profit_rows = _trade_int(getattr(ledger, "known_profit_rows", 0), 0)
    latest_buy_unit = 0
    latest_sell_unit = 0
    try:
        wanted_key = legacy.market_commodity_key(trade_commodity)
        for row in reversed(ledger_rows_raw):
            commodity_names.add(_valid_text(row.get("commodity"), ""))
            if legacy.market_commodity_key(row.get("commodity") or "") != wanted_key:
                continue
            typ = str(row.get("type") or "").upper()
            if typ == "BUY" and latest_buy_unit <= 0:
                latest_buy_unit = _trade_int(row.get("unit"), 0)
            elif typ == "SELL" and latest_sell_unit <= 0:
                latest_sell_unit = _trade_int(row.get("unit"), 0)
            if latest_buy_unit > 0 and latest_sell_unit > 0:
                break
    except Exception:
        pass
    commodity_names.discard("")
    commodity_options = sorted(commodity_names, key=lambda x: x.casefold())
    estimated_profit_cycle = 0
    if latest_buy_unit > 0 and latest_sell_unit > latest_buy_unit and trade_planned_cargo > 0:
        estimated_profit_cycle = (latest_sell_unit - latest_buy_unit) * trade_planned_cargo

    trade_loop_enabled = bool(getattr(app.trade_loop_enabled_var, "get", lambda: False)())
    trade_loop_status = _valid_text(getattr(app, "trade_loop_status", "-"), "-")
    trade_loop_last_action = _valid_text(getattr(app, "trade_loop_last_action", "-"), "-")
    trade_loop_buy_system = _valid_text(trade_cfg.get("buy_system"), "-")
    trade_loop_buy_station = _valid_text(trade_cfg.get("buy_station"), "-")
    trade_loop_sell_system = _valid_text(trade_cfg.get("sell_system"), "-")
    trade_loop_sell_station = _valid_text(trade_cfg.get("sell_station"), "-")
    trade_power_rank = _trade_int(getattr(s, "power_rank", 0), 0)
    trade_power_merits = _trade_int(getattr(s, "power_merits", 0), 0)
    trade_route_busy = bool(getattr(app, "trade_loop_search_busy", False))
    trade_route_status = _valid_text(getattr(app, "loop_search_status", "READY // SELECT COMMODITY AND SEARCH"), "READY // SELECT COMMODITY AND SEARCH")
    route_pairs = list(getattr(app, "trade_loop_search_results", []) or [])
    max_ls = int(getattr(getattr(app, "_qml_host", None), "trade_route_max_ls", 10000) or 10000) if hasattr(app, "_qml_host") else 10000
    trade_route_rows = []
    trade_route_pairs = []
    for pair in route_pairs:
        buy = pair.get("buy") or {}; sell = pair.get("sell") or {}
        buy_ls = float(buy.get("arrival_ls") or 0); sell_ls = float(sell.get("arrival_ls") or 0)
        if (buy_ls and buy_ls > max_ls) or (sell_ls and sell_ls > max_ls):
            continue
        trade_route_pairs.append(pair)
        trade_route_rows.append({
            "buySystem": _valid_text(buy.get("system"), "-"),
            "buyStation": _valid_text(buy.get("station"), "-"),
            "buyLy": float(buy.get("distance_ly") or 0),
            "buyLs": int(round(buy_ls)),
            "buyPrice": _trade_int(pair.get("buy_price"), 0),
            "supply": _trade_int(buy.get("volume"), 0),
            "sellSystem": _valid_text(sell.get("system"), "-"),
            "sellStation": _valid_text(sell.get("station"), "-"),
            "sellLy": float(sell.get("distance_ly") or 0),
            "sellLs": int(round(sell_ls)),
            "sellPrice": _trade_int(pair.get("sell_price"), 0),
            "demand": _trade_int(sell.get("volume"), 0),
            "profitPerT": _trade_int(pair.get("profit_per_t"), 0),
            "profitPerLoad": _trade_int(pair.get("profit_per_load"), 0),
            "sustainableLoads": _trade_int(pair.get("sustainable_loads"), 0),
            "legLy": float(pair.get("leg_ly") or 0),
            "score": float(pair.get("score") or 0),
        })
    if hasattr(app, "_qml_host"):
        app._qml_host.trade_route_filtered_pairs = trade_route_pairs

    best_host = getattr(app, "_qml_host", None)
    trade_best_busy = bool(getattr(best_host, "trade_best_busy", False)) if best_host is not None else False
    trade_best_status = _valid_text(getattr(best_host, "trade_best_status", "READY // FIND THE BEST COMMODITY + LOOP"), "READY // FIND THE BEST COMMODITY + LOOP") if best_host is not None else "READY // FIND THE BEST COMMODITY + LOOP"
    best_pairs = list(getattr(best_host, "trade_best_pairs", []) or []) if best_host is not None else []
    trade_best_rows = []
    for pair in best_pairs:
        buy = pair.get("buy") or {}; sell = pair.get("sell") or {}
        trade_best_rows.append({
            "commodity": _valid_text(pair.get("commodity"), "-"),
            "score": float(pair.get("score") or 0),
            "buySystem": _valid_text(buy.get("system"), "-"),
            "buyStation": _valid_text(buy.get("station"), "-"),
            "buyLs": int(round(float(buy.get("arrival_ls") or 0))),
            "buyPrice": _trade_int(pair.get("buy_price"), 0),
            "supply": _trade_int(buy.get("volume"), 0),
            "sellSystem": _valid_text(sell.get("system"), "-"),
            "sellStation": _valid_text(sell.get("station"), "-"),
            "sellLs": int(round(float(sell.get("arrival_ls") or 0))),
            "sellPrice": _trade_int(pair.get("sell_price"), 0),
            "demand": _trade_int(sell.get("volume"), 0),
            "profitPerT": _trade_int(pair.get("profit_per_t"), 0),
            "profitPerLoad": _trade_int(pair.get("profit_per_load"), 0),
            "sustainableLoads": _trade_int(pair.get("sustainable_loads"), 0),
            "startLy": (float(pair.get("start_ly")) if isinstance(pair.get("start_ly"), (int, float)) else None),
            "legLy": float(pair.get("leg_ly") or 0),
            "rareGood": bool(pair.get("rare_good", False)),
            "knownProhibited": bool(pair.get("known_prohibited", False)),
        })

    trade_last_merit = "-"
    tracker = getattr(s, "powerplay_tracker", None)
    if tracker is not None:
        try:
            ev = getattr(tracker, "last_merit_event", None)
            if isinstance(ev, dict):
                trade_last_merit = tracker._display_merits(ev)
        except Exception:
            pass

    # Colonization project/logistics projection. The .95 engine already owns the
    # authoritative ConstructionDepot/Contribution parsing and persistence. QML
    # only presents that state and hands a selected commodity to the existing
    # Trade route finder; there is intentionally no second market-search engine.
    colonization_projects = _colonization_project_records(s)
    if getattr(s, "colonization_current_market_id", None) is None and colonization_projects:
        try:
            s._restore_colonization_project(colonization_projects[0]["marketId"])
        except Exception:
            pass

    colonization_market_id = getattr(s, "colonization_current_market_id", None)
    colonization_has_project = colonization_market_id is not None
    colonization_current_index = -1
    if colonization_has_project:
        for idx, row in enumerate(colonization_projects):
            if str(row.get("marketId")) == str(colonization_market_id):
                colonization_current_index = idx
                break

    try:
        colonization_progress_pct = max(0.0, min(100.0, float(getattr(s, "colonization_progress", 0) or 0) * 100.0))
    except Exception:
        colonization_progress_pct = 0.0
    colonization_status = (
        "COMPLETE" if bool(getattr(s, "colonization_complete", False))
        else "FAILED" if bool(getattr(s, "colonization_failed", False))
        else "ACTIVE" if colonization_has_project
        else "NO PROJECT"
    )

    cargo_map: dict[str, int] = {}
    for cargo_item in list(getattr(s, "cargo", []) or []):
        if not isinstance(cargo_item, dict):
            continue
        try:
            key = legacy.market_commodity_key(cargo_item.get("Name_Localised") or cargo_item.get("Name") or "")
            cargo_map[key] = cargo_map.get(key, 0) + max(0, int(cargo_item.get("Count", 0) or 0))
        except Exception:
            continue

    colonization_requirement_rows = []
    try:
        raw_requirement_rows = list(s.colonization_remaining_rows() or [])
    except Exception:
        raw_requirement_rows = []
    for row in raw_requirement_rows:
        name = _valid_text(row.get("name"), "UNKNOWN")
        aboard = cargo_map.get(legacy.market_commodity_key(name), 0)
        colonization_requirement_rows.append({
            "name": name,
            "required": int(row.get("required", 0) or 0),
            "provided": int(row.get("provided", 0) or 0),
            "remaining": int(row.get("remaining", 0) or 0),
            "aboard": int(aboard or 0),
            "payment": int(row.get("payment", 0) or 0),
            "complete": bool(row.get("complete", False)),
        })

    colonization_remaining_total = sum(max(0, int(row.get("remaining", 0) or 0)) for row in colonization_requirement_rows)
    colonization_complete_count = sum(1 for row in colonization_requirement_rows if bool(row.get("complete")))
    colonization_incomplete_count = max(0, len(colonization_requirement_rows) - colonization_complete_count)
    colonization_next = next((row for row in colonization_requirement_rows if int(row.get("remaining", 0) or 0) > 0), None)
    colonization_next_commodity = _valid_text((colonization_next or {}).get("name"), "-")
    colonization_next_remaining = int((colonization_next or {}).get("remaining", 0) or 0)
    colonization_next_aboard = int((colonization_next or {}).get("aboard", 0) or 0)
    colony_capacity = max(0, ship_cargo_capacity)
    colonization_next_load_target = min(colonization_next_remaining, colony_capacity) if colony_capacity > 0 else colonization_next_remaining
    colonization_commodity_loads = (
        int(math.ceil(float(colonization_next_remaining) / float(colony_capacity)))
        if colony_capacity > 0 and colonization_next_remaining > 0 else 0
    )
    colonization_project_loads = (
        int(math.ceil(float(colonization_remaining_total) / float(colony_capacity)))
        if colony_capacity > 0 and colonization_remaining_total > 0 else 0
    )

    try:
        colonization_pace = dict(s.colonization_pace_estimate(colonization_market_id) or {})
    except Exception:
        colonization_pace = {}
    pace_samples = int(colonization_pace.get("samples") or 0)
    avg_tons = colonization_pace.get("avg_tons")
    trips_left = colonization_pace.get("trips_left")
    avg_cycle = colonization_pace.get("avg_cycle_seconds")
    hours_left = colonization_pace.get("hours_left")
    if colonization_remaining_total <= 0 and colonization_has_project:
        colonization_pace_text = "PROJECT MATERIAL GOAL COMPLETE"
    elif pace_samples <= 0 or not avg_tons:
        colonization_pace_text = "MAKE A CONFIRMED DELIVERY TO ESTABLISH HAULING PACE"
    else:
        colonization_pace_text = f"{pace_samples} TRIP(S) // AVG {float(avg_tons):,.0f} T/TRIP"
        if trips_left is not None:
            colonization_pace_text += f" // ~{int(trips_left):,} TRIPS LEFT"
        if avg_cycle:
            colonization_pace_text += f" // {float(avg_cycle)/60.0:.1f} MIN/CYCLE"
        if hours_left is not None:
            colonization_pace_text += f" // ~{float(hours_left):.1f} HR" if float(hours_left) >= 1.0 else f" // ~{float(hours_left)*60.0:.0f} MIN"

    colonization_log_rows = []
    for line in list(getattr(s, "colonization_contribution_history", []) or [])[:8]:
        colonization_log_rows.append({"kind": "DELIVERY", "text": str(line)})
    for line in list(getattr(s, "colonization_claim_history", []) or [])[:4]:
        colonization_log_rows.append({"kind": "CLAIM", "text": str(line)})
    if not colonization_log_rows and colonization_has_project:
        colonization_log_rows.append({
            "kind": "PROJECT",
            "text": f"Last project event: {_valid_text(getattr(s, 'colonization_last_event', '-'))} // {_valid_text(getattr(s, 'colonization_last_update', '-'))}",
        })

    # Commander / records adapter.  Keep .95 authoritative and surface only
    # values the journal/status/history layers can actually prove.
    try:
        commander_history = dict(app.history_reader.snapshot(s.system, s.station, limit=12, force=False) or {})
    except Exception as exc:
        commander_history = {"available": False, "error": str(exc), "counts": {}, "trade_summary": {}}
    history_available = bool(commander_history.get("available"))
    history_counts = dict(commander_history.get("counts") or {})
    history_trade = dict(commander_history.get("trade_summary") or {})

    credits_value = getattr(s, "credits", None)
    credits_source = "LOADGAME"
    if credits_value is None:
        latest_credit = commander_history.get("latest_credit") or {}
        credits_value = latest_credit.get("credits") if isinstance(latest_credit, dict) else None
        credits_source = "HISTORY" if credits_value is not None else "UNKNOWN"

    commander_power = _valid_text(getattr(s, "power", "-"), "-")
    commander_power_rank = getattr(s, "power_rank", None)
    commander_power_merits = getattr(s, "power_merits", None)
    commander_dossier_rows = [
        {"label": "CURRENT SYSTEM", "value": _valid_text(s.system), "level": "info"},
        {"label": "CURRENT STATION", "value": station_display, "level": "info"},
        {"label": "GAME MODE", "value": _valid_text(getattr(s, "game_mode", "-")), "level": "info"},
        {"label": "POWER", "value": commander_power, "level": "warn" if commander_power != "-" else "info"},
        {"label": "POWER RANK", "value": str(commander_power_rank) if commander_power_rank is not None else "-", "level": "ok" if commander_power_rank is not None else "info"},
        {"label": "MERITS", "value": f"{int(commander_power_merits):,}" if commander_power_merits is not None else "-", "level": "ok" if commander_power_merits is not None else "info"},
        {"label": "ACTIVE MISSIONS", "value": f"{len(getattr(s, 'missions', {}) or {}):,}", "level": "ok"},
    ]

    history_profit = history_trade.get("known_realized_profit") if history_available else None

    # Commander trade-profit display is source-aware.  Prefer the Bridge's own
    # reconstructed live/current-journal ledger whenever it has at least one
    # matched profit row.  If this Bridge instance/journal has not observed a
    # matched sale yet, fall back to the compact historical trade archive rather
    # than presenting a misleading 0 CR as though it were a career total.
    if trade_known_profit_rows > 0:
        commander_trade_profit = trade_realized_profit
        commander_trade_profit_label = "TRADE PROFIT // LIVE"
        commander_trade_profit_source = f"BRIDGE LEDGER // {trade_known_profit_rows:,} MATCHED SALE(S)"
    elif history_available and history_profit is not None:
        try:
            commander_trade_profit = int(round(float(history_profit)))
        except Exception:
            commander_trade_profit = None
        commander_trade_profit_label = "TRADE PROFIT // HISTORY"
        commander_trade_profit_source = "EDDISCOVERY COMPACT ARCHIVE"
    else:
        commander_trade_profit = None
        commander_trade_profit_label = "TRADE PROFIT // TRACKED"
        commander_trade_profit_source = "NO MATCHED TRADE PROFIT AVAILABLE"

    commander_career_rows = [
        {"label": "LAST KNOWN CREDITS", "value": _fmt_commander_cr(credits_value), "level": "ok" if credits_value is not None else "info"},
        {"label": commander_trade_profit_label, "value": _fmt_commander_cr(commander_trade_profit, "-"), "level": "ok" if commander_trade_profit is not None else "info"},
        {"label": "SYSTEM VISITS", "value": f"{int(history_counts.get('system_visits', 0) or 0):,}" if history_available else "-", "level": "ok" if history_available else "info"},
        {"label": "STATION VISITS", "value": f"{int(history_counts.get('station_visits', 0) or 0):,}" if history_available else "-", "level": "ok" if history_available else "info"},
        {"label": "KNOWN SHIPS", "value": f"{int(history_counts.get('ships', 0) or 0):,}" if history_available else "-", "level": "ok" if history_available else "info"},
    ]
    if history_available:
        last_import = _valid_text(commander_history.get("last_import_time"), "-")
        commander_history_note = f"{commander_trade_profit_source} // LAST EVENT {last_import} // ARCHIVE MARGIN {_fmt_commander_cr(history_profit, 'N/A')}"
    else:
        commander_history_note = f"{commander_trade_profit_source} // OPTIONAL EDDISCOVERY HISTORY NOT LOADED"

    commander_record_rows = [
        {"label": "JOURNAL", "value": "LIVE" if s.journal_connected else "WAITING", "level": "ok" if s.journal_connected else "bad"},
        {"label": "STATUS.JSON", "value": "LIVE" if s.status_connected else "WAITING", "level": "ok" if s.status_connected else "bad"},
        {"label": "MARKET DATA", "value": "AVAILABLE" if s.market_connected else "WAITING", "level": "ok" if s.market_connected else "warn"},
        {"label": "CARGO.JSON", "value": "LIVE" if s.cargo_file_connected else "JOURNAL", "level": "ok" if s.cargo_file_connected else "warn"},
        {"label": "HISTORY ARCHIVE", "value": "READY" if history_available else "OPTIONAL", "level": "ok" if history_available else "info"},
        {"label": "SESSION LEDGER", "value": "LIVE", "level": "ok"},
    ]

    cargo_rows = []
    for cargo_item in list(getattr(s, "cargo", []) or []):
        if not isinstance(cargo_item, dict):
            continue
        try:
            qty = max(0, int(cargo_item.get("Count", 0) or 0))
        except Exception:
            qty = 0
        if qty <= 0:
            continue
        name = legacy.pretty_name(cargo_item.get("Name_Localised") or cargo_item.get("Name") or "Cargo")
        try:
            stolen = max(0, int(cargo_item.get("Stolen", 0) or 0))
        except Exception:
            stolen = 0
        cargo_rows.append({
            "label": str(name).upper(),
            "value": f"{qty:,} T" + (f" // {stolen:,} STOLEN" if stolen else ""),
            "level": "warn" if stolen else "ok",
            "quantity": qty,
        })
    cargo_rows.sort(key=lambda row: (-int(row.get("quantity", 0)), str(row.get("label", ""))))
    commander_cargo_rows = cargo_rows[:3]
    try:
        commander_limpets = max(0, int(s.limpet_reserve_count() or 0))
    except Exception:
        commander_limpets = 0
    try:
        commander_stolen = max(0, int(s.stolen_cargo_count() or 0))
    except Exception:
        commander_stolen = 0

    if not hasattr(app, "_qml_commander_session_started"):
        app._qml_commander_session_started = time.strftime("%I:%M %p").lstrip("0")
    session_counts = _commander_event_counts(list(getattr(s, "event_log", []) or []))
    commander_session_rows = [
        {"label": "BRIDGE START", "value": str(getattr(app, "_qml_commander_session_started", "-")), "level": "warn"},
        {"label": "JUMPS", "value": f"{session_counts['jumps']:,}", "level": "info"},
        {"label": "DOCKINGS", "value": f"{session_counts['dockings']:,}", "level": "info"},
        {"label": "TRADE SALES", "value": f"{session_counts['trade_sales']:,}", "level": "ok"},
        {"label": "BOUNTY EVENTS", "value": f"{session_counts['bounties']:,}", "level": "ok"},
        {"label": "AI REQUESTS", "value": f"{int(getattr(app, 'ai_calls', 0) or 0):,}", "level": "info"},
    ]

    return {
        "integrationVersion": INTEGRATION_VERSION,
        "backendVersion": BACKEND_VERSION,
        "connected": True,
        "commander": _valid_text(s.commander),
        "ship": ship_display,
        "shipName": ship_name,
        "shipModel": ship_model,
        "system": _valid_text(s.system),
        "station": station_display,
        "gameState": game_state,
        "bridgeState": bridge_state,
        "bridgeMessage": bridge_message,
        "bridgeLevel": _level_color_name(bridge_level),
        "controlOwner": control_owner,
        "hullPercent": hull_percent,
        "fuelPercent": fuel_percent,
        "shieldState": ("UP" if s.flag("Shields Up") else "DOWN") if elite_live else "UNKNOWN",
        "cargoUsed": ship_cargo_used,
        "cargoCapacity": ship_cargo_capacity,
        "tradeRouteBusy": trade_route_busy,
        "tradeRouteStatus": trade_route_status,
        "tradeRouteRows": trade_route_rows,
        "tradeRouteMaxLs": max_ls,
        "tradeBestBusy": trade_best_busy,
        "tradeBestStatus": trade_best_status,
        "tradeBestRows": trade_best_rows,
        "tradeCommodity": trade_commodity,
        "tradeCommodityOptions": commodity_options,
        "tradeConfiguredCargo": configured_cargo,
        "tradePlannedCargo": trade_planned_cargo,
        "tradeCargoAvailable": ship_cargo_available,
        "tradeLatestBuyUnit": latest_buy_unit,
        "tradeLatestSellUnit": latest_sell_unit,
        "tradeEstimatedProfitCycle": estimated_profit_cycle,
        "tradeBuySystem": trade_loop_buy_system,
        "tradeBuyStation": trade_loop_buy_station,
        "tradeSellSystem": trade_loop_sell_system,
        "tradeSellStation": trade_loop_sell_station,
        "tradeLoopEnabled": trade_loop_enabled,
        "tradeLoopStatus": trade_loop_status,
        "tradeLoopLastAction": trade_loop_last_action,
        "tradeMarketStation": trade_market_station,
        "tradeMarketSystem": trade_market_system,
        "tradeMarketTimestamp": trade_market_timestamp,
        "tradeMarketRows": trade_market_rows,
        "tradeMarketBuy": trade_market_buy,
        "tradeMarketSell": trade_market_sell,
        "tradeMarketStock": trade_market_stock,
        "tradeMarketDemand": trade_market_demand,
        "tradeLedgerRows": trade_ledger_rows,
        "tradeRealizedProfit": trade_realized_profit,
        "tradePowerRank": trade_power_rank,
        "tradePowerMerits": trade_power_merits,
        "tradeLastMerit": trade_last_merit,
        "pips": pips_text,
        "fsdState": fsd_state,
        "gearState": ("DOWN" if s.flag("Landing Gear") else "UP") if elite_live else "UNKNOWN",
        "hardpointsState": ("DEPLOYED" if s.flag("Hardpoints") else "RETRACTED") if elite_live else "UNKNOWN",
        "systemRows": system_rows,
        "eliteTelemetryState": elite_telemetry_state,
        "eliteControlsReady": bool(live_elite_bindings),
        "eliteControlReason": "READY" if live_elite_bindings else "NO ACTIVE ELITE .BINDS PROFILE",
        "recentEvents": _event_rows(list(getattr(s, "event_log", []) or []), limit=5),
        "alertLabel": alert_label,
        "alertValue": alert_value,
        "alertDetail": alert_detail,
        "alertLevel": _level_color_name(alert_level),
        "destination": destination,
        "fsdTarget": target if target not in ("", "-") else destination,
        "routeStatus": route_status,
        "routeJumps": route_jumps if route_jumps is not None else -1,
        "nextStarSystem": next_star_system,
        "nextStarClass": next_star_class,
        "nextStarScoopable": next_star_scoopable,
        "nextStarText": next_star_text,
        "voiceMode": voice_mode,
        "wizardNarrationActive": bool(getattr(app, "_wizard_speaking_visual", False)),
        "pageHelpActive": bool(getattr(app, "_page_help_active", False)),
        "pageHelpPage": int(getattr(app, "_page_help_page", -1) if getattr(app, "_page_help_page", None) is not None else -1),
        "pageHelpStep": int(getattr(app, "_page_help_step", -1) if getattr(app, "_page_help_step", None) is not None else -1),
        "pageHelpLabel": str(getattr(app, "_page_help_label", "-") or "-"),
        "pageHelpCompletedSerial": int(getattr(app, "_page_help_completed_serial", 0) or 0),
        "pageHelpCompletedPage": int(getattr(app, "_page_help_completed_page", -1) if getattr(app, "_page_help_completed_page", None) is not None else -1),
        "uiPageHintSerial": int(getattr(app, "_qml_ui_hint_serial", 0) or 0),
        "uiPageHint": int(getattr(app, "_qml_ui_hint_page", -1) if getattr(app, "_qml_ui_hint_page", None) is not None else -1),
        "uiWorkspaceHint": str(getattr(app, "_qml_ui_hint_workspace", "") or ""),
        "pttStatus": ptt_status,
        "lunaStatus": luna_status,
        "aiCalls": int(getattr(app, "ai_calls", 0) or 0),
        "aiInputTokens": int(getattr(app, "ai_input_tokens", 0) or 0),
        "aiOutputTokens": int(getattr(app, "ai_output_tokens", 0) or 0),
        "aiEstimatedCost": round(estimated_cost, 6),
        "aiModel": str(getattr(legacy, "AI_MODEL", "gpt-5.6-luna")),
        "aiApiConfigured": ai_api_configured,
        "aiApiVerified": ai_api_verified,
        "aiApiVerifyStatus": ai_verify_status,
        "aiApiVerifyDetail": ai_verify_detail,
        "bridgeMode": bridge_mode,
        "setupApiKeyLast4": (ai_key_value[-4:] if ai_key_value else ""),
        "setupPreflightRows": setup_preflight_rows,
        "setupReady": bool(setup_ready),
        "setupLimited": bool(setup_limited),
        "eliteBindingsLive": bool(getattr(app, "_qml_live_elite_bindings", lambda: False)()),
        "eliteBindingsSource": str(getattr(getattr(app, "bindings", None), "source_kind", "not found") or "not found"),
        "setupControlRows": setup_control_rows,
        "setupEliteBindingRows": setup_elite_rows,
        "setupCommanderAddress": str(app._commander_address()),
        "setupAiContext": str(getattr(app, "_qml_user_ai_context", "") or ""),
        "setupAiContextDefault": DEFAULT_AI_CONTEXT[:1000],
        "setupAutoRefuel": bool(app.auto_refuel_var.get()),
        "setupAutoRepair": bool(app.auto_repair_var.get()),
        "setupAutoRearm": bool(app.auto_rearm_var.get()),
        "setupDynamicPips": bool(app.dynamic_pips_var.get()),
        "setupAutoPowerPlant": bool(app.auto_powerplant_var.get()),
        "setupAutoChaff": bool(app.auto_chaff_var.get()),
        "setupAutoChaffProfile": str(app.auto_chaff_profile_var.get() or "MED").upper(),
        "setupAiTradeAuto": bool(app.ai_trade_auto_var.get()),
        "setupAiMissionAuto": bool(app.ai_mission_auto_var.get()),
        "setupAiTravelAuto": bool(app.ai_travel_auto_var.get()),
        "aiCopilotStatus": ai_copilot_status,
        "aiCopilotResponse": ai_copilot_response,
        "aiToolActivity": ai_tool_activity,
        "aiCommsRows": ai_comms_rows,
        "aiToolMode": ai_tool_mode,
        "aiPendingAction": ai_pending_text,
        "aiPendingActionAvailable": bool(isinstance(pending_action, dict)),
        "aiSafetyLevel": ai_safety_level,
        "aiSafetyReason": ai_safety_reason,
        "aiSmartAutoEnabled": ai_smart_auto,
        "aiLaunchRuleEnabled": ai_launch_rule,
        "aiSessionRuleCount": int(ai_session_rule_count),
        "aiTranscriptionCalls": int(ai_transcription_calls),
        "aiTranscriptionFailures": int(ai_transcription_failures),
        "aiTranscriptionSeconds": round(float(ai_transcription_seconds), 1),
        "voiceInputMode": voice_input_mode,
        "voicePttMapping": ptt_mapping,
        "voiceInputDevice": voice_input_device,
        "voiceOutputDevice": audio_output_device,
        "voiceEngineMode": voice_engine_mode,
        "voiceName": voice_name,
        "voiceNameOptions": voice_name_options,
        "voicePitch": voice_pitch,
        "voicePitchOptions": voice_pitch_options,
        "voiceEffect": voice_effect,
        "voiceEffectOptions": voice_effect_options,
        "voiceEffectStrength": int(voice_effect_strength),
        "voiceLevel": voice_level,
        "voiceAttentionMode": voice_attention,
        "voiceVolume": int(voice_volume),
        "voiceSpeed": round(float(voice_speed), 2),
        "voiceMicLevel": round(float(voice_mic_level), 4),
        "voiceInputStatus": voice_input_status,
        "controlCaptureAction": control_capture_action,
        "controllerLastInput": str(getattr(getattr(app, "controller_manager", None), "last_input", "") or ""),
        "controlCaptureStatus": control_capture_status,
        "voiceLastText": voice_last_text,
        "voiceEngineStatus": voice_engine_status,
        "voiceEngineWarming": bool(voice_engine_warming),
        "voiceWarmDurationMs": int(voice_warm_duration_ms),
        "voiceSfxEnabled": sfx_enabled,
        "voiceStartupAudioEnabled": startup_audio_enabled,
        "audioInputDevices": audio_input_devices,
        "audioOutputDevices": audio_output_devices,
        "audioDefaultInput": audio_default_input,
        "audioDefaultOutput": audio_default_output,
        "audioSfxVolume": int(sfx_volume),
        "audioSfxRows": audio_sfx_rows,
        "audioSfxSelectedKey": selected_sfx_key,
        "audioSfxSelectedLabel": str(selected_spec.get("label") or selected_sfx_key).upper(),
        "audioSfxSelectedFile": selected_sfx_file,
        "audioSfxSelectedSource": selected_sfx_source,
        "audioSfxSelectedEnabled": selected_sfx_enabled,
        "audioSfxStatus": audio_sfx_status,
        "audioLastSound": audio_last_sound,
        "navArmed": nav_armed,
        "navStatus": nav_status,
        "navDestinationInput": nav_input,
        "navMassLock": nav_mass_lock,
        "navMassLockLevel": nav_mass_lock_level,
        "navRouteValid": nav_route_valid,
        "navRouteSource": nav_route_source,
        "navRouteFileConnected": nav_route_file_connected,
        "navRouteEntries": nav_route_entries,
        "navFlightPlan": nav_flight_plan,
        "navHistory": _nav_history_rows(list(getattr(app, "_qml_nav_trip_history", []) or []), limit=7),
        "navInSystemTargetVisible": bool(in_system_target.get("visible")),
        "navInSystemTargetName": _valid_text(in_system_target.get("name"), "-"),
        "navInSystemTargetKind": _valid_text(in_system_target.get("kind"), "-"),
        "navInSystemTargetStationType": _valid_text(in_system_target.get("stationType"), ""),
        "navInSystemTargetConfirmedStation": bool(in_system_target.get("confirmedStation")),
        "navHomeSystem": nav_memories.get("home", NAV_MEMORY_DEFAULTS["home"]),
        "navBookmark1System": nav_memories.get("bookmark1", ""),
        "navBookmark2System": nav_memories.get("bookmark2", ""),
        "navMemoryCaptureSystem": nav_memory_capture_system,
        "navMemoryCaptureSource": nav_memory_capture_source,
        "colonizationHasProject": colonization_has_project,
        "colonizationStatus": colonization_status,
        "colonizationSystem": _valid_text(getattr(s, "colonization_current_system", "-"), "-"),
        "colonizationStation": _valid_text(getattr(s, "colonization_current_station", "-"), "-"),
        "colonizationMarketId": "-" if colonization_market_id is None else str(colonization_market_id),
        "colonizationProgressPercent": round(colonization_progress_pct, 2),
        "colonizationLastUpdate": _valid_text(getattr(s, "colonization_last_update", "-"), "-"),
        "colonizationLastEvent": _valid_text(getattr(s, "colonization_last_event", "-"), "-"),
        "colonizationRemainingTotal": int(colonization_remaining_total),
        "colonizationCompleteCount": int(colonization_complete_count),
        "colonizationIncompleteCount": int(colonization_incomplete_count),
        "colonizationRequirementRows": colonization_requirement_rows,
        "colonizationNextCommodity": colonization_next_commodity,
        "colonizationNextRemaining": int(colonization_next_remaining),
        "colonizationNextAboard": int(colonization_next_aboard),
        "colonizationNextLoadTarget": int(colonization_next_load_target),
        "colonizationCommodityLoads": int(colonization_commodity_loads),
        "colonizationProjectLoads": int(colonization_project_loads),
        "colonizationContributionTotal": int(getattr(s, "colonization_contribution_total", 0) or 0),
        "colonizationPaceText": colonization_pace_text,
        "colonizationClaimStatus": _valid_text(getattr(s, "colonization_last_claim_status", "-"), "-"),
        "colonizationClaimSystem": _valid_text(getattr(s, "colonization_last_claim_system", "-"), "-"),
        "colonizationLogRows": colonization_log_rows[:10],
        "colonizationProjectRows": colonization_projects,
        "colonizationCurrentProjectIndex": int(colonization_current_index),
        "colonizationDataSource": "ELITE JOURNAL + SAVED PROJECTS",
        "combatActive": bool(s.combat_active),
        "combatState": "ACTIVE" if s.combat_active else "IDLE",
        "combatStatusRows": combat_status_rows,
        "combatSessionRows": combat_session_rows,
        "combatAlertRows": combat_alert_rows,
        "combatThreatWarning": threat_warning if threat_warning not in ("", "-") else "-",
        "combatScanAlertActive": scan_active,
        "combatScanAlertText": scan_alert_text,
        "combatSupportRows": combat_support_rows,
        "combatTargetRows": combat_target_rows,
        "combatThreatHistory": _nav_history_rows(list(getattr(s, "threat_history", []) or []), limit=4),
        "combatEventHistory": _nav_history_rows(list(getattr(s, "combat_event_history", []) or []), limit=5),
        "combatTargetPresent": target_present,
        "combatTargetName": _valid_text(getattr(s, "target", "-"), "NO TARGET") if target_present else "NO TARGET",
        "combatTargetPilot": _valid_text(getattr(s, "target_pilot", "-")) if target_present else "-",
        "combatTargetShip": _valid_text(getattr(s, "target_ship", "-")) if target_present else "-",
        "combatTargetLegal": target_legal if target_present else "-",
        "combatTargetFaction": _valid_text(getattr(s, "target_faction", "-")) if target_present else "-",
        "combatTargetRank": _valid_text(getattr(s, "target_rank", "-")) if target_present else "-",
        "combatTargetHullPercent": target_hull_pct,
        "combatTargetShieldPercent": target_shield_pct,
        "combatTargetBounty": target_bounty_text if target_present else "-",
        "combatTargetSubsystem": _valid_text(getattr(s, "target_subsystem", "-")) if target_present else "-",
        "combatTargetSubsystemPercent": target_subsystem_pct,
        "combatTargetScanStage": target_scan_stage,
        "combatTacticalAdvisory": combat_advisory,
        "combatUnderAttack": under_attack_recent,
        "combatHudMode": "ANALYSIS" if s.flag("Analysis Mode") else "COMBAT",
        "combatFireGroup": fire_group_text,
        "combatCollectorUpperBound": collector_upper,
        "combatLimpetReserve": limpet_reserve,
        "combatStolenCargo": stolen_aboard,
        "combatCrewWagesTotal": int(getattr(s, "crew_wages_total", 0) or 0),
        "combatCommandStatus": combat_command_status,
        "combatEgressStatus": _valid_text(getattr(app, "egress_status", "-")),
        "combatDynamicPipsEnabled": dynamic_pips_enabled,
        "combatDynamicPipsMode": _valid_text(getattr(app, "dynamic_pip_mode", "OFF"), "OFF"),
        "combatDynamicPipsStatus": _valid_text(getattr(app, "dynamic_pip_status", "-")),
        "combatAutoSubsystemEnabled": auto_subsystem_enabled,
        "combatAutoSubsystemStatus": _valid_text(getattr(app, "auto_powerplant_status", "-")),
        "combatAutoChaffEnabled": auto_chaff_enabled,
        "combatAutoChaffStatus": _valid_text(getattr(app, "auto_chaff_status", "-")),
        "combatResStatus": _valid_text(getattr(app, "res_search_status", "-")),
        "combatResBusy": bool(getattr(app, "res_search_busy", False)),
        "combatResRows": res_rows,
        "combatResNearest": res_nearest,
        "commanderDossierRows": commander_dossier_rows,
        "commanderCareerRows": commander_career_rows,
        "commanderRecordRows": commander_record_rows,
        "commanderCargoRows": commander_cargo_rows,
        "commanderCargoTypeCount": len(cargo_rows),
        "commanderCargoSource": _valid_text(getattr(s, "cargo_source", "-"), "-"),
        "commanderLimpetReserve": commander_limpets,
        "commanderStolenCargo": commander_stolen,
        "commanderSessionRows": commander_session_rows,
        "commanderHistoryAvailable": history_available,
        "commanderHistoryNote": commander_history_note,
        "commanderCreditsSource": credits_source,
        "journalConnected": bool(s.journal_connected),
        "statusConnected": bool(s.status_connected),
    }


class SharedState:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._snapshot: dict[str, Any] = {
            "integrationVersion": INTEGRATION_VERSION,
            "backendVersion": BACKEND_VERSION,
            "connected": False,
            "bridgeState": "INITIALIZING",
            "bridgeMessage": "Starting Bridge systems...",
        }

    def set(self, value: dict[str, Any]) -> None:
        with self._lock:
            self._snapshot = copy.deepcopy(value)

    def get(self) -> dict[str, Any]:
        with self._lock:
            return copy.deepcopy(self._snapshot)


class HeadlessBridgeApp(legacy.BridgeApp):
    """Run .95 unchanged as the engine while suppressing its legacy windows."""

    def __init__(self):
        # v0.30.00 OOBE policy lives in the adapter so the protected .95 engine
        # remains byte-for-byte unchanged. Existing user files always win. Only
        # a genuinely new profile receives release-safe neutral defaults.
        fresh_automation = not legacy.AUTOMATION_CONFIG_FILE.exists()
        fresh_trade = not legacy.TRADE_LOOP_CONFIG_FILE.exists()
        super().__init__()

        # v0.30.08 distributor arbitration. Physical/manual PIP changes and direct
        # voice PIP requests temporarily outrank Dynamic PIPs until a meaningful
        # flight-state transition or explicit Resume Auto Pips request.
        self._qml_dynamic_pips_manual_override = False
        self._qml_dynamic_pips_manual_override_reason = "-"
        self._qml_dynamic_pips_manual_override_token = None
        self._qml_last_observed_pips = None
        self._qml_last_pip_state_token = None

        # v0.30.08 beta diagnostics + target-finder memory. These are tiny bounded
        # in-memory structures; they add no continuous disk I/O.
        self._qml_target_legal_memory = {}
        self._qml_best_target_history = deque(maxlen=24)
        self._qml_hostile_voice_by_sender = {}

        if fresh_trade:
            for var in (
                self.trade_loop_commodity_var, self.trade_loop_cargo_var,
                self.trade_loop_buy_system_var, self.trade_loop_buy_station_var,
                self.trade_loop_sell_system_var, self.trade_loop_sell_station_var,
                self.market_search_commodity_var, self.market_search_volume_var,
                self.loop_search_commodity_var, self.loop_search_cargo_var,
            ):
                var.set("")
            self.trade_loop_status = "Loop disabled. Select or load a trade route to begin."

        if fresh_automation:
            self.dynamic_pips_var.set(False)
            self.dynamic_pips_enabled = False
            self.dynamic_pip_mode = "OFF"
            self.dynamic_pip_status = "Dynamic PIPs are OFF until the pilot enables them."

            # Deliberate public voice baseline: local voice when available, clean
            # fallback otherwise, moderate chatter, and restrained processing.
            self.voice_level_var.set("MED")
            self.voice_engine_mode_var.set("AUTO")
            self.voice_name_var.set("F5")
            self.voice_volume_var.set(50.0)
            self.voice_speed_var.set(1.0)
            self.voice_quality_var.set(8)
            self.voice_pitch_var.set("NORMAL")
            self.voice_effect_var.set("BRIDGE")
            self.voice_effect_strength_var.set(35.0)
            self.voice_attention_mode_var.set("IMPORTANT")
            try:
                self._voice_apply_settings(save=False)
                self._sfx_apply_settings(save=False)
            except Exception:
                pass

    def _drain_controller_events(self):
        # QML owns Elite-overlap warnings. Suppress only the legacy Windows showwarning
        # during this inherited drain; all detection, saving and conflict status remain engine-owned.
        original_showwarning = legacy.messagebox.showwarning
        try:
            legacy.messagebox.showwarning = lambda *args, **kwargs: None
            return super()._drain_controller_events()
        finally:
            legacy.messagebox.showwarning = original_showwarning

    def _apply_display_mode(self, save: bool = False):  # noqa: D401
        try:
            self.withdraw()
        except Exception:
            pass

    def _show_startup_overview(self):
        # QML owns the visible startup/setup experience.
        return

    def _qml_bridge_mode(self):
        host = getattr(self, "_qml_host", None)
        mode = str(getattr(host, "setup_overrides", {}).get("bridge_mode") if host is not None else "").strip().upper()
        if mode in ("CORE", "COPILOT"):
            return mode
        return "COPILOT" if str(os.environ.get("OPENAI_API_KEY") or "").strip() else "CORE"

    def _qml_copilot_enabled(self):
        return self._qml_bridge_mode() == "COPILOT"

    def _qml_api_verified(self):
        key = str(os.environ.get("OPENAI_API_KEY") or "").strip()
        host = getattr(self, "_qml_host", None)
        fp = str(getattr(host, "setup_overrides", {}).get("api_verified_fingerprint") if host is not None else "").strip().lower()
        return bool(key and fp and fp == _api_key_fingerprint(key))

    def _qml_live_elite_bindings(self):
        """Return whether Bridge is reading the pilot's actual live Elite profile.

        The bundled HCS snapshot is useful as a development/reference fallback, but it
        must never make a clean PC look configured. Feature readiness is based only on
        the live Frontier bindings folder.
        """
        source = str(getattr(self.bindings, "source_kind", "") or "").strip()
        path = getattr(self.bindings, "path", None)
        return bool(source == "LIVE Elite bindings" and path)

    def _setup_preflight_rows(self):
        """Mode-aware readiness with one hard gate: a verified Copilot API key.

        Missing Elite bindings, audio devices, PTT, telemetry, controllers, or Bridge
        shortcuts are reported as limited features, never as a reason to trap the pilot
        in first-run setup. Core Bridge can always finish. AI Co-Pilot can finish once
        its OpenAI key is verified; the wizard offers a Core escape if verification fails.
        """
        copilot_mode = self._qml_copilot_enabled()
        ptt = self.controller_bindings.get("push_to_talk")
        ptt_mapped = isinstance(ptt, dict)
        registered = set(getattr(self.bridge_hotkeys, "registered", set()) or set())
        ptt_keyboard_ready = "push_to_talk" in registered
        ptt_ok = ptt_mapped or ptt_keyboard_ready
        ptt_detail = (
            f"{ptt.get('device_name')} • {legacy.BridgeControllerManager.binding_label(ptt)}"
            if ptt_mapped
            else (
                "Keyboard / Stream Deck shortcut ready • Ctrl+Alt+Shift+V"
                if ptt_keyboard_ready
                else "Voice commands stay unavailable until Push-to-Talk is mapped; setup may still finish."
            )
        )

        elite_rows, elite_missing = self._setup_elite_binding_rows()
        live_elite_bindings = self._qml_live_elite_bindings()
        if not live_elite_bindings:
            # Do not count the bundled reference snapshot as the commander's bindings.
            elite_missing = [str(row[0]) for row in elite_rows] or ["Elite bindings profile"]
            elite_detail = "No active Elite .binds profile detected. Elite-control features stay unavailable until one appears."
        elif elite_missing:
            elite_detail = (
                f"{len(elite_rows)-len(elite_missing)}/{len(elite_rows)} controls ready • Missing: "
                + ", ".join(elite_missing[:5])
                + ("…" if len(elite_missing) > 5 else "")
            )
        else:
            elite_detail = f"{len(elite_rows)}/{len(elite_rows)} controls ready from the active Elite profile."

        required_hotkey_ids = [row[0] for row in legacy.BRIDGE_HOTKEY_SPECS if copilot_mode or row[0] != "push_to_talk"]
        hotkey_count = sum(1 for command_id in required_hotkey_ids if command_id in registered)
        hotkey_ok = hotkey_count == len(required_hotkey_ids)
        api_verified = self._qml_api_verified()
        audio_ok = bool(legacy.SOUNDDEVICE_AVAILABLE)
        rows = [
            ("Bridge core", "READY", "Core services are online and saved settings are loaded."),
            (
                "Push-to-Talk",
                ("READY" if ptt_ok else "NEEDS ATTENTION") if copilot_mode else "OFF",
                ptt_detail if copilot_mode else "Core Bridge mode does not use AI Push-to-Talk.",
            ),
            ("Elite keyboard controls", "READY" if live_elite_bindings and not elite_missing else "NEEDS ATTENTION", elite_detail),
            (
                "Microphone",
                "READY" if audio_ok else "NEEDS ATTENTION",
                str(self.voice_input_device_var.get() or "System Default")
                if audio_ok
                else "Microphone support is unavailable. Voice input will stay disabled until an input device is available.",
            ),
            (
                "Speakers / output",
                "READY" if audio_ok else "NEEDS ATTENTION",
                str(self.audio_output_device_var.get() or "System Default")
                if audio_ok
                else "Audio output is unavailable. Visual Bridge controls remain usable.",
            ),
            (
                "Bridge shortcuts",
                "READY" if hotkey_ok else "NEEDS ATTENTION",
                f"{hotkey_count}/{len(required_hotkey_ids)} shortcuts ready. Missing shortcuts disable only their related controls.",
            ),
            ("Elite game data", "READY" if self.state_data.journal_connected and self.state_data.status_connected else "WAITING", f"Journal {'ready' if self.state_data.journal_connected else 'waiting'} • live ship status {'ready' if self.state_data.status_connected else 'waiting'}"),
            (
                "AI Co-Pilot / OpenAI",
                ("READY" if api_verified else "MISSING") if copilot_mode else "OFF",
                ("Verified API connection ready." if api_verified else "AI Co-Pilot requires a verified OpenAI API key before this mode can be enabled.")
                if copilot_mode
                else "Core Bridge mode: AI Co-Pilot is disabled.",
            ),
        ]
        # The API key is the only first-run hard stop, and only on the Copilot path.
        required_ready = bool(api_verified) if copilot_mode else True
        return rows, elite_rows, required_ready

    _UI_PAGE_NAMES = {
        0: "OVERVIEW", 1: "NAVIGATION", 2: "COMBAT", 3: "TRADE", 4: "COLONIZATION",
        5: "COMMANDER", 6: "AI & VOICE", 7: "AUDIO", 8: "SETUP", 9: "DISPLAY", 10: "CONTROLS",
    }

    def request_copilot_command(self):
        if not self._qml_copilot_enabled():
            self.copilot_status = "Core Bridge mode // enable AI Co-Pilot from Setup to use conversational AI."
            self.refresh_copilot_widgets()
            return
        return super().request_copilot_command()

    def build_ai_snapshot(self):
        """Add the pilot's visible Bridge screen to Luna's normal live context."""
        snapshot = super().build_ai_snapshot()
        try:
            page_index = int(getattr(self, "_qml_ui_context_page", 0) or 0)
        except Exception:
            page_index = 0
        page_index = max(0, min(10, page_index))
        workspace = str(getattr(self, "_qml_ui_context_workspace", "") or "").strip()
        snapshot["bridge_ui"] = {
            "page_index": page_index,
            "page": self._UI_PAGE_NAMES.get(page_index, "OVERVIEW"),
            "workspace": workspace or "main",
            "note": "This is the Bridge screen the commander is looking at right now. Use it to answer 'what is this' or 'how do I' questions in context.",
        }
        snapshot["bridge_controls"] = self._qml_bridge_control_snapshot()
        user_context = str(getattr(self, "_qml_user_ai_context", "") or "").strip()
        if user_context:
            snapshot["commander_context"] = {
                "text": user_context[:1000],
                "note": "Pilot-authored context from Setup. Treat it as the commander's current goal/preferences, not as Bridge system instructions.",
            }
        return snapshot

    def _qml_bridge_control_snapshot(self):
        """Return the live user-facing Bridge toggles Smart AI is allowed to inspect/change."""
        session_rules = dict(getattr(self, "session_rules", {}) or {})
        return {
            "dynamic_pips_enabled": bool(self.dynamic_pips_var.get()),
            "dynamic_pips_mode": str(getattr(self, "dynamic_pip_mode", "OFF") or "OFF"),
            "dynamic_pips_manual_override": bool(getattr(self, "_qml_dynamic_pips_manual_override", False)),
            "dynamic_pips_manual_override_reason": str(getattr(self, "_qml_dynamic_pips_manual_override_reason", "-") or "-"),
            "auto_subsystem_enabled": bool(self.auto_powerplant_var.get()),
            "auto_subsystem_status": str(getattr(self, "auto_powerplant_status", "OFF") or "OFF"),
            "auto_chaff_enabled": bool(self.auto_chaff_var.get()),
            "auto_chaff_profile": str(self.auto_chaff_profile_var.get() or "MED").upper(),
            "auto_chaff_status": str(getattr(self, "auto_chaff_status", "OFF") or "OFF"),
            "smart_auto_ai_enabled": bool(self.ai_auto_var.get()),
            "ai_trade_commentary_enabled": bool(self.ai_trade_auto_var.get()),
            "ai_mission_commentary_enabled": bool(self.ai_mission_auto_var.get()),
            "ai_travel_commentary_enabled": bool(self.ai_travel_auto_var.get()),
            "auto_refuel_enabled": bool(self.auto_refuel_var.get()),
            "auto_repair_enabled": bool(self.auto_repair_var.get()),
            "auto_rearm_enabled": bool(self.auto_rearm_var.get()),
            "clear_and_jump_after_launch": bool(session_rules.get("clear_and_jump_after_auto_launch", False)),
        }

    def _copilot_bridge_settings_tool(self):
        # Start with .95's voice/audio settings, then add every operational toggle
        # surfaced by the QML Bridge. This keeps status questions truthful even
        # when the control is not represented in Elite telemetry.
        result = dict(super()._copilot_bridge_settings_tool())
        persistent = dict(result.get("persistent") or {})
        controls = self._qml_bridge_control_snapshot()
        session_value = bool(controls.pop("clear_and_jump_after_launch", False))
        pip_override = bool(controls.pop("dynamic_pips_manual_override", False))
        pip_override_reason = str(controls.pop("dynamic_pips_manual_override_reason", "-") or "-")
        persistent.update(controls)
        result["persistent"] = persistent
        session_rules = dict(result.get("session_rules") or {})
        session_rules["clear_and_jump_after_auto_launch"] = session_value
        session_rules["dynamic_pips_manual_override"] = pip_override
        session_rules["dynamic_pips_manual_override_reason"] = pip_override_reason
        result["session_rules"] = session_rules
        result["note"] = (
            "Bridge settings are live values. Auto Subsystem is the user-facing name for automatic Power Plant targeting. "
            "Persistent settings survive restart; clear-and-jump-after-launch and the Dynamic Pips manual override are session-only."
        )
        return result

    def _copilot_set_bridge_setting_tool(self, args):
        setting = str((args or {}).get("setting") or "").strip()
        value = (args or {}).get("value")
        alias = {
            "auto_powerplant_enabled": "auto_subsystem_enabled",
            "auto_power_plant_enabled": "auto_subsystem_enabled",
            "auto_chaff": "auto_chaff_enabled",
            "dynamic_pips": "dynamic_pips_enabled",
            "smart_auto_ai": "smart_auto_ai_enabled",
        }
        setting = alias.get(setting, setting)

        # Existing .95-owned reversible settings keep using the proven implementation.
        legacy_settings = {
            "dynamic_pips_enabled", "voice_level", "voice_volume", "voice_speed",
            "sfx_enabled", "sfx_volume", "startup_sound_enabled",
            "voice_attention_mode", "voice_input_mode",
        }
        if setting == "voice_attention_mode":
            target = str(value or "IMPORTANT").strip().upper()
            aliases = {
                "LOW": "OFF", "QUIET": "OFF",
                "MED": "IMPORTANT", "MEDIUM": "IMPORTANT", "BALANCED": "IMPORTANT",
                "HIGH": "MOST", "TALKATIVE": "MOST",
            }
            target = aliases.get(target, target)
            if target not in self._PUBLIC_TALK_PROFILES:
                return {"ok": False, "setting": setting, "error": "voice_attention_mode must be Quiet/Low, Balanced/Medium, or Talkative/High."}
            attention, level, label = self._public_talk_profile_apply(target)
            return {
                "ok": True, "setting": setting, "value": attention, "voice_level": level,
                "scope": "persistent", "message": f"Talk level {label}.",
            }
        if setting in legacy_settings:
            return super()._copilot_set_bridge_setting_tool({"setting": setting, "value": value})

        supported = {
            "auto_subsystem_enabled", "auto_chaff_enabled", "auto_chaff_profile",
            "smart_auto_ai_enabled", "ai_trade_commentary_enabled",
            "ai_mission_commentary_enabled", "ai_travel_commentary_enabled",
            "auto_refuel_enabled", "auto_repair_enabled", "auto_rearm_enabled",
            "clear_and_jump_after_launch",
        }
        if setting not in supported:
            return {"ok": False, "setting": setting, "error": f"Unsupported Bridge setting: {setting}"}

        done = threading.Event()
        box = {}

        def apply_setting():
            try:
                host = getattr(self, "_qml_host", None)
                if setting == "auto_subsystem_enabled":
                    enabled = self._copilot_bool(value)
                    self.auto_powerplant_var.set(enabled)
                    self._auto_powerplant_toggle_changed()
                    if host is not None:
                        host.setup_overrides["auto_powerplant"] = bool(enabled)
                        host._save_setup_overrides()
                    applied = bool(self.auto_powerplant_var.get())
                elif setting == "auto_chaff_enabled":
                    enabled = self._copilot_bool(value)
                    self.auto_chaff_var.set(enabled)
                    self._auto_chaff_toggle_changed()
                    if host is not None:
                        host.setup_overrides["auto_chaff"] = bool(enabled)
                        host._save_setup_overrides()
                    applied = bool(self.auto_chaff_var.get())
                elif setting == "auto_chaff_profile":
                    profile = str(value or "").strip().upper()
                    if profile not in {"LOW", "MED", "HIGH"}:
                        raise ValueError("auto_chaff_profile must be LOW, MED, or HIGH.")
                    self.auto_chaff_profile_var.set(profile)
                    self._auto_chaff_profile_changed()
                    if host is not None:
                        host.setup_overrides["auto_chaff_profile"] = profile
                        host._save_setup_overrides()
                    applied = profile
                elif setting == "smart_auto_ai_enabled":
                    enabled = self._copilot_bool(value)
                    self.ai_auto_var.set(enabled)
                    if host is not None:
                        host.setup_overrides["ai_smart_auto"] = bool(enabled)
                        host._save_setup_overrides()
                    self.refresh_preferences_widgets()
                    applied = bool(self.ai_auto_var.get())
                elif setting in {
                    "ai_trade_commentary_enabled", "ai_mission_commentary_enabled", "ai_travel_commentary_enabled"
                }:
                    enabled = self._copilot_bool(value)
                    mapping = {
                        "ai_trade_commentary_enabled": (self.ai_trade_auto_var, "ai_trade_auto"),
                        "ai_mission_commentary_enabled": (self.ai_mission_auto_var, "ai_mission_auto"),
                        "ai_travel_commentary_enabled": (self.ai_travel_auto_var, "ai_travel_auto"),
                    }
                    var, override_key = mapping[setting]
                    var.set(enabled)
                    if host is not None:
                        host.setup_overrides[override_key] = bool(enabled)
                        host._save_setup_overrides()
                    self.refresh_preferences_widgets()
                    applied = bool(var.get())
                elif setting in {"auto_refuel_enabled", "auto_repair_enabled", "auto_rearm_enabled"}:
                    enabled = self._copilot_bool(value)
                    mapping = {
                        "auto_refuel_enabled": self.auto_refuel_var,
                        "auto_repair_enabled": self.auto_repair_var,
                        "auto_rearm_enabled": self.auto_rearm_var,
                    }
                    var = mapping[setting]
                    var.set(enabled)
                    self._automation_toggle_changed()
                    applied = bool(var.get())
                elif setting == "clear_and_jump_after_launch":
                    enabled = self._copilot_bool(value)
                    result = self._copilot_set_session_rule_tool({
                        "rule": "clear_and_jump_after_auto_launch", "enabled": enabled
                    })
                    if not result.get("ok"):
                        raise RuntimeError(result.get("error") or "Session rule update failed.")
                    applied = bool(result.get("enabled"))
                else:
                    raise ValueError("Unsupported setting.")

                box["result"] = {
                    "ok": True,
                    "setting": setting,
                    "value": applied,
                    "scope": "session_only" if setting == "clear_and_jump_after_launch" else "persistent",
                    "message": f"{setting} updated.",
                    "bridge_controls": self._qml_bridge_control_snapshot(),
                }
            except Exception as exc:
                box["result"] = {"ok": False, "setting": setting, "error": str(exc)}
            finally:
                done.set()

        self.after(0, apply_setting)
        if not done.wait(3.0):
            return {"ok": False, "setting": setting, "error": "Bridge UI did not apply the setting in time."}
        return box.get("result") or {"ok": False, "setting": setting, "error": "No setting result returned."}

    # Contextual page help + AI UI director. QML remains the visible UI, while
    # this adapter owns narration sequencing and one-shot navigation hints.
    _PAGE_HELP = {
        # Built-in help is a Bridge feature, not an AI feature. Keep the narration
        # product-neutral so it works with AI disabled and with any selected voice.
        # The ? button is intentionally beginner-friendly; PTT can answer deeper
        # questions when optional AI is configured.
        0: [
            ("BRIDGE MODULES", "These are the main working areas of the Bridge. The flashing yellow highlight shows what is being explained. Overview is your home screen, and the other buttons take you to combat, trade, travel, colonization, and setup."),
            ("OVERVIEW", "Overview is your home screen. It shows your ship, current destination, Bridge systems, alerts, and other important information at a glance. Commander Records are also tucked inside Overview, so your cargo and session history stay close to home."),
            ("COMBAT", "Use Combat when you are fighting or looking for a place to fight. It has target tools, fighter controls, warnings, and the Resource Extraction Site Finder."),
            ("TRADE", "Use Trade when you want to make money moving cargo. The Bridge can show strong trades, routes for one commodity, or help manage a trade loop."),
            ("NAVIGATION", "Navigation is mainly your travel monitor. Once a route is plotted, it follows your next jumps, fuel stars, saved locations, docking, and launch tools while you fly."),
            ("COLONIZATION", "Use Colonization when you are helping build a system project. It tracks what is still needed and can send shopping work over to Trade."),
            ("SETUP", "Setup holds configuration in one place. System, Controls, AI and Voice, Audio, and Display are separate sections, along with guided setup and orientation controls."),
        ],
        1: [
            ("YOUR ROUTE", "Navigation is mostly here to follow the trip you are already flying. When Elite has a route plotted, the Bridge keeps the next jumps easy to read and points out useful fuel stars."),
            ("DESTINATION AREA", "If you already know a system name, this area can send that destination to Elite. For guided activities such as trading or combat, the Bridge can bring you here after the destination is chosen."),
            ("TRAVEL SHORTCUTS", "These are quick travel buttons for Home, bookmarks, docking, launch, and canceling a travel action while you are on the move."),
        ],
        2: [
            ("COMBAT BUTTONS", "These are quick fighting controls. Find Best Target does a fast hull-type sweep without waiting for a full scan; the other controls handle targets, fighters, wing commands, and getting out of danger."),
            ("TACTICAL OR RES FINDER", "Tactical View is for the fight you are in now. The Resource Extraction Site Finder helps you find nearby mining areas where combat is common, making them useful places to hunt ships and earn bounties."),
            ("COMBAT INFORMATION", "This side keeps the important things together, such as bounty progress, scans, risky cargo, crew costs, and warnings."),
        ],
        3: [
            ("CHOOSE YOUR TRADE TOOL", "Best Trade looks for strong money-making options. Route Finder finds a buy and sell route for one commodity. Trade Loop is where you manage, plot, and run the route you selected."),
            ("RUN THE SEARCH", "Once Best Trade is selected, press the Find Best Trade button to start the market scan. The filters above it control how far the Bridge is willing to look and what kind of routes it prefers."),
            ("TRADE RESULTS", "The routes the Bridge finds show up here after the scan finishes. Pick one, and the Bridge can load it so you can start plotting and flying the trade."),
        ],
        4: [
            ("PROJECT", "This shows the colonization project you are working on and how far along it is."),
            ("WHAT IS STILL NEEDED", "This list shows the materials the project still needs. Pick one when you want help finding the next load."),
            ("NEXT DELIVERY", "This turns the item you picked into your next job and can send the shopping work over to Trade."),
        ],
        5: [
            ("YOUR RECORD", "Commander Records lives inside Overview. This is a simple summary of your commander and current ship using information the Bridge has seen from Elite."),
            ("CARGO AND SESSION", "This area shows what you are carrying and useful things that have happened during this play session."),
            ("SAVE OR REFRESH", "Use these buttons when you want fresh information, a saved copy, or something you can send for support."),
        ],
        6: [
            ("AI AND VOICE STATUS", "AI and Voice contains the Bridge voice, personality, optional AI behavior, and the mission context you want the AI to keep in mind."),
            ("VOICE AND PERSONALITY", "Use these controls to change the Bridge voice, how talkative it is, and how optional AI assistance behaves."),
            ("MISSION CONTEXT", "Mission Context is optional. Put your current goal here when you want AI answers to account for what you are doing. Push to Talk mapping itself now lives under Controls."),
        ],
        7: [
            ("MICROPHONE AND SPEAKERS", "Audio is a Setup section. Choose which microphone the Bridge listens to and which speakers play the Bridge voice."),
            ("BRIDGE SOUNDS", "You can test, replace, turn off, or restore the sounds the Bridge uses for buttons and alerts."),
            ("VOLUME", "Use the remaining controls to balance the Bridge voice and sound effects so neither gets in the way of the game."),
        ],
        8: [
            ("QUICK CHECK", "System is the health and maintenance section. Use it to check Bridge readiness, Elite connections, diagnostics, and the guided setup tools."),
            ("GENERAL SETTINGS", "General Bridge preferences stay here. Input mappings, AI mission context, audio routing, and display controls each have their own dedicated section."),
            ("WELCOME SETUP", "Guided setup and the cockpit orientation can be reopened here later if you want to repeat onboarding."),
        ],
        9: [
            ("ACTIVE DISPLAY", "Display shows which monitor the Bridge is using, its resolution, and the current window mode."),
            ("DISPLAY CONTROLS", "Use Next Monitor to move the Bridge, Maximize to fit the active display, Fullscreen to toggle window mode, or Reset Display to return to the primary monitor."),
            ("AUTOMATIC SCALE", "The cockpit interface scales automatically from the current window using the twenty five sixty by fourteen forty design grid, so resolution changes do not require manual UI sizing."),
        ],
        10: [
            ("PUSH TO TALK", "Controls shows Push to Talk status, its keyboard fallback, and input tests. HOTAS or gamepad mapping is reserved for PTT."),
            ("BRIDGE COMMAND REFERENCE", "This read-only list shows Bridge-owned commands and their fixed keyboard or Stream Deck shortcuts."),
            ("ELITE BINDINGS", "The Bridge reads the active Elite bindings profile here and flags missing required controls. It does not rewrite Elite's control file."),
        ],
    }

    def _demo_transcript_path(self):
        return legacy.BRIDGE_DATA_DIR / "demo_narration_transcript.log"

    def _demo_transcript_reset(self):
        try:
            path = self._demo_transcript_path()
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                "ELITE AI BRIDGE // LIVE DEMO NARRATION LOG\n"
                + f"STARTED // {time.strftime('%Y-%m-%d %H:%M:%S')}\n"
                + "=" * 72 + "\n",
                encoding="utf-8",
            )
        except Exception:
            pass

    def _demo_transcript_append(self, phase, label, text):
        try:
            path = self._demo_transcript_path()
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.exists():
                self._demo_transcript_reset()
            line = f"{time.strftime('%H:%M:%S')} // {str(phase).upper()} // {str(label).upper()} // {str(text).strip()}\n"
            with path.open("a", encoding="utf-8") as fh:
                fh.write(line)
        except Exception:
            pass

    def _page_help_voice_pending(self):
        try:
            status = str(getattr(self.voice_engine, "status", "") or "").strip().upper()
            busy = bool(getattr(self.voice_engine, "_qml_speech_active", False)) or status.startswith(("LOADING", "SYNTHESIZING", "SPEAKING", "WARMING"))
            return busy or int(self.voice_engine.queue.qsize()) > 0
        except Exception:
            return False

    def _page_help_start(self, page, start_step=0, end_step=None):
        try:
            page = max(0, min(10, int(page)))
        except Exception:
            page = 0
        rows = self._PAGE_HELP.get(page) or []
        if not rows:
            return
        try:
            start_step = max(0, min(len(rows) - 1, int(start_step)))
        except Exception:
            start_step = 0
        if end_step is None:
            end_step = len(rows) - 1
        try:
            end_step = max(start_step, min(len(rows) - 1, int(end_step)))
        except Exception:
            end_step = len(rows) - 1
        self._page_help_serial = int(getattr(self, "_page_help_serial", 0) or 0) + 1
        serial = self._page_help_serial
        self._page_help_active = True
        self._page_help_page = page
        self._page_help_step = start_step
        self._page_help_end_step = end_step
        self._page_help_label = rows[start_step][0]
        self._native_set_status(f"Page help started // {self._page_help_label}")
        self.after(40, lambda token=serial, step=start_step: self._page_help_speak_step(token, step))

    def _page_help_stop(self):
        global _WIZARD_VOICE_INTERRUPT
        self._page_help_serial = int(getattr(self, "_page_help_serial", 0) or 0) + 1
        self._page_help_active = False
        self._page_help_step = -1
        self._page_help_end_step = -1
        self._page_help_label = "-"

        # Page help owns the voice bus while it is speaking. Stop that stream cold.
        # Existing queued speech holds the old Event object, so setting it cancels
        # the active Supertonic/PCM stream. Immediately replace the global event
        # with a fresh clear Event so later normal Bridge speech is not poisoned.
        try:
            active_cancel = _WIZARD_VOICE_INTERRUPT
            active_cancel.set()
            _WIZARD_VOICE_INTERRUPT = threading.Event()
        except Exception:
            pass
        try:
            if not legacy.SOUNDDEVICE_AVAILABLE and os.name == "nt":
                winsound.PlaySound(None, 0)
        except Exception:
            pass
        try:
            self.voice_engine._stop_windows_process()
        except Exception:
            pass
        self._native_set_status("Page help stopped // speech interrupted.")

    def _page_help_force_voice_release(self):
        """Release a stale voice bus without cancelling the active help sequence."""
        global _WIZARD_VOICE_INTERRUPT
        try:
            active_cancel = _WIZARD_VOICE_INTERRUPT
            active_cancel.set()
            _WIZARD_VOICE_INTERRUPT = threading.Event()
        except Exception:
            pass
        try:
            self.voice_engine._stop_windows_process()
        except Exception:
            pass
        try:
            if not legacy.SOUNDDEVICE_AVAILABLE and os.name == "nt":
                winsound.PlaySound(None, 0)
        except Exception:
            pass

    def _page_help_speak_step(self, serial, step, attempt=0):
        if serial != int(getattr(self, "_page_help_serial", -1)) or not bool(getattr(self, "_page_help_active", False)):
            return
        page = int(getattr(self, "_page_help_page", 0) or 0)
        rows = self._PAGE_HELP.get(page) or []
        end_step = int(getattr(self, "_page_help_end_step", len(rows) - 1) or 0)
        if step >= len(rows) or step > end_step:
            completed_page = int(getattr(self, "_page_help_page", -1))
            self._page_help_active = False
            self._page_help_step = -1
            self._page_help_label = "-"
            # Signal completion for both full tours and focused segments. The QML
            # first-orientation state machine decides when the entire onboarding tour
            # is complete; focused AI help outside that tour is unaffected.
            self._page_help_completed_serial = int(getattr(self, "_page_help_completed_serial", 0) or 0) + 1
            self._page_help_completed_page = completed_page
            self._native_set_status("Page help complete.")
            return
        # Never talk over an existing AI/voice response. Wait for the voice bus to clear.
        if self._page_help_voice_pending():
            if attempt == 120:
                self._native_set_status("Page help is waiting for the current voice response // orientation will continue automatically.")
            if attempt >= 250:
                # A stale TTS/process state must never strand the locked first-run
                # orientation. Release the old stream, then retry this same step.
                self._native_set_status("Page help voice watchdog // clearing a stalled stream and retrying.")
                self._page_help_force_voice_release()
                self.after(350, lambda: self._page_help_speak_step(serial, step, 0))
                return
            self.after(100, lambda: self._page_help_speak_step(serial, step, attempt + 1))
            return
        label, text = rows[step]
        self._page_help_step = step
        self._page_help_label = label
        self.voice_last_announcement = text
        self.voice_last_kind = "PAGE HELP"
        self.voice_history.append(f"{time.strftime('%H:%M:%S')}  PAGE HELP | {label} | {text}")
        self._demo_transcript_append(f"PAGE {page}", label, text)
        try:
            queued = bool(self.voice_engine.say(text, speed_scale=0.98))
        except Exception:
            queued = False
        self.refresh_preferences_widgets()
        if not queued:
            self.after(350, lambda: self._page_help_speak_step(serial, step + 1))
            return
        self.after(120, lambda: self._page_help_wait_for_step(serial, step, False, 0))

    def _page_help_wait_for_step(self, serial, step, seen_busy=False, quiet_checks=0):
        if serial != int(getattr(self, "_page_help_serial", -1)) or not bool(getattr(self, "_page_help_active", False)):
            return
        busy = self._page_help_voice_pending()
        if busy:
            self.after(100, lambda: self._page_help_wait_for_step(serial, step, True, 0))
            return
        # Give synthesis a moment to leave the queue before deciding a segment is done.
        if not seen_busy and quiet_checks < 15:
            self.after(100, lambda: self._page_help_wait_for_step(serial, step, False, quiet_checks + 1))
            return
        if quiet_checks < 3:
            self.after(90, lambda: self._page_help_wait_for_step(serial, step, seen_busy, quiet_checks + 1))
            return
        self.after(180, lambda: self._page_help_speak_step(serial, step + 1))

    def _focused_help_step(self, page, workspace):
        """Pick the single saved ?-tour segment that best matches an AI how-to request."""
        workspace = str(workspace or "").strip().lower()
        focused = {
            (1, "route"): 1,
            (1, "shortcuts"): 2,
            (2, "res_finder"): 1,
            (2, "tactical"): 0,
            (3, "best_trade"): 1,
            (3, "route_finder"): 1,
            (3, "loop_setup"): 1,
            (3, "trade_loop"): 1,
            (4, "requirements"): 1,
            (5, "records"): 0,
            (6, "main"): 1,
            (7, "main"): 0,
            (8, "settings"): 1,
            (9, "main"): 1,
            (10, "main"): 0,
            (10, "ptt"): 0,
            (10, "bindings"): 2,
        }
        return focused.get((int(page), workspace), None)

    def _qml_set_ui_hint(self, page, workspace=""):
        """Publish one navigation hint. QML consumes each serial only once."""
        try:
            page = max(0, min(10, int(page)))
        except Exception:
            return
        self._qml_ui_hint_serial = int(getattr(self, "_qml_ui_hint_serial", 0) or 0) + 1
        self._qml_ui_hint_page = page
        self._qml_ui_hint_workspace = str(workspace or "").strip().lower()

    def _copilot_tools(self):
        tools = list(super()._copilot_tools())
        tools.append({
            "type": "function",
            "name": "search_res_sites",
            "description": (
                "Search for nearby High RES or Hazardous RES, meaning Resource Extraction Site, combat areas. Use this when the commander asks "
                "to find a High RES, Haz RES, resource extraction site, or nearby combat hunting ground. "
                "The Bridge will automatically open Combat > RES Finder while the search runs."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": ["HIGH", "HAZ"], "description": "RES type to search for."},
                    "radius_ly": {"type": "number", "minimum": 1, "maximum": 250, "description": "Search radius in light years. Default keeps the current Bridge value."},
                    "max_ls": {"type": "number", "minimum": 100, "maximum": 500000, "description": "Maximum RES distance from arrival star. Default 10000."},
                },
                "required": ["type"],
                "additionalProperties": False,
            },
            "strict": False,
        })
        tools.append({
            "type": "function",
            "name": "show_bridge_workspace",
            "description": (
                "Open the Bridge page that best answers a how-to or where-is question. Use this when the commander asks how to use a Bridge feature. "
                "For beginner questions, set guide=true. Bridge will open the correct page and then play only the saved ?-help segment that matches that workspace, with the same highlight box. "
                "Use TRADE/best_trade when the commander asks for the best or most profitable trade without naming a commodity. Use TRADE/route_finder when they want a route for one commodity. "
                "Keep your own spoken reply brief when guide=true because the saved beginner explanation will speak immediately afterward."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "page": {"type": "string", "enum": ["OVERVIEW", "LIVE", "NAVIGATION", "COMBAT", "TRADE", "COLONIZATION", "COMMANDER", "AI", "AUDIO", "SETUP", "DISPLAY", "CONTROLS"]},
                    "workspace": {"type": "string", "description": "Optional subview such as tactical, res_finder, best_trade, route_finder, trade_loop, or main."},
                    "guide": {"type": "boolean", "description": "Start the beginner page-help walkthrough after opening the destination."},
                },
                "required": ["page"],
                "additionalProperties": False,
            },
            "strict": False,
        })
        tools.append({
            "type": "function",
            "name": "set_cockpit_control",
            "description": (
                "Set one safe Elite cockpit state using the commander's active Elite keyboard binding and verify the result from Status.json. "
                "Use this for explicit requests to turn Night Vision or lights on/off, raise/lower landing gear, deploy/retract cargo scoop or hardpoints, "
                "turn Flight Assist or Silent Running on/off, or switch Combat/Analysis HUD mode. The action is state-aware, so asking for a state that is already active does not toggle it back."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "control": {
                        "type": "string",
                        "enum": ["night_vision", "ship_lights", "landing_gear", "cargo_scoop", "hardpoints", "flight_assist", "silent_running", "hud_mode"]
                    },
                    "state": {
                        "type": "string",
                        "enum": ["on", "off", "up", "down", "deployed", "retracted", "combat", "analysis"]
                    }
                },
                "required": ["control", "state"],
                "additionalProperties": False
            },
            "strict": False,
        })
        return tools

    def _copilot_search_res_sites_tool(self, args):
        kind = str(args.get("type") or "HIGH").strip().upper()
        if kind not in {"HIGH", "HAZ"}:
            kind = "HIGH"
        self._qml_set_ui_hint(2, "res_finder")
        started = threading.Event()
        box = {}

        def begin():
            try:
                self.res_search_high_var.set(kind == "HIGH")
                self.res_search_haz_var.set(kind == "HAZ")
                if args.get("radius_ly") is not None:
                    self.res_search_radius_var.set(f"{max(1.0, min(250.0, float(args.get('radius_ly')))):g}")
                max_ls = args.get("max_ls", 10000)
                self.res_search_max_ls_var.set(f"{max(100.0, min(500000.0, float(max_ls))):g}")
                self.find_nearby_res()
                box["started"] = bool(getattr(self, "res_search_busy", False))
                box["status"] = str(getattr(self, "res_search_status", "-") or "-")
            except Exception as exc:
                box["error"] = str(exc)
            finally:
                started.set()

        self.after(0, begin)
        if not started.wait(3.0):
            return {"ok": False, "type": kind, "error": "RES Finder did not start in time."}
        if box.get("error"):
            return {"ok": False, "type": kind, "error": box["error"]}
        if not box.get("started"):
            return {"ok": False, "type": kind, "status": box.get("status", "RES search did not start.")}

        deadline = time.monotonic() + 40.0
        while bool(getattr(self, "res_search_busy", False)) and time.monotonic() < deadline:
            time.sleep(0.20)
        if bool(getattr(self, "res_search_busy", False)):
            return {"ok": True, "type": kind, "status": "RES search is still running; results will appear in Combat > RES Finder.", "pending": True}
        rows = []
        for raw in list(getattr(self, "res_search_results", []) or [])[:10]:
            rows.append({
                "type": raw.get("type"), "system": raw.get("system"), "body": raw.get("body"),
                "distance_ly": raw.get("distance_ly"), "res_ls": raw.get("res_ls"),
                "support_quality": raw.get("support_quality"), "support_station": raw.get("support_station"),
            })
        return {
            "ok": True,
            "type": kind,
            "status": str(getattr(self, "res_search_status", "-") or "-"),
            "count": len(rows),
            "results": rows,
        }

    @staticmethod
    def _qml_cockpit_control_specs():
        return {
            "night_vision": {
                "label": "Night vision", "action": "NightVisionToggle", "flag": "Night Vision",
                "states": {"on": True, "off": False},
            },
            "ship_lights": {
                "label": "Ship lights", "action": "ShipSpotLightToggle", "flag": "Lights",
                "states": {"on": True, "off": False},
            },
            "landing_gear": {
                "label": "Landing gear", "action": "LandingGearToggle", "flag": "Landing Gear",
                "states": {"down": True, "up": False},
            },
            "cargo_scoop": {
                "label": "Cargo scoop", "action": "ToggleCargoScoop", "flag": "Cargo Scoop",
                "states": {"deployed": True, "retracted": False},
            },
            "hardpoints": {
                "label": "Hardpoints", "action": "DeployHardpointToggle", "flag": "Hardpoints",
                "states": {"deployed": True, "retracted": False},
            },
            "flight_assist": {
                "label": "Flight assist", "action": "ToggleFlightAssist", "flag": "Flight Assist Off",
                "states": {"on": False, "off": True},
            },
            "silent_running": {
                "label": "Silent running", "action": "SilentRunningToggle", "flag": "Silent Running",
                "states": {"on": True, "off": False},
            },
            "hud_mode": {
                "label": "HUD mode", "action": "PlayerHUDModeToggle", "flag": "Analysis Mode",
                "states": {"analysis": True, "combat": False},
            },
        }

    def _qml_cockpit_control_state(self, spec):
        return bool(self.state_data.flag(spec["flag"]))

    def _qml_cockpit_control_phrase(self, control, state):
        phrases = {
            ("night_vision", "on"): "Night vision on.",
            ("night_vision", "off"): "Night vision off.",
            ("ship_lights", "on"): "Ship lights on.",
            ("ship_lights", "off"): "Ship lights off.",
            ("landing_gear", "down"): "Landing gear down.",
            ("landing_gear", "up"): "Landing gear up.",
            ("cargo_scoop", "deployed"): "Cargo scoop deployed.",
            ("cargo_scoop", "retracted"): "Cargo scoop retracted.",
            ("hardpoints", "deployed"): "Hardpoints deployed.",
            ("hardpoints", "retracted"): "Hardpoints retracted.",
            ("flight_assist", "on"): "Flight assist on.",
            ("flight_assist", "off"): "Flight assist off.",
            ("silent_running", "on"): "Silent running on.",
            ("silent_running", "off"): "Silent running off.",
            ("hud_mode", "combat"): "Combat mode active.",
            ("hud_mode", "analysis"): "Analysis mode active.",
        }
        return phrases.get((control, state), "Cockpit control confirmed.")

    def _copilot_set_cockpit_control_tool(self, args):
        control = str(args.get("control") or "").strip().lower()
        state = str(args.get("state") or "").strip().lower()
        specs = self._qml_cockpit_control_specs()
        spec = specs.get(control)
        if spec is None:
            return {"ok": False, "error": f"Unsupported cockpit control: {control}"}
        if state not in spec["states"]:
            allowed = ", ".join(spec["states"].keys())
            return {"ok": False, "error": f"{spec['label']} accepts: {allowed}."}
        desired = bool(spec["states"][state])
        current = self._qml_cockpit_control_state(spec)
        if current == desired:
            return {
                "ok": True, "control": control, "state": state, "already": True,
                "status": self._qml_cockpit_control_phrase(control, state),
            }
        if self._wizard_runtime_paused():
            return {"ok": False, "control": control, "error": "Guided setup currently owns Bridge controls."}
        if self.egress_phase != "IDLE" or self.station_automation_busy or self.native_command_busy:
            owner = "Emergency Egress" if self.egress_phase != "IDLE" else ("station maintenance" if self.station_automation_busy else self.native_command_name)
            return {"ok": False, "control": control, "error": f"Cockpit controls are busy with {owner}."}
        binding = self.bindings.keyboard_binding(spec["action"])
        if not binding:
            return {
                "ok": False,
                "control": control,
                "error": f"{spec['label']} cannot be controlled by voice yet because {spec['action']} has no keyboard Primary/Secondary binding in the active Elite preset.",
            }

        accepted = threading.Event()
        start_box = {}
        command_name = f"Set {spec['label']}"

        def worker():
            self._native_prepare_cockpit(command_name)
            # Re-check after focus/Status.json catch-up so a state change made by
            # the pilot while the command was queued cannot be accidentally toggled.
            if self._qml_cockpit_control_state(spec) == desired:
                self.native_command_status = self._qml_cockpit_control_phrase(control, state)
                return
            live_binding = self._native_binding(spec["action"])
            self._native_tap(live_binding, 0.10)
            if not self._wait_for(lambda: self._qml_cockpit_control_state(spec) == desired, 2.75, 0.05):
                actual = "ON" if self._qml_cockpit_control_state(spec) else "OFF"
                raise RuntimeError(f"{spec['label']} toggle was sent, but Elite did not confirm the requested state (current flag={actual}).")
            self.native_command_status = self._qml_cockpit_control_phrase(control, state)
            self._native_command_log(f"SUCCESS {command_name} | {control}={state} confirmed")

        def begin():
            try:
                before_generation = int(getattr(self, "native_command_generation", 0) or 0)
                self._native_begin(command_name, worker)
                start_box["generation"] = int(getattr(self, "native_command_generation", 0) or 0)
                start_box["accepted"] = start_box["generation"] > before_generation and bool(self.native_command_busy)
                start_box["status"] = str(self.native_command_status or "-")
            except Exception as exc:
                start_box["error"] = str(exc)
            finally:
                accepted.set()

        self.after(0, begin)
        if not accepted.wait(3.0):
            return {"ok": False, "control": control, "error": "Bridge did not accept the cockpit control in time."}
        if start_box.get("error"):
            return {"ok": False, "control": control, "error": start_box["error"]}
        if not start_box.get("accepted"):
            return {"ok": False, "control": control, "error": start_box.get("status", "Cockpit control was not started.")}

        generation = start_box.get("generation")
        deadline = time.monotonic() + 5.5
        while time.monotonic() < deadline:
            if int(getattr(self, "native_command_generation", 0) or 0) != generation:
                break
            if not bool(getattr(self, "native_command_busy", False)):
                break
            time.sleep(0.05)
        actual = self._qml_cockpit_control_state(spec)
        if actual == desired:
            return {
                "ok": True, "control": control, "state": state, "already": False,
                "status": self._qml_cockpit_control_phrase(control, state),
                "binding": self.bindings.binding_display(spec["action"]),
            }
        return {
            "ok": False, "control": control, "state": state,
            "error": str(getattr(self, "native_command_status", "Elite did not confirm the requested cockpit state.")),
        }

    @staticmethod
    def _qml_elite_action_label(action):
        label = legacy.BindingsManager.DISPLAY_NAMES.get(action)
        if label:
            return str(label)
        text = str(action or "").replace("_", " ")
        text = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", text)
        return re.sub(r"\s+", " ", text).strip() or str(action or "-")

    def _qml_elite_action_policy(self, action):
        action = str(action or "").strip()
        stateful = {spec["action"]: control for control, spec in self._qml_cockpit_control_specs().items()}
        if action in stateful:
            return "STATEFUL", f"Use set_cockpit_control for {stateful[action]} so Bridge can verify the requested state."
        if action in COCKPIT_PROTECTED_ELITE_ACTIONS:
            return "PROTECTED", "Weapon fire and destructive cargo actions are not available through generic AI execution."
        if action in COCKPIT_CONTEXTUAL_OR_HOLD_ACTIONS:
            return "UNSUPPORTED", "This action is contextual, continuous, or requires press/hold timing and is not safe to blind-tap."
        if action.endswith("_Buggy") or action.startswith(COCKPIT_BLOCKED_ACTION_PREFIXES):
            return "UNSUPPORTED", "This build limits generic execution to main-ship one-shot controls."
        return "READY", ""

    def _qml_supported_binding_rows(self, query=""):
        """Inspect the live .binds tree, not a hand-maintained list of physical keys."""
        query = str(query or "").strip().casefold()
        rows = []
        root = getattr(self.bindings, "root", None)
        if root is None:
            return rows
        curated_actions = {spec["action"] for spec in COCKPIT_ACTIONS.values()}
        curated_actions.update(spec["action"] for spec in self._qml_cockpit_control_specs().values())
        for elem in root:
            action = str(getattr(elem, "tag", "") or "")
            if not action:
                continue
            binding = self.bindings.keyboard_binding(action)
            label = self._qml_elite_action_label(action)
            haystack = f"{action} {label}".casefold()
            if query:
                if query not in haystack:
                    continue
            elif action not in curated_actions:
                # An unfiltered query stays compact for conversational use. An
                # explicit filter searches the full active Elite action catalog.
                continue
            policy_status, reason = self._qml_elite_action_policy(action)
            if binding:
                status = policy_status
            else:
                non_keyboard = False
                for slot in ("Primary", "Secondary"):
                    node = elem.find(slot)
                    if node is not None and node.attrib.get("Key") and node.attrib.get("Device") not in (None, "", "Keyboard"):
                        non_keyboard = True
                        break
                status = "HOTAS ONLY" if non_keyboard else "UNBOUND"
                reason = "Add a keyboard Primary/Secondary binding in Elite before Bridge can execute this action by voice."
            command = next((cid for cid, spec in COCKPIT_ACTIONS.items() if spec["action"] == action), None)
            control = next((cid for cid, spec in self._qml_cockpit_control_specs().items() if spec["action"] == action), None)
            rows.append({
                "command": command or (f"state:{control}" if control else None),
                "elite_action": action,
                "label": label,
                "status": status,
                "binding": self.bindings.binding_display(action),
                "note": reason,
            })
        rows.sort(key=lambda row: (row["status"] != "READY", row["label"].casefold(), row["elite_action"].casefold()))
        return rows

    def _copilot_get_cockpit_bindings_tool(self, args):
        query = str((args or {}).get("query") or "").strip()
        rows = self._qml_supported_binding_rows(query)
        ready = sum(1 for row in rows if row["status"] == "READY")
        return {
            "ok": True,
            "preset": str(getattr(self.bindings, "preset", "-") or "-"),
            "source": str(getattr(self.bindings, "source_kind", "-") or "-"),
            "query": query,
            "ready": ready,
            "count": len(rows),
            "actions": rows[:80],
        }

    def _copilot_perform_elite_binding_tool(self, args):
        elite_action = str((args or {}).get("elite_action") or "").strip()
        if not elite_action:
            return {"ok": False, "error": "No Elite action was supplied."}
        status, reason = self._qml_elite_action_policy(elite_action)
        if status != "READY":
            return {"ok": False, "elite_action": elite_action, "status": status, "error": reason}
        if self._wizard_runtime_paused():
            return {"ok": False, "elite_action": elite_action, "error": "Guided setup currently owns Bridge controls."}
        if self.egress_phase != "IDLE" or self.station_automation_busy or self.native_command_busy:
            owner = "Emergency Egress" if self.egress_phase != "IDLE" else ("station maintenance" if self.station_automation_busy else self.native_command_name)
            return {"ok": False, "elite_action": elite_action, "error": f"Cockpit controls are busy with {owner}."}
        binding = self.bindings.keyboard_binding(elite_action)
        if not binding:
            return {"ok": False, "elite_action": elite_action, "error": "That Elite action has no keyboard Primary/Secondary binding in the active preset."}
        label = self._qml_elite_action_label(elite_action)
        accepted = threading.Event()
        start_box = {}
        command_name = f"Cockpit: {label}"

        def worker():
            self._native_prepare_cockpit(command_name)
            live_binding = self._native_binding(elite_action)
            self._native_tap(live_binding, 0.10)
            self.native_command_status = f"{label} command sent."
            self._native_command_log(f"SUCCESS {command_name} | generic elite_action={elite_action} | binding={self.bindings.binding_display(elite_action)}")

        def begin():
            try:
                before_generation = int(getattr(self, "native_command_generation", 0) or 0)
                self._native_begin(command_name, worker)
                start_box["generation"] = int(getattr(self, "native_command_generation", 0) or 0)
                start_box["accepted"] = start_box["generation"] > before_generation and bool(self.native_command_busy)
                start_box["status"] = str(self.native_command_status or "-")
            except Exception as exc:
                start_box["error"] = str(exc)
            finally:
                accepted.set()

        self.after(0, begin)
        if not accepted.wait(3.0):
            return {"ok": False, "elite_action": elite_action, "error": "Bridge did not accept the Elite binding command in time."}
        if start_box.get("error"):
            return {"ok": False, "elite_action": elite_action, "error": start_box["error"]}
        if not start_box.get("accepted"):
            return {"ok": False, "elite_action": elite_action, "error": start_box.get("status", "Elite binding command was not started.")}
        generation = start_box.get("generation")
        deadline = time.monotonic() + 4.0
        while time.monotonic() < deadline:
            if int(getattr(self, "native_command_generation", 0) or 0) != generation or not bool(getattr(self, "native_command_busy", False)):
                break
            time.sleep(0.05)
        if bool(getattr(self, "native_command_busy", False)) and int(getattr(self, "native_command_generation", 0) or 0) == generation:
            return {"ok": False, "elite_action": elite_action, "error": "Elite binding command did not finish in time."}
        return {
            "ok": True,
            "elite_action": elite_action,
            "label": label,
            "binding": self.bindings.binding_display(elite_action),
            "status": f"{label} command sent.",
        }

    def _copilot_perform_cockpit_action_tool(self, args):
        command = str((args or {}).get("action") or "").strip().lower()
        spec = COCKPIT_ACTIONS.get(command)
        if spec is None:
            return {"ok": False, "action": command, "error": f"Unsupported cockpit action: {command}"}
        elite_action = str(spec["action"])
        if elite_action in COCKPIT_PROTECTED_ELITE_ACTIONS:
            return {"ok": False, "action": command, "error": "That Elite action is protected from generic AI execution."}
        if self._wizard_runtime_paused():
            return {"ok": False, "action": command, "error": "Guided setup currently owns Bridge controls."}
        if self.egress_phase != "IDLE" or self.station_automation_busy or self.native_command_busy:
            owner = "Emergency Egress" if self.egress_phase != "IDLE" else ("station maintenance" if self.station_automation_busy else self.native_command_name)
            return {"ok": False, "action": command, "error": f"Cockpit controls are busy with {owner}."}
        binding = self.bindings.keyboard_binding(elite_action)
        if not binding:
            return {
                "ok": False,
                "action": command,
                "elite_action": elite_action,
                "error": f"{spec['label']} has no keyboard Primary/Secondary binding in the active Elite preset.",
            }

        accepted = threading.Event()
        start_box = {}
        command_name = f"Cockpit: {spec['label']}"

        def worker():
            self._native_prepare_cockpit(command_name)
            live_binding = self._native_binding(elite_action)
            self._native_tap(live_binding, 0.10)
            self.native_command_status = spec["spoken"]
            self._native_command_log(
                f"SUCCESS {command_name} | elite_action={elite_action} | binding={self.bindings.binding_display(elite_action)}"
            )

        def begin():
            try:
                before_generation = int(getattr(self, "native_command_generation", 0) or 0)
                self._native_begin(command_name, worker)
                start_box["generation"] = int(getattr(self, "native_command_generation", 0) or 0)
                start_box["accepted"] = start_box["generation"] > before_generation and bool(self.native_command_busy)
                start_box["status"] = str(self.native_command_status or "-")
            except Exception as exc:
                start_box["error"] = str(exc)
            finally:
                accepted.set()

        self.after(0, begin)
        if not accepted.wait(3.0):
            return {"ok": False, "action": command, "error": "Bridge did not accept the cockpit action in time."}
        if start_box.get("error"):
            return {"ok": False, "action": command, "error": start_box["error"]}
        if not start_box.get("accepted"):
            return {"ok": False, "action": command, "error": start_box.get("status", "Cockpit action was not started.")}

        generation = start_box.get("generation")
        deadline = time.monotonic() + 4.0
        while time.monotonic() < deadline:
            if int(getattr(self, "native_command_generation", 0) or 0) != generation:
                break
            if not bool(getattr(self, "native_command_busy", False)):
                break
            time.sleep(0.05)
        if bool(getattr(self, "native_command_busy", False)) and int(getattr(self, "native_command_generation", 0) or 0) == generation:
            return {"ok": False, "action": command, "error": "Cockpit action did not finish in time."}
        status = str(getattr(self, "native_command_status", "") or "")
        if status.startswith("FAILED") or status.startswith("BUSY"):
            return {"ok": False, "action": command, "error": status}
        return {
            "ok": True,
            "action": command,
            "elite_action": elite_action,
            "binding": self.bindings.binding_display(elite_action),
            "status": spec["spoken"],
        }

    def _copilot_set_power_distribution_tool(self, args):
        profile = str((args or {}).get("profile") or "").strip().lower()
        if profile == "auto":
            done = threading.Event()
            box = {}
            def resume():
                try:
                    if not bool(self.dynamic_pips_var.get()):
                        self.dynamic_pips_var.set(True)
                        self._dynamic_pips_toggle_changed()
                    self._qml_clear_manual_pip_override("explicit Resume Auto Pips command")
                    self.dynamic_pip_candidate = None
                    self.dynamic_pip_candidate_since = 0.0
                    self.dynamic_pip_last_applied = "-"
                    box["ok"] = True
                except Exception as exc:
                    box["error"] = str(exc)
                finally:
                    done.set()
            self.after(0, resume)
            if not done.wait(2.0):
                return {"ok": False, "profile": profile, "error": "Bridge did not resume Auto Pips in time."}
            if box.get("error"):
                return {"ok": False, "profile": profile, "error": box["error"]}
            return {"ok": True, "profile": "auto", "status": "Auto Pips resumed."}

        mapping = {"shields": "RECOVERY", "weapons": "WEAPONS", "engines": "EGRESS", "balanced": "BALANCED"}
        mode = mapping.get(profile)
        if mode is None:
            return {"ok": False, "profile": profile, "error": "PIP profile must be shields, weapons, engines, balanced, or auto."}
        if self._wizard_runtime_paused():
            return {"ok": False, "profile": profile, "error": "Guided setup currently owns Bridge controls."}
        if self.egress_phase != "IDLE" or self.station_automation_busy or self.native_command_busy:
            owner = "Emergency Egress" if self.egress_phase != "IDLE" else ("station maintenance" if self.station_automation_busy else self.native_command_name)
            return {"ok": False, "profile": profile, "error": f"Cockpit controls are busy with {owner}."}

        labels = {"shields": "Power to shields.", "weapons": "Power to weapons.", "engines": "Power to engines.", "balanced": "Power balanced."}
        expected_map = {
            "shields": list(legacy.DYNAMIC_PIP_PRESETS["RECOVERY"]["expected"]),
            "weapons": list(legacy.DYNAMIC_PIP_PRESETS["WEAPONS"]["expected"]),
            "engines": list(legacy.DYNAMIC_PIP_PRESETS["EGRESS"]["expected"]),
            "balanced": [4, 4, 4],
        }
        accepted = threading.Event()
        start_box = {}
        command_name = f"Set PIPs: {profile.title()}"

        def worker():
            self._native_prepare_cockpit(command_name)
            if bool(self.dynamic_pips_var.get()):
                self._qml_set_manual_pip_override(f"explicit pilot request: {profile}")
            reset = self._native_binding("ResetPowerDistribution")
            self._native_tap(reset, 0.06)
            if mode != "BALANCED":
                _reset, sequence, missing = self._dynamic_pips_bindings(mode)
                if missing:
                    raise RuntimeError("Missing Elite keyboard binding(s): " + ", ".join(missing))
                for _action_name, binding, count in sequence:
                    for _ in range(int(count)):
                        self._native_tap(binding, 0.04)
            expected = expected_map[profile]
            verified = self._wait_for(lambda: self._dynamic_pips_current() == expected, 1.6, 0.05)
            self.dynamic_pip_last_command_mono = time.monotonic()
            self._qml_last_observed_pips = list(self._dynamic_pips_current() or expected)
            self.dynamic_pip_pending_verify = None
            self.dynamic_pip_last_applied = "MANUAL" if bool(self.dynamic_pips_var.get()) else "-"
            self.native_command_status = labels[profile] if verified else f"{labels[profile][:-1]} command sent; distributor confirmation not received."
            self._dynamic_pips_log(f"PILOT DIRECT {profile.upper()} | expected={expected} | observed={self._dynamic_pips_current()}")

        def begin():
            try:
                before_generation = int(getattr(self, "native_command_generation", 0) or 0)
                self._native_begin(command_name, worker)
                start_box["generation"] = int(getattr(self, "native_command_generation", 0) or 0)
                start_box["accepted"] = start_box["generation"] > before_generation and bool(self.native_command_busy)
                start_box["status"] = str(self.native_command_status or "-")
            except Exception as exc:
                start_box["error"] = str(exc)
            finally:
                accepted.set()
        self.after(0, begin)
        if not accepted.wait(3.0):
            return {"ok": False, "profile": profile, "error": "Bridge did not accept the PIP command in time."}
        if start_box.get("error"):
            return {"ok": False, "profile": profile, "error": start_box["error"]}
        if not start_box.get("accepted"):
            return {"ok": False, "profile": profile, "error": start_box.get("status", "PIP command was not started.")}
        generation = start_box.get("generation")
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            if int(getattr(self, "native_command_generation", 0) or 0) != generation or not bool(getattr(self, "native_command_busy", False)):
                break
            time.sleep(0.05)
        status = str(getattr(self, "native_command_status", "") or "")
        if "FAILED" in status or "BUSY" in status:
            return {"ok": False, "profile": profile, "error": status}
        return {"ok": True, "profile": profile, "status": labels[profile], "manual_override": bool(self.dynamic_pips_var.get())}

    def _copilot_find_best_target_tool(self, _args=None):
        if self._wizard_runtime_paused():
            return {"ok": False, "error": "Guided setup currently owns Bridge controls."}
        if self.egress_phase != "IDLE" or self.station_automation_busy or self.native_command_busy:
            owner = "Emergency Egress" if self.egress_phase != "IDLE" else ("station maintenance" if self.station_automation_busy else self.native_command_name)
            return {"ok": False, "error": f"Cockpit controls are busy with {owner}."}
        if not self.bindings.keyboard_binding("CycleNextTarget"):
            return {"ok": False, "error": "Cycle Next Target has no keyboard Primary/Secondary binding in the active Elite preset."}
        accepted = threading.Event()
        box = {}
        def begin():
            before = int(getattr(self, "native_command_generation", 0) or 0)
            self.start_find_best_target()
            box["generation"] = int(getattr(self, "native_command_generation", 0) or 0)
            box["accepted"] = box["generation"] > before and bool(self.native_command_busy)
            box["status"] = str(self.native_command_status or "-")
            accepted.set()
        self.after(0, begin)
        if not accepted.wait(3.0) or not box.get("accepted"):
            return {"ok": False, "error": box.get("status", "Best-target sweep was not started.")}
        generation = box.get("generation")
        deadline = time.monotonic() + 18.0
        while time.monotonic() < deadline:
            if int(getattr(self, "native_command_generation", 0) or 0) != generation or not bool(getattr(self, "native_command_busy", False)):
                break
            time.sleep(0.08)
        status = str(getattr(self, "native_command_status", "") or "")
        if bool(getattr(self, "native_command_busy", False)) and int(getattr(self, "native_command_generation", 0) or 0) == generation:
            return {"ok": False, "error": "Best-target sweep is still running; use Cancel if needed."}
        if "FAILED" in status or "BUSY" in status:
            return {"ok": False, "error": status}
        return {"ok": True, "status": status, "ship": str(getattr(self.state_data, "target_ship", "-") or "-")}

    def _execute_copilot_tool(self, name, args, action_mode):
        # Publish a one-shot UI destination before long-running tools start. QML
        # consumes the serial once, so a pilot who manually leaves is not yanked back.
        if name == "show_bridge_workspace":
            page_name = str(args.get("page") or "OVERVIEW").strip().upper()
            page_map = {"OVERVIEW":0, "LIVE":0, "NAVIGATION":1, "COMBAT":2, "TRADE":3, "COLONIZATION":4, "COMMANDER":5, "AI":6, "AUDIO":7, "SETUP":8, "DISPLAY":9, "CONTROLS":10}
            page = page_map.get(page_name, 0)
            workspace = str(args.get("workspace") or "").strip().lower()
            guide = bool(args.get("guide", False))
            self._qml_set_ui_hint(page, workspace)
            if guide:
                # Start after Luna's short direct answer. When the workspace points at a
                # specific feature, replay just the matching saved ?-tour segment instead
                # of forcing the commander through the entire page tour.
                focus_step = self._focused_help_step(page, workspace or "main")
                self._qml_guide_after_copilot = (page, focus_step, focus_step) if focus_step is not None else (page, 0, None)
            return {"ok": True, "page": page_name, "workspace": workspace or "main", "guide_started": guide}
        if name == "search_res_sites":
            return self._copilot_search_res_sites_tool(args)
        if name == "set_cockpit_control":
            return self._copilot_set_cockpit_control_tool(args)
        if name == "plot_route":
            self._qml_set_ui_hint(1, "route")
        elif name in {"search_market", "search_trade_loops"}:
            self._qml_set_ui_hint(3, "route_finder")
        elif name == "get_trade_loop_state":
            self._qml_set_ui_hint(3, "loop_setup")
        elif name == "get_commander_history":
            self._qml_set_ui_hint(5, "records")
        elif name == "execute_bridge_command":
            cmd = str(args.get("command") or "").strip()
            if cmd in {"target_highest_threat", "target_power_plant", "ensure_combat_mode", "emergency_egress", "cancel_egress"}:
                self._qml_set_ui_hint(2, "tactical")
            elif cmd in {"auto_launch", "docking_protocol", "clear_station_jump", "cancel_current_command"}:
                self._qml_set_ui_hint(0, "quick_actions")
        return super()._execute_copilot_tool(name, args, action_mode)

    def finish_copilot_command(self, result):
        super().finish_copilot_command(result)
        pending_guide = getattr(self, "_qml_guide_after_copilot", None)
        self._qml_guide_after_copilot = None
        if pending_guide is not None:
            try:
                page, start_step, end_step = pending_guide
                self.after(250, lambda p=int(page), s=int(start_step or 0), e=end_step: self._page_help_start(p, s, e))
            except Exception:
                pass

    @staticmethod
    def _copilot_tool_trace_line(name, args, result):
        if name == "search_res_sites":
            return f"search_res_sites({args.get('type')}) → {result.get('count', 0)} result(s); {result.get('status', result.get('error', '?'))}"
        if name == "show_bridge_workspace":
            return f"show_bridge_workspace({result.get('page','?')} / {result.get('workspace','main')}) → {'guide' if result.get('guide_started') else 'open'}"
        if name == "set_cockpit_control":
            return f"set_cockpit_control({args.get('control')}={args.get('state')}) → {result.get('status', result.get('error', '?'))}"
        return legacy.BridgeApp._copilot_tool_trace_line(name, args, result)

    def _wizard_runtime_paused(self):
        return bool(getattr(self, "_qml_wizard_gate_active", True))

    def _start_startup_sequence(self):
        # QML owns first-run startup. The .95 engine may ingest telemetry while the
        # wizard is visible, but speech, AI triggers and cockpit automation remain
        # gated until QML explicitly releases the wizard runtime gate.
        self.startup_gate_started_mono = time.monotonic()
        self.startup_voice_gate_active = True
        self._qml_wizard_gate_active = True
        self._qml_wizard_gate_released_once = False
        try:
            self.startup_voice_hold.clear()
        except Exception:
            pass
        try:
            self.sfx_manager.stop()
        except Exception:
            pass
        # No timer releases this gate. QML sends wizard_runtime_gate after it has
        # decided whether the welcome wizard is actually visible.

    def _set_qml_wizard_runtime_gate(self, active):
        active = bool(active)
        self._qml_wizard_gate_active = active
        if active:
            self.startup_voice_gate_active = True
            try:
                self.startup_voice_hold.clear()
            except Exception:
                pass
            self._native_set_status("Guided setup active // operational AI, voice and automation paused.")
            return

        # Do not replay telemetry chatter accumulated while setup was open. Start
        # normal operation cleanly from the moment the pilot enters the Bridge.
        try:
            self.startup_voice_hold.clear()
        except Exception:
            pass
        self.startup_voice_gate_active = False
        first_release = not bool(getattr(self, "_qml_wizard_gate_released_once", False))
        self._qml_wizard_gate_released_once = True
        self._native_set_status("Guided setup closed // Bridge runtime released.")
        if first_release:
            try:
                self.after(350, self._qml_startup_welcome)
            except Exception:
                pass

    def _voice_say(self, required_level, text, kind="INFO", key=None, cooldown=5.0, _startup_release=False):
        if self._wizard_runtime_paused() and not _startup_release:
            return False

        spoken_text = str(text or "")
        if str(kind or "").upper() == "POWERPLAY":
            match = re.search(r"merits awarded:\s*([0-9,]+)", spoken_text, flags=re.IGNORECASE)
            if match:
                try:
                    merit_delta = int(match.group(1).replace(",", ""))
                except Exception:
                    merit_delta = 0
                if merit_delta > 500:
                    spoken_text = f"{merit_delta:,} merits earned."
                else:
                    spoken_text = "Merits earned."
                    key = "powerplay:small-merits"
                    cooldown = max(float(cooldown or 0.0), 8.0)

        return super()._voice_say(required_level, spoken_text, kind=kind, key=key, cooldown=cooldown, _startup_release=_startup_release)

    def _dispatch_bridge_hotkey(self, command_id, source="HOTKEY"):
        # During guided setup, operational hotkeys stay blocked. The one exception is
        # Push-to-Talk while the wizard playback test is armed, because that page is
        # explicitly teaching the pilot to use the control they just mapped.
        if self._wizard_runtime_paused():
            if str(command_id) == "push_to_talk" and bool(getattr(self, "_wizard_ptt_test_armed", False)):
                return super()._dispatch_bridge_hotkey(command_id, source=source)
            return
        return super()._dispatch_bridge_hotkey(command_id, source=source)

    def _start_wizard_ptt_test_recording(self, source="PTT"):
        """Use the real PTT capture path as a safe wizard proof-of-life.

        The phrase is never sent to Copilot.  If an API key already exists, Bridge
        automatically transcribes the captured WAV after release and shows exactly
        what it heard.  Without an API key the page still proves PTT + microphone
        locally and labels transcription as optional/waiting rather than failed.
        """
        if bool(getattr(self, "_wizard_ptt_test_recording", False)):
            return
        if not legacy.SOUNDDEVICE_AVAILABLE:
            self.voice_input_status = f"PTT CHECK unavailable: {legacy.SOUNDDEVICE_IMPORT_ERROR}"
            self.refresh_preferences_widgets()
            return
        self._wizard_ptt_test_recording = True
        self._wizard_ptt_test_stop = threading.Event()
        self.voice_input_peak = 0.0
        self.voice_input_last_text = "-"
        self.voice_input_status = f"PTT DETECTED // LISTENING through {source}. Speak a short phrase, then release PTT."
        self.refresh_preferences_widgets()
        input_device = legacy._sd_device_arg(self.voice_input_device_var.get())

        def worker():
            chunks = []
            started = time.monotonic()
            path = None
            try:
                with legacy.sd.RawInputStream(samplerate=16000, blocksize=1600, channels=1, dtype="int16", device=input_device) as stream:
                    while not self._wizard_ptt_test_stop.is_set() and time.monotonic() - started < 15.0:
                        data, _overflowed = stream.read(1600)
                        raw = bytes(data)
                        chunks.append(raw)
                        self._publish_mic_level(self._voice_chunk_level(raw))
                duration = time.monotonic() - started
                if duration < 0.20 or not chunks:
                    self.after(0, lambda: self._wizard_ptt_test_finish(
                        "PTT detected, but it was released too quickly. Hold PTT, speak a short phrase, then release."
                    ))
                    return
                payload = b"".join(chunks)
                peak = float(getattr(self, "voice_input_peak", 0.0) or 0.0)
                key_ready = bool(str(os.environ.get("OPENAI_API_KEY") or "").strip())
                if key_ready:
                    self.after(0, lambda p=peak: self._wizard_ptt_test_set_status(
                        f"PTT PASS • MIC PASS • {self._format_mic_peak(p)} • transcribing safely..."
                    ))
                    path = self._write_voice_capture(payload)
                    try:
                        transcript = self._transcribe_voice_file(path)
                    finally:
                        try:
                            os.unlink(path)
                        except Exception:
                            pass
                        path = None
                    if transcript:
                        self.after(0, lambda t=transcript, p=peak: self._wizard_ptt_test_finish(
                            f"PTT PASS • MIC PASS • TRANSCRIPTION PASS • heard: {t}", transcript=t
                        ))
                    else:
                        self.after(0, lambda p=peak: self._wizard_ptt_test_finish(
                            f"PTT PASS • MIC PASS • {self._format_mic_peak(p)} • no speech was recognized."
                        ))
                else:
                    self.after(0, lambda p=peak: self._wizard_ptt_test_finish(
                        f"PTT PASS • MIC PASS • {self._format_mic_peak(p)} • transcription will be available after optional AI setup."
                    ))
            except urllib.error.HTTPError as exc:
                try:
                    detail = exc.read().decode("utf-8", errors="replace")
                except Exception:
                    detail = str(exc)
                self.after(0, lambda d=detail, c=exc.code: self._wizard_ptt_test_finish(
                    f"PTT PASS • MIC PASS • transcription HTTP {c}: {d[:180]}"
                ))
            except Exception as exc:
                self.after(0, lambda e=str(exc): self._wizard_ptt_test_finish(f"PTT check failed: {e}"))
            finally:
                if path:
                    try:
                        os.unlink(path)
                    except Exception:
                        pass

        threading.Thread(target=worker, daemon=True, name="EliteBridge-WizardPTTCheck").start()

    def _wizard_ptt_test_set_status(self, text):
        self.voice_input_status = str(text)
        self.refresh_preferences_widgets()

    def _wizard_ptt_test_finish(self, text, transcript=None):
        self._wizard_ptt_test_recording = False
        # Keep the check armed while the dedicated PTT page remains active so the pilot can
        # simply try the mapped PTT again without pressing another test button.
        self._wizard_ptt_test_armed = int(getattr(self, "_wizard_pending_step", -1)) == 4
        if transcript:
            self.voice_input_last_text = str(transcript)
        self.voice_input_status = str(text)
        self.refresh_preferences_widgets()
        try:
            self.after(900, lambda: self._update_mic_level_ui(0.0))
        except Exception:
            pass

    def _arm_wizard_ptt_test(self):
        self._wizard_ptt_test_armed = True
        self._wizard_ptt_test_recording = False
        self.voice_input_last_text = "-"
        if str(os.environ.get("OPENAI_API_KEY") or "").strip():
            self.voice_input_status = "PTT CHECK READY // hold your Push-to-Talk control, speak a short phrase, then release. Bridge will automatically transcribe it here and will NOT execute it as a command."
        else:
            self.voice_input_status = "PTT CHECK WAITING // AI Co-Pilot must be verified before Push-to-Talk can be tested."
        self.refresh_preferences_widgets()
        self._native_set_status("Wizard PTT check armed // waiting for mapped PTT press // no command execution.")

    def _start_ptt_recording(self, source="PTT"):
        # Pilot speech has absolute priority over automatic Bridge chatter.
        # Stop active playback immediately and discard queued announcements before
        # opening the microphone, then hand the normal PTT path a fresh cancel token
        # so the reply to this command can speak normally.
        self._pilot_interrupt_voice_for_ptt()
        if self._wizard_runtime_paused():
            if bool(getattr(self, "_wizard_ptt_test_armed", False)):
                return self._start_wizard_ptt_test_recording(source)
            try:
                self.voice_input_status = "Guided setup is active. PTT command execution is paused until you enter Bridge."
                self.refresh_preferences_widgets()
            except Exception:
                pass
            return
        if not self._qml_copilot_enabled():
            self.voice_input_status = "AI Co-Pilot is disabled in Core Bridge mode. Enable AI Co-Pilot from Setup to use voice commands."
            self.refresh_preferences_widgets()
            return
        return super()._start_ptt_recording(source)

    def _stop_ptt_recording(self):
        if self._wizard_runtime_paused() and bool(getattr(self, "_wizard_ptt_test_recording", False)):
            try:
                self._wizard_ptt_test_stop.set()
            except Exception:
                pass
            return
        return super()._stop_ptt_recording()

    # During guided setup, keep telemetry live for readiness/status cards but do
    # not run autonomous or key-sending operational behavior.
    def consider_station_automation_event(self, e):
        if self._wizard_runtime_paused():
            return
        return super().consider_station_automation_event(e)

    def _maybe_run_station_automation(self):
        if self._wizard_runtime_paused():
            return
        return super()._maybe_run_station_automation()

    def consider_ai_event(self, e):
        if self._wizard_runtime_paused() or not self._qml_copilot_enabled():
            return
        return super().consider_ai_event(e)

    def consider_ai_status_transition(self, old_flags, new_flags):
        if self._wizard_runtime_paused() or not self._qml_copilot_enabled():
            return
        return super().consider_ai_status_transition(old_flags, new_flags)

    def safety_watch_event(self, trigger, event=None):
        if self._wizard_runtime_paused():
            return
        return super().safety_watch_event(trigger, event)

    def maybe_auto_ai(self):
        if self._wizard_runtime_paused() or not self._qml_copilot_enabled():
            return
        return super().maybe_auto_ai()

    def _qml_weapons_priority_active(self):
        """Latch hardpoints briefly so transient Status.json samples cannot hand PIPs to another policy."""
        now = time.monotonic()
        hardpoints = bool(self.state_data.flag("Hardpoints"))
        if hardpoints:
            self._qml_weapons_priority_latched = True
            self._qml_weapons_priority_false_since = 0.0
            return True
        if bool(getattr(self, "_qml_weapons_priority_latched", False)):
            since = float(getattr(self, "_qml_weapons_priority_false_since", 0.0) or 0.0)
            if since <= 0.0:
                self._qml_weapons_priority_false_since = now
                return True
            if (now - since) < 0.75:
                return True
            self._qml_weapons_priority_latched = False
            self._qml_weapons_priority_false_since = 0.0
        return False

    def _qml_pip_state_token(self):
        s = self.state_data
        return (
            bool(s.flag("Hardpoints")),
            bool(getattr(s, "combat_active", False)),
            str(getattr(self, "egress_phase", "IDLE") or "IDLE"),
            bool(s.flag("Docked")),
            bool(s.flag("Supercruise")),
            bool(s.flag("FSD Jump")),
        )

    def _qml_clear_manual_pip_override(self, reason="state transition"):
        if not bool(getattr(self, "_qml_dynamic_pips_manual_override", False)):
            self._qml_last_pip_state_token = self._qml_pip_state_token()
            return False
        self._qml_dynamic_pips_manual_override = False
        self._qml_dynamic_pips_manual_override_reason = "-"
        self._qml_dynamic_pips_manual_override_token = None
        self.dynamic_pip_candidate = None
        self.dynamic_pip_candidate_since = 0.0
        self.dynamic_pip_last_applied = "-"
        self.dynamic_pip_pending_verify = None
        self._qml_last_pip_state_token = self._qml_pip_state_token()
        try:
            self._dynamic_pips_log(f"MANUAL OVERRIDE RELEASED | {reason}")
        except Exception:
            pass
        return True

    def _qml_set_manual_pip_override(self, reason="pilot distributor input"):
        self._qml_dynamic_pips_manual_override = True
        self._qml_dynamic_pips_manual_override_reason = str(reason or "pilot distributor input")
        self._qml_dynamic_pips_manual_override_token = self._qml_pip_state_token()
        self.dynamic_pip_candidate = None
        self.dynamic_pip_candidate_since = 0.0
        self.dynamic_pip_last_applied = "MANUAL"
        self.dynamic_pip_pending_verify = None
        self.dynamic_pip_mode = "MANUAL OVERRIDE"
        self.dynamic_pip_status = f"Pilot PIP override active • {self._qml_dynamic_pips_manual_override_reason}."
        try:
            self._dynamic_pips_log(f"MANUAL OVERRIDE ACTIVE | {self._qml_dynamic_pips_manual_override_reason}")
        except Exception:
            pass

    def _qml_update_manual_pip_override(self):
        current = self._dynamic_pips_current()
        token = self._qml_pip_state_token()
        previous_token = getattr(self, "_qml_last_pip_state_token", None)
        if previous_token is None:
            self._qml_last_pip_state_token = token

        if bool(getattr(self, "_qml_dynamic_pips_manual_override", False)):
            override_token = getattr(self, "_qml_dynamic_pips_manual_override_token", None)
            if override_token is not None and token != override_token:
                self._qml_clear_manual_pip_override("meaningful flight-state transition")
        self._qml_last_pip_state_token = token

        if current is None:
            return
        previous = getattr(self, "_qml_last_observed_pips", None)
        self._qml_last_observed_pips = list(current)
        if previous is None or list(previous) == list(current):
            return
        if not bool(self.dynamic_pips_var.get()):
            return
        # Changes inside a Bridge-owned transaction are not pilot overrides.
        owned = getattr(self, "dynamic_pip_pending_verify", None) is not None
        recent_bridge_send = (time.monotonic() - float(getattr(self, "dynamic_pip_last_command_mono", 0.0) or 0.0)) < 1.5
        pip_command = str(getattr(self, "native_command_name", "") or "").startswith("Set PIPs")
        if owned or recent_bridge_send or pip_command:
            return
        s = self.state_data
        if not s.flag("In Main Ship") or s.flag("Docked") or s.flag("Supercruise") or s.flag("FSD Jump"):
            return
        self._qml_set_manual_pip_override("manual distributor input detected")

    @staticmethod
    def _qml_target_hull_score(ship_name):
        key = re.sub(r"[^a-z0-9]+", "", str(ship_name or "").casefold())
        scores = {
            "anaconda": 100,
            "python": 96, "pythonmkii": 96, "pythonmk2": 96,
            "federalcorvette": 95, "federationcorvette": 95,
            "imperialcutter": 94, "type10defender": 93, "type9military": 93,
            "ferdelance": 90,
            "federalassaultship": 88, "federationdropshipmkii": 88,
            "federalgunship": 87, "federationgunship": 87,
            "kraitmkii": 86, "kraitmk2": 86, "mamba": 85,
            "alliancechallenger": 83, "alliancechieftain": 82, "alliancecrusader": 80,
            "imperialclipper": 79, "federaldropship": 78, "federationdropship": 78,
            "type9heavy": 76, "vulture": 74, "kraitphantom": 70,
            "aspexplorer": 62, "type7transporter": 58, "imperialcourier": 56,
            "cobramkv": 54, "cobramkiii": 52, "cobramkiv": 52,
            "vipermkiv": 48, "vipermkiii": 46, "diamondbackexplorer": 45,
            "asp scout": 40, "aspscout": 40, "eaglemkii": 30, "imperialeagle": 31,
            "sidewinder": 20, "hauler": 18, "adder": 22,
        }
        return int(scores.get(key, 35 if key else 0))

    def _qml_target_signature(self):
        s = self.state_data
        target = str(getattr(s, "target", "-") or "-")
        ship = str(getattr(s, "target_ship", "-") or "-")
        pilot = str(getattr(s, "target_pilot", "-") or "-")
        return (target.casefold(), ship.casefold(), pilot.casefold())

    def _qml_target_contact_key(self):
        """Return (key, strong_identity) for the currently selected ship.

        Elite does not expose a universal NPC contact id in ShipTargeted. Once a
        pilot name is known it is a useful stable identity for this local sweep;
        before that, hull-only identity is deliberately treated as weak so two
        separate Pythons are not assumed to be the same ship.
        """
        s = self.state_data
        ship = str(getattr(s, "target_ship", "-") or "-").strip()
        pilot = str(getattr(s, "target_pilot", "-") or "-").strip()
        target = str(getattr(s, "target", "-") or "-").strip()
        ship_key = re.sub(r"[^a-z0-9]+", "", ship.casefold())
        if pilot not in ("", "-"):
            return ("pilot", pilot.casefold(), ship_key), True
        if target not in ("", "-") and target.casefold() != ship.casefold() and "/" in target:
            return ("target", target.casefold(), ship_key), True
        return ("hull", ship_key), False

    def _qml_observe_target_candidate(self, step, settle=0.12):
        """Capture early target intel without requiring a fresh full scan."""
        if settle:
            time.sleep(max(0.0, float(settle)))
        s = self.state_data
        ship = str(getattr(s, "target_ship", "-") or "-").strip()
        if ship in ("", "-"):
            return None
        key, strong = self._qml_target_contact_key()
        pilot = str(getattr(s, "target_pilot", "-") or "-").strip()
        try:
            scan_stage = int(getattr(s, "target_scan_stage", 0) or 0)
        except Exception:
            scan_stage = 0
        legal = str(getattr(s, "target_legal", "-") or "-").strip()
        legal_key = legal.casefold()
        memory = getattr(self, "_qml_target_legal_memory", None)
        if not isinstance(memory, dict):
            memory = {}
            self._qml_target_legal_memory = memory
        if strong and scan_stage >= 3 and legal_key not in ("", "-"):
            memory[key] = legal
        elif strong and legal_key in ("", "-") and key in memory:
            legal = str(memory[key])
            legal_key = legal.casefold()
        clean = legal_key == "clean"
        wanted = legal_key == "wanted"
        hull_score = self._qml_target_hull_score(ship)
        score = hull_score + (12 if wanted else 0)
        return {
            "step": int(step),
            "signature": self._qml_target_signature(),
            "key": key,
            "strong": bool(strong),
            "ship": ship,
            "pilot": pilot,
            "scan_stage": scan_stage,
            "legal": legal if legal not in ("", "-") else "UNKNOWN",
            "clean": clean,
            "wanted": wanted,
            "hull_score": hull_score,
            "score": -9999 if clean else score,
        }

    @staticmethod
    def _qml_best_target_row_label(row):
        legal = str(row.get("legal") or "UNKNOWN").upper()
        return f"{row.get('ship','?')}[{legal}]={int(row.get('score',0))}"

    def _find_best_target_worker(self):
        s = self.state_data
        if s.flag("Docked") or s.flag("Supercruise") or s.flag("FSD Jump") or not s.flag("In Main Ship"):
            raise RuntimeError("Best-target sweep is only available in normal-space main-ship flight.")
        self._native_prepare_cockpit("Find Best Target")
        cycle = self._native_binding("CycleNextTarget")

        # Two-pass routine: survey first, then reacquire. Eighteen taps is long
        # enough to cover a busy RES list while remaining safely bounded if Elite
        # cannot give us a stable identity for every unscanned NPC.
        max_contacts = 18
        observations = []
        strong_seen = set()
        anchor_key = None
        anchor_passes = 0

        def remember(row):
            nonlocal anchor_key, anchor_passes
            if row is None:
                return
            observations.append(row)
            if row["strong"]:
                if anchor_key is None:
                    anchor_key = row["key"]
                    anchor_passes = 1
                elif row["key"] == anchor_key:
                    anchor_passes += 1
                strong_seen.add(row["key"])

        # Include the ship already selected, but never let it short-circuit the
        # survey merely because it is a Python/Anaconda.
        remember(self._qml_observe_target_candidate(0, settle=0.08))

        completed_cycle = False
        for step in range(1, max_contacts + 1):
            before_rev = int(getattr(s, "target_revision", 0) or 0)
            self.native_command_status = f"Find Best Target: surveying contact {step}/{max_contacts}..."
            self._native_tap(cycle, 0.075)
            changed = self._wait_for(
                lambda: int(getattr(s, "target_revision", 0) or 0) > before_rev,
                0.85, 0.035,
            )
            if not changed:
                continue
            self._wait_for(
                lambda: str(getattr(s, "target_ship", "-") or "-") not in ("", "-"),
                0.16, 0.025,
            )
            row = self._qml_observe_target_candidate(step, settle=0.11)
            if row is None:
                continue
            remember(row)
            # Only a strong identity can safely prove we wrapped the list. Hull-
            # only equality cannot, because several NPCs may all be Pythons.
            if anchor_key is not None and row["strong"] and row["key"] == anchor_key and anchor_passes >= 2 and step >= 3:
                completed_cycle = True
                break

        # Keep one row per known NPC identity. Weak/hull-only rows are retained as
        # separate observations because two identical hulls may be different ships.
        candidates = []
        strong_rows = {}
        for row in observations:
            if row["strong"]:
                prior = strong_rows.get(row["key"])
                if prior is None or row["scan_stage"] > prior["scan_stage"] or (row["wanted"] and not prior["wanted"]):
                    strong_rows[row["key"]] = row
            else:
                candidates.append(row)
        candidates.extend(strong_rows.values())

        valid = [row for row in candidates if not row["clean"] and int(row["score"]) > 0]
        valid.sort(key=lambda row: (int(row["score"]), bool(row["wanted"]), int(row["scan_stage"])), reverse=True)

        survey_bits = [self._qml_best_target_row_label(row) for row in sorted(candidates, key=lambda r: r["step"])[:18]]
        survey_text = "; ".join(survey_bits) if survey_bits else "no ship contacts"
        cycle_text = "loop-confirmed" if completed_cycle else "bounded-full-sweep"
        self._native_command_log(f"BEST TARGET SURVEY | {cycle_text} | {survey_text}")
        try:
            self._qml_best_target_history.append(f"{time.strftime('%H:%M:%S')}  SURVEY | {cycle_text} | {survey_text}")
        except Exception:
            pass

        if not valid:
            self.native_command_status = "Find Best Target: no eligible ship remained after the survey."
            self._native_command_log("BEST TARGET | no eligible candidate (known CLEAN contacts rejected)")
            return

        # Second pass: keep cycling until the highest-ranked still-valid candidate
        # is reacquired. If Elite immediately reveals that candidate is CLEAN, do
        # not hang on it; keep cycling and fall through to the next ranked choice.
        current_best = valid[0]
        taps = 0
        max_reacquire_taps = max_contacts + 6
        found = None
        while taps <= max_reacquire_taps and valid:
            row_now = self._qml_observe_target_candidate(-1, settle=0.06)
            if row_now is not None:
                # Immediate Stage-3 replay for a previously scanned ship can turn
                # a provisional favorite into a known-clean rejection.
                if row_now["clean"]:
                    # Reject the exact strong candidate when possible. For a weak
                    # hull candidate, simply keep cycling because another Python
                    # may still be valid.
                    if current_best["strong"] and row_now["strong"] and row_now["key"] == current_best["key"]:
                        valid = [r for r in valid if r is not current_best]
                        if not valid:
                            break
                        current_best = valid[0]
                else:
                    exact = current_best["strong"] and row_now["strong"] and row_now["key"] == current_best["key"]
                    weak_hull = (not current_best["strong"]) and row_now["ship"].casefold() == current_best["ship"].casefold()
                    if exact or weak_hull:
                        found = row_now
                        break

            before_rev = int(getattr(s, "target_revision", 0) or 0)
            self.native_command_status = f"Find Best Target: reacquiring {current_best['ship']}..."
            self._native_tap(cycle, 0.07)
            taps += 1
            self._wait_for(lambda: int(getattr(s, "target_revision", 0) or 0) > before_rev, 0.78, 0.035)

        if found is None:
            self.native_command_status = f"Find Best Target: surveyed {len(observations)} contacts, but no valid ranked target could be reacquired."
            self._native_command_log(
                f"BEST TARGET NOT REACQUIRED | candidates={len(valid)} observations={len(observations)} taps={taps}"
            )
            return

        legal_suffix = ""
        if str(found.get("legal") or "UNKNOWN").upper() not in {"UNKNOWN", "-"}:
            legal_suffix = f" • {str(found['legal']).upper()}"
        self.native_command_status = f"Best target found: {found['ship']}{legal_suffix}."
        self._native_command_log(
            f"BEST TARGET | ship={found['ship']} legal={found.get('legal','UNKNOWN')} score={current_best['score']} observations={len(observations)} reacquire_taps={taps}"
        )
        try:
            self._qml_best_target_history.append(
                f"{time.strftime('%H:%M:%S')}  SELECT | {found['ship']} | {found.get('legal','UNKNOWN')} | score={current_best['score']} | taps={taps}"
            )
        except Exception:
            pass

    def start_find_best_target(self):
        self._native_begin("Find Best Target", self._find_best_target_worker)

    def _dynamic_pips_apply_now(self, mode, reason):
        mode_key = str(mode or "").upper()
        # Emergency Egress is the absolute automation owner. No delayed Dynamic
        # PIPs transaction, hardpoint latch, station profile, or manual-override
        # bookkeeping may countermand the explicit escape sequence.
        if self.egress_phase != "IDLE" and mode_key != "EGRESS":
            self._dynamic_pips_log(f"{mode} IMMEDIATE BLOCKED | Emergency Egress owns distributor | {reason}")
            return False
        if bool(getattr(self, "_qml_dynamic_pips_manual_override", False)) and mode_key != "EGRESS":
            self._dynamic_pips_log(f"{mode} IMMEDIATE BLOCKED | pilot manual override | {reason}")
            return False
        # Hardpoints normally own the distributor, except when Emergency Egress
        # explicitly asks for the ENG-heavy escape profile.
        if self._qml_weapons_priority_active() and mode_key not in {"WEAPONS", "COMBAT", "EGRESS"}:
            self._dynamic_pips_log(f"{mode} IMMEDIATE BLOCKED | hardpoints own distributor | {reason}")
            return False
        return super()._dynamic_pips_apply_now(mode, reason)

    def _maybe_station_safety_pips(self):
        if self._wizard_runtime_paused():
            return
        if self.egress_phase != "IDLE":
            self._station_safety_pips_release("Emergency Egress owns distributor")
            return
        if bool(getattr(self, "_qml_dynamic_pips_manual_override", False)):
            self._station_safety_pips_release("Pilot manual PIP override owns distributor")
            return
        if bool(self.dynamic_pips_var.get()) and self._qml_weapons_priority_active():
            self._station_safety_pips_release("Hardpoints deployed // weapons priority owns distributor")
            return
        return super()._maybe_station_safety_pips()

    @staticmethod
    def _qml_dynamic_pips_voice_phrase(mode):
        mode = str(mode or "").upper()
        if mode in {"WEAPONS", "COMBAT"}:
            return "Power to weapons."
        if mode in {"RECOVERY", "STATION_SAFETY"}:
            return "Power to shields."
        if mode in {"CRUISE", "EGRESS"}:
            return "Power to engines."
        if mode == "BALANCED":
            return "Power balanced."
        return ""

    def _qml_announce_verified_dynamic_pips(self, pending_before):
        """Speak one fixed phrase only after Elite telemetry verifies the requested state."""
        if not pending_before:
            return
        try:
            mode, due, expected = pending_before
        except Exception:
            return
        if time.monotonic() < float(due or 0.0):
            return
        try:
            if list(self._dynamic_pips_current()) != list(expected):
                return
        except Exception:
            return
        phrase = self._qml_dynamic_pips_voice_phrase(mode)
        if not phrase:
            return
        last_phrase = getattr(self, "_qml_last_dynamic_pips_voice_phrase", "")
        last_mono = float(getattr(self, "_qml_last_dynamic_pips_voice_mono", 0.0) or 0.0)
        if phrase == last_phrase and (time.monotonic() - last_mono) < 8.0:
            return
        self._qml_last_dynamic_pips_voice_phrase = phrase
        self._qml_last_dynamic_pips_voice_mono = time.monotonic()
        # Fixed cockpit phrase goes straight to the normal TTS bus. It is never
        # generated or translated by the LLM.
        self._voice_say("HIGH", phrase, kind="PIPS", key=f"pips:{phrase}", cooldown=8.0)

    def _dynamic_pips_desired_mode(self):
        if bool(self.dynamic_pips_var.get()) and self._qml_weapons_priority_active():
            s = self.state_data
            if s.flag("In Main Ship") and not s.flag("Docked") and not s.flag("Supercruise") and not s.flag("FSD Jump"):
                return "WEAPONS"
        return super()._dynamic_pips_desired_mode()

    def _maybe_dynamic_pips(self):
        if self._wizard_runtime_paused():
            return

        if self.egress_phase != "IDLE":
            # Drop any pending WEAPONS verification so it cannot wake up a second
            # later and undo the escape profile. Egress itself drives its proven
            # PIP/throttle/boost/FSD sequence through the locked engine.
            self.dynamic_pip_pending_verify = None
            self.dynamic_pip_candidate = None
            self.dynamic_pip_candidate_since = 0.0
            self._qml_weapons_priority_attempts = 0
            self.dynamic_pip_mode = "EGRESS OWNER"
            self.dynamic_pip_status = f"Emergency Egress owns distributor • {self.egress_phase}."
            return

        self._qml_update_manual_pip_override()
        if bool(getattr(self, "_qml_dynamic_pips_manual_override", False)) and self.egress_phase == "IDLE":
            self.dynamic_pip_mode = "MANUAL OVERRIDE"
            self.dynamic_pip_status = f"Pilot PIP override active • {self._qml_dynamic_pips_manual_override_reason}. Auto Pips will resume after a flight-state transition or explicit resume command."
            return

        weapons_owner = bool(self.dynamic_pips_var.get()) and self._qml_weapons_priority_active()
        if weapons_owner:
            s = self.state_data
            valid_ship_flight = (
                s.flag("In Main Ship")
                and not s.flag("Docked")
                and not s.flag("Supercruise")
                and not s.flag("FSD Jump")
            )
            self._station_safety_pips_release("Hardpoints deployed // absolute weapons priority")
            self.dynamic_pip_mode = "WEAPONS"
            if not valid_ship_flight:
                self.dynamic_pip_status = "WEAPONS priority armed; waiting for normal main-ship flight."
                return

            now = time.monotonic()
            expected = list(legacy.DYNAMIC_PIP_PRESETS["WEAPONS"]["expected"])
            pending = getattr(self, "dynamic_pip_pending_verify", None)

            # One transaction owns the distributor until its verification window closes.
            if pending is not None:
                try:
                    mode, due, pending_expected = pending
                except Exception:
                    mode, due, pending_expected = "WEAPONS", now, expected
                if now < float(due or 0.0):
                    return
                current = self._dynamic_pips_current()
                self.dynamic_pip_pending_verify = None
                if current == expected:
                    self.dynamic_pip_last_applied = "WEAPONS"
                    self._qml_weapons_priority_attempts = 0
                    self.dynamic_pip_status = "WEAPONS verified: 1 SYS / 1 ENG / 4 WEP."
                    self._dynamic_pips_log(f"VERIFIED WEAPONS | {self._dynamic_pips_display(current)}")
                    self._qml_announce_verified_dynamic_pips(("WEAPONS", due, expected))
                else:
                    attempts = int(getattr(self, "_qml_weapons_priority_attempts", 0) or 0)
                    self.dynamic_pip_status = (
                        f"WEAPONS verification mismatch ({self._dynamic_pips_display(current)}); "
                        + ("one retry remains." if attempts < 2 else "retry limit reached; no loop will be started.")
                    )
                    self._dynamic_pips_log(f"VERIFY MISMATCH WEAPONS | expected {expected} | observed {current} | attempt {attempts}/2")
                return

            current = self._dynamic_pips_current()
            if current == expected:
                self.dynamic_pip_last_applied = "WEAPONS"
                self._qml_weapons_priority_attempts = 0
                self.dynamic_pip_status = "WEAPONS held: 1 SYS / 1 ENG / 4 WEP."
                return

            if getattr(self, "native_command_busy", False):
                self.dynamic_pip_status = "WEAPONS priority waiting for the current cockpit command."
                return
            if (now - float(getattr(self, "dynamic_pip_last_command_mono", 0.0) or 0.0)) < legacy.DYNAMIC_PIP_MIN_COMMAND_GAP_SECONDS:
                return
            attempts = int(getattr(self, "_qml_weapons_priority_attempts", 0) or 0)
            if attempts >= 2:
                self.dynamic_pip_status = "WEAPONS priority could not be verified after two attempts; automation is holding instead of looping."
                return

            applied = super()._dynamic_pips_apply_now(
                "WEAPONS",
                f"Hardpoints deployed // exclusive weapons transaction attempt {attempts + 1}/2",
            )
            if applied:
                self._qml_weapons_priority_attempts = attempts + 1
                self.dynamic_pip_candidate = "WEAPONS"
                self.dynamic_pip_candidate_since = now
            return

        # Hardpoints have genuinely retracted. Release the exclusive latch and let
        # the proven .95 state machine handle cruise/recovery/station behavior again.
        self._qml_weapons_priority_attempts = 0
        return super()._maybe_dynamic_pips()

    def _maybe_auto_heavy_power_plant(self):
        if self._wizard_runtime_paused():
            return
        return super()._maybe_auto_heavy_power_plant()

    def _maybe_auto_chaff(self):
        if self._wizard_runtime_paused():
            return
        return super()._maybe_auto_chaff()

    def _maybe_emergency_egress(self):
        if self._wizard_runtime_paused():
            return
        return super()._maybe_emergency_egress()

    def _maybe_execute_pending_trade_loop_route(self):
        if self._wizard_runtime_paused():
            return
        return super()._maybe_execute_pending_trade_loop_route()

    def _maybe_run_trade_loop_auto_fsd_prep(self):
        if self._wizard_runtime_paused():
            return
        return super()._maybe_run_trade_loop_auto_fsd_prep()

    def _maybe_auto_route_health(self):
        if self._wizard_runtime_paused():
            return
        return super()._maybe_auto_route_health()


    def _stop_all_sfx(self, *, except_manager=None, cancel_wizard_narration=False):
        """Only one Bridge sound effect may own the output at a time."""
        managers = [
            getattr(self, "sfx_manager", None),
            getattr(self, "_qml_wizard_sfx_manager", None),
            getattr(self, "_qml_ui_sfx_manager", None),
        ]
        for manager in managers:
            if manager is None or manager is except_manager:
                continue
            try:
                manager.stop()
            except Exception:
                pass
        if cancel_wizard_narration:
            self._wizard_music_active = False
            # The welcome still waits for completion if another cue replaces music.

    def _sfx_play(self, key, *, cooldown=0.0, force=False, allow_disabled=False):
        # Preserve .95 cooldown semantics, but make playback globally exclusive:
        # a new Bridge SFX immediately stops whichever SFX is already playing.
        now = time.monotonic()
        key = str(key or "").strip().lower()
        last = float(self.sfx_last_by_key.get(key, 0.0) or 0.0)
        if not force and cooldown and (now - last) < float(cooldown):
            return False
        if self._wizard_runtime_paused():
            self._wizard_narration_serial = int(getattr(self, "_wizard_narration_serial", 0)) + 1
            self._wizard_narration_pending = False
            self._wizard_interrupt_voice()
            self.sfx_manager.wait_for_voice = self._wizard_voice_busy
        else:
            self.sfx_manager.wait_for_voice = None
        self._stop_all_sfx(except_manager=self.sfx_manager, cancel_wizard_narration=True)
        try:
            self.sfx_manager.stop()
        except Exception:
            pass
        played = self.sfx_manager.play(key, force=True if force else False, allow_disabled=allow_disabled)
        if played:
            self.sfx_last_by_key[key] = now
        return played

    def _wizard_sfx_manager(self):
        manager = getattr(self, "_qml_wizard_sfx_manager", None)
        if manager is None:
            manager = legacy.BridgeSFXManager(
                Path(__file__).resolve().parent / "Sounds",
                legacy.BRIDGE_DATA_DIR / "sfx_cache_wizard",
                legacy.CUSTOM_SFX_DIR,
            )
            self._qml_wizard_sfx_manager = manager
        # Voice prewarming is silent and must not delay the opening music.
        manager.wait_for_voice = lambda: bool(getattr(self.voice_engine, "_qml_speech_active", False))
        manager.configure(
            enabled=bool(self.sfx_enabled_var.get()),
            # Keep the existing quieter intro level; narration follows completion.
            volume=max(0.0, min(100.0, float(self.sfx_volume_var.get()) * 0.50)),
            custom_overrides=self.sfx_custom_files,
            enabled_by_key=self.sfx_event_enabled,
            output_device=self.sfx_output_device_var.get(),
        )
        return manager

    def _wizard_music_start(self, *, allow_disabled=False, initial_step=None):
        try:
            if initial_step is None and getattr(self, "_wizard_session_open", False):
                # Explicit music previews supersede speech, not the current page.
                self._wizard_narration_serial = int(getattr(self, "_wizard_narration_serial", 0)) + 1
                self._wizard_narration_pending = False
                self._wizard_interrupt_voice()
            manager = self._wizard_sfx_manager()
            self._stop_all_sfx(except_manager=manager, cancel_wizard_narration=False)
            try:
                manager.stop()
            except Exception:
                pass
            ok = bool(manager.play("startup", force=True, allow_disabled=allow_disabled))
            self._wizard_music_active = ok
            generation = int(getattr(self, "_wizard_music_generation", 0) or 0) + 1
            self._wizard_music_generation = generation
            if initial_step is not None:
                self._wizard_pending_step = max(0, min(6, int(initial_step)))
                self._wizard_last_narrated_step = -1
                self._wizard_narration_pending = False
                self.after(40, lambda gen=generation: self._wizard_welcome_after_music(gen))
            return ok
        except Exception as exc:
            self._wizard_music_active = False
            self._native_set_status(f"Wizard music unavailable: {exc}")
            if initial_step is not None:
                self._wizard_narrate_step(initial_step, play_cue=False)
            return False

    def _wizard_open(self, step=0):
        """Open one wizard session without replaying the welcome on frontend resyncs."""
        try:
            step = max(0, min(6, int(step)))
        except Exception:
            step = 0

        already_open = bool(getattr(self, "_wizard_session_open", False))
        self._set_qml_wizard_runtime_gate(True)

        if already_open:
            if step != int(getattr(self, "_wizard_pending_step", -1)):
                self._wizard_narrate_step(step)
                return True
            # QML can resync after a transient transport/state update. Resync is
            # deliberately silent. Only the physical Back/Next action may narrate.
            self._native_set_status(f"Guided setup resynced // page {step + 1}/7 // narration unchanged.")
            print(f"[WIZARD] resync page={step + 1} silent", flush=True)
            return True

        self._wizard_session_open = True
        self._wizard_pending_step = step
        try:
            self._demo_transcript_reset()
        except Exception:
            pass
        print(f"[WIZARD] open page={step + 1} welcome_once=true", flush=True)
        self._wizard_interrupt_voice()
        ok = self._wizard_music_start(initial_step=step)
        self._native_set_status(
            "Guided setup opened // wizard music queued // operational runtime paused."
            if ok else
            "Guided setup opened // music unavailable; wizard welcome queued // operational runtime paused."
        )
        return ok

    def _wizard_voice_busy(self):
        """Return True while the voice worker is still synthesizing or playing audio."""
        try:
            status = str(getattr(self.voice_engine, "status", "") or "").strip().upper()
            return bool(getattr(self.voice_engine, "_qml_speech_active", False)) or status.startswith(("LOADING", "SYNTHESIZING", "WARMING")) or "SPEAKING" in status
        except Exception:
            return False

    def _wizard_clear_voice_queue(self):
        """Discard queued speech so only the newest wizard page can speak."""
        try:
            while True:
                self.voice_engine.queue.get_nowait()
        except queue.Empty:
            pass
        except Exception:
            pass

    def _pilot_interrupt_voice_for_ptt(self):
        """Barge-in policy: a PTT press immediately owns the voice bus."""
        global _WIZARD_VOICE_INTERRUPT
        current_cancel = _WIZARD_VOICE_INTERRUPT
        current_cancel.set()
        # New speech queued after the PTT press must not inherit the cancelled token.
        _WIZARD_VOICE_INTERRUPT = threading.Event()
        self._wizard_clear_voice_queue()
        try:
            self.voice_engine._stop_windows_process()
        except Exception:
            pass
        if os.name == "nt":
            try:
                winsound.PlaySound(None, 0)
            except Exception:
                pass
        try:
            self.voice_engine.status = "LISTENING • pilot voice priority"
        except Exception:
            pass
        print("[VOICE] PTT barge-in // active speech cancelled // queued chatter cleared", flush=True)

    def _wizard_interrupt_voice(self):
        """Cancel active wizard speech and discard anything waiting behind it."""
        global _WIZARD_VOICE_INTERRUPT
        _WIZARD_VOICE_INTERRUPT.set()
        # Never clear an old job's cancellation when the next page becomes ready.
        _WIZARD_VOICE_INTERRUPT = threading.Event()
        _WIZARD_VOICE_INTERRUPT.set()
        self._wizard_clear_voice_queue()
        if not legacy.SOUNDDEVICE_AVAILABLE and os.name == "nt":
            winsound.PlaySound(None, 0)
        try:
            self.voice_engine._stop_windows_process()
        except Exception:
            pass

    def _wizard_release_interrupt_when_idle(self, attempt=0):
        """Keep cancellation asserted until stale synthesis/playback has actually exited."""
        if self._wizard_session_open:
            return
        if self._wizard_voice_busy():
            self.after(40, lambda n=attempt + 1: self._wizard_release_interrupt_when_idle(n))
            return
        _WIZARD_VOICE_INTERRUPT.clear()

    def _wizard_close(self):
        """Hard-stop all wizard audio, then release normal Bridge runtime."""
        if not getattr(self, "_wizard_session_open", False) and not self._wizard_runtime_paused():
            return
        self._wizard_session_open = False
        self._wizard_narration_serial = int(getattr(self, "_wizard_narration_serial", 0) or 0) + 1
        self._wizard_narration_pending = False
        self._wizard_pending_step = -1
        self._wizard_last_narrated_step = -1
        self._wizard_speaking_visual = False
        self._wizard_ptt_test_armed = False
        self._wizard_voice_test_serial = int(getattr(self, "_wizard_voice_test_serial", 0) or 0) + 1
        try:
            if bool(getattr(self, "_wizard_ptt_test_recording", False)):
                self._wizard_ptt_test_stop.set()
        except Exception:
            pass
        self._wizard_interrupt_voice()
        self._wizard_music_stop()
        self._stop_all_sfx()
        self._set_qml_wizard_runtime_gate(False)
        self._native_set_status("Guided setup closed // wizard speech queue cancelled // Bridge runtime released.")
        # Do not clear the cancellation signal on a blind timer. A Supertonic job may
        # still be synthesizing even though its queued page was superseded. Keep the
        # gate asserted until that job reaches playback and exits, then allow normal
        # Bridge speech to resume.
        self.after(40, self._wizard_release_interrupt_when_idle)

    def _wizard_music_stop(self):
        try:
            manager = getattr(self, "_qml_wizard_sfx_manager", None)
            if manager is not None:
                manager.stop()
        except Exception:
            pass
        self._wizard_music_active = False
        self._wizard_music_generation = int(getattr(self, "_wizard_music_generation", 0) or 0) + 1

    def _wizard_page_text(self, step):
        step = max(0, min(6, int(step)))
        pages = {
            0: "Welcome to E leet A I Bridge, {name}. First, choose how you want to use the Bridge. Core Bridge gives you cockpit controls, automation, and voice feedback without an A I account. A I Co-Pilot adds conversational voice control and uses an Open A I API key. If you are unsure, choose A I Co-Pilot. You can change this later. Choose a mode, then press Next.",
            1: "Choose your Bridge speakers and microphone. Use Test Bridge Voice to check the sound. When it sounds right, press Next.",
            2: "A I Co-Pilot needs an Open A I API key. If you do not have one, choose Help Getting an API Key for simple instructions. Paste your key below, then choose Save and Verify. If you prefer, switch to Core Bridge and add A I Co-Pilot later.",
            3: "Choose how the Bridge should sound and what it should call you. Balanced is the default. Use Test to hear your settings, then press Next.",
            4: "Now set Push to Talk for A I Co-Pilot. The keyboard and Stream Deck shortcut is Control Alt Shift V. You can also map a HOTAS or gamepad button. Test Push to Talk, then press Next.",
            5: "The tutorial is available from the main Bridge after setup.",
            6: "Setup is complete, {name}. E leet A I Bridge is ready. Select Enter Bridge to continue.",
        }
        return pages[step].format(name=self._commander_address())

    def _wizard_voice_has_pending(self):
        try:
            return self._wizard_voice_busy() or int(self.voice_engine.queue.qsize()) > 0
        except Exception:
            return self._wizard_voice_busy()

    def _wizard_monitor_speaking_visual(self, token, quiet_checks=0):
        if not self._wizard_runtime_paused():
            self._wizard_speaking_visual = False
            return
        if int(getattr(self, "_wizard_visual_token", -1)) != int(token):
            return
        if self._wizard_voice_has_pending():
            self._wizard_speaking_visual = True
            self.after(90, lambda: self._wizard_monitor_speaking_visual(token, 0))
            return
        # Hold the yellow state across tiny gaps between sentence chunks so the UI
        # reads as one explanation rather than blinking between READY/SPEAKING.
        if quiet_checks < 4:
            self.after(90, lambda: self._wizard_monitor_speaking_visual(token, quiet_checks + 1))
            return
        self._wizard_speaking_visual = False

    def _wizard_say(self, text):
        try:
            if self._voice_level_value() <= 0 or not self._wizard_runtime_paused():
                return False
            text = str(text or "").strip()
            if not text:
                return False
            self.voice_last_announcement = text
            self.voice_last_kind = "WIZARD"
            self._wizard_speaking_visual = True
            self._wizard_visual_token = int(getattr(self, "_wizard_visual_token", 0) or 0) + 1
            visual_token = self._wizard_visual_token
            self.voice_history.append(f"{time.strftime('%H:%M:%S')}  WIZARD | {text}")
            self._demo_transcript_append("WIZARD", f"PAGE {int(getattr(self, '_wizard_pending_step', 0) or 0) + 1}", text)

            # Fixed wizard paragraphs used to be synthesized as one large Supertonic
            # request, which created a noticeable pause before the first word. Queue
            # sentence-sized chunks instead. The first short sentence starts quickly,
            # and Back/Next can discard the remaining chunks immediately.
            chunks = [part.strip() for part in re.split(r"(?<=[.!?])\s+", text) if part.strip()]
            if not chunks:
                chunks = [text]
            queued = 0
            for chunk in chunks:
                if not self._wizard_runtime_paused() or _WIZARD_VOICE_INTERRUPT.is_set():
                    break
                if self.voice_engine.say(chunk, speed_scale=0.98):
                    queued += 1
            self.refresh_preferences_widgets()
            self.after(90, lambda token=visual_token: self._wizard_monitor_speaking_visual(token))
            return queued > 0
        except Exception:
            return False

    def _wizard_voice_test(self):
        """Audition the selected TTS profile without cutting off the wizard guide.

        The voice/talk-level page is intentionally interactive while narration is
        playing. A Test Commander click therefore waits for the current guide paragraph
        to finish instead of barging in. A newer test click supersedes an older pending
        test, while Back/Next still own page-narration interruption.
        """
        if not self._wizard_runtime_paused():
            return self._voice_test()
        self._wizard_voice_test_serial = int(getattr(self, "_wizard_voice_test_serial", 0) or 0) + 1
        serial = self._wizard_voice_test_serial

        def _start(attempt=0):
            if not self._wizard_runtime_paused():
                return
            if int(getattr(self, "_wizard_voice_test_serial", 0)) != serial:
                return
            if bool(getattr(self, "_wizard_narration_pending", False)) or self._wizard_voice_has_pending() or self._wizard_audio_busy():
                self.after(70, lambda: _start(attempt + 1))
                return
            _WIZARD_VOICE_INTERRUPT.clear()
            self._wizard_speaking_visual = True
            self._wizard_visual_token = int(getattr(self, "_wizard_visual_token", 0) or 0) + 1
            visual_token = self._wizard_visual_token
            self._voice_test()
            self.after(90, lambda token=visual_token: self._wizard_monitor_speaking_visual(token))

        self.after(40, _start)

    def _wizard_welcome_after_music(self, generation):
        if int(generation) != int(getattr(self, "_wizard_music_generation", 0) or 0):
            return
        if not self._wizard_runtime_paused():
            return
        if self._wizard_audio_busy():
            self.after(40, lambda: self._wizard_welcome_after_music(generation))
            return
        self._wizard_music_active = False
        self._wizard_narrate_step(self._wizard_pending_step, play_cue=False)

    def _wizard_audio_busy(self):
        return any(manager is not None and manager.is_playing() for manager in (
            getattr(self, "sfx_manager", None),
            getattr(self, "_qml_wizard_sfx_manager", None),
            getattr(self, "_qml_ui_sfx_manager", None),
        ))

    def _wizard_narrate_step(self, step, *, play_cue=True):
        if not self._wizard_runtime_paused():
            return
        try:
            step = max(0, min(6, int(step)))
        except Exception:
            step = 0
        if step == 4:
            self._arm_wizard_ptt_test()
        else:
            self._wizard_ptt_test_armed = False
            try:
                if bool(getattr(self, "_wizard_ptt_test_recording", False)):
                    self._wizard_ptt_test_stop.set()
            except Exception:
                pass
        previous_pending = int(getattr(self, "_wizard_pending_step", -1))
        already_narrated = int(getattr(self, "_wizard_last_narrated_step", -1))
        pending_active = bool(getattr(self, "_wizard_narration_pending", False))
        if step == previous_pending and (step == already_narrated or pending_active):
            return
        # Back/Next owns the wizard voice bus. Any deferred Test Commander request
        # from the page being left is invalid once navigation begins.
        self._wizard_voice_test_serial = int(getattr(self, "_wizard_voice_test_serial", 0) or 0) + 1
        self._wizard_pending_step = step
        self._wizard_narration_pending = True
        self._wizard_speaking_visual = True
        narration = self._wizard_page_text(step)
        print(f"[WIZARD] narrate request page={step + 1} last={already_narrated + 1 if already_narrated >= 0 else 0}", flush=True)
        # A page change supersedes old speech. Set the host-owned cancellation
        # signal first so an active Supertonic RawOutputStream exits on its next
        # audio block, then clear anything stale from the queue. Windows fallback
        # is interrupted by terminating its dedicated speech process.
        self._wizard_interrupt_voice()
        serial = int(getattr(self, "_wizard_narration_serial", 0) or 0) + 1
        self._wizard_narration_serial = serial

        # Every page change gets one confirmation cue, followed by the narration
        # captured for that exact page. Newer page changes invalidate older queued
        # callbacks so stale welcome text cannot replay on later pages.
        if play_cue:
            self._wizard_music_stop()
        cue_pending = play_cue
        delay_ms = 40
        self._native_set_status(f"Guided setup page {step + 1}/7 // page-specific narration queued.")

        def _speak_page(value=step, text=narration, token=serial, attempt=0):
            nonlocal cue_pending
            if not self._wizard_runtime_paused():
                return
            if int(getattr(self, "_wizard_narration_serial", -1)) != token:
                return
            if int(getattr(self, "_wizard_pending_step", -1)) != value:
                return
            # Keep the stop signal asserted until the previous page has genuinely
            # exited. This closes the race where the new page cleared cancellation
            # before the old Welcome stream noticed it.
            if self._wizard_voice_busy():
                self.after(40, lambda: _speak_page(value, text, token, attempt + 1))
                return
            if cue_pending:
                cue_pending = False
                self._ui_sfx_play("ui_nav")
                self.after(40, _speak_page)
                return
            if self._wizard_audio_busy():
                self.after(40, lambda: _speak_page(value, text, token, attempt + 1))
                return
            _WIZARD_VOICE_INTERRUPT.clear()
            if value == 6:
                print("[WIZARD] final-page voice start // health/UI cues deferred until narration clears", flush=True)
            ok = self._wizard_say(text)
            self._wizard_narration_pending = False
            print(f"[WIZARD] narrate queued page={value + 1} ok={bool(ok)} chunks=sentence", flush=True)
            if ok:
                self._wizard_last_narrated_step = value

        self.after(delay_ms, _speak_page)

    def _ui_sfx_play(self, key):
        try:
            # Wizard controls are live while the guide speaks. UI beeps must never
            # cancel narration. The page-navigation path itself performs the only
            # intentional Back/Next interruption; ordinary selection/health cues wait
            # for the current wizard voice queue to drain.
            manager = getattr(self, "_qml_ui_sfx_manager", None)
            if manager is None:
                manager = legacy.BridgeSFXManager(
                    Path(__file__).resolve().parent / "Sounds",
                    legacy.BRIDGE_DATA_DIR / "sfx_cache_ui",
                    legacy.CUSTOM_SFX_DIR,
                )
                self._qml_ui_sfx_manager = manager
            manager.wait_for_voice = self._wizard_voice_has_pending if getattr(self, "_wizard_session_open", False) else None
            manager.configure(
                enabled=bool(self.sfx_enabled_var.get()),
                volume=max(0.0, min(100.0, float(self.sfx_volume_var.get()))),
                custom_overrides=self.sfx_custom_files,
                enabled_by_key=self.sfx_event_enabled,
                output_device=self.sfx_output_device_var.get(),
            )
            self._stop_all_sfx(except_manager=manager, cancel_wizard_narration=False)
            try:
                manager.stop()
            except Exception:
                pass
            return manager.play(key, force=True)
        except Exception:
            return False

    def _qml_startup_welcome(self):
        try:
            if self._wizard_runtime_paused():
                return
            if _WIZARD_VOICE_INTERRUPT.is_set() or self._wizard_audio_busy():
                self.after(80, self._qml_startup_welcome)
                return
            if self._voice_level_value() <= 0:
                return
            text = f"Welcome, {self._commander_address()}. Elite AI Bridge is online and ready."
            self.voice_last_announcement = text
            self.voice_last_kind = "STARTUP"
            self.voice_history.append(f"{time.strftime('%H:%M:%S')}  STARTUP | {text}")
            self.voice_engine.say(text, speed_scale=1.0)
            self.refresh_preferences_widgets()
        except Exception:
            pass

    @staticmethod
    def _qml_prompt_explicitly_requests_guidance(prompt):
        raw = " ".join(str(prompt or "").strip().lower().split())
        markers = (
            "help me", "can you help", "how do i", "how can i", "how does",
            "show me how", "show me where", "walk me through", "teach me",
            "explain", "what does", "what is this", "training", "tutorial",
        )
        return bool(raw == "help" or raw.startswith("help ") or any(m in raw for m in markers))

    def _page_navigation_intent(self, prompt):
        raw = " ".join(str(prompt or "").strip().lower().split())
        if not raw or self._qml_prompt_explicitly_requests_guidance(raw):
            return None
        nav_markers = ("show me", "show", "open", "go to", "take me to", "switch to", "bring up", "display")
        if not any(raw == marker or raw.startswith(marker + " ") for marker in nav_markers):
            return None
        page_terms = [
            (2, "", ("combat", "combat screen", "combat page")),
            (3, "", ("trade", "trade screen", "trade page")),
            (1, "", ("navigation", "navigation screen", "nav screen", "nav page")),
            (4, "", ("colonization", "colonisation", "colony")),
            (5, "", ("commander", "commander records", "records")),
            (6, "", ("ai", "ai and voice", "voice settings")),
            (7, "", ("audio", "audio settings")),
            (10, "", ("controls", "control settings", "bindings")),
            (9, "", ("display settings", "display")),
            (8, "", ("setup", "settings")),
            (0, "", ("overview", "live screen", "home screen")),
        ]
        for page, workspace, terms in page_terms:
            if any(term in raw for term in terms):
                return {"page": page, "workspace": workspace}
        return None

    def _guided_help_intent(self, prompt):
        """Route obvious how-to/help requests locally to the saved ? tours.

        This deliberately avoids treating a beginner question as an operational
        search form. Real action requests still fall through to the normal LLM/tool loop.
        """
        raw = " ".join(str(prompt or "").strip().lower().split())
        if not raw:
            return None

        guidance_markers = (
            "help me", "can you help", "how do i", "how can i", "how does",
            "show me how", "show me where", "where is", "where do i",
            "walk me through", "teach me", "explain", "what does", "what is this",
        )
        if not (raw == "help" or raw.startswith("help ") or any(marker in raw for marker in guidance_markers)):
            return None

        page = None
        workspace = ""

        # Strong domain cues first so 'trade route' goes to Trade rather than Navigation.
        if any(word in raw for word in ("trade", "trading", "commodity", "market", "profit")):
            page = 3
            if any(phrase in raw for phrase in ("best trade", "best route", "most profitable", "best profit")):
                workspace = "best_trade"
            elif "loop" in raw:
                workspace = "trade_loop"
            elif any(phrase in raw for phrase in ("route finder", "commodity route", "trade route", "route for")):
                workspace = "route_finder"
        elif any(word in raw for word in ("combat", "res ", " res", "bounty", "fighter", "target", "haz res", "high res")):
            page = 2
            if any(phrase in raw for phrase in ("res", "resource extraction", "high res", "haz res")):
                workspace = "res_finder"
        elif any(word in raw for word in ("colonization", "colonisation", "colony", "project material", "system project")):
            page = 4
        elif any(word in raw for word in ("commander", "cargo", "record", "history", "session record")):
            page = 5
        elif any(word in raw for word in ("audio", "speaker", "speakers", "microphone", "sound effect", "volume")):
            page = 7
        elif any(word in raw for word in ("push to talk", "ptt", "controller", "binding", "hotas", "stream deck", "control mapping")):
            page = 10
            workspace = "ptt" if ("push to talk" in raw or "ptt" in raw) else "bindings"
        elif any(word in raw for word in ("luna", "ai voice", "personality", "talkative", "voice setting", "mission context")):
            page = 6
        elif any(word in raw for word in ("display", "monitor", "fullscreen", "resolution", "window mode")):
            page = 9
        elif any(word in raw for word in ("setup", "preference", "setting")):
            page = 8
        elif any(word in raw for word in ("navigation", "navigate", "galaxy", "jump", "bookmark", "home system", "dock", "launch")):
            page = 1
            if any(word in raw for word in ("dock", "launch", "bookmark", "home system")):
                workspace = "shortcuts"
            elif any(phrase in raw for phrase in ("plot", "destination", "route")):
                workspace = "route"
        elif any(word in raw for word in ("live", "home screen", "overview", "bridge modules")):
            page = 0

        if page is None:
            try:
                page = max(0, min(10, int(getattr(self, "_qml_ui_context_page", 0) or 0)))
            except Exception:
                page = 0

        names = self._UI_PAGE_NAMES
        page_name = names.get(page, "OVERVIEW")
        focus_step = self._focused_help_step(page, workspace) if workspace else None
        if focus_step is None:
            guide = (page, 0, None)
            spoken = f"Sure. I'll show you the {page_name.title()} page."
        else:
            guide = (page, focus_step, focus_step)
            pretty = workspace.replace("_", " ").title()
            spoken = f"Sure. I'll show you {pretty}."
        return {"page": page, "workspace": workspace, "guide": guide, "spoken": spoken}

    _PUBLIC_TALK_PROFILES = {
        "OFF": ("LOW", "Quiet"),
        "IMPORTANT": ("MED", "Balanced"),
        "MOST": ("HIGH", "Talkative"),
    }

    def _public_talk_profile_current(self):
        attention = str(self.voice_attention_mode_var.get() or "IMPORTANT").strip().upper()
        if attention in self._PUBLIC_TALK_PROFILES:
            return attention
        level = str(self.voice_level_var.get() or "MED").strip().upper()
        return {"LOW": "OFF", "MED": "IMPORTANT", "HIGH": "MOST"}.get(level, "IMPORTANT")

    def _public_talk_profile_apply(self, attention):
        attention = str(attention or "IMPORTANT").strip().upper()
        if attention not in self._PUBLIC_TALK_PROFILES:
            attention = "IMPORTANT"
        level, label = self._PUBLIC_TALK_PROFILES[attention]
        self.voice_attention_mode_var.set(attention)
        self.voice_level_var.set(level)
        self._save_automation_config()
        try:
            self.refresh_preferences_widgets()
        except Exception:
            pass
        self.voice_history.append(
            f"{time.strftime('%H:%M:%S')}  PROFILE | TALK/ATTENTION {attention} // {level} // voice command"
        )
        self._native_set_status(f"Talk level // {label.upper()} // commentary profile {level}")
        return attention, level, label

    def _natural_talk_level_intent(self, prompt):
        """Resolve short natural-language chatter requests without an LLM round trip.

        The public three-position talk control deliberately couples legacy chatter
        level and attention mode. This prevents phrases like 'talk less' from
        becoming an ambiguous settings conversation while the pilot is flying.
        """
        raw = " ".join(str(prompt or "").strip().lower().split())
        if not raw:
            return None
        clean = re.sub(r"[^a-z0-9% ]+", " ", raw)
        clean = " ".join(clean.split())
        words = clean.split()
        # Keep this deterministic shortcut narrow. Longer conversational prompts
        # still go through Smart AI normally.
        if len(words) > 10:
            return None

        explicit = None
        quiet_markers = (
            "verbosity low", "voice level low", "talk level low", "set it to low",
            "set verbosity low", "set voice level low", "quiet mode", "be quiet",
            "mute commentary", "minimal commentary",
        )
        balanced_markers = (
            "verbosity medium", "verbosity med", "voice level medium", "voice level med",
            "talk level medium", "talk level med", "set verbosity medium",
            "set verbosity med", "balanced mode", "balanced commentary",
        )
        talkative_markers = (
            "verbosity high", "voice level high", "talk level high", "set verbosity high",
            "talkative mode", "maximum commentary",
        )
        if any(marker in clean for marker in quiet_markers):
            explicit = "OFF"
        elif any(marker in clean for marker in balanced_markers):
            explicit = "IMPORTANT"
        elif any(marker in clean for marker in talkative_markers):
            explicit = "MOST"
        if explicit:
            return explicit

        lower_markers = (
            "talk less", "speak less", "be less chatty", "less chatty",
            "shorter answers", "shorter responses", "keep it brief",
            "keep things brief", "less commentary", "reduce verbosity",
            "lower verbosity", "less verbose", "be less verbose",
        )
        higher_markers = (
            "talk more", "speak more", "be more chatty", "more chatty",
            "more commentary", "give me more detail", "more detail",
            "increase verbosity", "higher verbosity", "more verbose",
            "be more verbose", "be more talkative",
        )
        current = self._public_talk_profile_current()
        order = ["OFF", "IMPORTANT", "MOST"]
        idx = order.index(current)
        if any(marker in clean for marker in lower_markers):
            return order[max(0, idx - 1)]
        if any(marker in clean for marker in higher_markers):
            return order[min(len(order) - 1, idx + 1)]
        return None

    def _direct_departure_intent(self, prompt):
        """Resolve unambiguous departure commands locally from live flight state.

        This removes the LLM ambiguity seen in beta logs where a docked commander
        had to confirm 'launch' several times, and keeps 'clear and jump now'
        separate from the persistent after-launch session rule.
        """
        raw = " ".join(str(prompt or "").strip().lower().split())
        clean = re.sub(r"[^a-z0-9 ]+", " ", raw)
        clean = " ".join(clean.split())
        if not clean:
            return None

        # Setting language must never be mistaken for an immediate departure.
        if any(marker in clean for marker in ("automatic", "automatically", "after launch", "session rule", "toggle rule", "enable rule", "disable rule")):
            return None

        docked = bool(self.state_data.flag("Docked"))
        launch_phrases = {
            "launch", "launch us", "launch the ship", "launch from station",
            "launch from the station", "take off", "take us off", "depart",
            "depart station", "depart the station", "leave station",
            "leave the station", "undock", "get us out of here",
            "get us out of the station", "get me out of here",
        }
        if docked and clean in launch_phrases:
            return "launch"

        clear_phrases = {
            "clear and jump", "clear and jump now", "clear station and jump",
            "clear the station and jump", "clear station then jump",
            "clear the station then jump", "clear station plus fsd",
            "clear station and fsd",
        }
        if not docked and clean in clear_phrases:
            return "clear"

        sco_phrases = {
            "sco", "engage sco", "activate sco", "supercruise overcharge",
            "engage supercruise overcharge", "engage overcharge", "activate overcharge",
        }
        if bool(self.state_data.flag("Supercruise")) and clean in sco_phrases:
            return "sco"
        return None

    def request_copilot_command(self):
        if self.copilot_busy:
            return super().request_copilot_command()
        prompt = str(self.copilot_input_var.get() or "").strip()

        direct_departure = self._direct_departure_intent(prompt)
        if direct_departure is not None:
            self.copilot_busy = True
            self.copilot_last_prompt = prompt
            self.copilot_input_var.set("")
            if direct_departure == "launch":
                self.copilot_status = "Starting Auto Launch..."
                try:
                    self.start_auto_launch()
                    text = "Auto launch started."
                    trace = ["direct_departure(auto_launch)"]
                except Exception as exc:
                    text = f"Auto launch could not start: {exc}"
                    trace = ["direct_departure(auto_launch_failed)"]
            elif direct_departure == "clear":
                self.copilot_status = "Clearing station and jumping..."
                try:
                    self.start_clear_station_jump()
                    text = "Clear and jump started."
                    trace = ["direct_departure(clear_station_jump)"]
                except Exception as exc:
                    text = f"Clear and jump could not start: {exc}"
                    trace = ["direct_departure(clear_station_jump_failed)"]
            else:
                self.copilot_status = "Engaging Supercruise Overcharge..."
                try:
                    if not bool(getattr(self.state_data, "fsd_is_sco", False)):
                        raise RuntimeError("the installed Frame Shift Drive is not reporting SCO capability")
                    if self.egress_phase != "IDLE" or self.station_automation_busy or self.native_command_busy:
                        owner = "Emergency Egress" if self.egress_phase != "IDLE" else ("station maintenance" if self.station_automation_busy else self.native_command_name)
                        raise RuntimeError(f"cockpit controls are busy with {owner}")
                    if not self.bindings.keyboard_binding("UseBoostJuice"):
                        raise RuntimeError("UseBoostJuice has no keyboard Primary/Secondary binding in the active Elite preset")
                    def sco_worker():
                        self._native_prepare_cockpit("Cockpit: Supercruise Overcharge")
                        live_binding = self._native_binding("UseBoostJuice")
                        self._native_tap(live_binding, 0.10)
                        self.native_command_status = "Supercruise overcharge command sent."
                        self._native_command_log(f"SUCCESS Cockpit: Supercruise Overcharge | elite_action=UseBoostJuice | binding={self.bindings.binding_display('UseBoostJuice')}")
                    self._native_begin("Cockpit: Supercruise Overcharge", sco_worker)
                    text = "Supercruise overcharge."
                    trace = ["direct_flight(sco)"]
                except Exception as exc:
                    text = f"Supercruise overcharge could not start: {exc}"
                    trace = ["direct_flight(sco_failed)"]
            self.refresh_copilot_widgets()
            self.finish_copilot_command({
                "prompt": prompt, "text": text, "trace": trace,
                "api_calls": 0, "input_tokens": 0, "output_tokens": 0,
            })
            return

        talk_target = self._natural_talk_level_intent(prompt)
        if talk_target is not None:
            _attention, _level, label = self._public_talk_profile_apply(talk_target)
            self.copilot_busy = True
            self.copilot_status = "Adjusting talk level..."
            self.copilot_last_prompt = prompt
            self.copilot_input_var.set("")
            self.refresh_copilot_widgets()
            result = {
                "prompt": prompt,
                "text": f"Talk level {label}.",
                "trace": [f"talk_level({label.lower()})"],
                "api_calls": 0,
                "input_tokens": 0,
                "output_tokens": 0,
            }
            self.finish_copilot_command(result)
            return

        nav_only = self._page_navigation_intent(prompt)
        if nav_only is not None:
            page = int(nav_only["page"])
            workspace = str(nav_only.get("workspace") or "")
            self._qml_set_ui_hint(page, workspace)
            self._qml_guide_after_copilot = None
            self.copilot_busy = True
            self.copilot_status = "Opening Bridge page..."
            self.copilot_last_prompt = prompt
            self.copilot_input_var.set("")
            self.refresh_copilot_widgets()
            page_label = self._UI_PAGE_NAMES.get(page, "OVERVIEW").title()
            result = {
                "prompt": prompt,
                "text": f"{page_label} screen opened.",
                "trace": [f"page_navigation({page_label.lower()})"],
                "api_calls": 0, "input_tokens": 0, "output_tokens": 0,
            }
            self.finish_copilot_command(result)
            return

        guided = self._guided_help_intent(prompt)
        if not guided:
            return super().request_copilot_command()

        page = int(guided["page"])
        workspace = str(guided.get("workspace") or "")
        self._qml_set_ui_hint(page, workspace)
        self._qml_guide_after_copilot = guided["guide"]

        self.copilot_busy = True
        self.copilot_status = "Opening help..."
        self.copilot_last_prompt = prompt
        self.copilot_input_var.set("")
        self.refresh_copilot_widgets()
        result = {
            "prompt": prompt,
            "text": guided["spoken"],
            "trace": [f"guided_help({self._UI_PAGE_NAMES.get(page, 'LIVE')} / {workspace or 'full tour'})"],
            "api_calls": 0,
            "input_tokens": 0,
            "output_tokens": 0,
        }
        self.finish_copilot_command(result)

    def _copilot_tools(self):
        tools = list(super()._copilot_tools())
        # Expand the inherited Bridge settings tools so Smart AI can both read
        # and change the same operational toggles the pilot sees in QML.
        for tool in tools:
            if tool.get("name") == "get_bridge_settings":
                tool["description"] = (
                    "Read the live Elite AI Bridge settings and operational toggles. Use this whenever the commander asks whether Auto Pips/Dynamic Pips, Auto Subsystem, Auto Chaff, Smart Auto AI, commentary triggers, station auto-service toggles, audio toggles, or the clear-and-jump launch rule are on/off or how they are configured."
                )
            elif tool.get("name") == "set_bridge_setting":
                tool["description"] = (
                    "Change one reversible Elite AI Bridge setting at the commander's explicit request. Apply the change in the background and do not navigate away from the commander's current page. For how much the Bridge talks, use voice_attention_mode with Quiet/Low, Balanced/Medium, or Talkative/High semantics; natural 'talk less'/'talk more' requests are handled as one-step changes. This includes the operational QML toggles: Dynamic Pips, Auto Subsystem (automatic Power Plant targeting), Auto Chaff, Smart Auto AI, Trade/Powerplay commentary, Mission commentary, Travel/Docking commentary, Auto Refuel, Auto Repair, Auto Rearm, and the current-session Clear + Jump After Launch rule, plus the existing voice/audio settings."
                )
                props = tool.setdefault("parameters", {}).setdefault("properties", {})
                props.setdefault("setting", {})["enum"] = list(BRIDGE_AI_SETTING_NAMES)
        tools.extend([
            {
                "type": "function",
                "name": "search_res_sites",
                "description": (
                    "Search for nearby High RES or Hazardous RES, meaning Resource Extraction Site, combat areas. Use this only when the commander asks to actually find/search for a RES site. "
                    "For how-to/help questions about RES Finder, use show_bridge_workspace instead. The Bridge automatically opens Combat > RES Finder while a real search runs."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "type": {"type": "string", "enum": ["HIGH", "HAZ"], "description": "RES type to search for."},
                        "radius_ly": {"type": "number", "minimum": 1, "maximum": 250, "description": "Optional search radius in light years."},
                        "max_ls": {"type": "number", "minimum": 100, "maximum": 500000, "description": "Optional maximum RES distance from arrival star."}
                    },
                    "required": ["type"],
                    "additionalProperties": False
                },
                "strict": False
            },
            {
                "type": "function",
                "name": "show_bridge_workspace",
                "description": (
                    "Open the Bridge page that answers a how-to/help/where-is question. For guidance, set guide=true rather than asking the commander for operational search parameters. "
                    "Broad help opens the module's normal beginner tour. Specific help may open tactical, res_finder, best_trade, route_finder, trade_loop, route, or shortcuts and replay the matching saved help segment."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "page": {"type": "string", "enum": ["OVERVIEW", "LIVE", "NAVIGATION", "COMBAT", "TRADE", "COLONIZATION", "COMMANDER", "AI", "AUDIO", "SETUP", "DISPLAY", "CONTROLS"]},
                        "workspace": {"type": "string", "description": "Optional focused subview."},
                        "guide": {"type": "boolean", "description": "Start the saved beginner help after opening the page."}
                    },
                    "required": ["page"],
                    "additionalProperties": False
                },
                "strict": False
            },
            {
                "type": "function",
                "name": "set_cockpit_control",
                "description": (
                    "Set one safe Elite cockpit state using the commander's active Elite keyboard binding and verify the result from Status.json. "
                    "Use this for explicit requests to turn Night Vision or lights on/off, raise/lower landing gear, deploy/retract cargo scoop or hardpoints, "
                    "turn Flight Assist or Silent Running on/off, or switch Combat/Analysis HUD mode. State-aware requests do not toggle an already-correct control back the wrong way."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "control": {"type": "string", "enum": ["night_vision", "ship_lights", "landing_gear", "cargo_scoop", "hardpoints", "flight_assist", "silent_running", "hud_mode"]},
                        "state": {"type": "string", "enum": ["on", "off", "up", "down", "deployed", "retracted", "combat", "analysis"]},
                    },
                    "required": ["control", "state"],
                    "additionalProperties": False,
                },
                "strict": False,
            },
            {
                "type": "function",
                "name": "perform_cockpit_action",
                "description": (
                    "Perform one supported one-shot Elite cockpit command using the commander's CURRENT active keyboard binding. "
                    "Use this for throttle presets and discrete commands such as boost, SCO/supercruise overcharge, chaff, heat sink, shield cell, targeting, fire-group cycling, radar range, maps, FSD/supercruise, wing commands, fighter orders, and panels. "
                    "Natural throttle language maps directly: half speed/half throttle/50 percent = throttle_50; quarter = throttle_25; three quarters = throttle_75; full = throttle_100; stop/zero = throttle_0. "
                    "Never guess a physical key. Bridge resolves the active .binds file at execution time. Weapon-fire and cargo-ejection bindings are intentionally not exposed."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "action": {"type": "string", "enum": list(COCKPIT_ACTIONS.keys())}
                    },
                    "required": ["action"],
                    "additionalProperties": False,
                },
                "strict": False,
            },
            {
                "type": "function",
                "name": "set_power_distribution",
                "description": (
                    "Set the ship distributor directly from an explicit pilot request. shields = 4 SYS / 2 ENG / 0 WEP, weapons = 1 SYS / 1 ENG / 4 WEP, engines = 1 SYS / 4 ENG / 1 WEP, balanced = 2/2/2. "
                    "Direct pilot requests temporarily override Dynamic PIPs so automation will not fight the commander. profile=auto resumes Dynamic PIPs and clears the manual override."
                ),
                "parameters": {"type": "object", "properties": {"profile": {"type": "string", "enum": ["shields", "weapons", "engines", "balanced", "auto"]}}, "required": ["profile"], "additionalProperties": False},
                "strict": False,
            },
            {
                "type": "function",
                "name": "find_best_target",
                "description": (
                    "Run a bounded two-pass target survey. First cycle the local target list and record every ship contact seen using early ship type plus any legal status Elite already knows; CLEAN ships are rejected and WANTED ships are preferred. Then rank the observed contacts and cycle again to reacquire the best remaining candidate. "
                    "Do not stop at the first Python or Anaconda and do not wait for a fresh full scan of every contact. Use for requests like 'find the best target' or 'find me a better target'. It only changes the selected target and never fires weapons or starts an engagement."
                ),
                "parameters": {"type": "object", "properties": {}, "additionalProperties": False},
                "strict": False,
            },
            {
                "type": "function",
                "name": "get_cockpit_bindings",
                "description": (
                    "Inspect the commander's CURRENT Elite .binds preset for Bridge-supported voice-executable cockpit controls. "
                    "Use this when the commander asks what is bound/available, when a requested control is uncommon, or when execution reports no keyboard binding. "
                    "Optionally filter by a word such as throttle, target, fighter, map, boost, chaff, heat sink, or radar."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {"type": ["string", "null"], "description": "Optional plain-language or Elite-action filter."}
                    },
                    "additionalProperties": False,
                },
                "strict": False,
            },
            {
                "type": "function",
                "name": "perform_elite_binding",
                "description": (
                    "Execute one exact READY Elite action returned by get_cockpit_bindings using the commander's CURRENT keyboard Primary/Secondary binding. "
                    "Use this only for uncommon one-shot controls after inspecting the live bindings. Stateful toggles, weapon fire, cargo ejection, UI navigation, continuous movement, hold-timed controls, SRV, camera, and on-foot actions are rejected by Bridge policy."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "elite_action": {"type": "string", "description": "Exact Elite action identifier returned by get_cockpit_bindings, for example GalnetAudio_Play_Pause."}
                    },
                    "required": ["elite_action"],
                    "additionalProperties": False,
                },
                "strict": False,
            },
            {
                "type": "function",
                "name": "get_navigation_memories",
                "description": "Read the commander-defined Home, Bookmark 1, and Bookmark 2 system memories used by the QML Navigation page.",
                "parameters": {"type": "object", "properties": {}, "additionalProperties": False},
                "strict": False,
            },
            {
                "type": "function",
                "name": "set_navigation_memory",
                "description": (
                    "Set or clear one persistent Navigation memory only when the commander explicitly asks to remember, change, set, or clear Home, Bookmark 1, or Bookmark 2. "
                    "If system is omitted/null, use the commander's current system. Set clear=true only when the commander explicitly asks to clear a bookmark. Home falls back to Ega if cleared."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "slot": {"type": "string", "enum": ["home", "bookmark1", "bookmark2"]},
                        "system": {"type": ["string", "null"], "description": "Exact Elite system name. Omit/null to remember the current system."},
                        "clear": {"type": "boolean", "description": "Clear the selected memory instead of setting it. Default false."},
                    },
                    "required": ["slot"],
                    "additionalProperties": False,
                },
                "strict": False,
            },
            {
                "type": "function",
                "name": "run_station_service",
                "description": "Run exactly one docked station quick service now: refuel, repair, or rearm. This is a one-shot action and does not change the Auto Refuel/Repair/Rearm preferences.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "service": {"type": "string", "enum": ["refuel", "repair", "rearm"]}
                    },
                    "required": ["service"],
                    "additionalProperties": False
                },
                "strict": False,
            },
        ])
        return tools

    def _run_single_station_service_now(self, service):
        service = str(service or "").strip().lower()
        spec = {
            "refuel": {"label": "Refuel", "index": 0},
            "repair": {"label": "Repair", "index": 1},
            "rearm": {"label": "Rearm", "index": 2},
        }.get(service)
        if not spec:
            return {"ok": False, "status": "rejected", "error": "Unknown station service."}
        if self.station_automation_busy:
            return {"ok": False, "status": "busy", "error": "Station maintenance is already running."}
        if not self.state_data.flag("Docked"):
            return {"ok": False, "status": "not_docked", "error": "You must be docked to use station quick services."}
        available = set(getattr(self.state_data, "station_services", set()) or set())
        if getattr(self.state_data, "station_services_explicit", False) and service not in available:
            return {"ok": False, "status": "unavailable", "error": f"{spec['label']} is not offered at this station."}

        # Reuse .95's proven preflight without changing the persistent auto-service toggles.
        vars_ = [self.auto_refuel_var, self.auto_repair_var, self.auto_rearm_var]
        before = [bool(v.get()) for v in vars_]
        try:
            for v in vars_: v.set(False)
            {"refuel": self.auto_refuel_var, "repair": self.auto_repair_var, "rearm": self.auto_rearm_var}[service].set(True)
            ok, reason = self._station_preflight()
        finally:
            for v, oldv in zip(vars_, before): v.set(oldv)
        if not ok:
            self.station_automation_status = "Blocked: " + reason
            self.refresh_preferences_widgets()
            return {"ok": False, "status": "blocked", "error": reason}

        token = f"{self.state_data.station}|single-{service}|{time.time():.3f}"
        snapshot = {
            "token": token,
            "generation": self.station_automation_generation,
            "station": self.state_data.station,
            "plan": [{"service": service, "label": spec["label"], "index": spec["index"]}],
            "focus_mode": self.bindings.ui_focus_mode(),
            "bindings": {a: self.bindings.keyboard_binding(a) for a in ("UI_Up", "UI_Left", "UI_Right", "UI_Select")},
        }
        self.station_automation_dock_token = token
        self.station_automation_completed_token = "-"
        self.station_automation_pending = False
        self.station_automation_busy = True
        self.station_automation_active_generation = self.station_automation_generation
        self.station_automation_worker_done.clear()
        self.station_automation_started_mono = time.monotonic()
        self.station_automation_status = f"Starting one-shot {spec['label']}..."
        self._station_automation_log(f"One-shot {spec['label']} requested.")
        threading.Thread(target=self._run_station_automation_worker, args=(snapshot,), daemon=True, name=f"EliteAIStation{spec['label']}").start()
        self.refresh_preferences_widgets()
        return {"ok": True, "status": "queued", "service": service, "message": f"{spec['label']} was queued using the proven station-service routine."}

    def _execute_copilot_tool(self, name, args, action_mode):
        if name == "show_bridge_workspace":
            page_name = str((args or {}).get("page") or "OVERVIEW").strip().upper()
            page_map = {"OVERVIEW":0, "LIVE":0, "NAVIGATION":1, "COMBAT":2, "TRADE":3, "COLONIZATION":4, "COMMANDER":5, "AI":6, "AUDIO":7, "SETUP":8, "DISPLAY":9, "CONTROLS":10}
            page = page_map.get(page_name, 0)
            workspace = str((args or {}).get("workspace") or "").strip().lower()
            guide = bool((args or {}).get("guide", False))
            # Defensive guard: a plain "show/open/go to page" command must never
            # accidentally launch Page Help because the model over-interpreted it.
            if guide and not self._qml_prompt_explicitly_requests_guidance(getattr(self, "copilot_last_prompt", "")):
                guide = False
            self._qml_set_ui_hint(page, workspace)
            if guide:
                focus_step = self._focused_help_step(page, workspace) if workspace else None
                self._qml_guide_after_copilot = (page, focus_step, focus_step) if focus_step is not None else (page, 0, None)
            return {"ok": True, "page": page_name, "workspace": workspace or "main", "guide_started": guide}
        if name == "search_res_sites":
            return self._copilot_search_res_sites_tool(args or {})
        if name == "set_cockpit_control":
            return self._copilot_set_cockpit_control_tool(args or {})
        if name == "perform_cockpit_action":
            return self._copilot_perform_cockpit_action_tool(args or {})
        if name == "set_power_distribution":
            return self._copilot_set_power_distribution_tool(args or {})
        if name == "find_best_target":
            return self._copilot_find_best_target_tool(args or {})
        if name == "get_cockpit_bindings":
            return self._copilot_get_cockpit_bindings_tool(args or {})
        if name == "perform_elite_binding":
            return self._copilot_perform_elite_binding_tool(args or {})
        if name == "run_station_service":
            service = str((args or {}).get("service") or "").strip().lower()
            if service not in {"refuel", "repair", "rearm"}:
                return {"ok": False, "status": "rejected", "error": "Service must be refuel, repair, or rearm."}
            if action_mode == "Suggest Only":
                return {"ok": True, "status": "suggest_only", "service": service, "message": "Service was not run because action mode is Suggest Only."}
            if action_mode == "Ask Before Acting":
                self.copilot_pending_action = {"type": "station_service", "service": service, "created": datetime.now().isoformat(timespec="seconds")}
                self.after(0, self.refresh_copilot_widgets)
                return {"ok": True, "status": "pending_approval", "service": service, "message": f"{service.title()} is waiting for commander approval."}
            box = {}
            done = threading.Event()
            def run():
                try: box["result"] = self._run_single_station_service_now(service)
                except Exception as exc: box["result"] = {"ok": False, "status": "error", "error": str(exc)}
                finally: done.set()
            self.after(0, run)
            if not done.wait(3.0):
                return {"ok": False, "status": "timeout", "error": "Bridge UI did not accept the station service in time."}
            return box.get("result") or {"ok": False, "status": "error", "error": "No station-service result returned."}
        if name == "get_navigation_memories":
            values = _load_nav_memories()
            return {"ok": True, "memories": values}
        if name == "set_navigation_memory":
            slot = str((args or {}).get("slot") or "").strip().lower()
            if slot not in NAV_MEMORY_DEFAULTS:
                return {"ok": False, "error": "Unknown navigation memory slot."}
            clear = bool((args or {}).get("clear", False))
            if clear:
                system = ""
            else:
                supplied = _sanitize_nav_memory_value((args or {}).get("system"))
                system = supplied or _valid_text(getattr(self.state_data, "system", ""), "")
                if not system:
                    return {"ok": False, "error": "Current system is unavailable; provide an exact system name."}
            try:
                values = _save_nav_memory(slot, system)
            except Exception as exc:
                return {"ok": False, "error": str(exc)}
            return {"ok": True, "slot": slot, "system": values.get(slot, ""), "memories": values}
        if name == "plot_route":
            self._qml_set_ui_hint(1, "route")
        elif name in {"search_market", "search_trade_loops"}:
            self._qml_set_ui_hint(3, "route_finder")
        elif name == "get_trade_loop_state":
            self._qml_set_ui_hint(3, "loop_setup")
        elif name == "get_commander_history":
            self._qml_set_ui_hint(5, "records")
        elif name == "execute_bridge_command":
            cmd = str((args or {}).get("command") or "").strip()
            if cmd in {"target_highest_threat", "target_power_plant", "ensure_combat_mode", "emergency_egress", "cancel_egress"}:
                self._qml_set_ui_hint(2, "tactical")
            elif cmd in {"auto_launch", "docking_protocol", "clear_station_jump", "cancel_current_command"}:
                self._qml_set_ui_hint(0, "quick_actions")
        return super()._execute_copilot_tool(name, args, action_mode)

    def approve_pending_copilot_action(self):
        pending = self.copilot_pending_action
        if pending and pending.get("type") == "station_service":
            self.copilot_pending_action = None
            service = str(pending.get("service") or "")
            result = self._run_single_station_service_now(service)
            self.copilot_status = result.get("message") or result.get("error") or f"Station service {service} processed."
            self.refresh_copilot_widgets()
            return
        return super().approve_pending_copilot_action()

    def reject_pending_copilot_action(self):
        pending = self.copilot_pending_action
        if pending and pending.get("type") == "station_service":
            self.copilot_pending_action = None
            self.copilot_status = f"Rejected one-shot {str(pending.get('service') or 'station service').title()}."
            self.refresh_copilot_widgets()
            return
        return super().reject_pending_copilot_action()

    def _copilot_tool_trace_line(self, name, args, result):
        if name == "search_res_sites":
            return f"search_res_sites({args.get('type')}) → {result.get('count', 0)} result(s); {result.get('status', result.get('error', '?'))}"
        if name == "show_bridge_workspace":
            return f"show_bridge_workspace({result.get('page','?')} / {result.get('workspace','main')}) → {'guide' if result.get('guide_started') else 'open'}"
        if name == "set_cockpit_control":
            return f"set_cockpit_control({args.get('control')}={args.get('state')}) → {result.get('status', result.get('error', '?'))}"
        if name == "perform_cockpit_action":
            return f"perform_cockpit_action({args.get('action')}) → {result.get('status', result.get('error', '?'))}"
        if name == "set_power_distribution":
            return f"set_power_distribution({args.get('profile')}) → {result.get('status', result.get('error', '?'))}"
        if name == "find_best_target":
            return f"find_best_target() → {result.get('status', result.get('error', '?'))}"
        if name == "get_cockpit_bindings":
            return f"get_cockpit_bindings({args.get('query') or '*'}) → {result.get('ready', 0)}/{result.get('count', 0)} ready"
        if name == "perform_elite_binding":
            return f"perform_elite_binding({args.get('elite_action')}) → {result.get('status', result.get('error', '?'))}"
        if name == "run_station_service":
            return f"run_station_service({args.get('service')}) → {result.get('status', result.get('error', '?'))}"
        if name == "get_navigation_memories":
            return "get_navigation_memories() → Home/Bookmark memories"
        if name == "set_navigation_memory":
            return f"set_navigation_memory({args.get('slot')}) → {result.get('system', result.get('error', '?'))}"
        return super()._copilot_tool_trace_line(name, args, result)


DEFAULT_AI_CONTEXT = (
    "Act as my Elite Dangerous copilot. Always respond in English unless I explicitly request another language. "
    "Do not switch languages because speech transcription is unclear or malformed. Keep responses concise, practical, and focused on what I am doing now. "
    "Use current Bridge telemetry and screen context before answering. Do not invent game state, targets, routes, cargo, "
    "or other information the Bridge cannot verify. If something is uncertain, say so. Explain unfamiliar controls when useful, "
    "prefer clear next actions over long explanations, and ask before dangerous or irreversible actions."
)

SETUP_OVERRIDE_DEFAULTS = {
    "bridge_mode": "",
    "api_verified_fingerprint": "",
    "api_verified_at": 0.0,
    "auto_powerplant": False,
    "auto_chaff": False,
    "auto_chaff_profile": "MED",
    "ai_trade_auto": True,
    "ai_mission_auto": True,
    "ai_travel_auto": False,
    # QML-facing AI preferences that .95 keeps in memory only.  Persist them in
    # the adapter sidecar so changing either AI page or Setup survives restart.
    "ai_tool_mode": "Ask Before Acting",
    "ai_smart_auto": False,
    # Optional pilot-authored context sent with each AI request. This is deliberately
    # context, not a replacement system prompt, so core Bridge behavior stays intact.
    "ai_context": "",
    "ai_context_seeded": False,
    "hotkey_overrides": {},
}


def _qml_apply_hotkey_specs(app, overrides=None):
    """Apply adapter-owned Bridge hotkey overrides without changing protected engine defaults."""
    overrides = overrides if isinstance(overrides, dict) else {}
    specs = []
    for command_id, default_display, default_vk, label in legacy.BRIDGE_HOTKEY_SPECS:
        item = overrides.get(command_id) if isinstance(overrides, dict) else None
        display = str((item or {}).get("display") or default_display)
        vk = int((item or {}).get("vk") or default_vk)
        specs.append((command_id, display, vk, label))
    try:
        old = getattr(app, "bridge_hotkeys", None)
        if old:
            old.stop()
    except Exception:
        pass
    app.bridge_hotkeys = legacy.BridgeGlobalHotkeys(tuple(specs), app.bridge_hotkey_queue)
    app.bridge_hotkeys.start()
    app._qml_hotkey_overrides = dict(overrides)


def _qml_restrict_controller_bindings_to_ptt(app):
    """Keep direct controller listening exclusive to Push-to-Talk.

    Normal Bridge commands use fixed keyboard/Stream Deck shortcuts.  Any legacy
    direct-controller assignments are removed from both the live manager and the
    persisted controller binding file so an Elite HOTAS button cannot silently
    trigger a Bridge automation.
    """
    current = dict(getattr(app, "controller_bindings", {}) or {})
    ptt = current.get("push_to_talk")
    allowed = {"push_to_talk": ptt} if isinstance(ptt, dict) else {}
    removed = sorted(key for key in current if key != "push_to_talk")
    app.controller_bindings = allowed
    try:
        app.controller_manager.set_bindings(allowed)
    except Exception as exc:
        print(f"[CONTROLS] PTT-only controller filter failed: {exc}", flush=True)
    if removed:
        try:
            app._save_controller_bindings_file()
        except Exception as exc:
            print(f"[CONTROLS] could not persist PTT-only controller bindings: {exc}", flush=True)
        print(f"[CONTROLS] removed legacy direct controller mappings: {', '.join(removed)}", flush=True)
    return removed


def _setup_control_rows(app):
    """Read-only fixed Bridge shortcuts for keyboard/Stream Deck use."""
    rows = []
    registered = set(getattr(getattr(app, "bridge_hotkeys", None), "registered", {}) or {})
    failures = getattr(getattr(app, "bridge_hotkeys", None), "failures", {}) or {}
    overrides = getattr(app, "_qml_hotkey_overrides", {}) or {}
    for command_id, default_hotkey, default_vk, label in legacy.BRIDGE_HOTKEY_SPECS:
        override = overrides.get(command_id) if isinstance(overrides, dict) else None
        hotkey = str((override or {}).get("display") or default_hotkey)
        controller_binding = (getattr(app, "controller_bindings", {}) or {}).get(command_id)
        try:
            controller_label = app.controller_manager.binding_label(controller_binding) if isinstance(controller_binding, dict) else "NOT MAPPED"
            controller_state = app.controller_manager.binding_status(controller_binding) if isinstance(controller_binding, dict) else "UNBOUND"
            controller_conflicts = app.bindings.controller_binding_collisions(controller_binding) if isinstance(controller_binding, dict) else []
            controller_conflict_detail = app.bindings.controller_conflict_display(controller_binding, limit=3) if controller_conflicts else ""
        except Exception:
            controller_label = "NOT MAPPED"
            controller_state = "UNBOUND"
            controller_conflicts = []
            controller_conflict_detail = ""
        rows.append({
            "id": str(command_id),
            "commandId": str(command_id),
            "label": str(label).upper(),
            "hotkey": str(hotkey),
            "hotkeyState": "READY" if command_id in registered else ("CONFLICT" if command_id in failures else "NOT REGISTERED"),
            "controller": str(controller_label).upper(),
            "controllerState": str(controller_state).upper(),
            "controllerConflict": bool(controller_conflicts),
            "controllerConflictDetail": str(controller_conflict_detail).upper(),
            "required": bool(command_id == "push_to_talk"),
        })
    return rows


def _elite_keyboard_recommendations(app):
    """Recommend unused keyboard chords from the active Elite profile.

    Read-only: this never edits Elite's .binds file. Prefer the modifier family
    already dominant in the pilot's profile, while avoiding every keyboard
    chord Elite currently uses plus Bridge global-hotkey defaults.
    """
    used = set()
    modifier_counts = {}
    try:
        root = getattr(app.bindings, "root", None)
        if root is not None:
            for elem in root:
                for slot in ("Primary", "Secondary"):
                    node = elem.find(slot)
                    if node is None or node.attrib.get("Device") != "Keyboard":
                        continue
                    key = str(node.attrib.get("Key") or "")
                    if not key:
                        continue
                    mods = tuple(sorted(
                        str(m.attrib.get("Key") or "") for m in node.findall("Modifier")
                        if m.attrib.get("Device") == "Keyboard" and m.attrib.get("Key")
                    ))
                    used.add((mods, key))
                    if mods:
                        modifier_counts[mods] = modifier_counts.get(mods, 0) + 1
    except Exception:
        pass

    # Also reserve Bridge's configured/default keyboard chords when available.
    try:
        for _action, _label, default_hotkey in legacy.BRIDGE_HOTKEY_SPECS:
            text = str(default_hotkey or "").upper().replace(" ", "")
            if not text:
                continue
            parts = [x for x in text.split("+") if x]
            if not parts:
                continue
            key_name = parts[-1]
            mod_names = tuple(sorted(parts[:-1]))
            used.add((("BRIDGE:" + ",".join(mod_names),), "BRIDGE:" + key_name))
    except Exception:
        pass

    preferred = sorted(modifier_counts, key=lambda m: (-modifier_counts[m], len(m), m))
    # Safe fallback families. Avoid Windows key, Alt+F4, Ctrl+Alt+Del, etc.
    fallback_mods = [
        ("Key_LeftShift",), ("Key_LeftControl",), ("Key_LeftAlt",),
        ("Key_LeftControl", "Key_LeftShift"),
        ("Key_LeftAlt", "Key_LeftShift"),
    ]
    mod_families = []
    for mods in preferred + fallback_mods:
        mods = tuple(sorted(mods))
        if mods and mods not in mod_families:
            mod_families.append(mods)

    # Human-friendly candidates first. F-keys and punctuation come later.
    keys = [f"Key_{c}" for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"] + \
           [f"Key_{n}" for n in "1234567890"] + \
           [f"Key_F{n}" for n in range(1, 13)]
    suggestions = []
    for mods in mod_families:
        for key in keys:
            if (mods, key) in used:
                continue
            # Display using the same formatter as the active bindings reader.
            try:
                display = " + ".join([app.bindings.key_display(m) for m in mods] + [app.bindings.key_display(key)])
            except Exception:
                display = " + ".join([m.replace("Key_", "") for m in mods] + [key.replace("Key_", "")])
            suggestions.append(display)
    return suggestions


def _setup_elite_rows(app):
    try:
        rows, _missing = app._setup_elite_binding_rows()
    except Exception:
        rows = []
    live = bool(getattr(app, "_qml_live_elite_bindings", lambda: False)())
    if not live:
        return [
            {
                "label": str(a).upper(),
                "status": "UNAVAILABLE",
                "detail": "NO ACTIVE ELITE PROFILE",
                "suggestion": "",
            }
            for a, _b, _c in rows
        ]
    suggestions = iter(_elite_keyboard_recommendations(app))
    rendered = []
    for a, b, c in rows:
        missing = str(b).upper() != "READY"
        rendered.append({
            "label": str(a).upper(),
            "status": str(b).upper(),
            "detail": str(c),
            "suggestion": (next(suggestions, "") if missing else ""),
        })
    return rendered


def _setup_preflight_rows(app):
    try:
        rows, _elite, ready = app._setup_preflight_rows()
    except Exception as exc:
        try:
            ready = bool(app._qml_api_verified()) if bool(app._qml_copilot_enabled()) else True
        except Exception:
            ready = True
        return ([{"label": "SETUP", "status": "ERROR", "detail": str(exc)}], bool(ready), True)
    rendered = [{"label": str(a).upper(), "status": str(b), "detail": str(c)} for a,b,c in rows]
    limited = any(str(row.get("status", "")).upper() in {"MISSING", "NEEDS ATTENTION", "ERROR"} for row in rendered)
    return (rendered, bool(ready), bool(limited))


def _api_key_fingerprint(value: str) -> str:
    value = str(value or "").strip()
    return hashlib.sha256(value.encode("utf-8")).hexdigest() if value else ""


def _verify_openai_api_key(app, value: str):
    """Run one tiny real Copilot request so setup only accepts a working key."""
    value = str(value or "").strip()
    if not value:
        return False, "No API key was entered."
    if len(value) < 20:
        return False, "The API key looks too short."
    try:
        payload = {
            "model": str(getattr(legacy, "AI_MODEL", "gpt-5.6-luna")),
            "input": "Reply with OK.",
            "max_output_tokens": 32,
        }
        app._openai_response_request(value, payload, timeout=20)
        return True, "OpenAI connection verified. AI Co-Pilot is ready."
    except Exception as exc:
        detail = " ".join(str(exc or type(exc).__name__).replace("\r", " ").replace("\n", " ").split()).strip()
        if not detail:
            detail = type(exc).__name__
        return False, ("Verification failed: " + detail)[:360]


def _set_windows_user_api_key(value: str):
    value = str(value or "").strip()
    if not value:
        raise ValueError("API key cannot be blank.")
    if len(value) < 20:
        raise ValueError("API key looks too short.")
    os.environ["OPENAI_API_KEY"] = value
    if os.name == "nt":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Environment", 0, winreg.KEY_SET_VALUE) as key:
                winreg.SetValueEx(key, "OPENAI_API_KEY", 0, winreg.REG_SZ, value)
            try:
                HWND_BROADCAST = 0xFFFF
                WM_SETTINGCHANGE = 0x001A
                SMTO_ABORTIFHUNG = 0x0002
                ctypes.windll.user32.SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment", SMTO_ABORTIFHUNG, 1000, None)
            except Exception:
                pass
        except Exception as exc:
            raise RuntimeError(f"Could not save the API key for this Windows user: {exc}")


class BridgeHost:
    def __init__(self, port: int, token: str):
        self.port = int(port)
        self.token = token
        self.shared = SharedState()
        self.command_queue: queue.Queue[dict[str, Any]] = queue.Queue()
        self.httpd: ThreadingHTTPServer | None = None
        self.app: HeadlessBridgeApp | None = None
        self.trade_run_target_cycles: int = 0  # 0 = continuous
        self.trade_run_baseline_sells: int = 0
        self.trade_run_completed_cycles: int = 0
        self.trade_route_max_ls: int = 10000
        self.trade_route_filtered_pairs: list[dict[str, Any]] = []
        # v0.29.24 additive Best Trade workspace.  Keep the existing route finder
        # untouched and maintain a separate result set/state for galaxy-wide
        # commodity discovery.
        self.trade_best_busy: bool = False
        self.trade_best_status: str = "READY // FIND THE BEST COMMODITY + LOOP"
        self.trade_best_pairs: list[dict[str, Any]] = []
        self.trade_best_max_ls: int = 10000
        self.trade_best_legality: str = "LEGAL ONLY"
        self.trade_best_rare_mode: str = "EXCLUDE"
        self.trade_best_lock = threading.Lock()

        # Persistent AI usage accounting belongs to the QML adapter, not the locked .95 engine.
        # The .95 counters reset each process; this sidecar accumulates positive deltas across runs.
        local_appdata = Path(os.environ.get("LOCALAPPDATA", str(Path.home())))
        self.ai_usage_path = local_appdata / "EliteAIBridge" / "ai_usage_totals.json"
        self.ai_usage_path.parent.mkdir(parents=True, exist_ok=True)
        self.ai_usage_totals = self._load_ai_usage_totals()
        self.ai_usage_last_session = {"calls": 0, "input_tokens": 0, "output_tokens": 0, "transcription_calls": 0, "transcription_failures": 0, "transcription_seconds": 0.0}
        self.ai_usage_last_save = 0.0
        self.setup_override_path = local_appdata / "EliteAIBridge" / "qml_setup_overrides.json"
        self.setup_overrides = self._load_setup_overrides()
        # QML-side player shield transition watcher. The protected .95 engine already
        # ingests ShieldState; this adapter adds immediate cockpit voice feedback
        # without changing the locked engine. None means we have not established a
        # live baseline yet, so startup never announces a stale shield state.
        self._last_player_shield_state: str | None = None
        # v0.30.56 QML-native Elite controller-conflict acknowledgement.
        # The engine still owns detection/persistence; the adapter only exposes presentation state.
        self.controller_conflict_modal = {"active": False, "serial": 0, "command": "", "control": "", "elite": ""}
        self._controller_conflict_seen = {}

    def _load_setup_overrides(self):
        data = dict(SETUP_OVERRIDE_DEFAULTS)
        try:
            saved = json.loads(self.setup_override_path.read_text(encoding="utf-8"))
            if isinstance(saved, dict):
                data.update({k: saved[k] for k in data if k in saved})
        except Exception:
            pass
        bridge_mode = str(data.get("bridge_mode") or "").strip().upper()
        data["bridge_mode"] = bridge_mode if bridge_mode in ("CORE", "COPILOT") else ""
        data["api_verified_fingerprint"] = str(data.get("api_verified_fingerprint") or "").strip().lower()
        try:
            data["api_verified_at"] = float(data.get("api_verified_at") or 0.0)
        except Exception:
            data["api_verified_at"] = 0.0
        profile = str(data.get("auto_chaff_profile") or "MED").upper()
        data["auto_chaff_profile"] = profile if profile in ("LOW", "MED", "HIGH") else "MED"
        mode = str(data.get("ai_tool_mode") or "Ask Before Acting").strip()
        if mode not in ("Suggest Only", "Ask Before Acting", "Auto Navigation"):
            mode = "Ask Before Acting"
        data["ai_tool_mode"] = mode
        data["ai_smart_auto"] = bool(data.get("ai_smart_auto", False))
        data["ai_context"] = str(data.get("ai_context") or "").strip()[:1000]
        if not bool(data.get("ai_context_seeded", False)):
            if not data["ai_context"]:
                data["ai_context"] = DEFAULT_AI_CONTEXT[:1000]
            data["ai_context_seeded"] = True
            try:
                tmp = self.setup_override_path.with_suffix(".tmp")
                tmp.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
                tmp.replace(self.setup_override_path)
            except Exception:
                pass
        return data

    def _save_setup_overrides(self):
        try:
            tmp = self.setup_override_path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.setup_overrides, indent=2, sort_keys=True), encoding="utf-8")
            tmp.replace(self.setup_override_path)
        except Exception:
            pass

    def _apply_setup_overrides(self):
        if self.app is None:
            return
        mapping = {
            "auto_powerplant": "auto_powerplant_var",
            "auto_chaff": "auto_chaff_var",
            "ai_trade_auto": "ai_trade_auto_var",
            "ai_mission_auto": "ai_mission_auto_var",
            "ai_travel_auto": "ai_travel_auto_var",
        }
        for key, attr in mapping.items():
            try:
                getattr(self.app, attr).set(bool(self.setup_overrides.get(key, SETUP_OVERRIDE_DEFAULTS[key])))
            except Exception:
                pass
        try:
            self.app.auto_chaff_profile_var.set(str(self.setup_overrides.get("auto_chaff_profile", "MED")).upper())
        except Exception:
            pass
        try:
            self.app.ai_tool_mode_var.set(str(self.setup_overrides.get("ai_tool_mode", "Ask Before Acting")))
        except Exception:
            pass
        try:
            self.app.ai_auto_var.set(bool(self.setup_overrides.get("ai_smart_auto", False)))
        except Exception:
            pass
        self.app._qml_user_ai_context = str(self.setup_overrides.get("ai_context") or "").strip()[:1000]

    def _load_ai_usage_totals(self):
        defaults = {"calls": 0, "input_tokens": 0, "output_tokens": 0, "transcription_calls": 0, "transcription_failures": 0, "transcription_seconds": 0.0}
        try:
            data = json.loads(self.ai_usage_path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                for key in defaults:
                    if key in data:
                        defaults[key] = float(data[key]) if key == "transcription_seconds" else int(data[key])
        except Exception:
            pass
        return defaults

    def _save_ai_usage_totals(self, force=False):
        now = time.time()
        if not force and now - self.ai_usage_last_save < 2.0:
            return
        try:
            tmp = self.ai_usage_path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.ai_usage_totals, indent=2, sort_keys=True), encoding="utf-8")
            tmp.replace(self.ai_usage_path)
            self.ai_usage_last_save = now
        except Exception:
            pass

    def _sync_ai_usage(self):
        if self.app is None:
            return
        current = {
            "calls": int(getattr(self.app, "ai_calls", 0) or 0),
            "input_tokens": int(getattr(self.app, "ai_input_tokens", 0) or 0),
            "output_tokens": int(getattr(self.app, "ai_output_tokens", 0) or 0),
            "transcription_calls": int(getattr(self.app, "voice_transcription_calls", 0) or 0),
            "transcription_failures": int(getattr(self.app, "voice_transcription_failures", 0) or 0),
            "transcription_seconds": float(getattr(self.app, "voice_transcription_audio_seconds", 0.0) or 0.0),
        }
        changed = False
        for key, value in current.items():
            previous = self.ai_usage_last_session.get(key, 0)
            delta = value - previous
            if delta > 0:
                self.ai_usage_totals[key] = self.ai_usage_totals.get(key, 0) + delta
                changed = True
            self.ai_usage_last_session[key] = value
        if changed:
            self._save_ai_usage_totals()

    def _reset_ai_usage(self):
        self.ai_usage_totals = {"calls": 0, "input_tokens": 0, "output_tokens": 0, "transcription_calls": 0, "transcription_failures": 0, "transcription_seconds": 0.0}
        if self.app is not None:
            self.ai_usage_last_session = {
                "calls": int(getattr(self.app, "ai_calls", 0) or 0),
                "input_tokens": int(getattr(self.app, "ai_input_tokens", 0) or 0),
                "output_tokens": int(getattr(self.app, "ai_output_tokens", 0) or 0),
                "transcription_calls": int(getattr(self.app, "voice_transcription_calls", 0) or 0),
                "transcription_failures": int(getattr(self.app, "voice_transcription_failures", 0) or 0),
                "transcription_seconds": float(getattr(self.app, "voice_transcription_audio_seconds", 0.0) or 0.0),
            }
        self._save_ai_usage_totals(force=True)

    @staticmethod
    def _best_report_records(data):
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            for key in ("results", "data", "commodities", "items"):
                if isinstance(data.get(key), list):
                    return data[key]
        return []

    @staticmethod
    def _best_is_rare_report(report, cargo_tons):
        """Conservative rare-goods screen for the broad optimizer.

        EDData's aggregate commodity report does not expose an explicit rare flag.
        Rare goods are source-limited by design, so tiny galaxy-wide stock is a
        useful screen.  The normal sustainability test still remains authoritative.
        """
        try:
            stock = int(report.get("totalStock") or report.get("total_stock") or 0)
        except Exception:
            stock = 0
        try:
            markets = int(report.get("marketCount") or report.get("market_count") or 0)
        except Exception:
            markets = 0
        if markets and markets <= 2:
            return True
        threshold = max(2000, int(cargo_tons or 1) * 2)
        return 0 < stock < threshold

    def _best_commodity_reports(self):
        errors = []
        # Prefer Ardent first to match the legacy market-search provider order.
        for client in (getattr(self.app, "ardent_client", None), getattr(self.app, "eddata_client", None)):
            if client is None:
                continue
            try:
                data = client._get_json("/commodities", timeouts=(15, 30))
                rows = self._best_report_records(data)
                if rows:
                    return rows, getattr(client, "source_label", "MARKET DATA"), errors
            except Exception as exc:
                errors.append(f"{getattr(client, 'source_label', 'provider')}: {exc}")
        return [], "-", errors

    def _collect_best_pairs_for_commodity(self, anchor, commodity, cargo_tons, min_loops, max_start_ly, max_leg_ly, max_ls, max_days, origin_coords):
        """Collect qualifying pairs without per-commodity score normalization.

        BUY markets must start within max_start_ly of the commander's current
        system. SELL discovery uses a wider anchor radius so a valid loop can
        begin nearby and extend outward by as much as max_leg_ly.
        """
        app = self.app
        engine = legacy.MarketSearchEngine([app.ardent_client, app.eddata_client], app.eddn_cache)
        required_volume = int(cargo_tons) * int(min_loops)
        try:
            local_market = app._local_market_snapshot_for_search(commodity)
        except Exception:
            local_market = None
        buy_rows = engine.search(anchor, commodity, "BUY", required_volume, max_start_ly, max_days, True, local_market=local_market, origin_coords=origin_coords)
        sell_radius_ly = min(500.0, float(max_start_ly) + float(max_leg_ly))
        sell_rows = engine.search(anchor, commodity, "SELL", required_volume, sell_radius_ly, max_days, True, local_market=local_market, origin_coords=origin_coords)
        buy_rows, _ = app._filter_rows_ship_compatible_explicit(buy_rows, True)
        sell_rows, _ = app._filter_rows_ship_compatible_explicit(sell_rows, True)
        buy_rows = [app._enrich_loop_market_row(r) for r in buy_rows][:70]
        sell_rows = [app._enrich_loop_market_row(r) for r in sell_rows][:70]
        pairs = []
        for buy in buy_rows:
            start_ly = buy.get("distance_ly")
            if not isinstance(start_ly, (int, float)) or float(start_ly) > float(max_start_ly) + 1e-6:
                continue
            start_ly = float(start_ly)
            buy_stock = int(buy.get("volume") or 0)
            buy_loads = buy_stock // cargo_tons if cargo_tons else 0
            if buy_loads < min_loops:
                continue
            buy_ls = float(buy.get("arrival_ls") or 0)
            if buy_ls and buy_ls > max_ls:
                continue
            for sell in sell_rows:
                if buy.get("market_id") is not None and buy.get("market_id") == sell.get("market_id"):
                    continue
                if app._trade_norm(buy.get("system")) == app._trade_norm(sell.get("system")) and app._trade_norm(buy.get("station")) == app._trade_norm(sell.get("station")):
                    continue
                sell_ls = float(sell.get("arrival_ls") or 0)
                if sell_ls and sell_ls > max_ls:
                    continue
                sell_demand = int(sell.get("volume") or 0)
                sell_loads = 999999 if sell.get("infinite_volume") else (sell_demand // cargo_tons if cargo_tons else 0)
                sustainable = min(buy_loads, sell_loads)
                if sustainable < min_loops:
                    continue
                leg = app._loop_direct_distance(buy, sell, anchor)
                if leg is None or leg > max_leg_ly + 1e-6:
                    continue
                profit_per_t = int(sell.get("price") or 0) - int(buy.get("price") or 0)
                if profit_per_t <= 0:
                    continue
                ages = [a for a in (legacy.market_age_seconds(buy.get("updated_at")), legacy.market_age_seconds(sell.get("updated_at"))) if a is not None]
                worst_age = max(ages) if ages else None
                pairs.append({
                    "commodity": commodity, "buy": buy, "sell": sell,
                    "buy_price": int(buy.get("price") or 0), "sell_price": int(sell.get("price") or 0),
                    "profit_per_t": profit_per_t, "profit_per_load": profit_per_t * cargo_tons,
                    "target_profit": profit_per_t * cargo_tons * min_loops,
                    "buy_loads": buy_loads, "sell_loads": sell_loads, "sustainable_loads": sustainable,
                    "start_ly": start_ly,
                    "leg_ly": float(leg), "round_trip_ly": float(leg) * 2.0,
                    "arrival_total_ls": buy_ls + sell_ls, "worst_age_seconds": worst_age,
                    "freshness_confidence": app._loop_freshness_confidence(worst_age),
                    "buy_environment": app._station_environment(buy.get("station_type")),
                    "sell_environment": app._station_environment(sell.get("station_type")),
                    "estimated_jumps_one_way": app._estimated_leg_jumps(leg),
                })
        return pairs

    def _score_best_pairs(self, pairs, max_start_ly, max_leg_ly, max_days, min_loops):
        if not pairs:
            return []
        app = self.app
        profits = [p["profit_per_load"] for p in pairs]
        pmin, pmax = min(profits), max(profits); pspan = max(1, pmax-pmin)
        try:
            perf_lookup = app._route_performance_lookup()
        except Exception:
            perf_lookup = {}
        observed_values = []
        for p in pairs:
            key=(app._trade_norm(p.get("commodity")), app._trade_norm((p.get("buy") or {}).get("system")), app._trade_norm((p.get("buy") or {}).get("station")), app._trade_norm((p.get("sell") or {}).get("system")), app._trade_norm((p.get("sell") or {}).get("station")))
            obs=perf_lookup.get(key); p["observed"]=obs
            if obs and isinstance(obs.get("profit_per_hour"),(int,float)) and obs.get("profit_per_hour")>0:
                observed_values.append(float(obs["profit_per_hour"]))
        obs_max=max(observed_values) if observed_values else None
        for p in pairs:
            price_score=(p["profit_per_load"]-pmin)/pspan
            distance_score=max(0.0,1.0-p["leg_ly"]/max(1.0,max_leg_ly))
            start_score=max(0.0,1.0-float(p.get("start_ly") or 0.0)/max(1.0,max_start_ly))
            arrival_score=max(0.0,1.0-math.log10(1.0+p["arrival_total_ls"])/6.0)
            if p["worst_age_seconds"] is None: freshness_score=.25
            else: freshness_score=max(0.0,1.0-min(p["worst_age_seconds"],max_days*86400.0)/max(1.0,max_days*86400.0))
            surplus=max(0,p["sustainable_loads"]-min_loops); sustain_score=min(1.0,surplus/max(1.0,min_loops*2.0))
            envs=(p.get("buy_environment"),p.get("sell_environment")); surfaces=sum(1 for e in envs if e=="SURFACE"); unknown=sum(1 for e in envs if e=="UNKNOWN")
            if surfaces>=2: env_score=.05; mult=.68
            elif surfaces==1: env_score=.25; mult=.82
            elif unknown: env_score=.78; mult=1.0
            else: env_score=1.0; mult=1.0
            # Best Trade adds a light 5% preference for a nearby starting market
            # while preserving the long-loop optimizer's profit/travel/sustainability philosophy.
            theoretical=100.0*(.38*price_score+.14*distance_score+.05*start_score+.10*arrival_score+.09*freshness_score+.09*sustain_score+.15*env_score)*mult
            p["theoretical_score"]=round(theoretical,1)
            obs=p.get("observed") or {}; obs_pph=obs.get("profit_per_hour"); timed=int(obs.get("timed_cycles") or 0)
            p["observed_cr_per_hour"]=obs_pph; p["observed_timed_cycles"]=timed; p["observed_avg_profit"]=obs.get("avg_profit"); p["observed_loads"]=int(obs.get("loads") or 0)
            smart=theoretical
            if isinstance(obs_pph,(int,float)) and obs_pph>0 and obs_max:
                observed_score=min(1.0,float(obs_pph)/obs_max)*100.0
                if timed>=2: smart=.72*theoretical+.28*observed_score
                elif timed==1: smart=.90*theoretical+.10*observed_score
            p["score"]=round(smart,1)
        pairs.sort(key=lambda p:(-p["score"],-(p.get("observed_cr_per_hour") or 0),-p["profit_per_load"],p.get("start_ly",10**9),p["leg_ly"],p["arrival_total_ls"]))
        return pairs

    def _known_prohibited_at_sell(self, pair):
        """Best-effort legal-market guard using station CAPI metadata when available."""
        sell=pair.get("sell") or {}; system=str(sell.get("system") or ""); station=str(sell.get("station") or ""); commodity=str(pair.get("commodity") or "")
        if not system or not station or not commodity:
            return False
        try:
            rows=self.app.eddata_client.stations_in_system(system, timeout=5)
        except Exception:
            return False
        wanted=self.app._trade_norm(commodity); station_key=self.app._trade_norm(station)
        for row in rows:
            if self.app._trade_norm(row.get("stationName") or row.get("name")) != station_key:
                continue
            prohibited=row.get("prohibited") or []
            if isinstance(prohibited,str): prohibited=[prohibited]
            return any(self.app._trade_norm(x)==wanted for x in prohibited)
        return False

    def _run_best_trade_search(self, anchor, cargo, min_runs, max_start_ly, max_leg_ly, max_ls, legality, rare_mode, origin_coords):
        with self.trade_best_lock:
            if self.trade_best_busy:
                return
            self.trade_best_busy=True; self.trade_best_pairs=[]
            self.trade_best_max_ls=max_ls; self.trade_best_legality=legality; self.trade_best_rare_mode=rare_mode
            self.trade_best_status="PREPARING // BUILDING COMMODITY CANDIDATE POOL"

        def worker():
            try:
                reports, provider, provider_errors = self._best_commodity_reports()
                if not reports:
                    raise RuntimeError("No commodity catalog was returned by the market-data providers" + ((" // "+" | ".join(provider_errors)) if provider_errors else ""))
                required=cargo*min_runs; candidates=[]
                for r in reports:
                    name=str(r.get("commodityName") or r.get("commodity") or r.get("name") or "").strip()
                    if not name: continue
                    try: stock=int(r.get("totalStock") or 0); demand=int(r.get("totalDemand") or 0)
                    except Exception: stock=demand=0
                    if stock and stock < required: continue
                    if demand and demand < required: continue
                    is_rare=self._best_is_rare_report(r,cargo)
                    if rare_mode.startswith("EXCLUDE") and is_rare: continue
                    try: potential=max(0,int(r.get("maxSellPrice") or 0)-int(r.get("minBuyPrice") or 0))
                    except Exception: potential=0
                    if potential<=0: continue
                    candidates.append((potential,name,is_rare))
                candidates.sort(reverse=True)
                # Broad enough to capture profitable standard goods without turning one
                # click into hundreds of provider calls. Global spread is only a prefilter;
                # the final score is recomputed across every surviving route together.
                candidates=candidates[:40]
                if not candidates:
                    raise RuntimeError("No commodities met the selected stock/demand filters")
                all_pairs=[]; done=0
                with ThreadPoolExecutor(max_workers=6, thread_name_prefix="BestTradeCommodity") as pool:
                    futs={pool.submit(self._collect_best_pairs_for_commodity,anchor,name,cargo,min_runs,max_start_ly,max_leg_ly,max_ls,7,origin_coords):(name,is_rare) for _,name,is_rare in candidates}
                    for fut in as_completed(futs):
                        name,is_rare=futs[fut]; done+=1
                        try:
                            rows=fut.result()
                            for p in rows: p["rare_good"]=bool(is_rare)
                            all_pairs.extend(rows)
                        except Exception:
                            pass
                        with self.trade_best_lock:
                            self.trade_best_status=f"SCANNING ALL COMMODITIES // {done}/{len(candidates)} // {name.upper()}"
                scored=self._score_best_pairs(all_pairs,max_start_ly,max_leg_ly,7,min_runs)
                if legality.startswith("LEGAL") and scored:
                    # Standard commodity orders are regular-market data.  Where EDData
                    # also has CAPI station prohibition metadata, verify the strongest
                    # candidates in parallel and reject an explicit prohibition. Unknown
                    # station metadata remains eligible rather than being invented.
                    top_check=scored[:60]
                    systems=sorted({str((p.get("sell") or {}).get("system") or "").strip() for p in top_check if str((p.get("sell") or {}).get("system") or "").strip()})
                    station_rows={}
                    def fetch_stations(system_name):
                        try: return system_name, self.app.eddata_client.stations_in_system(system_name, timeout=5)
                        except Exception: return system_name, []
                    with ThreadPoolExecutor(max_workers=8, thread_name_prefix="BestTradeLegal") as legal_pool:
                        legal_futs=[legal_pool.submit(fetch_stations, sysname) for sysname in systems]
                        for lf in as_completed(legal_futs):
                            sysname, rows_for_system=lf.result(); station_rows[self.app._trade_norm(sysname)]=rows_for_system
                    checked=[]
                    for p in top_check:
                        sell=p.get("sell") or {}; syskey=self.app._trade_norm(sell.get("system")); stkey=self.app._trade_norm(sell.get("station")); wanted=self.app._trade_norm(p.get("commodity"))
                        prohibited=False
                        for sr in station_rows.get(syskey, []):
                            if self.app._trade_norm(sr.get("stationName") or sr.get("name")) != stkey: continue
                            values=sr.get("prohibited") or []
                            if isinstance(values,str): values=[values]
                            prohibited=any(self.app._trade_norm(x)==wanted for x in values)
                            break
                        p["known_prohibited"]=bool(prohibited)
                        if not prohibited: checked.append(p)
                    if len(checked)<40: checked.extend(scored[60:120])
                    scored=checked
                rows=scored[:100]
                with self.trade_best_lock:
                    self.trade_best_pairs=rows
                    if rows:
                        top=rows[0]
                        self.trade_best_status=f"BEST TRADE FOUND // {top.get('commodity','?').upper()} // SCORE {float(top.get('score') or 0):.1f} // {int(top.get('profit_per_load') or 0):,} CR/LOAD // {len(rows)} RESULTS"
                    else:
                        self.trade_best_status="NO QUALIFYING BEST-TRADE LOOPS // TRY MORE LY/LS OR FEWER MIN RUNS"
            except Exception as exc:
                with self.trade_best_lock:
                    self.trade_best_pairs=[]; self.trade_best_status=f"BEST TRADE SEARCH FAILED // {type(exc).__name__}: {exc}"
            finally:
                with self.trade_best_lock:
                    self.trade_best_busy=False
        threading.Thread(target=worker,daemon=True,name="BestTradeSearch").start()

    def _handler_class(self):
        host = self

        class Handler(BaseHTTPRequestHandler):
            server_version = "EliteAIBridgeQMLHost/0.29.44"

            def log_message(self, fmt: str, *args):
                return

            def _auth(self) -> bool:
                return self.headers.get("X-Bridge-Token", "") == host.token

            def _json(self, status: int, payload: dict[str, Any]):
                raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(raw)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(raw)

            def do_GET(self):
                if not self._auth():
                    self._json(403, {"ok": False, "error": "forbidden"})
                    return
                if self.path == "/health":
                    self._json(200, {"ok": True, "backendVersion": BACKEND_VERSION, "integrationVersion": INTEGRATION_VERSION})
                elif self.path == "/state":
                    self._json(200, host.shared.get())
                else:
                    self._json(404, {"ok": False, "error": "not found"})

            def do_POST(self):
                if not self._auth():
                    self._json(403, {"ok": False, "error": "forbidden"})
                    return
                try:
                    length = min(65536, int(self.headers.get("Content-Length", "0") or 0))
                    body = self.rfile.read(length) if length else b"{}"
                    data = json.loads(body.decode("utf-8") or "{}")
                    if not isinstance(data, dict):
                        raise ValueError("JSON object required")
                except Exception as exc:
                    self._json(400, {"ok": False, "error": str(exc)})
                    return

                if self.path == "/command":
                    command = str(data.get("command") or "").strip().lower()
                    allowed = {"dock", "launch", "clear", "cancel", "nav_plot", "nav_memory_plot", "nav_memory_set", "nav_memory_capture", "combat_mode", "combat_enter", "combat_leave", "combat_threat", "combat_powerplant", "combat_best_target", "combat_egress", "combat_toggle_pips", "combat_toggle_subsystem", "combat_res_high", "combat_res_haz", "combat_res_plot", "combat_res_plot_index", "combat_fighter_1", "combat_fighter_2", "combat_fighter_recall", "combat_wing_target_1", "combat_wing_target_2", "combat_wing_target_3", "combat_navlock_1", "combat_navlock_2", "combat_navlock_3", "combat_firegroup_next", "trade_buy", "trade_sell", "trade_start", "trade_pause", "trade_config", "trade_route_search", "trade_route_use_index", "trade_best_search", "trade_best_use_index", "trade_learn_recent", "colonization_project_use_index", "colonization_find_supply", "save_data", "journal", "diagnostic", "cmdr_refresh", "mic_test", "hearing_test", "voice_test", "wizard_ptt_test", "ptt_map", "voice_toggle_input_mode", "voice_cycle_level", "voice_cycle_attention", "voice_set_attention", "ai_cycle_tool_mode", "ai_toggle_smart_auto", "ai_toggle_launch_rule", "ai_approve", "ai_reject", "clear_rules", "ai_usage_reset", "audio_rescan", "setup_preflight", "setup_binds", "setup_api_key_set", "setup_api_key_verify", "setup_setting", "station_refuel", "station_repair", "station_rearm", "control_bind", "control_bind_row", "control_clear", "control_clear_row", "control_cancel", "control_copy_hotkey", "control_set_hotkey", "control_restore_hotkeys", "control_keyboard_capture_begin", "control_keyboard_capture_end", "control_conflict_ack", "ui_cue", "wizard_open", "wizard_close", "wizard_music_start", "wizard_music_stop", "wizard_runtime_gate", "wizard_narrate", "wizard_narrate_page_1", "wizard_narrate_page_2", "wizard_narrate_page_3", "wizard_narrate_page_4", "wizard_narrate_page_5", "wizard_narrate_page_6", "wizard_narrate_page_7", "page_help_start", "page_help_stop", "orientation_intro", "orientation_stopped", "orientation_complete", "ui_context", "sfx_select", "sfx_set_enabled", "sfx_import_path", "sfx_test", "sfx_reset", "audio_set_level", "audio_set_device", "voice_set_tuning"}
                    if command not in allowed:
                        self._json(400, {"ok": False, "error": f"unsupported command: {command}"})
                        return
                    item = {"type": "command", "command": command, "requested_at": time.time()}
                    if command == "control_bind_row":
                        try:
                            row_index = int(data.get("row_index", -1))
                        except Exception:
                            row_index = -1
                        if row_index < 0 or row_index >= len(legacy.BRIDGE_HOTKEY_SPECS):
                            self._json(400, {"ok": False, "error": f"valid Bridge control row required: {row_index}"})
                            return
                        item["row_index"] = row_index
                        print(f"[CONTROL MAP] HTTP accepted REMAP row={row_index}", flush=True)
                    if command == "control_clear_row":
                        try:
                            row_index = int(data.get("row_index", -1))
                        except Exception:
                            row_index = -1
                        if row_index < 0 or row_index >= len(legacy.BRIDGE_HOTKEY_SPECS):
                            self._json(400, {"ok": False, "error": f"valid Bridge control row required: {row_index}"})
                            return
                        item["row_index"] = row_index
                        print(f"[CONTROL MAP] HTTP accepted CLEAR row={row_index}", flush=True)
                    if command in {"sfx_select", "sfx_set_enabled", "sfx_import_path", "sfx_test", "sfx_reset"}:
                        key = str(data.get("key") or "").strip().lower()
                        if key not in legacy.SFX_SPECS:
                            self._json(400, {"ok": False, "error": "valid SFX event key required"})
                            return
                        item["key"] = key
                        if command == "sfx_set_enabled":
                            item["enabled"] = bool(data.get("enabled", True))
                        if command == "sfx_import_path":
                            path = str(data.get("path") or "").strip()
                            if not path or len(path) > 2048:
                                self._json(400, {"ok": False, "error": "valid WAV path required"})
                                return
                            item["path"] = path
                    if command == "audio_set_level":
                        bus = str(data.get("bus") or "").strip().lower()
                        try: value = max(0, min(100, int(data.get("value", 0))))
                        except Exception: value = -1
                        if bus not in {"voice", "sfx"} or value < 0:
                            self._json(400, {"ok": False, "error": "valid audio bus/value required"})
                            return
                        item["bus"] = bus; item["value"] = value
                    if command == "audio_set_device":
                        kind = str(data.get("kind") or "").strip().lower()
                        device = str(data.get("device") or "System Default").strip() or "System Default"
                        if kind not in {"input", "output"} or len(device) > 512:
                            self._json(400, {"ok": False, "error": "valid audio device required"})
                            return
                        item["kind"] = kind; item["device"] = device
                    if command == "voice_set_tuning":
                        field = str(data.get("field") or "").strip().lower()
                        if field not in {"name", "pitch", "effect", "effect_strength", "speed"}:
                            self._json(400, {"ok": False, "error": "valid voice tuning field required"})
                            return
                        item["field"] = field
                        item["value"] = data.get("value")
                    if command == "voice_set_attention":
                        value = str(data.get("value") or "").strip().upper()
                        if value not in {"OFF", "IMPORTANT", "MOST"}:
                            self._json(400, {"ok": False, "error": "voice attention must be OFF, IMPORTANT, or MOST"})
                            return
                        item["value"] = value
                    if command == "setup_api_key_set":
                        # Preserve the secret value through the HTTP command queue.
                        # v0.30.07 accepted the command but forgot to copy `value`
                        # from the request into the queued item, so the backend
                        # always received an empty string and rejected every key.
                        # Keep the key in memory only; diagnostics never export it.
                        item["value"] = str(data.get("value") or "").strip()
                    if command == "setup_setting":
                        name = str(data.get("name") or "").strip().lower()
                        allowed_setup_names = {
                            "auto_refuel", "auto_repair", "auto_rearm", "dynamic_pips", "auto_powerplant",
                            "auto_chaff", "auto_chaff_profile", "ai_trade_auto", "ai_mission_auto", "ai_travel_auto",
                            "ai_smart_auto", "commander_address", "ai_context", "ai_tool_mode", "bridge_mode",
                        }
                        if name not in allowed_setup_names:
                            self._json(400, {"ok": False, "error": "valid setup setting name required"})
                            return
                        value = data.get("value")
                        if name == "ai_context":
                            value = str(value or "").strip()[:1000]
                        elif name == "commander_address":
                            value = str(value or "Commander").strip()[:120]
                        elif name == "ai_tool_mode":
                            value = str(value or "Ask Before Acting").strip()
                            if value not in ("Suggest Only", "Ask Before Acting", "Auto Navigation"):
                                self._json(400, {"ok": False, "error": "invalid AI action mode"})
                                return
                        elif name == "bridge_mode":
                            value = str(value or "").strip().upper()
                            if value not in ("CORE", "COPILOT"):
                                self._json(400, {"ok": False, "error": "bridge mode must be CORE or COPILOT"})
                                return
                        item["name"] = name
                        item["value"] = value
                    if command == "nav_plot":
                        destination = str(data.get("destination") or "").strip()
                        if not destination or len(destination) > 160 or any(ord(ch) < 32 for ch in destination):
                            self._json(400, {"ok": False, "error": "valid destination system required"})
                            return
                        item["destination"] = destination
                    elif command in {"nav_memory_plot", "nav_memory_set", "nav_memory_capture"}:
                        slot = str(data.get("slot") or "").strip().lower()
                        if slot not in NAV_MEMORY_DEFAULTS:
                            self._json(400, {"ok": False, "error": "valid navigation memory slot required"})
                            return
                        item["slot"] = slot
                        if command == "nav_memory_set":
                            destination = str(data.get("destination") or "").strip()
                            if len(destination) > 160 or any(ord(ch) < 32 for ch in destination):
                                self._json(400, {"ok": False, "error": "invalid navigation memory value"})
                                return
                            item["destination"] = destination
                    if command == "page_help_start":
                        try:
                            page = int(data.get("page", 0))
                        except Exception:
                            page = -1
                        if page < 0 or page > 10:
                            self._json(400, {"ok": False, "error": "valid page index required"})
                            return
                        item["page"] = page
                        try:
                            item["start_step"] = max(0, int(data.get("start_step", 0) or 0))
                        except Exception:
                            item["start_step"] = 0
                        if data.get("end_step") is not None:
                            try:
                                item["end_step"] = max(item["start_step"], int(data.get("end_step")))
                            except Exception:
                                item["end_step"] = item["start_step"]
                    if command == "ui_context":
                        try:
                            page = int(data.get("page", 0))
                        except Exception:
                            page = 0
                        page = max(0, min(10, page))
                        workspace = str(data.get("workspace") or "main").strip().lower()[:80]
                        item["page"] = page
                        item["workspace"] = workspace
                    if command == "combat_res_plot_index":
                        try:
                            idx = int(data.get("index", -1))
                        except Exception:
                            idx = -1
                        if idx < 0 or idx > 24:
                            self._json(400, {"ok": False, "error": "valid RES result index required"})
                            return
                        item["index"] = idx
                    if command in {"trade_config", "trade_start"}:
                        for key in ("commodity", "cargo", "buy_system", "buy_station", "sell_system", "sell_station", "run_length"):
                            if key in data:
                                item[key] = str(data.get(key) or "").strip()[:180]
                    if command == "trade_route_search":
                        for key in ("commodity", "max_ly", "max_ls", "min_runs"):
                            if key in data:
                                item[key] = str(data.get(key) or "").strip()[:80]
                    if command == "trade_best_search":
                        for key in ("max_start_ly", "max_leg_ly", "max_ly", "max_ls", "min_runs", "legality", "rare_mode"):
                            if key in data:
                                item[key] = str(data.get(key) or "").strip()[:80]
                    if command == "trade_route_use_index":
                        try:
                            idx = int(data.get("index", -1))
                        except Exception:
                            idx = -1
                        if idx < 0 or idx > 99:
                            self._json(400, {"ok": False, "error": "valid trade route index required"})
                            return
                        item["index"] = idx
                    if command == "trade_best_use_index":
                        try:
                            idx = int(data.get("index", -1))
                        except Exception:
                            idx = -1
                        if idx < 0 or idx > 99:
                            self._json(400, {"ok": False, "error": "valid best trade index required"})
                            return
                        item["index"] = idx
                    if command == "colonization_project_use_index":
                        try:
                            idx = int(data.get("index", -1))
                        except Exception:
                            idx = -1
                        if idx < 0 or idx > 99:
                            self._json(400, {"ok": False, "error": "valid colonization project index required"})
                            return
                        item["index"] = idx
                    if command == "colonization_find_supply":
                        commodity = str(data.get("commodity") or "").strip()[:180]
                        if not commodity:
                            self._json(400, {"ok": False, "error": "commodity required"})
                            return
                        item["commodity"] = commodity
                        for key in ("quantity", "max_ly", "max_ls", "min_runs"):
                            if key in data:
                                item[key] = str(data.get(key) or "").strip()[:80]
                    host.command_queue.put(item)
                    self._json(202, {"ok": True, "accepted": command})
                elif self.path == "/shutdown":
                    host.command_queue.put({"type": "shutdown"})
                    self._json(202, {"ok": True})
                else:
                    self._json(404, {"ok": False, "error": "not found"})

        return Handler

    def start_http(self):
        self.httpd = ThreadingHTTPServer(("127.0.0.1", self.port), self._handler_class())
        threading.Thread(target=self.httpd.serve_forever, name="EliteBridge-QML-HTTP", daemon=True).start()

    def stop_http(self):
        if self.httpd is not None:
            try:
                self.httpd.shutdown()
                self.httpd.server_close()
            except Exception:
                pass
            self.httpd = None

    def _shield_generator_reason(self) -> str:
        """Return a reason only when Elite's ModulesInfo data proves one."""
        try:
            modules_path = Path(getattr(legacy, "JOURNAL_DIR")) / "ModulesInfo.json"
            data = json.loads(modules_path.read_text(encoding="utf-8"))
            for module in list(data.get("Modules") or []):
                if not isinstance(module, dict):
                    continue
                item = str(module.get("Item") or "").casefold().replace("_", "")
                if "shieldgenerator" not in item:
                    continue
                health = module.get("Health")
                if isinstance(health, (int, float)) and float(health) <= 0.001:
                    return "FAILED"
                if module.get("On") is False:
                    return "DISABLED"
                return ""
        except Exception:
            pass
        return ""

    def _handle_player_shield_transition(self, snap: dict[str, Any]) -> None:
        state = str(snap.get("shieldState") or "UNKNOWN").upper()
        if state not in {"UP", "DOWN"}:
            return
        previous = self._last_player_shield_state
        self._last_player_shield_state = state
        if previous is None or previous == state:
            return
        if state == "DOWN":
            reason = self._shield_generator_reason()
            if reason == "DISABLED":
                phrase = "Shield generator disabled. Shields offline."
            elif reason == "FAILED":
                phrase = "Shield generator failure. Shields offline."
            else:
                phrase = "Warning. Shields offline."
            self.app._voice_say("HIGH", phrase, kind="WARNING", key="player:shields-down", cooldown=2.0)
            self.app._native_set_status(phrase)
        else:
            self.app._voice_say("HIGH", "Shields restored.", kind="INFO", key="player:shields-up", cooldown=2.0)
            self.app._native_set_status("Shields restored.")

    def refresh_snapshot(self):
        if self.app is None:
            return
        try:
            sell_count = self._trade_sell_count()
            self.trade_run_completed_cycles = max(0, sell_count - self.trade_run_baseline_sells)
            if (self.trade_run_target_cycles > 0 and bool(self.app.trade_loop_enabled_var.get())
                    and self.trade_run_completed_cycles >= self.trade_run_target_cycles):
                self.app.trade_loop_enabled_var.set(False)
                self.app.toggle_trade_loop()
                self.app.trade_loop_status = (
                    f"RUN COMPLETE // {self.trade_run_completed_cycles}/{self.trade_run_target_cycles} CYCLES // PILOT CONTROL"
                )
            self._sync_ai_usage()
            snap = build_live_snapshot(self.app)
            # Present newly-created Elite overlaps in QML instead of a Windows notification.
            # Rows remain red independently until the underlying overlap is actually removed.
            live_conflicts = {}
            for crow in list(snap.get("setupControlRows") or []):
                if not isinstance(crow, dict) or not bool(crow.get("controllerConflict")):
                    continue
                action = str(crow.get("commandId") or crow.get("id") or "")
                control = str(crow.get("controller") or "HOTAS / CONTROLLER")
                elite = str(crow.get("controllerConflictDetail") or "ELITE DANGEROUS CONTROL")
                sig = f"{control}|{elite}"
                live_conflicts[action] = sig
                if action and self._controller_conflict_seen.get(action) != sig:
                    self.controller_conflict_modal = {
                        "active": True,
                        "serial": int(self.controller_conflict_modal.get("serial", 0)) + 1,
                        "command": str(crow.get("label") or action).upper(),
                        "control": control.upper(),
                        "elite": elite.upper(),
                    }
            self._controller_conflict_seen = live_conflicts
            snap["controlConflictModalActive"] = bool(self.controller_conflict_modal.get("active"))
            snap["controlConflictModalSerial"] = int(self.controller_conflict_modal.get("serial", 0))
            snap["controlConflictModalCommand"] = str(self.controller_conflict_modal.get("command") or "")
            snap["controlConflictModalControl"] = str(self.controller_conflict_modal.get("control") or "")
            snap["controlConflictModalElite"] = str(self.controller_conflict_modal.get("elite") or "")
            self._handle_player_shield_transition(snap)
            usage = self.ai_usage_totals
            snap["aiUsageCalls"] = int(usage.get("calls", 0) or 0)
            snap["aiUsageInputTokens"] = int(usage.get("input_tokens", 0) or 0)
            snap["aiUsageOutputTokens"] = int(usage.get("output_tokens", 0) or 0)
            snap["aiUsageTranscriptionCalls"] = int(usage.get("transcription_calls", 0) or 0)
            snap["aiUsageTranscriptionFailures"] = int(usage.get("transcription_failures", 0) or 0)
            snap["aiUsageTranscriptionSeconds"] = round(float(usage.get("transcription_seconds", 0.0) or 0.0), 1)
            snap["aiUsageEstimatedCost"] = round(
                snap["aiUsageInputTokens"] / 1_000_000 * legacy.AI_INPUT_PER_MILLION
                + snap["aiUsageOutputTokens"] / 1_000_000 * legacy.AI_OUTPUT_PER_MILLION, 6
            )
            snap["tradeRunTargetCycles"] = int(self.trade_run_target_cycles)
            snap["tradeRunCompletedCycles"] = int(self.trade_run_completed_cycles)
            snap["tradeRunRemainingCycles"] = max(0, self.trade_run_target_cycles - self.trade_run_completed_cycles) if self.trade_run_target_cycles > 0 else -1
            snap["tradeRunLength"] = "CONTINUOUS" if self.trade_run_target_cycles <= 0 else f"{self.trade_run_target_cycles} CYCLES"
            per_cycle = int(snap.get("tradeEstimatedProfitCycle") or 0)
            remaining = int(snap.get("tradeRunRemainingCycles") or 0)
            snap["tradeEstimatedRemainingProfit"] = per_cycle * remaining if per_cycle > 0 and remaining >= 0 else 0
            snap["tradeEstimatedTotalProfit"] = per_cycle * self.trade_run_target_cycles if per_cycle > 0 and self.trade_run_target_cycles > 0 else 0
            self.shared.set(snap)
        except Exception as exc:
            snap = self.shared.get()
            snap.update({
                "connected": False,
                "bridgeState": "ADAPTER ERROR",
                "bridgeMessage": str(exc),
                "bridgeLevel": "bad",
            })
            self.shared.set(snap)
        try:
            self.app.after(200, self.refresh_snapshot)
        except Exception:
            pass

    def _apply_trade_profile(self, item: dict[str, Any]) -> None:
        if self.app is None:
            return
        fields = (
            ("commodity", self.app.trade_loop_commodity_var),
            ("buy_system", self.app.trade_loop_buy_system_var),
            ("buy_station", self.app.trade_loop_buy_station_var),
            ("sell_system", self.app.trade_loop_sell_system_var),
            ("sell_station", self.app.trade_loop_sell_station_var),
        )
        for key, var in fields:
            if key in item:
                var.set(str(item.get(key) or "").strip())
        # Cargo target follows the active ship.  Never trust a stale/manual QML
        # value from a previous hull.
        try:
            cap = int(float(getattr(self.app.state_data, "cargo_capacity", 0) or 0))
        except Exception:
            cap = 0
        if cap > 0:
            self.app.trade_loop_cargo_var.set(str(cap))
        run = str(item.get("run_length") or "CONTINUOUS").strip().upper()
        m = re.search(r"(\d+)", run)
        self.trade_run_target_cycles = max(0, int(m.group(1))) if m else 0
        try:
            self.app._save_trade_loop_config()
        except Exception:
            pass
        target_text = "CONTINUOUS" if self.trade_run_target_cycles <= 0 else f"{self.trade_run_target_cycles} CYCLES"
        self.app.trade_loop_status = f"PROFILE SAVED // RUN LENGTH {target_text}"
        try:
            self.app.refresh_trade_loop_widgets()
        except Exception:
            pass

    def _trade_sell_count(self) -> int:
        if self.app is None:
            return 0
        try:
            cfg = self.app._trade_loop_config()
            wanted = str(cfg.get("commodity_key") or "")
            sell_system = str(cfg.get("sell_system") or "").strip().casefold()
            sell_station = str(cfg.get("sell_station") or "").strip().casefold()
            rows = list(getattr(self.app.state_data.trade_ledger, "rows", []) or [])
            count = 0
            for row in rows:
                if str(row.get("type") or "").upper() != "SELL":
                    continue
                key = legacy.market_commodity_key(row.get("commodity") or "")
                if wanted and key != wanted:
                    continue
                if sell_system and str(row.get("system") or "").strip().casefold() != sell_system:
                    continue
                if sell_station and str(row.get("station") or "").strip().casefold() != sell_station:
                    continue
                count += 1
            return count
        except Exception:
            return 0

    def drain_commands(self):
        if self.app is None:
            return
        for _ in range(12):
            try:
                item = self.command_queue.get_nowait()
            except queue.Empty:
                break
            if item.get("type") == "shutdown":
                try:
                    # Flush adapter-owned persistent preferences/accounting before
                    # asking the locked .95 engine to perform its own graceful close.
                    self._save_setup_overrides()
                    self._save_ai_usage_totals(force=True)
                    self.stop_http()
                finally:
                    self.app._on_close_bridge()
                return

            command = item.get("command")
            try:
                if command in ELITE_CONTROL_COMMANDS and not bool(self.app._qml_live_elite_bindings()):
                    label = str(command or "Elite control").replace("_", " ").upper()
                    self.app._native_set_status(
                        f"{label} unavailable // no active Elite .binds profile. Configure Elite controls, then Bridge will enable this action automatically."
                    )
                    continue
                if command == "dock":
                    self.app.start_docking_protocol()
                elif command == "launch":
                    self.app.start_auto_launch()
                elif command == "clear":
                    self.app.start_clear_station_jump()
                elif command == "cancel":
                    self.app.cancel_current_command("QML dashboard")
                elif command == "cmdr_refresh":
                    try:
                        self.app.history_snapshot = self.app.history_reader.snapshot(
                            self.app.state_data.system, self.app.state_data.station, limit=20, force=True
                        )
                        self.app._native_set_status("Commander record refreshed from live state + compact history.")
                    except Exception as exc:
                        self.app._native_set_status(f"Commander refresh failed: {exc}")
                elif command == "journal":
                    path = Path(getattr(legacy, "JOURNAL_DIR"))
                    if os.name == "nt":
                        os.startfile(str(path))
                    else:
                        self.app._native_set_status(f"Journal folder: {path}")
                elif command == "save_data":
                    # One-click beta export: preserve the simple commander JSON but
                    # also create a support bundle containing cumulative Bridge logs
                    # and current diagnostics. No API key is exported.
                    export_dir = Path(getattr(legacy, "BRIDGE_DATA_DIR")) / "exports"
                    export_dir.mkdir(parents=True, exist_ok=True)
                    stamp = time.strftime("%Y%m%d_%H%M%S")
                    payload = build_live_snapshot(self.app)
                    commander_keys = {
                        key: value for key, value in payload.items()
                        if key.startswith("commander") or key in {
                            "commander", "ship", "shipName", "shipModel", "system", "station",
                            "gameState", "hullPercent", "fuelPercent", "shieldState", "cargoUsed",
                            "cargoCapacity", "fsdState", "gearState", "hardpointsState",
                            "tradeRealizedProfit", "tradePowerRank", "tradePowerMerits"
                        }
                    }
                    record_target = export_dir / f"Commander_Record_{stamp}.json"
                    diagnostic_target = export_dir / f"Bridge_Diagnostic_{stamp}.txt"
                    bundle_target = export_dir / f"Elite_AI_Bridge_Diagnostics_{stamp}.zip"
                    record_target.write_text(json.dumps(commander_keys, ensure_ascii=False, indent=2), encoding="utf-8")
                    diagnostic_target.write_text(self.app.diagnostic_text() + "\n", encoding="utf-8")
                    metadata = {
                        "integration_version": INTEGRATION_VERSION,
                        "backend_version": BACKEND_VERSION,
                        "exported_local": time.strftime("%Y-%m-%d %H:%M:%S"),
                        "note": "Support bundle intentionally excludes OpenAI/API credentials.",
                    }
                    # Compact beta trace is assembled only when the pilot presses
                    # Save Data. It reuses bounded in-memory histories, so it adds
                    # essentially zero continuous CPU/disk overhead while giving
                    # support a fast chronology before opening the raw journals.
                    beta_trace = {
                        "integration_version": INTEGRATION_VERSION,
                        "exported_local": metadata["exported_local"],
                        "voice_last_transcript": str(getattr(self.app, "voice_input_last_text", "-") or "-"),
                        "voice_latency_last": str(getattr(self.app, "voice_latency_last", "-") or "-"),
                        "voice_backend_status": str(getattr(self.app.voice_engine, "status", "-") or "-"),
                        "voice_backend_last_error": str(getattr(self.app.voice_engine, "last_error", "-") or "-"),
                        "voice_last_backend": str(getattr(self.app.voice_engine, "last_backend", "-") or "-"),
                        "copilot_last_prompt": str(getattr(self.app, "copilot_last_prompt", "-") or "-"),
                        "copilot_history": list(getattr(self.app, "copilot_history", []) or [])[-30:],
                        "native_command_history": list(getattr(self.app, "native_command_history", []) or [])[-80:],
                        "dynamic_pip_history": list(getattr(self.app, "dynamic_pip_history", []) or [])[-50:],
                        "emergency_egress_history": list(getattr(self.app, "egress_history", []) or [])[-40:],
                        "hostile_chat_history": list(getattr(self.app, "combat_hostile_chat_history", []) or [])[-30:],
                        "session_rule_history": list(getattr(self.app, "session_rule_history", []) or [])[-30:],
                        "best_target_history": list(getattr(self.app, "_qml_best_target_history", []) or [])[-24:],
                        "current_settings": {
                            "dynamic_pips": bool(getattr(self.app.dynamic_pips_var, "get", lambda: False)()),
                            "auto_subsystem": bool(getattr(self.app.auto_powerplant_var, "get", lambda: False)()),
                            "auto_chaff": bool(getattr(self.app.auto_chaff_var, "get", lambda: False)()),
                            "auto_chaff_profile": str(getattr(self.app.auto_chaff_profile_var, "get", lambda: "-")() or "-"),
                            "smart_auto_ai": bool(getattr(self.app.ai_auto_var, "get", lambda: False)()),
                            "clear_and_jump_after_auto_launch": bool((getattr(self.app, "session_rules", {}) or {}).get("clear_and_jump_after_auto_launch", False)),
                        },
                    }
                    with zipfile.ZipFile(bundle_target, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                        zf.write(record_target, arcname=record_target.name)
                        zf.write(diagnostic_target, arcname=diagnostic_target.name)
                        zf.writestr("bundle_metadata.json", json.dumps(metadata, indent=2))
                        zf.writestr("beta_trace_summary.json", json.dumps(beta_trace, ensure_ascii=False, indent=2, default=str))
                        log_root = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "EliteAIBridge"
                        qml_log = log_root / "qml_backend.log"
                        qml_log_prev = log_root / "qml_backend.log.1"
                        if qml_log.exists():
                            zf.write(qml_log, arcname="logs/qml_backend.log")
                        if qml_log_prev.exists():
                            zf.write(qml_log_prev, arcname="logs/qml_backend.log.1")
                        demo_log = self.app._demo_transcript_path()
                        if demo_log.exists():
                            zf.write(demo_log, arcname="logs/demo_narration_transcript.log")
                        history_db = Path(getattr(legacy, "HISTORY_DB_FILE"))
                        if history_db.exists():
                            zf.write(history_db, arcname="data/bridge_history.sqlite3")
                        # Add the most recent Elite journals for event-level beta diagnosis
                        # without turning a one-click bundle into an unbounded archive.
                        try:
                            journals = sorted(Path(getattr(legacy, "JOURNAL_DIR")).glob("Journal*.log"), key=lambda q: q.stat().st_mtime, reverse=True)[:8]
                            for journal in reversed(journals):
                                zf.write(journal, arcname=f"elite_journals/{journal.name}")
                        except Exception:
                            pass
                    self.app._native_set_status(f"Export complete // {bundle_target}")
                    try:
                        self.app._ui_sfx_play("ui_confirm")
                    except Exception:
                        pass
                    try:
                        if os.name == "nt":
                            subprocess.Popen(["explorer.exe", f"/select,{bundle_target}"], creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                    except Exception:
                        try:
                            if os.name == "nt":
                                os.startfile(str(export_dir))
                        except Exception:
                            pass
                elif command == "diagnostic":
                    def _copy_full_diagnostic():
                        try:
                            self.app.copy_diagnostic()
                            self.app._native_set_status("Full Bridge diagnostic report copied to clipboard.")
                        except Exception as exc:
                            self.app._native_set_status(f"Diagnostic copy failed // {exc}")
                    self.app.after(0, _copy_full_diagnostic)
                elif command == "page_help_start":
                    self.app.after(0, lambda page=int(item.get("page", 0)), start=int(item.get("start_step", 0) or 0), end=item.get("end_step"): self.app._page_help_start(page, start, end))
                elif command == "orientation_intro":
                    orientation_text = "Welcome to your first cockpit orientation. For this one tour, normal controls are temporarily locked while the Bridge opens each module. Watch the flashing yellow highlight as each area is explained. You can end the tutorial at any time using the Stop Tutorial button at the top of the Bridge."
                    self.app._demo_transcript_append("ORIENTATION", "OPENING", orientation_text)
                    self.app.voice_engine.say(orientation_text, speed_scale=0.98)
                    self.app._native_set_status("First cockpit orientation started // controls temporarily locked by QML.")
                elif command == "orientation_stopped":
                    stop_text = "Orientation stopped. Your controls are available again. The first cockpit tour was not marked complete, so you can start it again later from Setup."
                    self.app._demo_transcript_append("ORIENTATION", "STOPPED", stop_text)
                    self.app.voice_engine.say(stop_text, speed_scale=0.98)
                    self.app._native_set_status("First cockpit orientation stopped // controls restored.")
                elif command == "orientation_complete":
                    complete_text = "Orientation complete. Your controls have returned. Explore the Bridge normally from here. Press Page Help on any page when you want a guided explanation. You can replay the full cockpit orientation later from Setup. If optional AI is enabled, you can also use Push to Talk to ask the Bridge a specific question."
                    self.app._demo_transcript_append("ORIENTATION", "COMPLETE", complete_text)
                    self.app.voice_engine.say(complete_text, speed_scale=0.98)
                    self.app._native_set_status("First cockpit orientation complete // narration log saved to %LOCALAPPDATA%\\EliteAIBridge\\demo_narration_transcript.log")
                elif command == "page_help_stop":
                    self.app.after(0, self.app._page_help_stop)
                elif command == "ui_context":
                    page = max(0, min(10, int(item.get("page", 0))))
                    workspace = str(item.get("workspace") or "main").strip().lower()
                    def _set_ui_context():
                        self.app._qml_ui_context_page = page
                        self.app._qml_ui_context_workspace = workspace
                    self.app.after(0, _set_ui_context)
                elif command == "wizard_ptt_test":
                    self.app.after(0, self.app._arm_wizard_ptt_test)
                elif command == "mic_test":
                    # Manual diagnostics are one-click captures. They never require PTT.
                    def _run_mic_check_when_idle(attempt=0):
                        try:
                            self.app._stop_ptt_recording()
                        except Exception:
                            pass
                        if bool(getattr(self.app, "voice_input_recording", False)) and attempt < 25:
                            self.app.after(80, lambda: _run_mic_check_when_idle(attempt + 1))
                            return
                        self.app.voice_input_status = "MIC CHECK STARTING // speak normally // do not hold PTT."
                        self.app.refresh_preferences_widgets()
                        self.app._test_microphone_level()
                    self.app.after(0, _run_mic_check_when_idle)
                    self.app._native_set_status("Mic check started // one-click local capture // PTT is not required.")
                elif command == "hearing_test":
                    def _run_hearing_check_when_idle(attempt=0):
                        try:
                            self.app._stop_ptt_recording()
                        except Exception:
                            pass
                        if bool(getattr(self.app, "voice_input_recording", False)) and attempt < 25:
                            self.app.after(80, lambda: _run_hearing_check_when_idle(attempt + 1))
                            return
                        self.app.voice_input_status = "TRANSCRIPTION TEST STARTING // speak normally // do not hold PTT."
                        self.app.refresh_preferences_widgets()
                        self.app._test_ai_hearing()
                    self.app.after(0, _run_hearing_check_when_idle)
                    self.app._native_set_status("Transcription test started // one-click capture // PTT is not required // nothing executes.")
                elif command == "voice_test":
                    if self.app._wizard_runtime_paused():
                        self.app.after(0, self.app._wizard_voice_test)
                        self.app._native_set_status("Wizard voice output test queued // speaking status lamp active.")
                    else:
                        self.app.after(0, self.app._voice_test)
                        self.app._native_set_status("Voice output test queued.")
                elif command == "control_conflict_ack":
                    self.controller_conflict_modal["active"] = False
                    self.app._ui_sfx_play("ui_confirm")
                elif command == "ui_cue":
                    cue = str(item.get("cue") or "nav").strip().lower()
                    key = {"nav": "ui_nav", "confirm": "ui_confirm", "warn": "ui_warning"}.get(cue, "ui_nav")
                    self.app._ui_sfx_play(key)
                elif command == "wizard_open":
                    step = int(item.get("step", 0) or 0)
                    self.app._wizard_open(step)
                elif command == "wizard_close":
                    self.app._wizard_close()
                elif command == "wizard_runtime_gate":
                    active = bool(item.get("active", False))
                    self.app.after(0, lambda value=active: self.app._set_qml_wizard_runtime_gate(value))
                elif command.startswith("wizard_narrate_page_"):
                    try:
                        page_number = int(command.rsplit("_", 1)[-1])
                    except Exception:
                        page_number = 1
                    step = max(0, min(6, page_number - 1))
                    print(f"[WIZARD] explicit command={command} -> page={step + 1}", flush=True)
                    self.app._wizard_narrate_step(step)
                elif command == "wizard_narrate":
                    # Compatibility with older QML. New builds encode page identity
                    # in the command name so a missing/coerced payload cannot become page 1.
                    step = int(item.get("step", 0) or 0)
                    self.app._wizard_narrate_step(step)
                elif command == "wizard_music_start":
                    ok = self.app._wizard_music_start(allow_disabled=True)
                    self.app._native_set_status("Guided setup music // playing on dedicated wizard audio channel" if ok else "Guided setup music // unavailable or disabled")
                elif command == "wizard_music_stop":
                    self.app._wizard_music_stop()
                elif command == "sfx_select":
                    key = str(item.get("key") or "startup")
                    spec = legacy.SFX_SPECS.get(key) or legacy.SFX_SPECS["startup"]
                    self.app.sfx_test_event_var.set(str(spec.get("label") or key))
                    self.app._sfx_refresh_editor()
                    self.app._native_set_status(f"Sound event selected // {spec.get('label', key)}")
                elif command == "sfx_set_enabled":
                    key = str(item.get("key") or "startup")
                    enabled = bool(item.get("enabled", True))
                    self.app.sfx_event_enabled[key] = enabled
                    if key == self.app._sfx_selected_key():
                        self.app.sfx_selected_enabled_var.set(enabled)
                    self.app._sfx_apply_settings(save=True)
                    self.app._sfx_refresh_editor()
                    self.app._native_set_status(f"{legacy.SFX_SPECS[key]['label']} // {'ON' if enabled else 'OFF'}")
                elif command == "sfx_import_path":
                    key = str(item.get("key") or "startup")
                    source = Path(str(item.get("path") or ""))
                    ok, reason = self.app._validate_custom_wav(source)
                    if not ok:
                        self.app._native_set_status(f"Custom sound rejected // {reason}")
                    else:
                        try:
                            legacy.CUSTOM_SFX_DIR.mkdir(parents=True, exist_ok=True)
                            old_name = self.app.sfx_custom_files.get(key)
                            target = legacy.CUSTOM_SFX_DIR / _managed_sfx_target_name(key, source)
                            shutil.copy2(source, target)
                            self.app.sfx_custom_files[key] = target.name
                            self.app.sfx_event_enabled[key] = True
                            self.app.sfx_test_event_var.set(legacy.SFX_SPECS[key]["label"])
                            self.app.sfx_selected_enabled_var.set(True)
                            self.app._sfx_apply_settings(save=True)
                            self.app._sfx_refresh_editor()
                            if old_name and Path(old_name).name != target.name:
                                try:
                                    old_path = legacy.CUSTOM_SFX_DIR / Path(old_name).name
                                    if old_path.exists():
                                        old_path.unlink()
                                except Exception:
                                    pass
                            if key == "startup":
                                self.app._wizard_music_start(allow_disabled=True)
                            else:
                                self.app._sfx_play(key, force=True, allow_disabled=True)
                            self.app._native_set_status(f"Custom sound assigned // {legacy.SFX_SPECS[key]['label']} // {source.name}")
                        except Exception as exc:
                            self.app._native_set_status(f"Custom sound import failed // {exc}")
                elif command == "sfx_test":
                    key = str(item.get("key") or self.app._sfx_selected_key())
                    self.app.sfx_test_event_var.set(legacy.SFX_SPECS[key]["label"])
                    self.app._sfx_refresh_editor()
                    if key == "startup":
                        ok = self.app._wizard_music_start(allow_disabled=True)
                        manager = self.app._wizard_sfx_manager()
                    else:
                        ok = self.app._sfx_play(key, force=True, allow_disabled=True)
                        manager = self.app.sfx_manager
                    if not ok:
                        self.app._native_set_status(f"SFX test failed // {manager.last_error or manager.status}")
                    else:
                        self.app._native_set_status(f"SFX test // {legacy.SFX_SPECS[key]['label']}")
                elif command == "sfx_reset":
                    key = str(item.get("key") or self.app._sfx_selected_key())
                    self.app.sfx_test_event_var.set(legacy.SFX_SPECS[key]["label"])
                    old_name = self.app.sfx_custom_files.pop(key, None)
                    try:
                        if old_name:
                            old_path = legacy.CUSTOM_SFX_DIR / Path(old_name).name
                            if old_path.exists(): old_path.unlink()
                    except Exception:
                        pass
                    self.app.sfx_event_enabled[key] = True
                    self.app.sfx_selected_enabled_var.set(True)
                    self.app._sfx_apply_settings(save=True)
                    self.app._sfx_refresh_editor()
                    self.app._native_set_status(f"Factory sound restored // {legacy.SFX_SPECS[key]['label']}")
                elif command == "audio_set_level":
                    bus = str(item.get("bus") or "")
                    value = max(0, min(100, int(item.get("value", 0))))
                    if bus == "voice":
                        self.app.voice_volume_var.set(value)
                        self.app._voice_profile_changed()
                    else:
                        self.app.sfx_volume_var.set(value)
                        self.app._sfx_apply_settings(save=True)
                    self.app._native_set_status(f"{bus.upper()} volume // {value}%")
                elif command == "audio_set_device":
                    kind = str(item.get("kind") or "")
                    device = str(item.get("device") or "System Default")
                    valid = self.app.audio_input_devices if kind == "input" else self.app.audio_output_devices
                    if device not in valid:
                        self.app._native_set_status(f"Audio device unavailable // {device}")
                    else:
                        always_listen = str(self.app.voice_input_mode_var.get() or "PTT").strip().upper() == "ALWAYS LISTEN"
                        if kind == "input" and always_listen:
                            self.app._stop_always_listen()
                        if kind == "input":
                            self.app.voice_input_device_var.set(device)
                        else:
                            self.app.audio_output_device_var.set(device)
                        self.app._voice_apply_settings(save=False)
                        self.app._sfx_apply_settings(save=False)
                        self.app._save_automation_config()
                        if kind == "input" and always_listen:
                            self.app.after(300, self.app._start_always_listen)
                        self.app._native_set_status(f"{kind.upper()} device // {device}")
                elif command == "voice_set_tuning":
                    field = str(item.get("field") or "").strip().lower()
                    value = item.get("value")
                    try:
                        if field == "name":
                            name = str(value or "").strip()
                            engine = str(self.app.voice_engine_mode_var.get() or "AUTO").upper()
                            if engine in ("AUTO", "SUPERTONIC"):
                                valid = list(legacy.VoiceSpeechWorker.SUPER_VOICES)
                            else:
                                valid = list(self.app.voice_engine.windows_voice_names()) or ["System Default"]
                            if name not in valid:
                                raise ValueError("voice unavailable")
                            self.app.voice_name_var.set(name)
                        elif field == "pitch":
                            value = str(value or "NORMAL").strip().upper()
                            if value not in legacy.VoiceSpeechWorker.PITCH_PRESETS:
                                raise ValueError("pitch unavailable")
                            self.app.voice_pitch_var.set(value)
                        elif field == "effect":
                            value = str(value or "BRIDGE").strip().upper()
                            if value not in legacy.VoiceSpeechWorker.EFFECT_PRESETS:
                                raise ValueError("voice character unavailable")
                            self.app.voice_effect_var.set(value)
                        elif field == "effect_strength":
                            value = max(0.0, min(100.0, float(value)))
                            self.app.voice_effect_strength_var.set(value)
                        elif field == "speed":
                            value = max(0.7, min(2.0, float(value)))
                            self.app.voice_speed_var.set(value)
                        self.app._voice_apply_settings(save=True)
                        self.app.refresh_preferences_widgets()
                        self.app._native_set_status(f"Voice tuning // {field.upper()} // {value}")
                    except Exception as exc:
                        self.app._native_set_status(f"Voice tuning failed // {exc}")
                elif command == "setup_preflight":
                    def _qml_preflight():
                        try:
                            rows, _elite_rows, ready = self.app._setup_preflight_rows()
                            issues = [name for name, status, _detail in rows if status in ("MISSING", "NEEDS ATTENTION")]
                            message = "PREFLIGHT READY" if ready else ("PREFLIGHT NEEDS ATTENTION // " + ", ".join(issues[:4]))
                            self.app._native_set_status(message)
                            self.app.refresh_preferences_widgets()
                        except Exception as exc:
                            self.app._native_set_status(f"Preflight failed // {exc}")
                    self.app.after(0, _qml_preflight)
                elif command == "setup_binds":
                    self.app.after(0, self.app._setup_rescan)
                elif command in {"setup_api_key_set", "setup_api_key_verify"}:
                    # Verification is a real network request. Keep it off the Tk/backend
                    # event thread so the wizard stays responsive and the VERIFYING state
                    # can reach QML immediately.
                    value = str(item.get("value") or "").strip() if command == "setup_api_key_set" else str(os.environ.get("OPENAI_API_KEY") or "").strip()
                    verify_command = command
                    self.app._ai_api_verify_status = "VERIFYING"
                    self.app._ai_api_verify_detail = "Testing the OpenAI connection with a tiny Co-Pilot request..."
                    self.app._native_set_status("OpenAI API key verification in progress...")
                    try:
                        self.app.refresh_preferences_widgets()
                    except Exception:
                        pass

                    def _api_verify_worker(candidate=value, requested_command=verify_command):
                        ok, detail = _verify_openai_api_key(self.app, candidate)

                        def _finish_api_verify():
                            if ok:
                                try:
                                    if requested_command == "setup_api_key_set":
                                        _set_windows_user_api_key(candidate)
                                    self.setup_overrides["api_verified_fingerprint"] = _api_key_fingerprint(candidate)
                                    self.setup_overrides["api_verified_at"] = time.time()
                                    self._save_setup_overrides()
                                    self.app._ai_api_verify_status = "VERIFIED"
                                    self.app._ai_api_verify_detail = detail
                                    self.app.ai_status = "Ready"
                                    self.app._native_set_status("OpenAI API verified // AI Co-Pilot connection ready.")
                                except Exception as exc:
                                    self.app._ai_api_verify_status = "FAILED"
                                    self.app._ai_api_verify_detail = f"Verification passed, but the key could not be saved: {exc}"
                                    self.app._native_set_status(f"API key save failed // {exc}")
                            else:
                                self.app._ai_api_verify_status = "FAILED"
                                self.app._ai_api_verify_detail = detail
                                self.app._native_set_status(detail)
                            try:
                                self.app.refresh_preferences_widgets()
                            except Exception:
                                pass

                        try:
                            self.app.after(0, _finish_api_verify)
                        except Exception:
                            _finish_api_verify()

                    threading.Thread(target=_api_verify_worker, daemon=True, name="EliteBridge-OpenAIVerify").start()
                elif command in {"station_refuel", "station_repair", "station_rearm"}:
                    service = command.split("_", 1)[1]
                    self.app.after(0, lambda s=service: self.app._run_single_station_service_now(s))
                elif command == "setup_setting":
                    name = str(item.get("name") or "").strip().lower()
                    value = item.get("value")
                    def _apply_setup_setting():
                        try:
                            if name in {"auto_refuel", "auto_repair", "auto_rearm"}:
                                getattr(self.app, name + "_var").set(bool(value))
                                self.app._automation_toggle_changed()
                            elif name == "dynamic_pips":
                                self.app.dynamic_pips_var.set(bool(value))
                                self.app._dynamic_pips_toggle_changed()
                                self.app._save_automation_config()
                            elif name == "auto_powerplant":
                                self.app.auto_powerplant_var.set(bool(value))
                                self.app._auto_powerplant_toggle_changed()
                                self.setup_overrides[name] = bool(value); self._save_setup_overrides()
                            elif name == "auto_chaff":
                                self.app.auto_chaff_var.set(bool(value))
                                self.app._auto_chaff_toggle_changed()
                                self.setup_overrides[name] = bool(value); self._save_setup_overrides()
                            elif name == "auto_chaff_profile":
                                profile = str(value or "MED").upper()
                                if profile not in ("LOW", "MED", "HIGH"): profile = "MED"
                                self.app.auto_chaff_profile_var.set(profile)
                                self.app._auto_chaff_profile_changed()
                                self.setup_overrides[name] = profile; self._save_setup_overrides()
                            elif name in {"ai_trade_auto", "ai_mission_auto", "ai_travel_auto"}:
                                getattr(self.app, name + "_var").set(bool(value))
                                self.setup_overrides[name] = bool(value); self._save_setup_overrides()
                            elif name == "ai_smart_auto":
                                enabled = bool(value)
                                self.app.ai_auto_var.set(enabled)
                                self.setup_overrides["ai_smart_auto"] = enabled
                                self._save_setup_overrides()
                                self.app.copilot_status = "Automatic AI Assistance ON" if enabled else "Automatic AI Assistance OFF // manual AI remains available"
                            elif name == "commander_address":
                                self.app.commander_address_var.set(str(value or "Commander"))
                                self.app._save_commander_profile()
                            elif name == "ai_context_reset":
                                context = DEFAULT_AI_CONTEXT[:1000]
                                self.setup_overrides["ai_context"] = context
                                self.setup_overrides["ai_context_seeded"] = True
                                self._save_setup_overrides()
                                self.app._qml_user_ai_context = context
                            elif name == "ai_context":
                                context = str(value or "").strip()[:1000]
                                if not context:
                                    context = DEFAULT_AI_CONTEXT[:1000]
                                self.setup_overrides["ai_context"] = context
                                self.setup_overrides["ai_context_seeded"] = True
                                self._save_setup_overrides()
                                self.app._qml_user_ai_context = context
                            elif name == "ai_tool_mode":
                                mode = str(value or "Ask Before Acting").strip()
                                if mode not in ("Suggest Only", "Ask Before Acting", "Auto Navigation"):
                                    mode = "Ask Before Acting"
                                self.app.ai_tool_mode_var.set(mode)
                                self.setup_overrides["ai_tool_mode"] = mode
                                self._save_setup_overrides()
                                self.app.copilot_status = f"Action mode: {mode}"
                            elif name == "bridge_mode":
                                mode = str(value or "CORE").strip().upper()
                                if mode not in ("CORE", "COPILOT"):
                                    mode = "CORE"
                                self.setup_overrides["bridge_mode"] = mode
                                self._save_setup_overrides()
                                if mode == "CORE":
                                    try:
                                        self.app.voice_input_mode_var.set("PTT")
                                    except Exception:
                                        pass
                                self.app.copilot_status = "Core Bridge mode" if mode == "CORE" else "AI Co-Pilot mode"
                            else:
                                raise ValueError("Unknown Setup setting")
                            self.app.refresh_preferences_widgets()
                            self.app._native_set_status(f"Setup setting updated // {name.replace('_',' ').upper()}")
                        except Exception as exc:
                            self.app._native_set_status(f"Setup setting failed // {exc}")
                    self.app.after(0, _apply_setup_setting)
                elif command == "control_keyboard_capture_begin":
                    action = str(item.get("action") or "").strip()
                    try:
                        old = getattr(self.app, "bridge_hotkeys", None)
                        if old:
                            old.stop()
                        print(f"[CONTROL MAP] keyboard capture armed action={action} // global shortcuts suspended", flush=True)
                    except Exception as exc:
                        print(f"[CONTROL MAP] keyboard capture suspend failed: {exc}", flush=True)
                elif command == "control_keyboard_capture_end":
                    try:
                        current = getattr(self.app, "bridge_hotkeys", None)
                        alive = bool(current and getattr(current, "thread", None) and current.thread.is_alive())
                        if not alive:
                            _qml_apply_hotkey_specs(self.app, dict(self.setup_overrides.get("hotkey_overrides") or {}))
                        print("[CONTROL MAP] keyboard capture ended // global shortcuts restored", flush=True)
                    except Exception as exc:
                        print(f"[CONTROL MAP] keyboard capture restore failed: {exc}", flush=True)
                elif command == "control_bind_row":
                    try:
                        row_index = int(item.get("row_index", -1))
                    except Exception:
                        row_index = -1
                    specs = list(legacy.BRIDGE_HOTKEY_SPECS)
                    action = str(specs[row_index][0]).strip() if 0 <= row_index < len(specs) else ""
                    print(f"[CONTROL MAP] REMAP row={row_index} resolved_action={action!r}", flush=True)
                    def _bind_control_row():
                        try:
                            if not action:
                                raise ValueError(f"Unknown Bridge control row {row_index}")
                            current = str(self.app.controller_manager.capture_snapshot() or "")
                            if current:
                                self.app.controller_manager.cancel_capture()
                            if self.app.controller_manager.begin_capture(action):
                                print(f"[CONTROL MAP] HOTAS capture armed row={row_index} action={action}", flush=True)
                                self.app.voice_input_status = f"CONTROL MAPPING ACTIVE // {self.app._controller_action_label(action)} // press one HOTAS/controller button or hat."
                                self.app._native_set_status(self.app.voice_input_status)
                            else:
                                print(f"[CONTROL MAP] HOTAS capture FAILED row={row_index} action={action} status={self.app.controller_manager.status}", flush=True)
                                self.app._native_set_status(f"Control mapping could not start // {self.app.controller_manager.status}")
                        except Exception as exc:
                            print(f"[CONTROL MAP] HOTAS capture ERROR row={row_index} action={action!r} error={exc}", flush=True)
                            self.app._native_set_status(f"Control mapping failed // {exc}")
                    self.app.after(0, _bind_control_row)
                elif command == "control_clear_row":
                    try:
                        row_index = int(item.get("row_index", -1))
                    except Exception:
                        row_index = -1
                    specs = list(legacy.BRIDGE_HOTKEY_SPECS)
                    action = str(specs[row_index][0]).strip() if 0 <= row_index < len(specs) else ""
                    print(f"[CONTROL MAP] CLEAR row={row_index} resolved_action={action!r}", flush=True)
                    def _clear_control_row():
                        try:
                            if not action:
                                raise ValueError(f"Unknown Bridge control row {row_index}")
                            # CLEAR is also the immediate escape hatch from REMAP capture.
                            # Cancel first so a late controller press cannot be captured after clear.
                            active_capture = str(self.app.controller_manager.capture_snapshot() or "")
                            if active_capture:
                                self.app.controller_manager.cancel_capture()
                                print(f"[CONTROL MAP] CLEAR cancelled active capture action={active_capture!r}", flush=True)
                            self.app.controller_bindings.pop(action, None)
                            try:
                                self.app.controller_manager.bindings.pop(action, None)
                            except Exception:
                                pass
                            self.app._save_controller_bindings()
                            self.app.controller_manager.status = f"Cleared controller binding for {self.app._controller_action_label(action)}."
                            self.app._native_set_status(self.app.controller_manager.status)
                            print(f"[CONTROL MAP] CLEAR complete row={row_index} action={action}", flush=True)
                        except Exception as exc:
                            print(f"[CONTROL MAP] CLEAR ERROR row={row_index} action={action!r} error={exc}", flush=True)
                            self.app._native_set_status(f"Control clear failed // {exc}")
                    self.app.after(0, _clear_control_row)
                elif command == "control_bind":
                    action = str(item.get("action") or "").strip()
                    valid = {row[0] for row in legacy.BRIDGE_HOTKEY_SPECS}
                    def _bind_control():
                        try:
                            if action not in valid:
                                raise ValueError("Unknown Bridge control")
                            current = str(self.app.controller_manager.capture_snapshot() or "")
                            if current:
                                self.app.controller_manager.cancel_capture()
                            if self.app.controller_manager.begin_capture(action):
                                print(f"[CONTROL MAP] HOTAS capture armed action={action}", flush=True)
                                self.app.voice_input_status = f"CONTROL MAPPING ACTIVE // {self.app._controller_action_label(action)} // press one HOTAS/controller button or hat."
                                self.app._native_set_status(self.app.voice_input_status)
                            else:
                                print(f"[CONTROL MAP] HOTAS capture FAILED action={action} status={self.app.controller_manager.status}", flush=True)
                                self.app._native_set_status(f"Control mapping could not start // {self.app.controller_manager.status}")
                        except Exception as exc:
                            self.app._native_set_status(f"Control mapping failed // {exc}")
                    self.app.after(0, _bind_control)
                elif command == "control_cancel":
                    def _cancel_control():
                        try:
                            self.app.controller_manager.cancel_capture()
                            self.app.voice_input_status = "CONTROL MAPPING CANCELLED // select a HOTAS cell to map another control."
                            self.app._native_set_status(self.app.voice_input_status)
                        except Exception as exc:
                            self.app._native_set_status(f"Control mapping cancel failed // {exc}")
                    self.app.after(0, _cancel_control)
                elif command == "control_clear":
                    action = str(item.get("action") or "").strip()
                    valid = {row[0] for row in legacy.BRIDGE_HOTKEY_SPECS}
                    def _clear_control():
                        if action in valid:
                            self.app.controller_bindings.pop(action, None)
                            self.app.controller_manager.set_bindings(self.app.controller_bindings)
                            self.app._save_controller_bindings_file()
                            self.app._native_set_status(f"HOTAS binding cleared // {self.app._controller_action_label(action)}")
                    self.app.after(0, _clear_control)
                elif command == "control_set_hotkey":
                    action = str(item.get("action") or "").strip()
                    display = str(item.get("display") or "").strip()
                    try:
                        vk = int(item.get("vk") or 0)
                    except Exception:
                        vk = 0
                    valid = {row[0] for row in legacy.BRIDGE_HOTKEY_SPECS}
                    def _set_hotkey():
                        try:
                            if action not in valid or vk <= 0 or not display:
                                raise ValueError("Invalid Bridge hotkey")
                            overrides = dict(self.setup_overrides.get("hotkey_overrides") or {})
                            overrides[action] = {"display": display, "vk": vk}
                            self.setup_overrides["hotkey_overrides"] = overrides
                            self._save_setup_overrides()
                            _qml_apply_hotkey_specs(self.app, overrides)
                            self.app._native_set_status(f"Bridge shortcut updated // {self.app._controller_action_label(action)} // {display}")
                        except Exception as exc:
                            self.app._native_set_status(f"Bridge shortcut update failed // {exc}")
                    self.app.after(0, _set_hotkey)
                elif command == "control_restore_hotkeys":
                    def _restore_hotkeys():
                        try:
                            self.setup_overrides["hotkey_overrides"] = {}
                            self._save_setup_overrides()
                            _qml_apply_hotkey_specs(self.app, {})
                            self.app._native_set_status("Bridge keyboard shortcuts restored to factory defaults // HOTAS mappings unchanged.")
                        except Exception as exc:
                            self.app._native_set_status(f"Restore default shortcuts failed // {exc}")
                    self.app.after(0, _restore_hotkeys)
                elif command == "control_copy_hotkey":
                    action = str(item.get("action") or "").strip()
                    row = next((r for r in legacy.BRIDGE_HOTKEY_SPECS if r[0] == action), None)
                    if row:
                        try:
                            self.app.clipboard_clear(); self.app.clipboard_append(str(row[1])); self.app.update_idletasks()
                            self.app._native_set_status(f"Stream Deck / keyboard shortcut copied // {row[3]} // {row[1]}")
                        except Exception as exc:
                            self.app._native_set_status(f"Could not copy shortcut // {exc}")
                elif command == "ai_usage_reset":
                    self._reset_ai_usage()
                    try:
                        self.app._native_set_status("AI usage counter reset // usage totals only // API key and all settings are unchanged.")
                    except Exception:
                        pass
                elif command == "audio_rescan":
                    # Re-enumerate current Windows/PortAudio defaults.  If Always Listen
                    # owns an open capture stream, restart that stream so the new default
                    # can actually take effect without restarting the whole Bridge.
                    always_listen = str(self.app.voice_input_mode_var.get() or "PTT").strip().upper() == "ALWAYS LISTEN"
                    if always_listen:
                        try:
                            self.app._stop_always_listen()
                        except Exception:
                            pass
                    self.app._refresh_audio_devices(save=True)
                    if always_listen:
                        try:
                            self.app.after(300, self.app._start_always_listen)
                        except Exception:
                            pass
                    self.app._native_set_status(
                        f"Audio devices rescanned // input {getattr(self.app, 'audio_default_input', 'System Default')} // "
                        f"output {getattr(self.app, 'audio_default_output', 'System Default')}"
                    )
                elif command == "ptt_map":
                    # QML-native one-click PTT capture.  The old implementation opened
                    # the hidden Tk command-map window behind QML, which looked like a no-op.
                    def _toggle_ptt_capture():
                        try:
                            current = str(self.app.controller_manager.capture_snapshot() or "")
                            if current == "push_to_talk":
                                self.app.controller_manager.cancel_capture()
                                self.app.voice_input_status = "PTT mapping cancelled."
                                self.app._native_set_status("PTT mapping cancelled.")
                            elif self.app.controller_manager.begin_capture("push_to_talk"):
                                self.app.voice_input_status = "PTT MAPPING ACTIVE // press one HOTAS/controller button or hat direction now."
                                self.app._native_set_status("PTT MAPPING // press one HOTAS/controller button or hat direction.")
                            else:
                                self.app.voice_input_status = f"PTT mapping could not start // {self.app.controller_manager.status}"
                                self.app._native_set_status(f"PTT mapping could not start // {self.app.controller_manager.status}")
                            self.app.refresh_preferences_widgets()
                        except Exception as exc:
                            self.app.voice_input_status = f"PTT mapping failed // {exc}"
                            self.app._native_set_status(f"PTT mapping failed // {exc}")
                    self.app.after(0, _toggle_ptt_capture)
                elif command == "voice_toggle_input_mode":
                    def _toggle_input_mode():
                        current = str(self.app.voice_input_mode_var.get() or "PTT").strip().upper()
                        self.app.voice_input_mode_var.set("ALWAYS LISTEN" if current != "ALWAYS LISTEN" else "PTT")
                        self.app._voice_input_mode_changed(save=True)
                        wanted = str(self.app.voice_input_mode_var.get() or "PTT").strip().upper()
                        self.app._native_set_status(f"Voice input mode // {wanted}")
                    self.app.after(0, _toggle_input_mode)
                elif command == "voice_cycle_level":
                    def _cycle_voice_level():
                        levels = ["OFF", "LOW", "MED", "HIGH"]
                        current = str(self.app.voice_level_var.get() or "MED").strip().upper()
                        try: idx = levels.index(current)
                        except ValueError: idx = 2
                        self.app.voice_level_var.set(levels[(idx + 1) % len(levels)])
                        self.app._voice_profile_changed()
                    self.app.after(0, _cycle_voice_level)
                elif command == "voice_cycle_attention":
                    def _cycle_attention():
                        # Public wizard semantics: this one three-position control sets
                        # both commentary density and the generic pre-voice attention cue.
                        # OFF remains safety-capable by mapping to the legacy LOW chatter
                        # profile rather than disabling speech completely.
                        values = ["OFF", "IMPORTANT", "MOST"]
                        chatter = {"OFF": "LOW", "IMPORTANT": "MED", "MOST": "HIGH"}
                        current = str(self.app.voice_attention_mode_var.get() or "IMPORTANT").strip().upper()
                        try: idx = values.index(current)
                        except ValueError: idx = 1
                        next_value = values[(idx + 1) % len(values)]
                        self.app.voice_attention_mode_var.set(next_value)
                        self.app.voice_level_var.set(chatter[next_value])
                        self.app._save_automation_config()
                        self.app.voice_history.append(
                            f"{time.strftime('%H:%M:%S')}  PROFILE | TALK/ATTENTION {next_value} // {chatter[next_value]}"
                        )
                        self.app._native_set_status(
                            f"Talk / Attention // {next_value} // commentary profile {chatter[next_value]}"
                        )
                        self.app.refresh_preferences_widgets()
                    self.app.after(0, _cycle_attention)
                elif command == "voice_set_attention":
                    # Capture this command before the queue advances to the UI cue.
                    def _set_attention(value=item.get("value")):
                        value = str(value or "IMPORTANT").strip().upper()
                        if value not in {"OFF", "IMPORTANT", "MOST"}:
                            value = "IMPORTANT"
                        chatter = {"OFF": "LOW", "IMPORTANT": "MED", "MOST": "HIGH"}
                        self.app.voice_attention_mode_var.set(value)
                        self.app.voice_level_var.set(chatter[value])
                        self.app._save_automation_config()
                        self.app.voice_history.append(
                            f"{time.strftime('%H:%M:%S')}  PROFILE | TALK/ATTENTION {value} // {chatter[value]}"
                        )
                        self.app._native_set_status(
                            f"Talk / Attention // {value} // commentary profile {chatter[value]}"
                        )
                        self.app.refresh_preferences_widgets()
                    self.app.after(0, _set_attention)
                elif command == "ai_cycle_tool_mode":
                    def _cycle_tool_mode():
                        values = ["Suggest Only", "Ask Before Acting", "Auto Navigation"]
                        current = str(self.app.ai_tool_mode_var.get() or "Ask Before Acting").strip()
                        try: idx = values.index(current)
                        except ValueError: idx = 2
                        self.app.ai_tool_mode_var.set(values[(idx + 1) % len(values)])
                        self.setup_overrides["ai_tool_mode"] = str(self.app.ai_tool_mode_var.get())
                        self._save_setup_overrides()
                        self.app.copilot_status = f"Action mode: {self.app.ai_tool_mode_var.get()}"
                        self.app.refresh_preferences_widgets()
                    self.app.after(0, _cycle_tool_mode)
                elif command == "ai_toggle_smart_auto":
                    def _toggle_smart_auto():
                        self.app.ai_auto_var.set(not bool(self.app.ai_auto_var.get()))
                        self.setup_overrides["ai_smart_auto"] = bool(self.app.ai_auto_var.get())
                        self._save_setup_overrides()
                        self.app._native_set_status(f"Smart Auto AI {'ON' if self.app.ai_auto_var.get() else 'OFF'}.")
                    self.app.after(0, _toggle_smart_auto)
                elif command == "ai_toggle_launch_rule":
                    def _toggle_launch_rule():
                        enabled = not bool((getattr(self.app, "session_rules", {}) or {}).get("clear_and_jump_after_auto_launch", False))
                        self.app._copilot_set_session_rule_tool({"rule": "clear_and_jump_after_auto_launch", "enabled": enabled})
                        self.app._native_set_status(f"Session rule clear + jump after launch {'ON' if enabled else 'OFF'}.")
                    self.app.after(0, _toggle_launch_rule)
                elif command == "ai_approve":
                    self.app.after(0, self.app.approve_pending_copilot_action)
                elif command == "ai_reject":
                    self.app.after(0, self.app.reject_pending_copilot_action)
                elif command == "clear_rules":
                    def _clear_rules():
                        changed = False
                        for rule in list((getattr(self.app, "session_rules", {}) or {}).keys()):
                            if self.app.session_rules.get(rule):
                                self.app.session_rules[rule] = False
                                changed = True
                        stamp = time.strftime("%H:%M:%S")
                        self.app.session_rule_history.append(f"{stamp}  CLEARED ALL SESSION RULES")
                        self.app._native_set_status("Session rules cleared." if changed else "No session rules were active.")
                        self.app.refresh_preferences_widgets()
                    self.app.after(0, _clear_rules)
                elif command == "nav_plot":
                    destination = str(item.get("destination") or "").strip()
                    self.app.nav_destination_var.set(destination)
                    self.app.nav_log(f"QML route request: {destination}")
                    self.app.nav_portable_route_current()
                elif command == "nav_memory_plot":
                    slot = str(item.get("slot") or "").strip().lower()
                    values = _load_nav_memories()
                    destination = _sanitize_nav_memory_value(values.get(slot, ""))
                    if not destination:
                        self.app.nav_log(f"Navigation memory {slot} is not set.")
                    else:
                        self.app.nav_quick_route(destination)
                elif command == "nav_memory_set":
                    slot = str(item.get("slot") or "").strip().lower()
                    destination = str(item.get("destination") or "").strip()
                    values = _save_nav_memory(slot, destination)
                    shown = values.get(slot, "") or "UNSET"
                    self.app.nav_log(f"Navigation memory {slot.upper()} saved: {shown}")
                elif command == "nav_memory_capture":
                    slot = str(item.get("slot") or "").strip().lower()
                    state = self.app.state_data
                    destination = _sanitize_nav_memory_value(getattr(state, "nav_route_destination", ""))
                    if destination in ("", "-"):
                        destination = _sanitize_nav_memory_value(getattr(state, "system", ""))
                    if not destination or destination == "-":
                        self.app.nav_log(f"Navigation memory {slot.upper()} was not saved: no plotted target/current system available.")
                    else:
                        values = _save_nav_memory(slot, destination)
                        shown = values.get(slot, "") or "UNSET"
                        self.app.nav_log(f"Navigation memory {slot.upper()} captured from cockpit state: {shown}")
                elif command == "colonization_project_use_index":
                    idx = int(item.get("index", -1))
                    projects = _colonization_project_records(self.app.state_data)
                    if 0 <= idx < len(projects):
                        market_id = projects[idx].get("marketId")
                        if self.app.state_data._restore_colonization_project(market_id):
                            try:
                                self.app.refresh_colonization_widgets()
                            except Exception:
                                pass
                elif command == "colonization_find_supply":
                    commodity = str(item.get("commodity") or "").strip()
                    try:
                        requested = max(1, int(float(item.get("quantity") or 1)))
                    except Exception:
                        requested = 1
                    try:
                        capacity = max(1, int(float(getattr(self.app.state_data, "cargo_capacity", 0) or requested)))
                    except Exception:
                        capacity = requested
                    cargo = max(1, min(requested, capacity))
                    try:
                        max_ly = max(5, min(500, int(float(item.get("max_ly") or 100))))
                    except Exception:
                        max_ly = 100
                    try:
                        self.trade_route_max_ls = max(100, min(100000, int(float(item.get("max_ls") or 10000))))
                    except Exception:
                        self.trade_route_max_ls = 10000
                    try:
                        min_runs = max(1, min(100, int(float(item.get("min_runs") or 1))))
                    except Exception:
                        min_runs = 1
                    self.app.trade_loop_commodity_var.set(commodity)
                    self.app.trade_loop_cargo_var.set(str(cargo))
                    self.app.loop_search_follow_current_var.set(True)
                    self.app.loop_search_commodity_var.set(commodity)
                    self.app.loop_search_cargo_var.set(str(cargo))
                    self.app.loop_search_min_loops_var.set(str(min_runs))
                    self.app.loop_search_radius_var.set(str(max_ly))
                    self.app.loop_search_max_leg_var.set(str(max_ly))
                    self.app.loop_search_age_var.set("7")
                    self.app.loop_search_exclude_carriers_var.set(True)
                    self.app.loop_search_ship_compatible_var.set(True)
                    self.app.loop_search_prefer_orbital_var.set(True)
                    self.app.trade_loop_status = f"COLONY SUPPLY TARGET // {commodity} // {cargo:,} T"
                    self.app.trade_loop_search_run()
                elif command == "trade_route_search":
                    commodity = str(item.get("commodity") or self.app.trade_loop_commodity_var.get() or "").strip()
                    try: max_ly = max(5, min(500, int(float(item.get("max_ly") or 100))))
                    except Exception: max_ly = 100
                    try: self.trade_route_max_ls = max(100, min(100000, int(float(item.get("max_ls") or 10000))))
                    except Exception: self.trade_route_max_ls = 10000
                    try: min_runs = max(1, min(100, int(float(item.get("min_runs") or 5))))
                    except Exception: min_runs = 5
                    try: cargo = max(1, int(float(getattr(self.app.state_data, "cargo_capacity", 0) or 1)))
                    except Exception: cargo = 1
                    self.app.loop_search_follow_current_var.set(True)
                    self.app.loop_search_commodity_var.set(commodity)
                    self.app.loop_search_cargo_var.set(str(cargo))
                    self.app.loop_search_min_loops_var.set(str(min_runs))
                    self.app.loop_search_radius_var.set(str(max_ly))
                    self.app.loop_search_max_leg_var.set(str(max_ly))
                    self.app.loop_search_age_var.set("7")
                    self.app.loop_search_exclude_carriers_var.set(True)
                    self.app.loop_search_ship_compatible_var.set(True)
                    self.app.loop_search_prefer_orbital_var.set(True)
                    self.app.trade_loop_search_run()
                elif command == "trade_best_search":
                    # max_ly remains accepted as a backward-compatible fallback.
                    try: max_start_ly = max(5, min(500, int(float(item.get("max_start_ly") or item.get("max_ly") or 100))))
                    except Exception: max_start_ly = 100
                    try: max_leg_ly = max(5, min(500, int(float(item.get("max_leg_ly") or item.get("max_ly") or 100))))
                    except Exception: max_leg_ly = 100
                    try: max_ls = max(100, min(100000, int(float(item.get("max_ls") or 10000))))
                    except Exception: max_ls = 10000
                    try: min_runs = max(1, min(100, int(float(item.get("min_runs") or 5))))
                    except Exception: min_runs = 5
                    try: cargo = max(1, int(float(getattr(self.app.state_data, "cargo_capacity", 0) or 1)))
                    except Exception: cargo = 1
                    legality = str(item.get("legality") or "LEGAL ONLY").strip().upper()
                    rare_mode = str(item.get("rare_mode") or "EXCLUDE").strip().upper()
                    anchor_system = str(getattr(self.app.state_data, "system", "") or "").strip()
                    if not anchor_system or anchor_system == "-":
                        with self.trade_best_lock:
                            self.trade_best_status = "BEST TRADE SEARCH NEEDS A VALID CURRENT SYSTEM"
                    elif not self.trade_best_busy:
                        origin_coords = getattr(self.app.state_data, "system_pos", None)
                        self._run_best_trade_search(anchor_system, cargo, min_runs, max_start_ly, max_leg_ly, max_ls, legality, rare_mode, origin_coords)
                elif command == "trade_best_use_index":
                    idx = int(item.get("index", -1))
                    pairs = list(self.trade_best_pairs or [])
                    if 0 <= idx < len(pairs):
                        pair = pairs[idx]; buy = pair.get("buy") or {}; sell = pair.get("sell") or {}
                        self.app.trade_loop_commodity_var.set(str(pair.get("commodity") or ""))
                        try: cap = max(1, int(float(getattr(self.app.state_data, "cargo_capacity", 0) or 1)))
                        except Exception: cap = 1
                        self.app.trade_loop_cargo_var.set(str(cap))
                        self.app.trade_loop_buy_system_var.set(str(buy.get("system") or ""))
                        self.app.trade_loop_buy_station_var.set(str(buy.get("station") or ""))
                        self.app.trade_loop_sell_system_var.set(str(sell.get("system") or ""))
                        self.app.trade_loop_sell_station_var.set(str(sell.get("station") or ""))
                        try: self.app._save_trade_loop_config()
                        except Exception: pass
                        self.app.trade_loop_status = f"BEST ROUTE LOADED // {pair.get('commodity','?')} // {buy.get('station')} -> {sell.get('station')} // SCORE {float(pair.get('score') or 0):.1f}"
                        try: self.app.refresh_trade_loop_widgets()
                        except Exception: pass
                elif command == "trade_route_use_index":
                    idx = int(item.get("index", -1))
                    pairs = list(self.trade_route_filtered_pairs or [])
                    if 0 <= idx < len(pairs):
                        pair = pairs[idx]; buy = pair.get("buy") or {}; sell = pair.get("sell") or {}
                        self.app.trade_loop_commodity_var.set(str(pair.get("commodity") or ""))
                        try: cap = max(1, int(float(getattr(self.app.state_data, "cargo_capacity", 0) or 1)))
                        except Exception: cap = 1
                        self.app.trade_loop_cargo_var.set(str(cap))
                        self.app.trade_loop_buy_system_var.set(str(buy.get("system") or ""))
                        self.app.trade_loop_buy_station_var.set(str(buy.get("station") or ""))
                        self.app.trade_loop_sell_system_var.set(str(sell.get("system") or ""))
                        self.app.trade_loop_sell_station_var.set(str(sell.get("station") or ""))
                        try: self.app._save_trade_loop_config()
                        except Exception: pass
                        self.app.trade_loop_status = f"ROUTE LOADED // {buy.get('station')} -> {sell.get('station')} // {int(pair.get('profit_per_load') or 0):,} CR/LOAD"
                        try: self.app.refresh_trade_loop_widgets()
                        except Exception: pass
                elif command == "trade_learn_recent":
                    self.app.trade_loop_learn_recent()
                elif command == "trade_config":
                    self._apply_trade_profile(item)
                elif command == "trade_buy":
                    self.app.trade_loop_plot_buy()
                elif command == "trade_sell":
                    self.app.trade_loop_plot_sell()
                elif command == "trade_start":
                    if any(k in item for k in ("commodity", "cargo", "buy_system", "buy_station", "sell_system", "sell_station", "run_length")):
                        self._apply_trade_profile(item)
                    self.trade_run_baseline_sells = self._trade_sell_count()
                    self.trade_run_completed_cycles = 0
                    self.app.start_resume_trade_loop()
                    if bool(self.app.trade_loop_enabled_var.get()):
                        run_text = "CONTINUOUS" if self.trade_run_target_cycles <= 0 else f"{self.trade_run_target_cycles} CYCLES"
                        self.app.trade_loop_status = f"LONG RUN ACTIVE // {run_text} // " + str(self.app.trade_loop_status)
                elif command == "trade_pause":
                    if bool(self.app.trade_loop_enabled_var.get()):
                        self.app.trade_loop_enabled_var.set(False)
                        self.app.toggle_trade_loop()
                    else:
                        self.app.trade_loop_status = "Loop is already disabled."
                        self.app.refresh_trade_loop_widgets()
                elif command == "combat_mode":
                    self.app.start_ensure_combat_mode()
                elif command == "combat_enter":
                    _combat_enter(self.app)
                elif command == "combat_leave":
                    _combat_leave(self.app)
                elif command == "combat_threat":
                    self.app.start_target_highest_threat()
                elif command == "combat_powerplant":
                    self.app.start_target_power_plant()
                elif command == "combat_best_target":
                    self.app.start_find_best_target()
                elif command == "combat_egress":
                    # A QML click makes the dashboard foreground.  Permission was
                    # granted by the parent process, so explicitly restore Elite
                    # before invoking .95's strict foreground/GUIfocus checks.
                    try:
                        self.app.key_sender.focus_elite()
                        time.sleep(0.12)
                    except Exception:
                        pass
                    self.app.start_emergency_egress()
                elif command == "combat_toggle_pips":
                    new_value = not bool(self.app.dynamic_pips_var.get())
                    self.app.dynamic_pips_var.set(new_value)
                    self.app._dynamic_pips_toggle_changed()
                elif command == "combat_toggle_subsystem":
                    new_value = not bool(self.app.auto_powerplant_var.get())
                    self.app.auto_powerplant_var.set(new_value)
                    self.app._auto_powerplant_toggle_changed()
                elif command == "combat_fighter_1":
                    if _fighter_deploy_preflight(self.app, 1):
                        self.app.start_deploy_fighter(1)
                elif command == "combat_fighter_2":
                    if _fighter_deploy_preflight(self.app, 2):
                        self.app.start_deploy_fighter(2)
                elif command == "combat_fighter_recall":
                    if _fighter_recall_preflight(self.app):
                        self.app.start_recall_fighter()
                elif command == "combat_wing_target_1":
                    if _wing_preflight(self.app, "Wing 1 Target"):
                        self.app.start_assist_wing(1)
                elif command == "combat_wing_target_2":
                    if _wing_preflight(self.app, "Wing 2 Target"):
                        self.app.start_assist_wing(2)
                elif command == "combat_wing_target_3":
                    if _wing_preflight(self.app, "Wing 3 Target"):
                        self.app.start_assist_wing(3)
                elif command == "combat_navlock_1":
                    if _wing_preflight(self.app, "Wing 1 Nav Lock"):
                        self.app.start_wing_nav_lock(1)
                elif command == "combat_navlock_2":
                    if _wing_preflight(self.app, "Wing 2 Nav Lock"):
                        self.app.start_wing_nav_lock(2)
                elif command == "combat_navlock_3":
                    if _wing_preflight(self.app, "Wing 3 Nav Lock"):
                        self.app.start_wing_nav_lock(3)
                elif command == "combat_firegroup_next":
                    def cycle_fire_group():
                        binding = self.app._native_binding("CycleFireGroupNext")
                        self.app._native_tap(binding, pause=0.10)
                        self.app.native_command_status = "Fire Group: cycled to next group."
                    self.app._native_begin("Cycle Fire Group", cycle_fire_group)
                elif command in {"combat_res_high", "combat_res_haz"}:
                    want_haz = command == "combat_res_haz"
                    self.app.res_search_high_var.set(not want_haz)
                    self.app.res_search_haz_var.set(want_haz)
                    # Combat page always uses the practical 10k-LS supercruise ceiling.
                    self.app.res_search_max_ls_var.set("10000")
                    self.app.find_nearby_res()
                elif command in {"combat_res_plot", "combat_res_plot_index"}:
                    rows = list(getattr(self.app, "res_search_results", []) or [])
                    eligible = []
                    for source_index, candidate in enumerate(rows):
                        try:
                            candidate_ls = float(candidate.get("res_ls", -1))
                        except Exception:
                            candidate_ls = -1
                        if 0 <= candidate_ls <= 10000.0:
                            eligible.append((source_index, candidate))
                        if len(eligible) >= 50:
                            break
                    qml_index = 0 if command == "combat_res_plot" else int(item.get("index", -1))
                    if qml_index < 0 or qml_index >= len(eligible):
                        self.app.res_search_status = "The selected RES result is no longer available. Refresh the search."
                    else:
                        idx, selected = eligible[qml_index]
                        row = dict(selected)
                        system = str(row.get("system") or "").strip()
                        kind = str(row.get("type") or "RES")
                        body = str(row.get("body") or "-")
                        if system:
                            self.app.res_selected_result = row
                            self.app.res_selected_signature = (kind, system, body)
                            self.app.res_search_status = f"Plotting selected {kind}: {system} / {body}."
                            self.app.nav_quick_route(system)
            except Exception as exc:
                # Keep failure handling inside the .95 status channel rather than
                # inventing a second command state machine in the adapter.
                try:
                    self.app._native_set_status(f"QML command request failed: {exc}")
                except Exception:
                    pass
        try:
            self.app.after(40, self.drain_commands)
        except Exception:
            pass

    def run(self):
        self.start_http()
        self.app = HeadlessBridgeApp()
        self.app._qml_host = self
        _qml_restrict_controller_bindings_to_ptt(self.app)
        self._apply_setup_overrides()
        try:
            _qml_apply_hotkey_specs(self.app, self.setup_overrides.get("hotkey_overrides") or {})
        except Exception as exc:
            print(f"[HOTKEY] adapter override apply failed: {exc}", flush=True)
        # v0.29.43 intentionally retires Always Listen from the QML product surface.
        # PTT remains the required, predictable input mode.
        try:
            self.app.voice_input_mode_var.set("PTT")
            self.app._voice_input_mode_changed(save=True)
        except Exception:
            pass
        _install_strong_elite_focus(self.app)
        _install_combat_intent_overrides(self.app)
        try:
            self.app.withdraw()
        except Exception:
            pass
        self.app.after(50, self.drain_commands)
        self.app.after(100, self.refresh_snapshot)
        try:
            self.app.mainloop()
        finally:
            self._save_ai_usage_totals(force=True)
            self.stop_http()


def _portable_voice_check() -> int:
    """Verify the frozen release can load bundled Supertonic without the network."""
    try:
        from supertonic import TTS
        model_dir = os.environ.get("SUPERTONIC_CACHE_DIR", "").strip()
        if not model_dir:
            raise RuntimeError("SUPERTONIC_CACHE_DIR is not configured")
        model_path = Path(model_dir)
        if not model_path.is_dir():
            raise RuntimeError(f"Bundled Supertonic model folder is missing: {model_path}")
        tts = TTS(model="supertonic-3", auto_download=False)
        voice = "F5" if "F5" in tuple(getattr(tts, "voice_style_names", ()) or ()) else "M1"
        style = tts.get_voice_style(voice_name=voice)
        wav, _ = tts.synthesize(text="Bridge voice ready.", voice_style=style, lang="en", total_steps=5, speed=1.0)
        if wav is None:
            raise RuntimeError("Supertonic returned no audio")
        print(f"SUPERTONIC_PORTABLE_CHECK_OK // {voice} // {model_path}")
        return 0
    except Exception as exc:
        print(f"SUPERTONIC_PORTABLE_CHECK_FAILED // {exc}")
        return 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int)
    parser.add_argument("--token")
    parser.add_argument("--portable-voice-check", action="store_true")
    args = parser.parse_args()
    if args.portable_voice_check:
        return _portable_voice_check()
    if args.port is None or not args.token:
        parser.error("--port and --token are required for normal Bridge runtime")
    BridgeHost(args.port, args.token).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
