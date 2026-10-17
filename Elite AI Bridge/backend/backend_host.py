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

# Supertonic (ONNX) uses every CPU core by default and its worker threads spin while
# waiting, which starved the cockpit's animations whenever the voice was synthesizing
# (worst in the first minute: welcome lines plus the phrase warm-up). Cap it; speech is
# still made faster than it plays. An explicit setting in the environment wins.
try:
    _cores = os.cpu_count() or 4
    os.environ.setdefault("SUPERTONIC_INTRA_OP_THREADS", str(max(2, min(4, _cores // 4))))
    os.environ.setdefault("SUPERTONIC_INTER_OP_THREADS", "1")
except Exception:
    pass

import EliteAIBridge_v0_12_95 as legacy


class _QmlEliteState(legacy.EliteState):
    """Commander page extras the engine reads past: Statistics (Elite's own career
    totals, written at login), Reputation (superpower standing) and Promotion
    (live rank-ups, for the rank board animation). Also keeps the ship ID, and
    clears the ship name when the new ship has none (.95 kept the previous
    ship's name after swapping to an unnamed ship)."""

    def process_event(self, e, seed=False):
        result = super().process_event(e, seed=seed)
        try:
            ev = e.get("event")
            if not seed:
                self._qml_odd_count(e, ev)
            if ev == "Statistics":
                self.qml_statistics = dict(e)
            elif ev == "Reputation":
                self.qml_reputation = {k: e.get(k) for k in ("Empire", "Federation", "Alliance", "Independent") if e.get(k) is not None}
            elif ev == "Promotion" and not seed:
                key = next((k for k in e.keys() if k not in ("timestamp", "event")), "")
                if key:
                    old = getattr(self, "qml_promotion", None) or {}
                    self.qml_promotion = {"serial": int(old.get("serial", 0)) + 1, "key": key, "rank": e.get(key)}
            elif ev == "Loadout":
                self.qml_ship_ident = str(e.get("ShipIdent") or "").strip()
                self.ship_name = str(e.get("ShipName") or "").strip()
                try:
                    self.qml_rebuy = int(e.get("Rebuy") or 0)
                except Exception:
                    self.qml_rebuy = 0
                self.qml_loadout = _qml_loadout_rows(e.get("Modules"))
        except Exception:
            pass
        return result

    def _qml_odd_count(self, e, ev):
        """Session counts for Commander > ODD STATS (live events only, never the startup replay)."""
        c = getattr(self, "qml_odd", None)
        if c is None:
            c = self.qml_odd = {}
        def add(k, n=1):
            c[k] = c.get(k, 0) + n
        try:
            if ev == "Scanned":
                add("scanned")
            elif ev == "Interdicted":
                add("interdicted")
            elif ev == "EscapeInterdiction":
                add("escaped")
            elif ev == "UnderAttack":
                add("attacked")
            elif ev == "FuelScoop":
                add("scooped", float(e.get("Scooped") or 0))
            elif ev == "FSDJump":
                d = float(e.get("JumpDist") or 0)
                add("ly", d)
                c["longest"] = max(float(c.get("longest", 0)), d)
            elif ev == "HeatWarning":
                add("heat")
            elif ev == "ReceiveText" and str(e.get("Channel") or "").lower() == "npc":
                add("npc")
            elif ev == "MaterialCollected":
                add("mats", int(e.get("Count") or 1))
            elif ev == "DockingDenied":
                add("denied")
            elif ev == "JetConeBoost":
                add("neutron")
            elif ev == "Died":
                add("died")
        except Exception:
            pass


def _qml_odd_stats(state):
    """Commander > ODD STATS rows: {label, value, note, session}. Only numbers worth showing
    (zero is skipped). Session rows first, then Elite's own records from Statistics."""
    def n(v, d=0):
        try:
            return float(v)
        except Exception:
            return 0.0
    def whole(v):
        return f"{int(round(n(v))):,}"
    def cr(v):
        v = n(v)
        for div, suf in ((1e9, " B"), (1e6, " M"), (1e3, " K")):
            if abs(v) >= div:
                return f"{v / div:.1f}{suf} CR"
        return f"{int(v):,} CR"
    rows = []
    def put(label, raw, value, note="", session=False):
        if n(raw) > 0:
            rows.append({"label": label, "value": value, "note": note, "session": session})

    c = dict(getattr(state, "qml_odd", None) or {})
    put("TIMES SCANNED", c.get("scanned"), whole(c.get("scanned")), "SOMEONE ALWAYS WANTS A LOOK IN YOUR HOLD", True)
    put("INTERDICTED", c.get("interdicted"), whole(c.get("interdicted")), f"ESCAPED {whole(c.get('escaped'))}" if c.get("escaped") else "", True)
    put("UNDER ATTACK WARNINGS", c.get("attacked"), whole(c.get("attacked")), "", True)
    put("LONGEST JUMP", c.get("longest"), f"{n(c.get('longest')):.1f} LY", f"{n(c.get('ly')):,.0f} LY JUMPED IN ALL", True)
    put("FUEL SCOOPED", c.get("scooped"), f"{n(c.get('scooped')):,.1f} T", "", True)
    put("NEUTRON BOOSTS", c.get("neutron"), whole(c.get("neutron")), "", True)
    put("HEAT WARNINGS", c.get("heat"), whole(c.get("heat")), "", True)
    put("NPC MESSAGES", c.get("npc"), whole(c.get("npc")), "MOSTLY THREATS", True)
    put("MATERIALS PICKED UP", c.get("mats"), whole(c.get("mats")), "", True)
    put("DOCKING DENIED", c.get("denied"), whole(c.get("denied")), "", True)
    put("SHIPS LOST", c.get("died"), whole(c.get("died")), "", True)

    st = getattr(state, "qml_statistics", None) or {}
    def g(sec, key):
        return (st.get(sec) or {}).get(key)
    p = "Passengers"
    put("PASSENGERS EJECTED", g(p, "Passengers_Missions_Ejected"), whole(g(p, "Passengers_Missions_Ejected")),
        f"OUT OF {whole(g(p, 'Passengers_Missions_Delivered'))} DELIVERED")
    put("CRIMINALS FLOWN AS VIPS", g(p, "Passengers_Missions_Criminal_vip_delivered"), whole(g(p, "Passengers_Missions_Criminal_vip_delivered")), "NO QUESTIONS ASKED")
    put("HEADS OF STATE CARRIED", g(p, "Passengers_Missions_HeadOfState_vip_delivered"), whole(g(p, "Passengers_Missions_HeadOfState_vip_delivered")), "")
    put("DISGRUNTLED PASSENGERS", g(p, "Passengers_Missions_Disgruntled"), whole(g(p, "Passengers_Missions_Disgruntled")), "")
    put("SHIPS LOST (REBUYS)", g("Bank_Account", "Insurance_Claims"), whole(g("Bank_Account", "Insurance_Claims")),
        f"{cr(g('Bank_Account', 'Spent_On_Insurance'))} IN REBUYS" if n(g("Bank_Account", "Spent_On_Insurance")) else "")
    put("SPENT ON REPAIRS", g("Bank_Account", "Spent_On_Repairs"), cr(g("Bank_Account", "Spent_On_Repairs")), "")
    put("SPENT ON FUEL", g("Bank_Account", "Spent_On_Fuel"), cr(g("Bank_Account", "Spent_On_Fuel")), "")
    put("CREW WAGES PAID", g("Crew", "NpcCrew_TotalWages"), cr(g("Crew", "NpcCrew_TotalWages")),
        f"{whole(g('Crew', 'NpcCrew_Hired'))} HIRED, {whole(g('Crew', 'NpcCrew_Fired'))} FIRED" if n(g("Crew", "NpcCrew_Hired")) else "")
    put("CREW LOST", g("Crew", "NpcCrew_Died"), whole(g("Crew", "NpcCrew_Died")), "")
    put("FINES", g("Crime", "Fines"), whole(g("Crime", "Fines")), f"{cr(g('Crime', 'Total_Fines'))} PAID" if n(g("Crime", "Total_Fines")) else "")
    put("BOUNTIES ON YOU", g("Crime", "Bounties_Received"), whole(g("Crime", "Bounties_Received")),
        f"BIGGEST {cr(g('Crime', 'Highest_Bounty'))}" if n(g("Crime", "Highest_Bounty")) else "")
    put("SKIMMERS KILLED", g("Combat", "Skimmers_Killed"), whole(g("Combat", "Skimmers_Killed")), "")
    put("BIGGEST SINGLE BOUNTY", g("Combat", "Highest_Single_Reward"), cr(g("Combat", "Highest_Single_Reward")), "")
    put("BIGGEST SINGLE TRADE", g("Trading", "Highest_Single_Transaction"), cr(g("Trading", "Highest_Single_Transaction")), "")
    put("BLACK MARKETS USED", g("Smuggling", "Black_Markets_Traded_With"), whole(g("Smuggling", "Black_Markets_Traded_With")),
        f"{whole(g('Smuggling', 'Resources_Smuggled'))} T SMUGGLED" if n(g("Smuggling", "Resources_Smuggled")) else "")
    put("FARTHEST FROM HOME", g("Exploration", "Greatest_Distance_From_Start"), f"{n(g('Exploration', 'Greatest_Distance_From_Start')):,.0f} LY", "")
    put("LIGHT YEARS JUMPED", g("Exploration", "Total_Hyperspace_Distance"), f"{n(g('Exploration', 'Total_Hyperspace_Distance')):,.0f} LY", "")
    l2, l3 = n(g("Exploration", "Planets_Scanned_To_Level_2")), n(g("Exploration", "Planets_Scanned_To_Level_3"))
    put("PLANETS SCANNED", l2 + l3, f"{int(l2 + l3):,}", f"{int(l3):,} FULLY MAPPED" if l3 else "")
    put("DISTANCE WALKED", g("Exploration", "OnFoot_Distance_Travelled"), f"{whole(g('Exploration', 'OnFoot_Distance_Travelled'))} M", "")
    put("THARGOID ENCOUNTERS", g("TG_ENCOUNTERS", "TG_ENCOUNTER_TOTAL"), whole(g("TG_ENCOUNTERS", "TG_ENCOUNTER_TOTAL")),
        ("LAST: " + str(g("TG_ENCOUNTERS", "TG_ENCOUNTER_TOTAL_LAST_SYSTEM") or "").upper()) if g("TG_ENCOUNTERS", "TG_ENCOUNTER_TOTAL_LAST_SYSTEM") else "")
    put("ENGINEERING ROLLS", g("Crafting", "Recipes_Generated"), whole(g("Crafting", "Recipes_Generated")),
        f"WITH {whole(g('Crafting', 'Count_Of_Used_Engineers'))} ENGINEERS" if n(g("Crafting", "Count_Of_Used_Engineers")) else "")
    put("MATERIALS TRADED", g("Material_Trader_Stats", "Materials_Traded"), whole(g("Material_Trader_Stats", "Materials_Traded")), "")
    put("MULTICREW TIME", g("Multicrew", "Multicrew_Time_Total"), f"{n(g('Multicrew', 'Multicrew_Time_Total')) / 3600:.1f} H", "")
    put("CARRIER JUMPS", g("FLEETCARRIER", "FLEETCARRIER_TOTAL_JUMPS"), whole(g("FLEETCARRIER", "FLEETCARRIER_TOTAL_JUMPS")),
        f"{n(g('FLEETCARRIER', 'FLEETCARRIER_DISTANCE_TRAVELLED')):,.0f} LY" if n(g("FLEETCARRIER", "FLEETCARRIER_DISTANCE_TRAVELLED")) else "")
    put("SPECIES LOGGED", g("Exobiology", "Organic_Species_Encountered"), whole(g("Exobiology", "Organic_Species_Encountered")), "")
    return rows


# ---- Loadout (2026-10): the ship's modules, from the journal Loadout event ---------------
# Rows: {group CORE / OPTIONAL / HARDPOINTS / UTILITY, name, rating (5A), note (SCO, G5 ...)}
_QML_CORE_SLOTS = {"PowerPlant": "POWER PLANT", "MainEngines": "THRUSTERS", "FrameShiftDrive": "FSD",
                   "LifeSupport": "LIFE SUPPORT", "PowerDistributor": "POWER DISTRIBUTOR", "Radar": "SENSORS",
                   "FuelTank": "FUEL TANK", "Armour": "BULKHEADS"}
_QML_MODULE_NAMES = [
    ("int_hyperdrive_overcharge", "FSD"), ("int_hyperdrive", "FSD"), ("int_shieldgenerator", "SHIELDS"),
    ("int_fuelscoop", "FUEL SCOOP"), ("int_cargorack", "CARGO RACK"), ("int_corrosionproofcargorack", "CARGO RACK"),
    ("int_fsdinterdictor", "FSD INTERDICTOR"), ("int_hullreinforcement", "HULL REINFORCEMENT"),
    ("int_modulereinforcement", "MODULE REINFORCEMENT"), ("int_shieldcellbank", "SHIELD CELL BANK"),
    ("int_dronecontrol_collection", "COLLECTOR LIMPETS"), ("int_dronecontrol_prospector", "PROSPECTOR LIMPETS"),
    ("int_dronecontrol_fueltransfer", "FUEL LIMPETS"), ("int_dronecontrol_repair", "REPAIR LIMPETS"),
    ("int_dronecontrol_resourcesiphon", "HATCH BREAKER LIMPETS"), ("int_dronecontrol_decontamination", "DECON LIMPETS"),
    ("int_dronecontrol_recon", "RECON LIMPETS"), ("int_multidronecontrol", "MULTI LIMPET CONTROLLER"),
    ("int_detailedsurfacescanner", "SURFACE SCANNER"), ("int_dockingcomputer_advanced", "ADVANCED DOCKING COMPUTER"),
    ("int_dockingcomputer", "DOCKING COMPUTER"), ("int_supercruiseassist", "SUPERCRUISE ASSIST"),
    ("int_guardianfsdbooster", "GUARDIAN FSD BOOSTER"), ("int_guardianshieldreinforcement", "GUARDIAN SHIELD REINFORCEMENT"),
    ("int_guardianhullreinforcement", "GUARDIAN HULL REINFORCEMENT"), ("int_guardianmodulereinforcement", "GUARDIAN MODULE REINFORCEMENT"),
    ("int_refinery", "REFINERY"), ("int_passengercabin", "PASSENGER CABIN"), ("int_buggybay", "SRV HANGAR"),
    ("int_fighterbay", "FIGHTER HANGAR"), ("int_repairer", "AUTO FIELD MAINTENANCE"), ("int_expmodulestabiliser", "EXPERIMENTAL WEAPON STABILISER"),
    ("hpt_shieldbooster", "SHIELD BOOSTER"), ("hpt_heatsinklauncher", "HEAT SINK"), ("hpt_chafflauncher", "CHAFF"),
    ("hpt_plasmapointdefence", "POINT DEFENCE"), ("hpt_electroniccountermeasure", "ECM"), ("hpt_cloudscanner", "WAKE SCANNER"),
    ("hpt_crimescanner", "KILL WARRANT SCANNER"), ("hpt_cargoscanner", "MANIFEST SCANNER"), ("hpt_mrascanner", "PULSE WAVE ANALYSER"),
    ("hpt_xenoscanner", "XENO SCANNER"), ("hpt_antiunknownshutdown", "SHUTDOWN FIELD NEUTRALISER"),
    ("hpt_pulselaserburst", "BURST LASER"), ("hpt_pulselaser", "PULSE LASER"), ("hpt_beamlaser", "BEAM LASER"),
    ("hpt_mininglaser", "MINING LASER"), ("hpt_multicannon", "MULTI-CANNON"), ("hpt_cannon", "CANNON"),
    ("hpt_slugshot", "FRAGMENT CANNON"), ("hpt_plasmaaccelerator", "PLASMA ACCELERATOR"), ("hpt_railgun", "RAIL GUN"),
    ("hpt_basicmissilerack", "SEEKER MISSILES"), ("hpt_dumbfiremissilerack", "MISSILE RACK"), ("hpt_drunkmissilerack", "PACK-HOUND MISSILES"),
    ("hpt_advancedtorppylon", "TORPEDO PYLON"), ("hpt_minelauncher", "MINE LAUNCHER"), ("hpt_mining_abrblstr", "ABRASION BLASTER"),
    ("hpt_mining_seismchrgwarhd", "SEISMIC CHARGE"), ("hpt_mining_subsurfdispmisle", "DISPLACEMENT MISSILE"),
    ("hpt_flakmortar", "REMOTE FLAK"), ("hpt_flechettelauncher", "SHOCK MORTAR"), ("hpt_guardian_", "GUARDIAN WEAPON"),
    ("hpt_atdumbfiremissile", "AX MISSILE RACK"), ("hpt_atmulticannon", "AX MULTI-CANNON"),
]
_QML_HP_SIZE = {"tiny": "0", "small": "1", "medium": "2", "large": "3", "huge": "4"}


def _qml_module_row(slot, item, engineering=None):
    slot = str(slot or "")
    key = str(item or "").lower()
    if not key:
        return None
    if slot in _QML_CORE_SLOTS:
        group, name = "CORE", _QML_CORE_SLOTS[slot]
    elif re.match(r"(?i)^(slot\d|military\d)", slot):
        group, name = "OPTIONAL", ""
    elif re.match(r"(?i)^tinyhardpoint", slot):
        group, name = "UTILITY", ""
    elif re.search(r"(?i)hardpoint\d", slot):
        group, name = "HARDPOINTS", ""
    else:
        return None          # paint, decals, cockpit, voice ...
    for prefix, label in _QML_MODULE_NAMES:
        if key.startswith(prefix):
            name = name if group == "CORE" and slot != "FrameShiftDrive" else label
            break
    if not name:
        bits = [b for b in re.sub(r"^(int|hpt)_", "", key).split("_") if not re.match(r"^(size\d+|class\d+|fixed|gimbal|turret|small|medium|large|huge|tiny|grade\d+)$", b)]
        name = " ".join(bits).upper() or key.upper()
    if group == "CORE" and slot == "Armour":
        grade = {"grade1": "LIGHTWEIGHT", "grade2": "REINFORCED", "grade3": "MILITARY", "mirrored": "MIRRORED", "reactive": "REACTIVE"}
        name = next((v + " ALLOY" if v in ("LIGHTWEIGHT", "REINFORCED", "MILITARY") else v + " SURFACE" for k, v in grade.items() if k in key), "BULKHEADS")
        name = "BULKHEADS // " + name
    rating, note = "", ""
    m = re.search(r"size(\d+)_class(\d+)", key)
    if m:
        cls = int(m.group(2))
        rating = m.group(1) + ("EDCBA"[cls - 1] if 1 <= cls <= 5 else str(cls))
    elif group in ("HARDPOINTS", "UTILITY"):
        sz = next((v for k, v in _QML_HP_SIZE.items() if "_" + k in key), "")
        mount = next((k.upper() for k in ("fixed", "gimbal", "turret") if "_" + k in key), "")
        rating = sz
        note = mount
    elif "guardianfsdbooster" in key:
        m2 = re.search(r"size(\d+)", key)
        rating = (m2.group(1) + "H") if m2 else ""
    if "hyperdrive_overcharge" in key:
        note = "SCO"
    if key.startswith("int_shieldgenerator"):
        note = "BI-WEAVE" if key.endswith("_fast") else ("PRISMATIC" if key.endswith("_strong") else note)
    if isinstance(engineering, dict) and engineering.get("Level"):
        note = (note + " " if note else "") + "G" + str(engineering.get("Level"))
    return {"group": group, "name": name, "rating": rating, "note": note}


def _qml_loadout_rows(modules):
    rows = []
    if not isinstance(modules, list):
        return rows
    order = {"CORE": 0, "OPTIONAL": 1, "HARDPOINTS": 2, "UTILITY": 3}
    core_order = list(_QML_CORE_SLOTS)
    for mod in modules:
        if not isinstance(mod, dict):
            continue
        row = _qml_module_row(mod.get("Slot"), mod.get("Item"), mod.get("Engineering"))
        if row:
            row["_k"] = (order[row["group"]], core_order.index(mod.get("Slot")) if mod.get("Slot") in core_order else 99, str(mod.get("Slot")))
            rows.append(row)
    rows.sort(key=lambda r: r["_k"])
    for r in rows:
        r.pop("_k", None)
    return rows


def _qml_loadout_key(rows):
    """The four lines Flight Deck shows: FSD, SHIELDS, FUEL SCOOP, POWER PLANT."""
    out = []
    for name in ("FSD", "SHIELDS", "FUEL SCOOP", "POWER PLANT"):
        r = next((r for r in rows if r["name"] == name), None)
        out.append({"name": name, "rating": r["rating"] if r else "NONE", "note": r["note"] if r else ""})
    return out


# .95 creates its state as EliteState() at start and when the journal resets.
legacy.EliteState = _QmlEliteState

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
- Never substitute a guessed physical key for an Elite action. When a tool result says an action needs a keyboard key in Elite, pass that message on to the commander as written. Don't reword it and don't suggest a specific key.
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

# ---------------------------------------------------------------------------
# One kept-alive HTTPS connection per host for the OpenAI calls (speech-to-text
# and Copilot). urllib opens a fresh TCP + TLS connection for every request,
# which costs a few hundred ms each time. Falls back to urllib on any trouble
# (proxies, odd networks), so behavior never gets worse than before.
# ---------------------------------------------------------------------------
import http.client as _http_client
import io as _io
import urllib.parse as _urlparse

import urllib.error as _urlerror
import urllib.request as _urlrequest
import urllib.error  # binds the name "urllib" (an older except-clause in the wizard PTT test used it unbound)

class _QmlHttpError(_urlerror.HTTPError):
    pass

class _QmlHttpsPool:
    def __init__(self):
        self._lock = threading.Lock()
        self._conns: dict = {}
        self.disabled = bool(os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")) or \
            str(os.environ.get("EAB_HTTP_KEEPALIVE", "1")).strip() in ("0", "off", "false")

    def _get(self, host, timeout):
        with self._lock:
            conn = self._conns.pop(host, None)
        if conn is None:
            conn = _http_client.HTTPSConnection(host, timeout=timeout)
        else:
            conn.timeout = timeout
            if conn.sock is not None:
                try:
                    conn.sock.settimeout(timeout)
                except Exception:
                    pass
        return conn

    def _put(self, host, conn):
        with self._lock:
            old = self._conns.get(host)
            self._conns[host] = conn
        if old is not None and old is not conn:
            try:
                old.close()
            except Exception:
                pass

    def warm(self, url):
        """Open the TLS connection ahead of time (called when PTT is pressed)."""
        if self.disabled:
            return
        host = _urlparse.urlsplit(url).netloc
        try:
            with self._lock:
                if host in self._conns:
                    return
            conn = _http_client.HTTPSConnection(host, timeout=10)
            conn.connect()
            self._put(host, conn)
        except Exception:
            pass

    def open(self, url, body, headers, timeout):
        """POST and return the live response (caller reads it, then calls done())."""
        parts = _urlparse.urlsplit(url)
        host, path = parts.netloc, parts.path + (("?" + parts.query) if parts.query else "")
        for attempt in range(2):
            conn = self._get(host, timeout)
            try:
                conn.request("POST", path, body=body, headers=dict(headers, Connection="keep-alive"))
                resp = conn.getresponse()
                return conn, host, resp
            except (_http_client.HTTPException, ConnectionError, OSError):
                try:
                    conn.close()
                except Exception:
                    pass
                if attempt == 1:
                    raise
        raise RuntimeError("unreachable")

    def done(self, host, conn, resp, reusable=True):
        try:
            if reusable and not resp.isclosed():
                resp.read()
            if reusable and not resp.will_close:
                self._put(host, conn)
                return
        except Exception:
            pass
        try:
            conn.close()
        except Exception:
            pass

    def post(self, url, body, headers, timeout):
        """POST and return (status, bytes). Raises HTTPError for >= 400 like urllib."""
        if self.disabled:
            req = _urlrequest.Request(url, data=body, headers=headers, method="POST")
            with _urlrequest.urlopen(req, timeout=timeout) as resp:
                return resp.status, resp.read()
        try:
            conn, host, resp = self.open(url, body, headers, timeout)
        except Exception:
            req = _urlrequest.Request(url, data=body, headers=headers, method="POST")
            with _urlrequest.urlopen(req, timeout=timeout) as resp:
                return resp.status, resp.read()
        data = resp.read()
        status = resp.status
        self.done(host, conn, resp)
        if status >= 400:
            raise _QmlHttpError(url, status, resp.reason, resp.headers, _io.BytesIO(data))
        return status, data

_HTTPS = _QmlHttpsPool()

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
                    print(f"[AUDIO] sound effect {key} failed on {device} // {exc}", flush=True)
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


# Lines worth having ready before they are needed (instant-command confirmations).
_QML_WARM_PHRASES = [
    "Requesting docking.", "Cancelled. Controls are yours.", "Targeting the highest threat.",
    "Targeting the power plant.", "Finding the best target.", "Deploying fighter one.",
    "Recalling fighter.", "Next fire group.", "Refuelling.", "Repairing.", "Rearming.",
    "Escaping the area.", "Auto launch started.", "Clear and jump started.",
]

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
        # plain "ay eye" (picked by ear in the voice test): a comma made a full pause,
        # "A I" ran together as "ayei"
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
        return QmlVoiceWorker._bridge_word_pass(spoken)

    # ---- word pass (2026-10): cockpit abbreviations and game terms --------
    _LETTER_NAMES = {
        "A": "ay", "B": "bee", "C": "see", "D": "dee", "E": "ee", "F": "eff", "G": "jee", "H": "aitch",
        "I": "eye", "J": "jay", "K": "kay", "L": "ell", "M": "em", "N": "en", "O": "oh", "P": "pee",
        "Q": "cue", "R": "ar", "S": "ess", "T": "tee", "U": "you", "V": "vee", "W": "double you",
        "X": "ex", "Y": "why", "Z": "zee",
    }
    # Whole words, matched case-sensitively unless noted. Order matters.
    _WORDS = [
        (r"\bSYS\b", "systems"), (r"\bENG\b", "engines"), (r"\bWEP\b", "weapons"),
        (r"\bco-?pilot(s?)\b", r"co pilot\1", re.IGNORECASE),
        (r"\bCMDR\b|\bCmdr\.?(?=\s)", "Commander"),
        (r"\bMk\.?\s*(?=I|V|\d)", "Mark "),
        (r"\bRES\b", "rez"), (r"\bSCO\b", "ess see oh"), (r"\bETA\b", "ee tee ay"),
        (r"\bHUD\b", "hud"), (r"\bOK\b", "okay"),
        (r"\bFC\b", "fleet carrier"), (r"\bLTD\b", "low temperature diamonds"),
        (r"\bSLF\b", "fighter"), (r"\bHRP\b", "hull reinforcement"),
        (r"\bpips\b", "pips", re.IGNORECASE),
        (r"\bvs\.?(?=\s)", "versus"),
        (r"\bw/(?=\s)", "with"), (r"\be\.g\.", "for example"), (r"\bi\.e\.", "that is"),
    ]
    _ROMAN = {"I": "one", "II": "two", "III": "three", "IV": "four", "V": "five", "VI": "six"}

    @staticmethod
    def _bridge_word_pass(spoken):
        cls = QmlVoiceWorker
        for entry in cls._WORDS:
            pattern, repl = entry[0], entry[1]
            flags = entry[2] if len(entry) > 2 else 0
            spoken = re.sub(pattern, repl, spoken, flags=flags)
        # Ship marks: "Mark II" -> "Mark two" (after the Mk expansion above)
        spoken = re.sub(r"\bMark (VI|IV|V|III|II|I)\b", lambda m: "Mark " + cls._ROMAN[m.group(1)], spoken)
        spoken = re.sub(r"\b(Type)-(\d+)\b", r"\1 \2", spoken)
        # Money and mass after a number: "842,500 CR" -> credits, "64 T" -> tons, "CR/HR"
        spoken = re.sub(r"\b(?:CR|cr)\s*/\s*(?:HR|hr)\b", "credits an hour", spoken)
        spoken = re.sub(r"(\d)\s*(?:CR|Cr)\b", r"\1 credits", spoken)
        spoken = re.sub(r"(\d)\s*T\b(?!-)", r"\1 tons", spoken)
        # Power distribution written "4/2/0" or "SYS 4 ENG 2 WEP 0" is handled above;
        # "4 / 2 / 0" reads better as words.
        spoken = re.sub(r"\b([0-4](?:\.5)?)\s*/\s*([0-4](?:\.5)?)\s*/\s*([0-4](?:\.5)?)\b",
                        r"\1, \2, \3", spoken)
        # Any other all-caps token of 2 to 4 letters with no vowel is read letter by letter
        # (FSD, SRV, NPC, PTT, LHS, HR, LTT, BD ...). Words with vowels are left alone.
        def _spell(m):
            word = m.group(0)
            return " ".join(cls._LETTER_NAMES[ch] for ch in word)
        spoken = re.sub(r"\b(?![A-Z]*[AEIOUY])[B-DF-HJ-NP-TV-XZ]{2,4}\b", _spell, spoken)
        return spoken

    def __init__(self):
        super().__init__()
        self._qml_neural_warm_state = "IDLE"
        self._qml_neural_warm_started_mono = 0.0
        self._qml_neural_warm_ready_mono = 0.0
        self._qml_neural_warm_duration_ms = 0
        self._qml_neural_warm_error = ""
        # Streaming speech state (see _speak_supertonic below).
        self._qml_prefetch = None          # (key, wav) for the next queued item
        self._qml_reveal_lock = threading.Lock()
        self._qml_reveal = None            # dict: id, text, shown, state, t0
        self._qml_reveal_serial = 0
        self._qml_reveal_marker = ""       # set by finish_copilot_command
        # Recently spoken short lines are kept as audio, so repeats play at once.
        from collections import OrderedDict as _OD
        self._qml_phrase_cache = _OD()
        self._qml_warm_list = list(_QML_WARM_PHRASES)
        self._qml_born_mono = time.monotonic()

    # ------------------------------------------------------------------
    # Streaming speech (2026-10 snappiness pass)
    #
    # The .95 worker synthesizes a whole reply, writes a temp WAV, reads it
    # back and only then plays it, so the first word waits for the last one.
    # This adapter speaks sentence by sentence instead: sentence 1 starts as
    # soon as it is ready, the next sentence is synthesized while the current
    # one plays (one sentence look-ahead, same total CPU work), and audio goes
    # straight from memory to the output stream. The old WAV path is kept as
    # a fallback (set EAB_VOICE_STREAM=0 to force it).
    # ------------------------------------------------------------------
    _STREAM_ENABLED = str(os.environ.get("EAB_VOICE_STREAM", "1")).strip() not in ("0", "false", "off", "no")
    _SENTENCE_GAP_S = 0.15        # pause added between streamed sentences
    _FIRST_STEP_CUT = 2           # first sentence uses (quality - 2) steps, min 5
    _FIRST_SPLIT_CHARS = 140      # a longer first sentence is split at a comma
    _ABBREV_END = re.compile(
        r"(?:\b(?:Mk|Mr|Mrs|Ms|Dr|St|Lt|Capt|Cmdr|Cdr|vs|No|approx|etc|Inc|Ltd|Jr|Sr)|\b[A-Z]|\be\.g|\bi\.e)\.$",
        re.IGNORECASE,
    )

    @classmethod
    def _speech_spans(cls, text):
        """Split normalized text into sentence spans [(start, end), ...].

        Spans index into `text`, so the UI can reveal the original wording in
        step with the voice. Short fragments are merged, abbreviations do not
        split, and a long first sentence is split at a comma so the first word
        arrives quickly.
        """
        text = str(text or "")
        n = len(text)
        if not n:
            return []
        cuts = [m.end() for m in re.finditer(r"(?<=[.!?])[\"')\]]*\s+(?=[\"'(\[]?[A-Z0-9])", text)]
        spans = []
        start = 0
        for cut in cuts:
            piece = text[start:cut].rstrip()
            if cls._ABBREV_END.search(piece):
                continue
            spans.append((start, cut))
            start = cut
        spans.append((start, n))
        # Merge tiny fragments ("Yes." "Copy.") into the following sentence,
        # and a tiny final fragment into the previous one.
        merged = []
        for s, e in spans:
            if merged and len(text[merged[-1][0]:merged[-1][1]].strip()) < 8:
                merged[-1] = (merged[-1][0], e)
            else:
                merged.append((s, e))
        if len(merged) > 1 and len(text[merged[-1][0]:merged[-1][1]].strip()) < 8:
            last = merged.pop()
            merged[-1] = (merged[-1][0], last[1])
        # Long first sentence: split once at a comma / semicolon / dash-free pause.
        s0, e0 = merged[0]
        first = text[s0:e0]
        if len(first.strip()) > cls._FIRST_SPLIT_CHARS:
            m = re.search(r"[,;:]\s+", first[40:cls._FIRST_SPLIT_CHARS + 40])
            if m:
                cut = s0 + 40 + m.end()
                merged[0:1] = [(s0, cut), (cut, e0)]
        return [(s, e) for s, e in merged if text[s:e].strip()]

    # Status-like announcements where only the newest matters: a newer one replaces
    # an older one that is still waiting in the queue.
    _REPLACE_KINDS = {"MATERIAL", "SALVAGE", "PICKUP", "PIPS", "POWERPLAY"}

    def _qml_drop_queued_kind(self, kind):
        dropped = 0
        try:
            with self.queue.mutex:
                keep = [it for it in self.queue.queue
                        if not (isinstance(it, tuple) and len(it) == 2 and isinstance(it[1], dict) and it[1].get("_kind") == kind)]
                dropped = len(self.queue.queue) - len(keep)
                if dropped:
                    self.queue.queue.clear()
                    self.queue.queue.extend(keep)
                    self.queue.not_full.notify_all()
        except Exception:
            return 0
        return dropped

    def say(self, text, speed_scale=1.0, hold_until=0.0, kind=""):
        """Queue speech. Same contract as the .95 worker, plus:

        hold_until: monotonic time before which playback must not start (used to
        let synthesis overlap the attention earcon instead of waiting for it).
        """
        text = " ".join(str(text or "").replace("\r", " ").replace("\n", " ").split()).strip()
        if not text or not self.running:
            return False
        cfg = self.config_snapshot()
        try:
            scale = max(0.70, min(1.20, float(speed_scale or 1.0)))
        except Exception:
            scale = 1.0
        cfg["speed"] = round(self._clamp(float(cfg.get("speed", 1.05)) * scale, 0.7, 2.0, 1.05), 2)
        try:
            cfg["_play_not_before"] = float(hold_until or 0.0)
        except Exception:
            cfg["_play_not_before"] = 0.0
        reveal_id = 0
        marker = str(getattr(self, "_qml_reveal_marker", "") or "")
        if marker and text == marker:
            with self._qml_reveal_lock:
                self._qml_reveal_serial += 1
                reveal_id = self._qml_reveal_serial
        cfg["_reveal_id"] = reveal_id
        kind = str(kind or "").upper()
        cfg["_kind"] = kind
        if kind in self._REPLACE_KINDS and self._qml_drop_queued_kind(kind):
            self.dropped_count += 1
        item = (text[:900], cfg)
        try:
            self.queue.put_nowait(item)
        except queue.Full:
            self.dropped_count += 1
            self.status = "Voice queue full • newest announcement dropped"
            return False
        if reveal_id:
            with self._qml_reveal_lock:
                self._qml_reveal = {
                    "id": reveal_id, "text": text, "spoken_len": len(text[:900]),
                    "shown": 0, "state": "QUEUED", "t0": time.monotonic(),
                }
        return True

    # Reveal state for the AI COMMS reply text -------------------------
    def _reveal_update(self, reveal_id, shown=None, state=None):
        if not reveal_id:
            return
        with self._qml_reveal_lock:
            r = self._qml_reveal
            if not r or r.get("id") != reveal_id:
                return
            if shown is not None:
                r["shown"] = max(int(r.get("shown", 0)), int(shown))
            if state is not None:
                r["state"] = state
            if r["shown"] >= int(r.get("spoken_len", 0)):
                r["state"] = "DONE"

    def reveal_view(self):
        """Return (full_text, shown_text) while a spoken reply is still being
        revealed, else None. Never holds text back for long: a queued reply
        shows in full after 10 s, a playing one after 90 s."""
        with self._qml_reveal_lock:
            r = self._qml_reveal
            if not r:
                return None
            state = r.get("state")
            age = time.monotonic() - float(r.get("t0", 0.0))
            if state == "DONE" or (state == "QUEUED" and age > 10.0) or age > 90.0:
                self._qml_reveal = None
                return None
            text = str(r.get("text") or "")
            return text, text[:int(r.get("shown", 0))].rstrip()

    # Synthesis ---------------------------------------------------------
    def _qml_style(self, tts, cfg):
        voice = str(cfg.get("voice") or "M1").upper()
        if voice not in self.SUPER_VOICES:
            voice = "M1"
        style = self._super_style_cache.get(voice)
        if style is None:
            style = tts.get_voice_style(voice_name=voice)
            self._super_style_cache[voice] = style
        return voice, style

    def _qml_audio_params(self, cfg):
        effect = str(cfg.get("effect") or "BRIDGE").upper()
        pitch = str(cfg.get("pitch") or "NORMAL").upper()
        if pitch not in self.PITCH_PRESETS:
            pitch = "NORMAL"
        return {
            "speed": self._clamp(cfg.get("speed"), 0.7, 2.0, 1.05),
            "quality": int(round(self._clamp(cfg.get("quality"), 5, 12, 8))),
            "volume": self._clamp(cfg.get("volume"), 0, 100, 80) / 100.0,
            "effect": effect,
            "strength": int(round(self._clamp(cfg.get("effect_strength"), 0, 100, 35))),
            "pitch": pitch,
            "device": str(cfg.get("output_device") or "System Default"),
        }

    def _qml_sentence_key(self, spoken, cfg, first, last):
        p = self._qml_audio_params(cfg)
        return (spoken, str(cfg.get("voice") or "M1").upper(), p["speed"], p["quality"], bool(first), bool(last),
                p["pitch"], p["effect"], p["strength"], round(p["volume"], 3))

    def _qml_synth_sentence(self, spoken, cfg, first, last):
        """Synthesize one sentence to a mono float32 array, with pitch,
        character and volume applied exactly like the .95 path."""
        import numpy as np
        tts = self._load_supertonic()
        _voice, style = self._qml_style(tts, cfg)
        p = self._qml_audio_params(cfg)
        steps = p["quality"]
        if first:
            steps = max(5, steps - self._FIRST_STEP_CUT)
        wav, _dur = tts.synthesize(text=spoken, voice_style=style, lang="en", total_steps=steps, speed=p["speed"])
        wav = self._apply_voice_pitch(wav, p["pitch"])
        arr = np.asarray(wav, dtype=np.float32).reshape(-1)
        sr = int(getattr(tts, "sample_rate", 44100) or 44100)
        if p["effect"] == "RADIO" and p["strength"] > 0:
            # RADIO adds squelch clicks at both ends of each utterance. Keep them
            # at the start and end of the whole reply only, not between sentences.
            pad = int(sr * 0.012) + 2
            padded = np.concatenate([np.zeros(pad, np.float32), arr, np.zeros(pad, np.float32)])
            out = np.asarray(self._apply_voice_character(padded.reshape(1, -1), "RADIO", p["strength"]), dtype=np.float32).reshape(-1)
            a = 0 if first else pad
            b = len(out) if last else len(out) - pad
            arr = out[a:b]
        else:
            arr = np.asarray(self._apply_voice_character(arr.reshape(1, -1), p["effect"], p["strength"]), dtype=np.float32).reshape(-1)
        try:
            arr = arr * float(p["volume"])
        except Exception:
            pass
        return arr, sr

    _CACHE_MAX_CHARS = 90
    _CACHE_MAX_ITEMS = 64

    def _qml_cached_synth(self, spoken, cfg, first, last):
        key = self._qml_sentence_key(spoken, cfg, first, last)
        cache = self._qml_phrase_cache
        hit = cache.get(key)
        if hit is not None:
            cache.move_to_end(key)
            return hit
        arr, sr = self._qml_synth_sentence(spoken, cfg, first, last)
        if len(spoken) <= self._CACHE_MAX_CHARS:
            cache[key] = (arr, sr)
            while len(cache) > self._CACHE_MAX_ITEMS:
                cache.popitem(last=False)
        return arr, sr

    def _run(self):
        """The .95 worker loop, plus: when idle (30 s after start), pre-synthesize
        the instant-command confirmations one at a time so they play at once."""
        self._prewarm_supertonic()
        while self.running:
            try:
                item = self.queue.get(timeout=0.4)
            except queue.Empty:
                self._qml_idle_warm()
                continue
            if item is None:
                break
            text, cfg = item
            engine = self._clean_engine(cfg.get("engine"))
            success = False
            super_error = ""
            if engine in ("AUTO", "SUPERTONIC"):
                try:
                    self._speak_supertonic(text, cfg)
                    success = True
                except Exception as exc:
                    super_error = str(exc)
                    self.last_error = super_error
            if not success:
                try:
                    self._speak_windows(text, cfg, fallback_reason=(f"Supertonic unavailable: {super_error}" if super_error else ""))
                    success = True
                except Exception as exc:
                    self.last_error = str(exc)
                    self.status = f"Voice backend error: {exc}"
                    self._stop_windows_process()
            if success:
                self.spoken_count += 1
                self.last_text = text

    def _qml_idle_warm(self):
        # one phrase at most every 6 s, starting 90 s after start, so the warm-up never
        # lands on top of the startup lines
        now = time.monotonic()
        if not self._qml_warm_list or now - self._qml_born_mono < 90.0:
            return
        if now - float(getattr(self, "_qml_warm_last", 0.0) or 0.0) < 6.0:
            return
        self._qml_warm_last = now
        if self._qml_neural_warm_state != "READY" or not self._STREAM_ENABLED:
            return
        cfg = self.config_snapshot()
        if self._clean_engine(cfg.get("engine")) not in ("AUTO", "SUPERTONIC"):
            return
        phrase = self._qml_warm_list.pop(0)
        try:
            self._qml_cached_synth(self._bridge_pronunciation_text(phrase), cfg, True, True)
        except Exception:
            self._qml_warm_list = []

    def _qml_prefetch_next(self):
        """While the last sentence plays, synthesize the first sentence of the
        next queued Supertonic item (wizard and tour narration queue one item
        per sentence, so this removes the gap between them)."""
        try:
            with self.queue.mutex:
                nxt = self.queue.queue[0] if self.queue.queue else None
        except Exception:
            nxt = None
        if not nxt or not isinstance(nxt, tuple) or len(nxt) != 2:
            return
        text, cfg = nxt
        if self._clean_engine(cfg.get("engine")) not in ("AUTO", "SUPERTONIC"):
            return
        cancel = cfg.get("_wizard_cancel")
        if cancel is not None and cancel.is_set():
            return
        spans = self._speech_spans(text) if self._STREAM_ENABLED else []
        if not spans:
            return
        s, e = spans[0]
        spoken = self._bridge_pronunciation_text(text[s:e].strip())
        key = self._qml_sentence_key(spoken, cfg, True, len(spans) == 1)
        if self._qml_prefetch and self._qml_prefetch[0] == key:
            return
        try:
            arr, sr = self._qml_cached_synth(spoken, cfg, True, len(spans) == 1)
            self._qml_prefetch = (key, arr, sr)
        except Exception:
            self._qml_prefetch = None

    # Playback ------------------------------------------------------------
    def _qml_player(self, audio_q, device, cancel, not_before, on_first, on_piece, result):
        """Runs on its own thread. Plays float32 pieces from audio_q through one
        sounddevice stream (or winsound per piece as a fallback)."""
        import numpy as np
        stream = None
        started = False
        try:
            while True:
                item = audio_q.get()
                if item is None or cancel.is_set():
                    break
                arr, sr, reveal_end = item
                if not started:
                    wait = float(not_before or 0.0) - time.monotonic()
                    if wait > 0 and cancel.wait(min(wait, 2.0)):
                        break
                pcm = (np.clip(arr, -1.0, 1.0) * 32767.0).astype(np.int16)
                if stream is None and legacy.SOUNDDEVICE_AVAILABLE and not result.get("winsound"):
                    try:
                        stream = legacy.sd.RawOutputStream(
                            samplerate=int(sr), channels=1, dtype="int16",
                            device=legacy._sd_device_arg(device), blocksize=4096,
                        )
                        stream.start()
                    except Exception as exc:
                        stream = None
                        result["stream_error"] = str(exc)
                        result["winsound"] = True
                if not started:
                    started = True
                    result["started"] = True
                    on_first()
                on_piece(reveal_end)
                if stream is not None:
                    # A stream that runs out of data underflows, and some Windows audio
                    # paths stutter / repeat when that happens. So the stream is stopped
                    # cleanly (after playing out) whenever the next sentence isn't ready
                    # yet, and started again when it is: a short pause instead of garble.
                    if not stream.active:
                        stream.start()
                    data = pcm.tobytes()
                    step = 4096 * 2
                    for i in range(0, len(data), step):
                        if cancel.is_set():
                            break
                        stream.write(data[i:i + step])
                    if audio_q.empty() and not cancel.is_set():
                        stream.stop()
                elif os.name == "nt":
                    import wave
                    import tempfile
                    fd, tmp = tempfile.mkstemp(prefix="elite_bridge_voice_", suffix=".wav")
                    os.close(fd)
                    try:
                        with wave.open(tmp, "wb") as wf:
                            wf.setnchannels(1)
                            wf.setsampwidth(2)
                            wf.setframerate(int(sr))
                            wf.writeframes(pcm.tobytes())
                        if not cancel.is_set():
                            _ORIGINAL_WINSOUND_PLAYER(tmp, winsound.SND_FILENAME)
                    finally:
                        try:
                            os.unlink(tmp)
                        except Exception:
                            pass
                else:
                    raise RuntimeError("No audio output available for streamed speech.")
                if cancel.is_set():
                    break
        except Exception as exc:
            result["error"] = str(exc)
        finally:
            if stream is not None:
                try:
                    if cancel.is_set() or result.get("error"):
                        stream.abort()
                    elif stream.active:
                        stream.stop()   # drains the buffered tail
                except Exception:
                    pass
                try:
                    stream.close()
                except Exception:
                    pass
            # Unblock the producer if we exited early.
            result["done"] = True

    def _speak_supertonic(self, text, cfg):
        self._qml_speech_active = True
        cancel = cfg.get("_wizard_cancel", _WIZARD_VOICE_INTERRUPT)
        _WIZARD_VOICE_CONTEXT.cancel = cancel
        reveal_id = int(cfg.get("_reveal_id", 0) or 0)
        try:
            if cancel.is_set():
                return None
            if not self._STREAM_ENABLED:
                self._reveal_update(reveal_id, shown=len(text))
                return super()._speak_supertonic(self._bridge_pronunciation_text(text), cfg)
            return self._speak_supertonic_stream(text, cfg, cancel, reveal_id)
        finally:
            self._reveal_update(reveal_id, shown=len(text), state="DONE")
            if cancel.is_set():
                self.status = "READY • cancelled wizard speech"
            self._qml_speech_active = False

    def _speak_supertonic_stream(self, text, cfg, cancel, reveal_id):
        t_begin = time.monotonic()
        spans = self._speech_spans(text) or [(0, len(text))]
        tts = self._load_supertonic()
        voice, _style = self._qml_style(tts, cfg)
        p = self._qml_audio_params(cfg)
        label = f"Supertonic {voice} / {p['pitch']} / {p['effect']} {p['strength']}%"
        self.status = f"SYNTHESIZING • Supertonic {voice} • {p['pitch']} • {p['effect']} {p['strength']}%"

        audio_q = queue.Queue()
        result = {}
        first_audio = {}

        def on_first():
            first_audio["t"] = time.monotonic()
            self.status = f"SPEAKING • Supertonic {voice}"
            # Latency meter: report the ORIGINAL text so it matches the reply.
            self._notify_speech_start(text, f"Supertonic {voice}")

        def on_piece(reveal_end):
            self._reveal_update(reveal_id, shown=reveal_end, state="PLAYING")

        player = threading.Thread(
            target=self._qml_player,
            args=(audio_q, p["device"], cancel, float(cfg.get("_play_not_before", 0.0) or 0.0), on_first, on_piece, result),
            name="EliteBridge-VoicePlay", daemon=True,
        )
        import numpy as np
        gap = None
        player_started = False
        try:
            for idx, (s, e) in enumerate(spans):
                if cancel.is_set() or result.get("done"):
                    break
                first = idx == 0
                last = idx == len(spans) - 1
                spoken = self._bridge_pronunciation_text(text[s:e].strip())
                key = self._qml_sentence_key(spoken, cfg, first, last)
                pre = self._qml_prefetch
                self._qml_prefetch = None
                if first and pre and pre[0] == key:
                    arr, sr = pre[1], pre[2]
                else:
                    arr, sr = self._qml_cached_synth(spoken, cfg, first, last)
                if not last:
                    if gap is None:
                        gap = np.zeros(int(sr * self._SENTENCE_GAP_S), np.float32)
                    arr = np.concatenate([arr, gap])
                audio_q.put((arr, sr, e))
                if not player_started:
                    player.start()
                    player_started = True
        except Exception as exc:
            if not player_started:
                raise  # nothing played yet: let the .95 worker fall back to Windows voice
            self.last_error = str(exc)
            print(f"[VOICE] stream synthesis stopped mid-reply // {exc}", flush=True)
        finally:
            audio_q.put(None)
        if not player_started:
            return None
        # While the tail plays, get the next queued item's first sentence ready.
        if not cancel.is_set():
            self._qml_prefetch_next()
        player.join()
        if result.get("error") and not result.get("started"):
            raise RuntimeError(result["error"])
        if result.get("error"):
            self.last_error = result["error"]
            print(f"[VOICE] stream playback error // {result['error']}", flush=True)
        if "t" in first_audio:
            print(
                f"[VOICE] streamed // sentences={len(spans)} first audio {int((first_audio['t'] - t_begin) * 1000)} ms"
                f" // total {time.monotonic() - t_begin:.2f}s{' // winsound' if result.get('winsound') else ''}",
                flush=True,
            )
        self.last_backend = label
        self.status = f"READY • Supertonic {voice} • {p['pitch']} • {p['effect']} {p['strength']}%"
        return None

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
            # Latency meter matches on the original reply text, not the
            # pronunciation-adjusted copy (that mismatch kept the meter blank).
            self._reveal_update(int(cfg.get("_reveal_id", 0) or 0), shown=len(text), state="DONE")
            self._notify_speech_start(text, f"Windows {voice}")
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


class _ColonySiteScanner:
    """MY SITES (Colonization): every construction site the commander has docked at
    (Elite does not write claim events for every claim, so depots are the source),
    plus any claimed system with no site seen yet, rebuilt from the journal folder.
    A site counts as COMPLETE once a finished station with its name has been seen.

    Nothing is saved: the list is read from the journals at startup (background
    thread, only lines with the few events it needs are parsed), then the newest
    journal is followed for new lines. Depot numbers are as of the last visit.
    """
    STALE_DAYS = 30
    LINE_RX = re.compile(rb'^[^\n]*"event"\s*:\s*"(?:Colonisation\w+|Docked|Location|FSDJump|CarrierJump|FSSSignalDiscovered)"[^\n]*$', re.M)

    def __init__(self, journal_dir):
        self.journal_dir = Path(journal_dir)
        self.offsets: dict[str, int] = {}
        self.claims: dict[str, dict] = {}        # system key -> {system, address, ts}
        self.sites: dict[int, dict] = {}         # market id -> latest depot snapshot
        self.dock: dict[int, dict] = {}          # market id -> {station, system, type}
        self.current_market = None
        self.coords: dict[str, tuple] = {}       # system key -> StarPos (only claimed ones are kept at the end)
        self.here = None                         # last StarPos seen
        self.seen_names: dict[str, str] = {}     # "address|name" -> last time a finished station of that name was seen
        self.files_read = 0
        self.busy = False
        self.done = False
        self.lock = threading.Lock()

    @staticmethod
    def _key(name):
        return re.sub(r"[^a-z0-9]+", "", str(name or "").lower())

    @staticmethod
    def _epoch(ts):
        try:
            import calendar
            return float(calendar.timegm(time.strptime(str(ts)[:19], "%Y-%m-%dT%H:%M:%S")))
        except Exception:
            return -1.0

    def _event(self, e):
        ev = e.get("event")
        ts = str(e.get("timestamp") or "")
        if ev in ("FSDJump", "Location", "CarrierJump"):
            pos = e.get("StarPos")
            name = e.get("StarSystem")
            if isinstance(pos, list) and len(pos) == 3 and name:
                try:
                    xyz = (float(pos[0]), float(pos[1]), float(pos[2]))
                    self.coords[self._key(name)] = xyz
                    self.here = xyz
                except Exception:
                    pass
        if ev == "FSDJump":
            self.current_market = None
            return
        if ev in ("Docked", "Location", "CarrierJump"):
            if ev != "Docked" and not e.get("Docked"):
                self.current_market = None
                return
            try:
                mid = int(e.get("MarketID"))
            except Exception:
                return
            station = str(e.get("StationName_Localised") or e.get("StationName") or "-")
            if station.startswith("$"):
                rest = station.split(";", 1)[1].strip() if ";" in station else ""
                station = rest or "COLONISATION SHIP"
            addr = str(e.get("SystemAddress") or "")
            stype = str(e.get("StationType") or "")
            if "construction" not in stype.lower() and "colonisationship" not in str(e.get("StationName") or "").lower():
                self.seen_names[addr + "|" + self._key(station)] = ts
            self.dock[mid] = {"address": addr, "station": station, "system": str(e.get("StarSystem") or "-"),
                              "type": str(e.get("StationType") or "")}
            self.current_market = mid
        elif ev == "FSSSignalDiscovered":
            name = str(e.get("SignalName_Localised") or e.get("SignalName") or "")
            stype = str(e.get("SignalType") or "")
            if name and not name.startswith("$") and "construction" not in name.lower() and stype in (
                    "Installation", "Outpost", "StationCoriolis", "StationONeilCylinder", "StationONeilOrbis",
                    "StationBernalSphere", "StationAsteroid", "StationMegaShip", "Settlement", "PlanetaryOutpost", "PlanetaryPort"):
                self.seen_names[str(e.get("SystemAddress") or "") + "|" + self._key(name)] = ts
        elif ev == "ColonisationSystemClaim":
            name = str(e.get("StarSystem") or e.get("SystemName") or "").strip()
            if name:
                self.claims[self._key(name)] = {"system": name, "address": e.get("SystemAddress"), "ts": ts}
        elif ev == "ColonisationSystemClaimRelease":
            name = str(e.get("StarSystem") or e.get("SystemName") or "").strip()
            self.claims.pop(self._key(name), None)
            # 2.0.1: a released system's build sites go with it
            gone_addr = str(e.get("SystemAddress") or "")
            for mid in [m for m, v in self.sites.items()
                        if self._key(v.get("system")) == self._key(name) or (gone_addr and str(v.get("address") or "") == gone_addr)]:
                self.sites.pop(mid, None)
        elif ev == "ColonisationConstructionDepot":
            try:
                mid = int(e.get("MarketID"))
            except Exception:
                return
            where = self.dock.get(mid) or {}
            required = left = 0
            for r in e.get("ResourcesRequired") or []:
                try:
                    req = max(0, int(r.get("RequiredAmount", 0) or 0))
                    got = max(0, int(r.get("ProvidedAmount", 0) or 0))
                except Exception:
                    continue
                required += req
                left += max(0, req - got)
            try:
                pct = max(0.0, min(100.0, float(e.get("ConstructionProgress") or 0) * 100.0))
            except Exception:
                pct = 0.0
            old = self.sites.get(mid) or {}
            self.sites[mid] = {
                "marketId": mid, "address": where.get("address") or old.get("address") or "",
                "station": where.get("station") or old.get("station") or "-",
                "system": where.get("system") or old.get("system") or "-",
                "type": where.get("type") or old.get("type") or "",
                "progressPct": pct, "total": required, "left": left,
                "complete": bool(e.get("ConstructionComplete")), "failed": bool(e.get("ConstructionFailed")),
                "ts": ts,
            }

    def _read_file(self, path):
        name = path.name
        start = self.offsets.get(name, 0)
        try:
            size = path.stat().st_size
        except Exception:
            return
        if size <= start:
            return
        try:
            with open(path, "rb") as fh:
                fh.seek(start)
                data = fh.read()
        except Exception:
            return
        # only complete lines; a half-written last line is read next time
        cut = data.rfind(b"\n")
        if cut < 0:
            return
        self.offsets[name] = start + cut + 1
        # the regex runs in C, so years of journals pass quickly without holding up the UI
        for m in self.LINE_RX.finditer(data, 0, cut):
            try:
                self._event(json.loads(m.group(0).decode("utf-8", errors="replace")))
            except Exception:
                continue

    def scan(self):
        """First call reads every journal; later calls only read new lines."""
        if self.busy:
            return
        self.busy = True
        try:
            files = sorted(self.journal_dir.glob("Journal.*.log"))
            with self.lock:
                for f in files:
                    self._read_file(f)
                    time.sleep(0)
                self.files_read = len(files)
            self.done = True
        except Exception:
            pass
        finally:
            self.busy = False

    @staticmethod
    def _age(ts):
        try:
            import calendar
            secs = max(0, time.time() - calendar.timegm(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S")))
        except Exception:
            return "-", -1.0
        hours = secs / 3600.0
        if secs < 3600:
            return f"{int(secs // 60)} MIN AGO", hours
        if secs < 86400:
            return f"{int(hours)} HR AGO", hours
        days = int(secs // 86400)
        return (f"{days} DAY AGO" if days == 1 else f"{days} DAYS AGO"), hours

    def _ly(self, system, here):
        pos = self.coords.get(self._key(system))
        if pos is None or here is None:
            return -1.0
        return round(math.dist(pos, here), 1)

    def rows(self, here=None):
        with self.lock:
            claimed = dict(self.claims)
            sites = [dict(v) for v in self.sites.values()]

            here = here if here is not None else self.here
        out = []
        seen_systems = set()
        for site in sites:
            key = self._key(site["system"])
            seen_systems.add(key)
            raw = str(site["station"])
            name, kind = raw, ("SURFACE" if "planet" in site["type"].lower() else ("ORBITAL" if site["type"] else "-"))
            m = re.match(r"^\s*(orbital|planetary)\s+construction\s+site\s*:\s*(.+)$", raw, re.I)
            if m:
                name = m.group(2).strip()
                kind = "ORBITAL" if m.group(1).lower() == "orbital" else "SURFACE"
            status = "COMPLETE" if site["complete"] else ("FAILED" if site["failed"] else "BUILDING")
            finished_seen = self.seen_names.get(str(site.get("address") or "") + "|" + self._key(name), "")
            seen_ts = site["ts"]
            if status == "BUILDING" and finished_seen and finished_seen > site["ts"]:
                status = "COMPLETE"      # seen since as a finished station
                seen_ts = finished_seen
            if status == "BUILDING":
                # 2.0.1: Elite writes nothing when a site is abandoned, removed, or finishes
                # under a new name, so an old snapshot would say BUILDING forever. No visit for
                # 30 days = NOT SEEN (we can't tell which). Checked against a real journal
                # history: Elite does not reliably list orbital build sites when you arrive in
                # a system, so a missing signal is NOT treated as proof a site is gone.
                last = self._epoch(site["ts"])
                if last >= 0 and time.time() - last > self.STALE_DAYS * 86400:
                    status = "NOT SEEN"
            age, hours = self._age(seen_ts)
            out.append({
                "system": site["system"], "station": name, "kind": kind,
                "status": status, "progressPct": 100.0 if status == "COMPLETE" else round(site["progressPct"], 1),
                "total": site["total"], "left": 0 if status in ("COMPLETE", "GONE") else site["left"],
                "lastSeen": age, "ageHours": round(hours, 2),
                "marketId": site["marketId"], "ly": self._ly(site["system"], here),
                "claimed": key in claimed,
            })
        for key, claim in claimed.items():
            if key in seen_systems:
                continue
            age, hours = self._age(claim["ts"])
            out.append({"system": claim["system"], "station": "-", "kind": "-", "status": "CLAIMED",
                        "progressPct": 0.0, "total": 0, "left": 0, "lastSeen": "CLAIMED " + age, "ageHours": round(hours, 2),
                        "marketId": -1, "ly": self._ly(claim["system"], here), "claimed": True})
        order = {"BUILDING": 0, "CLAIMED": 1, "NOT SEEN": 2, "COMPLETE": 3, "GONE": 4, "FAILED": 5}
        out.sort(key=lambda r: (order.get(r["status"], 9), r["ly"] if r["ly"] >= 0 else 1e9, r["system"].lower(), r["station"].lower()))
        return out


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


# Event log presentation (Flight Deck): readable names for raw journal events, and
# a few events that are noise in a cockpit log. The engine's event_log is unchanged.
_EVENT_LABELS = {
    "ReceiveText": "COMMS", "SendText": "MESSAGE SENT", "FSDTarget": "NEXT JUMP", "NavRoute": "ROUTE PLOTTED",
    "NavRouteClear": "ROUTE CLEARED", "FSDJump": "FSD JUMP", "StartJump": "JUMP CHARGING", "CarrierJump": "CARRIER JUMP",
    "SupercruiseEntry": "SUPERCRUISE", "SupercruiseExit": "SUPERCRUISE EXIT", "SupercruiseDestinationDrop": "DROPPED AT",
    "Docked": "DOCKED", "Undocked": "UNDOCKED", "DockingRequested": "DOCKING REQUESTED", "DockingGranted": "DOCKING GRANTED",
    "DockingDenied": "DOCKING DENIED", "DockingCancelled": "DOCKING CANCELLED", "DockingTimeout": "DOCKING TIMEOUT",
    "Scanned": "SCANNED", "Interdicted": "INTERDICTED", "Interdiction": "INTERDICTION", "EscapeInterdiction": "INTERDICTION EVADED",
    "HullDamage": "HULL DAMAGE", "ShieldState": "SHIELDS", "UnderAttack": "UNDER ATTACK", "FuelScoop": "FUEL SCOOP",
    "RefuelAll": "REFUEL", "RefuelPartial": "REFUEL", "RepairAll": "REPAIR", "Repair": "REPAIR", "BuyAmmo": "REARM",
    "MarketBuy": "MARKET BUY", "MarketSell": "MARKET SELL", "Bounty": "BOUNTY", "RedeemVoucher": "VOUCHERS REDEEMED",
    "MissionAccepted": "MISSION ACCEPTED", "MissionCompleted": "MISSION COMPLETE", "MissionFailed": "MISSION FAILED",
    "MissionAbandoned": "MISSION ABANDONED", "ApproachBody": "APPROACHING", "LeaveBody": "LEAVING", "Touchdown": "TOUCHDOWN",
    "Liftoff": "LIFTOFF", "ApproachSettlement": "SETTLEMENT", "Location": "LOCATION", "HeatWarning": "HEAT WARNING",
    "HeatDamage": "HEAT DAMAGE", "LaunchFighter": "FIGHTER LAUNCHED", "DockFighter": "FIGHTER DOCKED", "Died": "DESTROYED",
    "Resurrect": "REBUY", "CrewWage": "CREW WAGE", "NpcCrewPaidWage": "CREW WAGE", "JetConeBoost": "FSD BOOST",
}
_EVENT_HIDDEN = {"MUSIC", "NAVROUTEFILE", "RESERVOIRREPLENISHED", "FILEHEADER", "RECEIVETEXT_NPC_NOISE"}

def _event_label(name: str) -> str:
    raw = str(name or "").strip()
    if raw in _EVENT_LABELS:
        return _EVENT_LABELS[raw]
    for key, label in _EVENT_LABELS.items():
        if key.upper() == raw.upper():
            return label
    # Unknown CamelCase journal names read as words: "ApproachBody" -> "APPROACH BODY".
    if re.fullmatch(r"[A-Z][a-z]+(?:[A-Z][a-z0-9]*)+", raw):
        return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", raw).upper()
    return raw

def _event_rows(lines: list[str], limit: int = 5) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for raw in list(lines or [])[::-1]:
        if len(rows) >= limit:
            break
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
        if event_name.strip().upper().replace(" ", "") in _EVENT_HIDDEN:
            continue
        label = _event_label(event_name.strip())
        rows.append({
            "time": stamp,
            "event": label,
            "summary": summary.strip() if sep else "",
            "text": label + (" // " + summary.strip() if sep else ""),
        })
    return rows




# Route log presentation: the route engine's step-by-step lines are diagnostics, so
# the log keeps outcomes only and every row reads "EVENT // DETAIL".
_NAV_LOG_HIDE = re.compile(
    r"^(covas step|covas path:|covas timing|covas-style|qml route request|copied exact|pasted exact|quick destination selected|"
    r"bindings reloaded|route confirmed using|navigation is already armed)", re.IGNORECASE)

def _nav_log_body(body: str) -> str:
    text = str(body or "").strip()
    if " // " in text:
        return text
    low = text.lower()
    m = re.match(r"^(?:covas path failed|covas [a-z -]*failed|portable route (?:failed|aborted)[^:]*|navigation action failed)[^:]*:\s*(.*)$", text, re.IGNORECASE)
    if m:
        return "PLOT FAILED // " + (m.group(1) or text).strip()
    m = re.match(r"^portable route aborted at ([^:]+):\s*(.*)$", text, re.IGNORECASE)
    if m:
        return "PLOT ABORTED // " + m.group(2).strip()
    if low.startswith("portable route complete"):
        rest = text.split(":", 1)[1].strip() if ":" in text else ""
        return "ROUTE PLOTTED" + (" // " + rest if rest else "")
    if low.startswith("blocked:"):
        return "BLOCKED // " + text.split(":", 1)[1].strip()
    if low.startswith("navigation controls armed"):
        return "NAV ARMED"
    if low.startswith("navigation controls disarmed"):
        return "NAV DISARMED"
    if low.startswith("already in ") or low.startswith("route already points"):
        return "NO CHANGE NEEDED // " + text
    if low.startswith("navigation memory"):
        m = re.match(r"^navigation memory (\w+)[^:]*:\s*(.*)$", text, re.IGNORECASE)
        if m:
            slot = m.group(1).upper().replace("BOOKMARK", "BOOKMARK ").replace("  ", " ").strip()
            return f"{slot} SAVED // {m.group(2).strip()}"
    if ":" in text:
        head, rest = text.split(":", 1)
        if len(head) <= 32 and rest.strip():
            return head.strip() + " // " + rest.strip()
    return text

def _nav_history_rows(lines: list[str], limit: int = 6) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for raw in list(lines or [])[::-1]:
        if len(rows) >= limit:
            break
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
        if _NAV_LOG_HIDE.match(body):
            continue
        rows.append({"time": stamp, "text": _nav_log_body(body)})
    return rows

def _target_line(kind: str, name: str) -> str:
    kind = str(kind or "IN-SYSTEM TARGET").strip()
    return f"{kind} // {name}" if kind.upper().endswith("TARGET") else f"{kind} TARGET // {name}"

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
            _append_qml_nav_trip_line(app, _target_line(state['targetKind'], state['targetName']))
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
            _append_qml_nav_trip_line(app, _target_line(state['targetKind'], state['targetName']))
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

_SESSION_STATUS_KEYS = ("Pips", "Fuel", "GuiFocus", "LegalState", "Cargo", "Destination", "Oxygen", "Health", "SelectedWeapon")


def _elite_in_session(status):
    """True when Status.json describes a commander in a ship, SRV or on foot.

    At the main menu Elite writes only {"timestamp", "event", "Flags": 0}. In a
    session it adds Flags/Flags2 bits and fields such as Pips, Fuel and GuiFocus.
    An unreadable status counts as in session so this never hides real data.
    """
    if not isinstance(status, dict):
        return True
    try:
        if int(status.get("Flags", 0) or 0) or int(status.get("Flags2", 0) or 0):
            return True
    except Exception:
        return True
    return any(k in status for k in _SESSION_STATUS_KEYS)


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


# Audio device lists. Windows reports every device once per audio system (MME,
# DirectSound, WASAPI, WDM-KS) and MME cuts names at 31 characters. The Bridge
# lists DirectSound only (full names, one row per device) and opens streams by
# device index so a full name never matches more than one device.
_AUDIO_SKIP_RX = re.compile(r"^(microsoft sound mapper|primary sound (capture )?driver)", re.I)
_SD_INDEX = {"in": {}, "out": {}}
_SD_ALT = {}       # DirectSound index -> same device under MME (older name, cut at 31 chars)
_SD_BAD = set()    # MME indexes that failed to open this session (fall back to DirectSound)
_ORIG_SD_DEVICE_ARG = legacy._sd_device_arg


def _qml_sd_device_arg(name):
    n = str(name or "System Default").strip()
    if not n or n == "System Default":
        return None
    i_out = _SD_INDEX["out"].get(n)
    i_in = _SD_INDEX["in"].get(n)
    if i_out is not None and i_in is not None and i_out != i_in:
        return _ORIG_SD_DEVICE_ARG(n)
    idx = i_out if i_out is not None else i_in
    if idx is None:
        return _ORIG_SD_DEVICE_ARG(n)
    # Play and record through the same device under MME (the path Windows default
    # uses, and the one that works with virtual surround drivers). DirectSound is
    # only used when there is no MME twin, or the MME twin failed to open.
    mme = _SD_ALT.get(idx)
    if mme is not None and mme not in _SD_BAD:
        return mme
    return idx


legacy._sd_device_arg = _qml_sd_device_arg


class _SdRetryProxy:
    """Wraps the sounddevice module. If a stream can't open on the DirectSound
    device, log why and retry the same device the old way (MME) once."""

    def __init__(self, real):
        self._real = real

    def __getattr__(self, name):
        return getattr(self._real, name)

    def _open(self, kind, args, kw):
        ctor = getattr(self._real, kind)
        dev = kw.get("device")
        try:
            return ctor(*args, **kw)
        except Exception as exc:
            alt = None
            if isinstance(dev, int):
                alt = next((ds for ds, mme in _SD_ALT.items() if mme == dev), None)
            try:
                dname = str(self._real.query_devices(dev).get("name")) if dev is not None else "Windows default"
            except Exception:
                dname = str(dev)
            print(f"[AUDIO] {kind} could not open {dname} (device {dev}) // {exc}" + (f" // retrying as device {alt}" if alt is not None else ""), flush=True)
            if alt is None:
                raise
            _SD_BAD.add(dev)
            kw = dict(kw); kw["device"] = alt
            try:
                return ctor(*args, **kw)
            except Exception as exc2:
                print(f"[AUDIO] {kind} retry on device {alt} failed too // {exc2}", flush=True)
                raise

    def RawOutputStream(self, *args, **kw):
        return self._open("RawOutputStream", args, kw)

    def RawInputStream(self, *args, **kw):
        return self._open("RawInputStream", args, kw)

    def OutputStream(self, *args, **kw):
        return self._open("OutputStream", args, kw)

    def InputStream(self, *args, **kw):
        return self._open("InputStream", args, kw)


if getattr(legacy, "SOUNDDEVICE_AVAILABLE", False) and getattr(legacy, "sd", None) is not None and not isinstance(legacy.sd, _SdRetryProxy):
    legacy.sd = _SdRetryProxy(legacy.sd)


def _audio_full_name(name, names):
    """Map a saved or Windows-default name (possibly cut at 31 chars) to a listed full name."""
    n = " ".join(str(name or "").split())
    if not n or n == "System Default":
        return None
    if n in names:
        return n
    low = n.lower()
    hits = [x for x in names if x.lower().startswith(low)]
    return hits[0] if len(hits) == 1 else None


def _route_file_is_stale(state, upcoming) -> bool:
    """True when NavRoute.json's upcoming list disagrees with Elite's live FSD target.

    Elite does not always rewrite NavRoute.json (a same-destination replot only
    writes FSDTarget). Elite also writes the next FSDTarget during the jump
    countdown, before the FSDJump that moves us, so the target may sit one or more
    hops into the list. Consistent = the target is in the list and
    RemainingJumpsInRoute matches the jumps left from there.
    """
    try:
        rem = getattr(state, "nav_target_remaining_jumps", None)
        target = str(getattr(state, "nav_target_system", "") or "").strip().casefold()
        if not isinstance(rem, int) or rem <= 0 or target in ("", "-") or not upcoming:
            return False
        names = [str((r or {}).get("system") or "").strip().casefold() for r in upcoming]
        return not any(n == target and rem == len(names) - i for i, n in enumerate(names))
    except Exception:
        return False


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
    # 2.0.1: Elite also writes Status.json at the main menu, with Flags 0 and no ship
    # data. That is not a session yet, so it must not count as CONNECTED (the deck used
    # to show shields down, no cargo and so on at the menu). MENU = game running, not
    # loaded into a ship or on foot.
    if elite_telemetry_state == "CONNECTED" and not _elite_in_session(getattr(s, "status", None)):
        elite_telemetry_state = "MENU"

    # Never turn missing telemetry into plausible ship state. Status flags default
    # to false, which previously made a clean PC look like a real ship in normal
    # flight with shields down, gear up and hardpoints retracted. Only live Elite
    # telemetry may produce those values.
    elite_live = elite_telemetry_state == "CONNECTED"
    app._qml_elite_state = elite_telemetry_state      # setup wizard narration (CONNECT TO ELITE)
    if not elite_live:
        game_state = {"OFFLINE": "ELITE OFFLINE", "MENU": "MAIN MENU"}.get(elite_telemetry_state, "WAITING FOR ELITE")
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
    ai_credits_out = bool(getattr(app, "_qml_ai_credits_out", False))

    system_rows = [
        {"label": "ELITE DATA", "value": "AT MAIN MENU" if elite_telemetry_state == "MENU" else elite_telemetry_state,
         "level": "ok" if elite_telemetry_state == "CONNECTED" else ("info" if elite_telemetry_state == "MENU" else "warn")},
        {
            "label": "AI / VOICE",
            "value": ("NO CREDITS" if ai_credits_out else ("THINKING" if app.copilot_busy else ("READY" if ai_api_verified else "CHECK API"))) if copilot_mode else "OFF",
            "level": ("bad" if ai_credits_out else ("warn" if app.copilot_busy else ("ok" if ai_api_verified else "warn"))) if copilot_mode else "info",
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
        raw_upcoming = getattr(app, "_qml_raw_upcoming_route_entries", None) or app._travel_upcoming_route_entries
        route_upcoming = list(raw_upcoming() or [])
    except Exception:
        route_upcoming = []

    # ...but Elite does not always rewrite NavRoute.json. Replotting to the same
    # destination (e.g. after a ship swap) only writes FSDTarget, so the file keeps
    # the old route (2026-10-07: 12 jumps from the Panther shown after the Mandalay
    # replot to 5). When the live FSD target disagrees with the file (see
    # _route_file_is_stale), trust the target and show only what Elite told us.
    route_stale = False
    try:
        live_rem = getattr(s, "nav_target_remaining_jumps", None)
        live_target = _valid_text(getattr(s, "nav_target_system", "-"))
        if _route_file_is_stale(s, route_upcoming):
            route_stale = True
            old_dest = _valid_text(getattr(s, "nav_route_destination", "-"))
            synth = [{"system": live_target, "star_class": _valid_text(getattr(s, "nav_target_star_class", "-")),
                      "scoopable": None}]
            if live_rem >= 2 and old_dest not in ("", "-") and old_dest.casefold() != live_target.casefold():
                if live_rem > 2:
                    synth.append({"system": f"{live_rem - 2} MORE", "star_class": "-", "scoopable": None,
                                  "kind": "ELLIPSIS", "hidden_count": live_rem - 2})
                synth.append({"system": old_dest, "star_class": "-", "scoopable": None})
            for row in synth:
                if row.get("kind") != "ELLIPSIS" and row["star_class"] not in ("", "-"):
                    try:
                        row["scoopable"] = bool(app._travel_star_is_scoopable(app._travel_normalize_star_class(row["star_class"])))
                    except Exception:
                        pass
            route_upcoming = synth
    except Exception:
        route_stale = False

    route_jumps = None
    if route_stale:
        route_jumps = int(getattr(s, "nav_target_remaining_jumps", 0) or 0)
    if route_jumps is None and destination != "NO ROUTE" and bool(getattr(s, "nav_route_file_connected", False)) and route_upcoming:
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
        if route_stale:
            route_status += "  //  FULL ROUTE NOT SAVED BY ELITE"

    next_star_class = _valid_text(getattr(s, "nav_target_star_class", "-"))
    next_star_scoopable: bool | None = None
    next_star_system = target
    try:
        upcoming = [] if route_stale else app._travel_scoopability_lookahead_rows(limit=1)
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
    ai_tool_mode = _valid_text(getattr(app.ai_tool_mode_var, "get", lambda: "Auto Navigation")(), "Auto Navigation")
    if ai_tool_mode == "Ask Before Acting":
        ai_tool_mode = "Auto Navigation"
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
        # A spoken reply appears sentence by sentence as the voice reaches it.
        try:
            reveal = app.voice_engine.reveal_view() if hasattr(app.voice_engine, "reveal_view") else None
        except Exception:
            reveal = None
        if reveal and ai_comms_rows:
            full_text, shown_text = reveal
            row = ai_comms_rows[-1]
            if row.get("speaker") == "BRIDGE" and row.get("text") == full_text[:420]:
                row["text"] = shown_text[:420] if shown_text else "Working on that now..."
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

    # Full flight plan for the Navigation page list (the map above stays compressed).
    nav_full_route: list[dict[str, Any]] = []
    if current_system not in ("", "-"):
        nav_full_route.append({"system": current_system, "starClass": current_star_class,
                               "scoopable": bool(current_scoopable) if current_scoopable is not None else None,
                               "kind": "CURRENT"})
    _full_rows = [r for r in list(upcoming or []) if isinstance(r, dict) and _valid_text(r.get("system"), "-") not in ("", "-")]
    for _i, row in enumerate(_full_rows[:400]):
        if str(row.get("kind") or "").upper() == "ELLIPSIS":
            nav_full_route.append({"system": f"{int(row.get('hidden_count') or 0)} JUMPS NOT SAVED BY ELITE", "starClass": "-",
                                   "scoopable": None, "kind": "ROUTE"})
            continue
        nav_full_route.append({
            "system": _valid_text(row.get("system"), "-"),
            "starClass": _valid_text(row.get("star_class"), "-"),
            "scoopable": bool(row.get("scoopable")) if row.get("scoopable") is not None else None,
            "kind": "DESTINATION" if _i == len(_full_rows) - 1 else "ROUTE",
        })
    if len(nav_full_route) <= 1 and target not in ("", "-") and target != current_system:
        nav_full_route.append({"system": target, "starClass": next_star_class,
                               "scoopable": next_star_scoopable, "kind": "DESTINATION"})

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
    res_ls_limit = _qml_res_ls_limit(app)
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
        if res_ls < 0 or res_ls > res_ls_limit:
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
            "supportStation": _valid_text(row.get("support_station"), "-"),
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
        "recentEvents": _event_rows(list(getattr(s, "event_log", []) or []), limit=30),
        "alertLabel": alert_label,
        "alertValue": alert_value,
        "alertDetail": alert_detail,
        "alertLevel": _level_color_name(alert_level),
        "destination": destination,
        "fsdTarget": target if target not in ("", "-") else destination,
        "routeStatus": route_status,
        "routeStale": bool(route_stale),
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
        **(app._qml_mic_snapshot() if hasattr(app, "_qml_mic_snapshot") else {}),
        "voiceInputStatus": voice_input_status,
        "controlCaptureAction": control_capture_action,
        "keyboardCaptureArmed": str(getattr(app, "_qml_kb_capture_armed", "") or ""),
        "keyboardCaptureError": str(getattr(app, "_qml_kb_capture_error", "") or ""),
        "keyboardCaptureDone": dict(getattr(app, "_qml_kb_capture_done", {}) or {}),
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
        "navFullRoute": nav_full_route,
        "navHistory": _nav_history_rows(list(getattr(app, "_qml_nav_trip_history", []) or []), limit=30),
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
        "combatSweepContacts": list(getattr(app, "_qml_sweep_contacts", []) or []),
        "combatSweepTime": _event_stamp_local_12h(str(getattr(app, "_qml_sweep_time", "") or "")) if getattr(app, "_qml_sweep_time", "") else "-",
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


def _qml_res_ls_limit(app):
    """The SITE WITHIN limit of the last RES search (the list and PLOT: SITE must agree). Default 10,000 LS."""
    try:
        q = getattr(app, "res_search_last_query", None) or {}
        return max(100.0, float(q.get("max_ls") or 10000.0))
    except Exception:
        return 10000.0


class _QmlIntraResClient(legacy.INTRARESClient):
    """INTRA client for all four RES levels. INTRA's API keys: low, med (Elite's plain
    "Resource Extraction Site", shown as STANDARD), hi, haz. The engine's client only
    ever asked for hi / haz. `want` (a list of labels) picks the levels for the next
    search; None keeps the engine's High / Haz checkboxes."""
    KEYS = {"Low": "low", "Standard": "med", "High": "hi", "Hazardous": "haz"}
    ORDER = ("Low", "Standard", "High", "Hazardous")

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self.want = None

    @classmethod
    def _label(cls, kind):
        k = str(kind or "").strip().casefold()
        if k.startswith("haz"):
            return "Hazardous"
        if k.startswith("hi"):
            return "High"
        if k.startswith("lo"):
            return "Low"
        if k.startswith(("std", "stan", "med", "norm", "res")):
            return "Standard"
        return "High"

    @classmethod
    def normalize_row(cls, arena, kind):
        label = cls._label(kind)
        if label in ("High", "Hazardous"):
            return super().normalize_row(arena, kind)
        # same rules as the engine's row, read from this level's status object
        key = cls.KEYS[label]
        status = arena.get(key) if isinstance(arena, dict) else None
        if not isinstance(status, dict):
            return None
        shadow = dict(arena)
        shadow["hi"] = status
        row = super().normalize_row(shadow, "hi")
        if row:
            row["type"] = label
        return row

    def _post_kind(self, coords, radius_ly, max_ls, kind, timeout=8):
        label = self._label(kind)
        if label in ("High", "Hazardous"):
            return super()._post_kind(coords, radius_ly, max_ls, kind, timeout)
        x, y, z = (float(coords[0]), float(coords[1]), float(coords[2]))
        payload = {
            "ver": 1, "lim": 50,
            "ref": {"x": x, "y": y, "z": z, "max": float(radius_ly)},
            "arena": {"dist": {self.KEYS[label]: float(max_ls)}},
        }
        req = legacy.urllib.request.Request(
            self.endpoint,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json", "Accept": "application/json",
                     "User-Agent": f"EliteAIBridge/{legacy.APP_VERSION.split()[0]}"},
            method="POST",
        )
        with legacy.urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = json.loads(resp.read().decode("utf-8", errors="replace"))
        if not isinstance(raw, dict) or int(raw.get("ok", 0) or 0) != 1:
            raise RuntimeError(str((raw or {}).get("msg") or "INTRA returned an unsuccessful response"))
        out = []
        for row in raw.get("body") or []:
            arena = row.get("arena") if isinstance(row, dict) else None
            if isinstance(arena, dict):
                n = self.normalize_row(arena, label)
                if n:
                    out.append(n)
        return out

    def search(self, coords, radius_ly=50.0, max_ls=10000.0, include_high=True, include_haz=True):
        want = self.want
        if not want:
            return super().search(coords, radius_ly, max_ls, include_high=include_high, include_haz=include_haz)
        kinds = [k for k in self.ORDER if k in want]
        results, errors = [], []
        for kind in kinds:
            try:
                results.extend(self._post_kind(coords, radius_ly, max_ls, kind))
            except Exception as exc:
                errors.append(f"{kind}: {exc}")
        if not results and errors:
            raise RuntimeError(" | ".join(errors))
        rank = {k: i for i, k in enumerate(self.ORDER)}
        results.sort(key=lambda r: (
            r.get("distance_ly", 1e9) if r.get("distance_ly", -1) >= 0 else 1e9,
            rank.get(r.get("type"), 9), r.get("system", ""),
        ))
        return results, errors


class HeadlessBridgeApp(legacy.BridgeApp):
    """Run .95 unchanged as the engine while suppressing its legacy windows."""

    def _refresh_audio_devices(self, save=True):
        """One row per device with its full name (DirectSound). Falls back to the engine's scan."""
        sd = getattr(legacy, "sd", None)
        scan = None
        if legacy.SOUNDDEVICE_AVAILABLE and sd is not None:
            try:
                apis = list(sd.query_hostapis())
                ds = next((i for i, a in enumerate(apis) if "directsound" in str(a.get("name", "")).lower()), None)
                if ds is not None:
                    rows = list(sd.query_devices())
                    ins, outs, idx_in, idx_out = [], [], {}, {}
                    for i, row in enumerate(rows):
                        if int(row.get("hostapi", -1)) != ds:
                            continue
                        name = " ".join(str(row.get("name") or "").split())
                        if not name or _AUDIO_SKIP_RX.match(name):
                            continue
                        if int(row.get("max_input_channels", 0) or 0) > 0 and name not in idx_in:
                            ins.append(name); idx_in[name] = i
                        if int(row.get("max_output_channels", 0) or 0) > 0 and name not in idx_out:
                            outs.append(name); idx_out[name] = i
                    if ins or outs:
                        alt = {}
                        mme = next((i for i, a in enumerate(apis) if str(a.get("name", "")).strip().upper() == "MME"), None)
                        if mme is not None:
                            for kind_key, table in (("max_input_channels", idx_in), ("max_output_channels", idx_out)):
                                for full, di in table.items():
                                    cut = full[:31].strip()
                                    hits = []
                                    for j, r2 in enumerate(rows):
                                        if int(r2.get("hostapi", -1)) != mme or int(r2.get(kind_key, 0) or 0) <= 0:
                                            continue
                                        short = " ".join(str(r2.get("name") or "").split())
                                        if short and (short == full or short == cut):
                                            hits.append(j)
                                    if len(hits) == 1:
                                        alt[di] = hits[0]
                        default_in, default_out = "System Default", "System Default"
                        try:
                            di, do = sd.default.device
                            if isinstance(di, int) and di >= 0:
                                raw = str(rows[di].get("name") or "")
                                default_in = _audio_full_name(raw, ins) or raw or "System Default"
                            if isinstance(do, int) and do >= 0:
                                raw = str(rows[do].get("name") or "")
                                default_out = _audio_full_name(raw, outs) or raw or "System Default"
                        except Exception:
                            pass
                        scan = (ins, outs, idx_in, idx_out, default_in, default_out, alt)
            except Exception as exc:
                print(f"Audio device scan (DirectSound) failed, using engine scan: {exc}", flush=True)
                scan = None
        if scan is None:
            _SD_INDEX["in"], _SD_INDEX["out"] = {}, {}
            _SD_ALT.clear(); _SD_BAD.clear()
            return super()._refresh_audio_devices(save=save)
        ins, outs, idx_in, idx_out, default_in, default_out, alt = scan
        _SD_INDEX["in"], _SD_INDEX["out"] = idx_in, idx_out
        _SD_ALT.clear(); _SD_ALT.update(alt); _SD_BAD.clear()
        self.audio_input_devices = ["System Default"] + ins
        self.audio_output_devices = ["System Default"] + outs
        self.audio_default_input = default_in
        self.audio_default_output = default_out
        # saved picks from older builds may be cut at 31 characters; move them to the full name
        for var, names in ((self.voice_input_device_var, ins), (self.audio_output_device_var, outs)):
            cur = str(var.get() or "System Default")
            if cur != "System Default" and cur not in names:
                full = _audio_full_name(cur, names)
                var.set(full or "System Default")
                if full:
                    save = True
        for attr, values in (("voice_input_device_combo", self.audio_input_devices), ("audio_output_device_combo", self.audio_output_devices)):
            combo = getattr(self, attr, None)
            if combo is not None:
                try:
                    combo.configure(values=tuple(values))
                except Exception:
                    pass
        if hasattr(self, "audio_default_device_var"):
            self.audio_default_device_var.set(f"Windows/default input: {default_in}  \u2022  output: {default_out}")
        self._voice_apply_settings(save=False)
        self._sfx_apply_settings(save=False)
        if save:
            self._save_automation_config()
        self.refresh_preferences_widgets()

    # ---------------------------------------------------------------- MIC CHECK (one button)
    # Listens 5 seconds, no push to talk. Shows the level live, then a plain result.
    # With an API key it also shows the words the AI made out (nothing is run).
    _MIC_CHECK_SECONDS = 5.0

    def _qml_mic_check_start(self):
        words = bool(os.environ.get("OPENAI_API_KEY"))
        self._qml_mic = {"state": "LISTENING", "t0": time.monotonic(), "words": words,
                         "result": "", "detail": "", "level": "", "heard": ""}
        if words:
            self._test_ai_hearing()
        else:
            self._test_microphone_level()
        if not (getattr(self, "voice_mic_test_busy", False) or getattr(self, "voice_ai_hearing_test_busy", False)):
            self._qml_mic_finish("COULDN'T START", str(getattr(self, "voice_input_status", "") or "The microphone is busy."), "bad")

    def _qml_mic_finish(self, result, detail, level, heard=""):
        m = getattr(self, "_qml_mic", None)
        if not m:
            return
        m.update({"state": "DONE", "result": result, "detail": detail, "level": level, "heard": heard, "t_done": time.monotonic()})

    def _qml_mic_grade(self, peak_percent):
        raw = max(0.0, float(peak_percent or 0.0) / 100.0)
        _v, db, label = self._mic_signal_display(raw)
        if db <= -55.0:
            return "NOTHING HEARD", "No sound reached the Bridge. Check the microphone picked on Sound, and that it isn't muted.", "bad"
        if label in ("VERY LOW", "LOW"):
            return "HEARD YOU, BUT QUIET", f"Level {db:.0f} dB. Speak up, move the mic closer, or raise its level in Windows.", "warn"
        if label == "CLIPPING":
            return "TOO LOUD", f"Level {db:.0f} dB. Lower the mic level in Windows so speech doesn't distort.", "warn"
        return "HEARD YOU", f"Level {db:.0f} dB. That's a good level.", "ok"

    def _mic_test_complete(self, peak_percent):
        super()._mic_test_complete(peak_percent)
        m = getattr(self, "_qml_mic", None)
        if m and m.get("state") != "DONE" and not m.get("words"):
            r, d, lv = self._qml_mic_grade(peak_percent)
            self._qml_mic_finish(r, d + " Add an AI key to also see the words it hears.", lv)

    def _voice_hearing_test_result(self, text_value, peak_percent):
        super()._voice_hearing_test_result(text_value, peak_percent)
        m = getattr(self, "_qml_mic", None)
        if m and m.get("state") != "DONE" and m.get("words"):
            r, d, lv = self._qml_mic_grade(peak_percent)
            if text_value:
                self._qml_mic_finish(r, d, lv, str(text_value))
            elif lv == "bad":
                self._qml_mic_finish(r, d, lv)
            else:
                self._qml_mic_finish("NO WORDS MADE OUT", d + " Sound came through but no words were picked up. Try speaking a full sentence.", "warn")

    def _voice_test_error(self, message):
        super()._voice_test_error(message)
        m = getattr(self, "_qml_mic", None)
        if m and m.get("state") != "DONE":
            self._qml_mic_finish("MIC CHECK FAILED", str(message), "bad")

    def _qml_mic_snapshot(self):
        m = getattr(self, "_qml_mic", None)
        try:
            visual, _db, _label = self._mic_signal_display(float(getattr(self, "voice_input_level", 0.0) or 0.0))
        except Exception:
            visual = 0.0
        out = {"micCheckState": "IDLE", "micCheckSecondsLeft": 0, "micCheckResult": "", "micCheckDetail": "",
               "micCheckLevel": "", "micCheckHeard": "", "micCheckWords": bool(os.environ.get("OPENAI_API_KEY")),
               "voiceMicMeter": round(max(0.0, min(1.0, float(visual) / 100.0)), 3)}
        if not m:
            return out
        state = m.get("state", "IDLE")
        if state == "DONE" and time.monotonic() - float(m.get("t_done", 0)) > 30:
            return out
        if state == "LISTENING":
            left = self._MIC_CHECK_SECONDS - (time.monotonic() - float(m.get("t0", 0)))
            if left <= 0:
                state = "CHECKING" if m.get("words") else "LISTENING"
            out["micCheckSecondsLeft"] = max(0, int(math.ceil(left)))
            if time.monotonic() - float(m.get("t0", 0)) > 60:
                state = "IDLE"
        out.update({"micCheckState": state, "micCheckResult": m.get("result", ""), "micCheckDetail": m.get("detail", ""),
                    "micCheckLevel": m.get("level", ""), "micCheckHeard": m.get("heard", ""), "micCheckWords": bool(m.get("words"))})
        return out

    def __init__(self):
        # v0.30.00 OOBE policy lives in the adapter so the protected .95 engine
        # remains byte-for-byte unchanged. Existing user files always win. Only
        # a genuinely new profile receives release-safe neutral defaults.
        fresh_automation = not legacy.AUTOMATION_CONFIG_FILE.exists()
        fresh_trade = not legacy.TRADE_LOOP_CONFIG_FILE.exists()
        super().__init__()
        # all four RES levels for Combat > Bounty Hunting (engine client knew High / Haz only)
        self.intra_res_client = _QmlIntraResClient()

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
                ("NEEDS ATTENTION" if getattr(self, "_qml_ai_credits_out", False) else ("READY" if api_verified else "MISSING")) if copilot_mode else "OFF",
                ("Your OpenAI account is out of credit. Add credit at platform.openai.com; this clears by itself once the AI answers again." if getattr(self, "_qml_ai_credits_out", False)
                 else "Verified API connection ready." if api_verified else "AI Co-Pilot requires a verified OpenAI API key before this mode can be enabled.")
                if copilot_mode
                else "Core Bridge mode: AI Co-Pilot is disabled.",
            ),
        ]
        # The API key is the only first-run hard stop, and only on the Copilot path.
        required_ready = bool(api_verified) if copilot_mode else True
        return rows, elite_rows, required_ready

    _UI_PAGE_NAMES = {
        0: "FLIGHT DECK", 1: "NAVIGATION", 2: "COMBAT", 3: "TRADE", 4: "COLONIZATION",
        5: "COMMANDER", 6: "AI & VOICE", 7: "AUDIO", 8: "SETUP", 9: "DISPLAY", 10: "CONTROLS", 11: "AUTOMATION",
    }

    def request_copilot_command(self):
        if not self._qml_copilot_enabled():
            self.copilot_status = "Core Bridge mode // enable AI Co-Pilot from Setup to use conversational AI."
            self.refresh_copilot_widgets()
            return
        return super().request_copilot_command()

    def build_ai_snapshot(self):
        """Add the pilot's visible Bridge screen to Luna's normal live context."""
        self._qml_copilot_thread_gen()  # tag the AI thread as early as possible
        snapshot = super().build_ai_snapshot()
        try:
            page_index = int(getattr(self, "_qml_ui_context_page", 0) or 0)
        except Exception:
            page_index = 0
        page_index = max(0, min(11, page_index))
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
            ("BRIDGE MODULES", "These are the main working areas of the Bridge. The flashing yellow highlight shows what is being explained. Flight Deck is your home screen, and the other buttons take you to combat, trade, travel, colonization, your commander record, and setup."),
            ("FLIGHT DECK", "Flight Deck is your home screen. It shows your ship and shields, the event log, the next jumps on your route, and the most used flight actions. The yellow Master Caution light at the top lights up when something needs your attention."),
            ("COMBAT", "Use Combat when you are fighting or looking for a place to fight. It has targeting tools, fighter controls, warnings, and Bounty Hunting, which finds places to hunt pirates."),
            ("TRADE", "Use Trade when you want to make money moving cargo. The Bridge can show strong trades, routes for one commodity, or help manage a trade loop."),
            ("NAVIGATION", "Navigation is mainly your travel monitor. Once a route is plotted, it follows your next jumps, fuel stars, saved locations, docking, and launch tools while you fly."),
            ("COLONIZATION", "Use Colonization when you are helping build a system project. It tracks what is still needed and can send shopping work over to Trade."),
            ("COMMANDER", "Commander is your record: your ranks, Elite's own career totals, your ship and cargo, and what has happened during this play session."),
            ("SETUP", "Setup holds every setting in one place: Status, Voice and AI, Sound, Display, Controls and Automation, plus the setup wizard and the full tutorial."),
        ],
        1: [
            ("YOUR ROUTE", "Navigation is mostly here to follow the trip you are already flying. When Elite has a route plotted, the Bridge keeps the next jumps easy to read and points out useful fuel stars."),
            ("DESTINATION AREA", "If you already know a system name, this area can send that destination to Elite. For guided activities such as trading or combat, the Bridge can bring you here after the destination is chosen."),
            ("TRAVEL SHORTCUTS", "These are quick travel buttons for Home, bookmarks, docking, launch, and canceling a travel action while you are on the move."),
        ],
        2: [
            ("COMBAT BUTTONS", "These are quick fighting controls. Find Best Target does a fast hull-type sweep without waiting for a full scan; the other controls handle targets, fighters, wing commands, and getting out of danger."),
            ("TACTICAL OR BOUNTY HUNTING", "Tactical is for the fight you are in now. Bounty Hunting finds nearby Resource Extraction Sites, where pirates gather, so you can hunt them for bounties."),
            ("COMBAT INFORMATION", "This side keeps the important things together, such as bounty progress, scans, risky cargo, crew costs, and warnings."),
        ],
        3: [
            ("FIND A ROUTE OR MY RUN", "Trade has two views. Find A Route looks for a good trade near you. My Run follows the loop you are flying."),
            ("WHAT TO HAUL", "Leave What To Haul on Any for the best trade near you, or type the one commodity you want to carry."),
            ("FIND ROUTES", "Start here. Press Find Routes, pick a route from the list, then Use This Route and Plot Buy take you to the buy station."),
        ],
        4: [
            ("CONSTRUCTION SITE", "This is the project you are building: how far along it is, what is left to haul, and how many loads that is. The tower grows as you deliver."),
            ("SHOPPING LIST AND WHERE TO BUY", "The shopping list shows every material still needed, biggest first. Click one to haul it next. Find Supply switches this screen to the stations that sell it, nearest first, with how old the data is."),
            ("ACTION KEYS", "Find Supply searches for the material you picked. Plot Buy plots a route to the station you picked in the list, and Plot Site plots back to the build site. My Sites up top lists every system you have claimed, read from your journals, with how far away each one is. Pick one and Plot Site takes you there."),
        ],
        5: [
            ("RANKS", "Your eight ranks, straight from Elite. The dial shows how far you are to the next rank, the amber pip is where you are on the ladder, and the tall pips are the five Elite levels. Navy ranks also show your standing with that superpower, and say when you are ready for a promotion mission."),
            ("CAREER", "Career shows Elite's own lifetime totals, updated each time you load into the game: credits, total worth, profits, systems, jumps, ships and time played."),
            ("THIS SESSION", "This Session counts what has happened since the Bridge started: jumps, dockings, sales, bounties and AI requests."),
            ("YOUR SHIP", "Your current ship with hull, fuel, cargo and jump range."),
            ("ODD STATS", "The strange numbers: how often you've been scanned this session, passengers you've ejected, the farthest you've been from home. It pages through them on its own."),
            ("ACTION KEYS", "Refresh re-reads your record. Dock and Launch work the same as on every page, and Cancel stops all automation. Want to report a bug? Setup, Status shows you how."),
        ],
        6: [
            ("SHIP VOICE", "This is the Voice and AI page. Ship Voice chooses how the ship sounds and how much it talks. Quiet still warns you about danger."),
            ("WHAT THE BRIDGE HEARS", "What The Bridge Hears shows your push to talk button, your microphone level, and the last thing the Bridge heard you say."),
            ("THE AI", "The AI panel checks the AI co-pilot is working, and lets you tell it about yourself if you like."),
            ("ACTION KEYS", "Voice Test plays a sample. Mic Check listens for 5 seconds, no push to talk, and shows your level and the words the AI heard."),
        ],
        7: [
            ("WHERE SOUND GOES", "This is the Sound page. Where Sound Goes picks the speakers or headset the ship voice plays on, and the microphone the Bridge listens to. Windows default follows whatever Windows is set to."),
            ("LEVELS", "Levels sets the ship voice and sound effect volumes. The switch turns every sound effect on or off at once."),
            ("ALERT SOUNDS", "Under Alert Sounds, each alert has its own on and off switch. Click one to pick it."),
            ("ACTIONS", "Play Sound lets you hear the picked alert. Rescan Devices looks again after you plug in a headset."),
        ],
        8: [
            ("IS EVERYTHING WORKING", "This is the Status page, the place to start. Is Everything Working checks the whole Bridge. Green is ready, amber can wait, and red needs fixing. A red item's Fix button takes you straight to the tab that fixes it."),
            ("YOUR NAME AND USAGE", "Set what the ship's voice calls you, choose whether the setup wizard opens at start, and see roughly what the AI has cost so far."),
            ("ACTION KEYS", "Run Check looks at everything again. Setup Wizard and Tutorial are the guides. Found a bug? Make Support File saves one zip, then Report On GitHub or Email It sends it to the developer."),
        ],
        12: [
            ("YOUR SHIP", "Your ship: hull, fuel, power and shields, and the four modules that matter most in flight. While your frame shift drive charges or you scoop fuel, the middle shows that instead."),
            ("EVENT LOG", "Everything Elite tells the Bridge, newest at the top: comms, scans, docking, jumps and more. The buttons above it switch to your cargo hold and your full loadout."),
            ("ROUTE", "The next jumps on your plotted route. Green stars can be scooped for fuel, amber ones can't."),
            ("ACTION KEYS", "The flight keys: Dock, Launch, Clear and Jump, and station services. Click a key and the Bridge does it for you. Cancel always stops it."),
        ],
        11: [
            ("AFTER YOU DOCK", "This is the Automation page: everything the Bridge does on its own. After You Dock, it can refuel, repair and rearm for you."),
            ("IN COMBAT", "In a fight it can move power around, target power plants on big wanted ships, and fire chaff. These are the same switches as on the Combat page."),
            ("AI SPEAKS UP", "AI Speaks Up lets the AI comment or give advice when things happen, without you asking. The big master switch at the top turns all of it on or off; the switches under it choose what it talks about. It never flies the ship."),
            ("AFTER YOU LAUNCH", "Clear and Jump After Launch carries straight on into your plotted jump after Auto Launch. It turns itself off when you close the Bridge."),
        ],
        9: [
            ("THIS WINDOW", "This is the Display page. This Window shows which screen the Bridge is on, its resolution and Windows scaling. Sizing follows Windows on its own."),
            ("SCREEN EFFECTS", "Screen Effects: static and screen effects give the Bridge screens their old-monitor look. Set both to zero to turn the effect off."),
            ("IN-GAME OVERLAY", "In-Game Overlay turns the panel over Elite on or off and sets which screen it's on, what it shows, which side it sits on, its size and how solid it is. It steps aside while the Bridge is in front on that screen. Elite has to be borderless or windowed; if it isn't, this panel tells you how to change it."),
            ("ACTIONS", "The Screen keys move the Bridge to that monitor and Identify shows which number is which. Maximize fills the screen, Fullscreen switches it on or off, and Reset Window puts it back on your main screen."),
        ],
        10: [
            ("PUSH TO TALK", "This is the Controls page. Push To Talk is the button you hold to speak to the ship; it needs the AI co-pilot. Click a cell, then press a HOTAS button or a key, just like Elite. Escape or Backspace clears it."),
            ("SHORTCUT KEYS", "Shortcut Keys run Bridge commands from anywhere, even inside Elite, so they suit a Stream Deck. Click a key and press the new one. It needs Control or Alt."),
            ("ELITE KEYS", "Under Elite Keys, the Bridge presses these keys in Elite for you, so each needs a key in Elite's own controls. Missing ones show a free key you could use."),
            ("ACTIONS", "Hold Restore Keys to put the shortcuts back to default. Rescan Elite reads your Elite keys again, and Copy Suggestion copies a free key for a missing one."),
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
            page = max(0, min(12, int(page)))
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
            page = max(0, min(11, int(page)))
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
                "Search for nearby Resource Extraction Sites (Low, Standard, High or Hazardous), combat areas. Use this when the commander asks "
                "to find a High RES, Haz RES, resource extraction site, or nearby combat hunting ground. "
                "The Bridge will automatically open Combat > RES Finder while the search runs."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": ["LOW", "STANDARD", "HIGH", "HAZ"], "description": "RES danger level to search for. HIGH suits most pilots; LOW and STANDARD have fewer pirates; HAZ has no police."},
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
                    "page": {"type": "string", "enum": ["FLIGHT DECK", "OVERVIEW", "LIVE", "NAVIGATION", "COMBAT", "TRADE", "COLONIZATION", "COMMANDER", "AI", "AUDIO", "SETUP", "DISPLAY", "CONTROLS", "AUTOMATION", "STATUS", "SOUND"]},
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
        if kind not in {"LOW", "STANDARD", "HIGH", "HAZ"}:
            kind = "HIGH"
        self._qml_set_ui_hint(2, "res_finder")
        started = threading.Event()
        box = {}

        def begin():
            try:
                self.res_search_high_var.set(kind != "HAZ")
                self.res_search_haz_var.set(kind == "HAZ")
                try:
                    self.intra_res_client.want = [{"LOW": "Low", "STANDARD": "Standard", "HIGH": "High", "HAZ": "Hazardous"}[kind]]
                except Exception:
                    pass
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
                "error": self._no_key_message(spec["action"], spec["label"]),
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

    def _no_key_message(self, action, label=None):
        """2.0.0: one plain message, the same every time, when Elite has no keyboard key for an
        action. No specific key is suggested: we can't see what else the pilot's PC uses."""
        name = str(label or self._qml_elite_action_label(action))
        name = name[:1].upper() + name[1:]
        elite_name = {"UseBoostJuice": "Engine Boost"}.get(str(action)) or self._qml_elite_action_label(action)   # Elite-style control name
        msg = (f"{name} needs a keyboard key in Elite. In Elite, go to Options, Controls, find {elite_name}, "
               "and give it a key combination you don't use for anything else, like Control plus Alt plus a letter.")
        try:
            root = getattr(self.bindings, "root", None)
            elem = root.find(str(action)) if root is not None else None
            if elem is not None:
                for slot in ("Primary", "Secondary"):
                    node = elem.find(slot)
                    if node is not None and node.attrib.get("Key") and node.attrib.get("Device") not in (None, "", "Keyboard"):
                        msg += " It's on your joystick, but I can only press keyboard keys, so give it a keyboard key too."
                        break
        except Exception:
            pass
        return msg

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
                reason = self._no_key_message(action, label)
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
            return {"ok": False, "elite_action": elite_action, "error": self._no_key_message(elite_action)}
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
                "error": self._no_key_message(elite_action, spec["label"]),
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
            return {"ok": False, "error": self._no_key_message("CycleNextTarget", "Cycle Next Target")}
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
            page_map = {"FLIGHT DECK":0, "FLIGHT_DECK":0, "OVERVIEW":0, "LIVE":0, "NAVIGATION":1, "COMBAT":2, "TRADE":3, "COLONIZATION":4, "COMMANDER":5, "AI":6, "AUDIO":7, "SETUP":8, "DISPLAY":9, "CONTROLS":10, "AUTOMATION":11, "STATUS":8, "SOUND":7}
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
        # Mark the spoken reply so the voice worker can reveal its text in the
        # AI COMMS log sentence by sentence, in step with the voice.
        engine = getattr(self, "voice_engine", None)
        try:
            if engine is not None and getattr(self, "copilot_voice_reply_pending", False):
                engine._qml_reveal_marker = " ".join(str(result.get("text") or "").replace("\r", " ").replace("\n", " ").split()).strip()
        except Exception:
            pass
        try:
            super().finish_copilot_command(result)
        finally:
            try:
                if engine is not None:
                    engine._qml_reveal_marker = ""
            except Exception:
                pass
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

        return self._qml_voice_say(required_level, spoken_text, kind=kind, key=key, cooldown=cooldown, _startup_release=_startup_release)

    def _qml_voice_say(self, required_level, text, kind="INFO", key=None, cooldown=5.0, _startup_release=False):
        """Same rules as the .95 _voice_say, with one timing change: when the
        attention earcon plays, speech is queued at once with a 330 ms playback
        hold, so synthesis runs during the earcon instead of after it.
        (AI replies never get the earcon: kind AI is not in the earcon lists.)"""
        required = legacy.VOICE_LEVELS.get(str(required_level or "MED").upper(), 2)
        if self._voice_level_value() < required:
            return False
        text = " ".join(str(text or "").replace("\r", " ").replace("\n", " ").split()).strip()
        if not text:
            return False
        if self.startup_voice_gate_active and not _startup_release:
            self.startup_voice_hold.append((required_level, text, kind, key, cooldown))
            return True
        if str(kind or "").upper() in ("MATERIAL", "SALVAGE"):
            return self._qml_batch_pickup(required_level, text, str(kind).upper())
        now = time.monotonic()
        dedupe_key = str(key or text).casefold()
        last = float(self.voice_last_by_key.get(dedupe_key, 0.0) or 0.0)
        if last and now - last < max(0.0, float(cooldown or 0.0)):
            self.voice_suppressed_count += 1
            return False
        kind_up = str(kind or "INFO").upper()
        # FIND BEST TARGET cycles through every contact; stay quiet while it does.
        # The sweep speaks one result line for the ship it picked when it ends.
        if kind_up == "TARGET" and bool(getattr(self, "native_command_busy", False)) \
                and str(getattr(self, "native_command_name", "")) == "Find Best Target":
            self.voice_suppressed_count += 1
            return False
        # A streamed AI reply has already spoken its opening sentences; say only the rest.
        if kind_up == "AI":
            done = str(getattr(self, "_qml_stream_spoken", "") or "")
            self._qml_stream_spoken = ""
            if done and text.startswith(done):
                rest = text[len(done):].strip()
                self.voice_last_announcement = text
                self.voice_last_kind = kind_up
                self.voice_history.append(f"{time.strftime('%H:%M:%S')}  {kind_up} | {text}")
                if not rest:
                    return True
                text = rest
        self.voice_last_by_key[dedupe_key] = now
        self.voice_last_announcement = text
        self.voice_last_kind = kind_up
        self.voice_history.append(f"{time.strftime('%H:%M:%S')}  {self.voice_last_kind} | {text}")
        pace = 0.92 if "credits" in text.casefold() else 1.0
        hold_until = 0.0
        if self._voice_attention_for_kind(self.voice_last_kind):
            if self._sfx_play("attention", cooldown=1.5):
                hold_until = time.monotonic() + 0.33
        try:
            return bool(self.voice_engine.say(text, speed_scale=pace, hold_until=hold_until, kind=self.voice_last_kind))
        except TypeError:
            # Engine without the hold parameter (should not happen in the QML host).
            return bool(self.voice_engine.say(text, speed_scale=pace))

    # ---------- pickups: collectors can grab a dozen things in a few seconds
    _PICKUP_WINDOW_MS = 3000

    def _qml_batch_pickup(self, required_level, text, kind):
        batch = getattr(self, "_qml_pickup_batch", None)
        if not isinstance(batch, dict) or not batch.get("items"):
            batch = {"items": [], "level": required_level, "kinds": set()}
            self._qml_pickup_batch = batch
            try:
                self.after(self._PICKUP_WINDOW_MS, self._qml_flush_pickups)
            except Exception:
                return self._qml_voice_say(required_level, text, kind="PICKUP", key=f"pickup:{text}", cooldown=0)
        batch["items"].append(text)
        batch["kinds"].add(kind)
        return True

    def _qml_flush_pickups(self):
        batch = getattr(self, "_qml_pickup_batch", None) or {}
        self._qml_pickup_batch = None
        items = list(batch.get("items") or [])
        if not items:
            return
        if len(items) == 1:
            line = items[0]
        else:
            names = []
            for t in items:
                m = re.match(r"^Collected\s+(?:\d+\s+)?(.+?)\.(?:\s.*)?$", t)
                n = (m.group(1) if m else t).strip()
                if n and n.casefold() not in [x.casefold() for x in names]:
                    names.append(n)
            kinds = batch.get("kinds") or set()
            noun = "Materials" if kinds == {"MATERIAL"} else ("Cargo" if kinds == {"SALVAGE"} else "Pickups")
            if len(names) <= 3:
                listed = ", ".join(names[:-1]) + (" and " if len(names) > 1 else "") + names[-1]
            else:
                listed = f"{names[0]}, {names[1]}, and {len(names) - 2} more"
            line = f"{noun} collected: {listed}."
        self._qml_voice_say(batch.get("level") or "HIGH", line, kind="PICKUP", key=f"pickup:{time.monotonic()}", cooldown=0)

    def _voice_engine_speech_started(self, text_value, backend, started_mono):
        # The voice worker caps one utterance at 900 characters, so a very long
        # reply reaches this callback truncated. Match it to the waiting reply.
        waiting = str(getattr(self, "voice_latency_waiting_tts_text", "") or "").strip()
        value = str(text_value or "").strip()
        if waiting and value and value != waiting and len(value) >= 900 and waiting.startswith(value):
            value = waiting
        self._qml_log_ptt_timing(started_mono)
        return super()._voice_engine_speech_started(value, backend, started_mono)

    # ------------------------------------------------------------------
    # PTT snappiness (2026-10). Stage timing log, kept-alive HTTPS, lowest
    # reasoning effort and streamed replies for voice turns, instant local
    # commands. The locked .95 copilot loop is unchanged; these hooks sit
    # under it (_openai_response_request, _transcribe_voice_file) or in front
    # of it (request_copilot_command).
    # ------------------------------------------------------------------
    _QML_STREAM_AI = str(os.environ.get("EAB_STREAM_AI", "1")).strip() not in ("0", "off", "false")

    def _qml_log_ptt_timing(self, started_mono):
        t = getattr(self, "_qml_ptt_timing", None)
        if not isinstance(t, dict) or t.get("logged"):
            return
        t["logged"] = True
        rel = float(getattr(self, "voice_latency_release_mono", 0.0) or 0.0)
        parts = []
        cap = getattr(self, "voice_latency_capture_finalize_ms", None)
        if cap is not None:
            parts.append(f"capture {cap / 1000.0:.2f}s")
        tr = getattr(self, "voice_latency_transcribe_ms", None)
        if tr is not None:
            parts.append(f"speech-to-text {tr / 1000.0:.2f}s")
        if t.get("fast"):
            parts.append("instant command (no AI)")
        else:
            a0 = float(t.get("ai_start", 0.0) or 0.0)
            a1 = float(t.get("ai_first_text", 0.0) or 0.0)
            calls = int(t.get("ai_calls", 0) or 0)
            if a0 and a1:
                parts.append(f"AI first words {a1 - a0:.2f}s ({calls} call{'s' if calls != 1 else ''}, effort {t.get('effort', '?')}, {'streamed' if t.get('streamed') else 'whole reply'})")
        if rel > 0:
            parts.append(f"first audio {float(started_mono) - rel:.2f}s after release")
        print("[VOICE] PTT timing // " + " // ".join(parts), flush=True)

    def _voice_input_result(self, text_value, status):
        if not text_value and getattr(self, "_qml_ai_credits_out", False) and "HTTP" in str(status):
            status = "PTT: AI credits are used up. Add credit to your OpenAI account."
            now = time.monotonic()
            if now - float(getattr(self, "_qml_ai_credit_said", 0.0) or 0.0) > 30.0:
                self._qml_ai_credit_said = now
                self._qml_say_command("AI credits are still used up.", "ai-credits")
        if text_value:
            self._qml_abandon_copilot("new PTT command")
            self._qml_ptt_timing = {"logged": False, "ai_calls": 0}
            self._qml_stream_spoken = ""
        return super()._voice_input_result(text_value, status)

    # ---- AI credits (2026-10) ------------------------------------------------
    # When the OpenAI account runs out of credit every AI call fails with HTTP 429
    # "insufficient_quota". .95 only logged the raw error, so the Bridge just went
    # quiet. Now: AI / VOICE shows NO CREDITS (lights MASTER CAUTION), the voice
    # says so once, a failed push to talk gets a short reminder (at most every 30 s),
    # and the first AI call that works again clears it. Deck keys and shortcut keys
    # never use the AI, so they keep working.
    _QML_CREDIT_MARKERS = ("insufficient_quota", "exceeded your current quota", "billing_hard_limit",
                           "billing_not_active", "check your plan and billing")
    _QML_CREDIT_LINE = ("AI credits are used up. Voice commands and the co-pilot are paused until you add "
                        "credit to your OpenAI account. The deck keys and shortcut keys still work.")

    def _qml_ai_credit_check(self, detail):
        low = str(detail or "").lower()
        if not any(m in low for m in self._QML_CREDIT_MARKERS):
            return False
        first = not bool(getattr(self, "_qml_ai_credits_out", False))
        self._qml_ai_credits_out = True
        if first:
            self._qml_ai_credit_said = time.monotonic()
            print("[AI] credits exhausted (insufficient_quota) // MASTER CAUTION lit", flush=True)
            self.after(0, lambda: self._qml_say_command(self._QML_CREDIT_LINE, "ai-credits"))
        return True

    def _qml_ai_credit_ok(self):
        if getattr(self, "_qml_ai_credits_out", False):
            self._qml_ai_credits_out = False
            print("[AI] credits back // AI request succeeded", flush=True)
            self.after(0, lambda: self._qml_say_command("AI credits are back. The co-pilot is online.", "ai-credits"))

    def _qml_http_detail(self, exc):
        """Read an HTTPError body once and hand back (detail, re-raisable copy)."""
        try:
            detail = exc.read().decode("utf-8", errors="replace")
        except Exception:
            detail = ""
        return detail, _QmlHttpError(getattr(exc, "url", ""), exc.code, getattr(exc, "msg", ""), getattr(exc, "hdrs", None),
                                     _io.BytesIO(detail.encode("utf-8")))

    def _transcribe_voice_file(self, path):
        try:
            text = self._qml_transcribe_inner(path)
        except _urlerror.HTTPError as exc:
            detail, copy = self._qml_http_detail(exc)
            self._qml_ai_credit_check(detail)
            raise copy
        self._qml_ai_credit_ok()
        return text

    def _openai_response_request(self, key, payload, timeout=60):
        try:
            data = self._qml_openai_inner(key, payload, timeout)
        except _urlerror.HTTPError as exc:
            detail, copy = self._qml_http_detail(exc)
            self._qml_ai_credit_check(detail)
            raise copy
        self._qml_ai_credit_ok()
        return data

    def fail_copilot_command(self, message):
        if self._qml_ai_credit_check(message):
            message = "AI credits are used up. Add credit to your OpenAI account; deck keys and shortcut keys still work."
        return super().fail_copilot_command(message)

    def fail_ai_analysis(self, message):
        if self._qml_ai_credit_check(message):
            message = "AI credits are used up."
        return super().fail_ai_analysis(message)

    def _qml_transcribe_inner(self, path):
        """Same request as the .95 engine, sent over the kept-alive connection."""
        key = os.environ.get("OPENAI_API_KEY")
        if not key:
            raise RuntimeError("OpenAI API key is not set.")
        audio_seconds = 0.0
        try:
            import wave
            with wave.open(str(path), "rb") as wf:
                rate = max(1, int(wf.getframerate() or 1))
                audio_seconds = float(wf.getnframes() or 0) / float(rate)
        except Exception:
            audio_seconds = 0.0
        self.voice_transcription_calls += 1
        self.voice_transcription_audio_seconds += max(0.0, audio_seconds)
        boundary = "----EliteBridgeVoiceBoundary7MA4YWxkTrZu0gW"
        wav = Path(path).read_bytes()
        parts = []

        def field(name, value):
            parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode("utf-8"))
        field("model", legacy.TRANSCRIBE_MODEL)
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"command.wav\"\r\nContent-Type: audio/wav\r\n\r\n".encode("utf-8")
            + wav + b"\r\n"
        )
        parts.append(f"--{boundary}--\r\n".encode("utf-8"))
        started = time.monotonic()
        try:
            _status, raw = _HTTPS.post(
                legacy.TRANSCRIBE_ENDPOINT, b"".join(parts),
                {"Authorization": f"Bearer {key}", "Content-Type": f"multipart/form-data; boundary={boundary}"},
                45,
            )
            data = json.loads(raw.decode("utf-8"))
        except Exception:
            self.voice_transcription_failures += 1
            raise
        finally:
            self.voice_transcription_last_seconds = max(0.0, time.monotonic() - started)
        return " ".join(str(data.get("text") or "").split()).strip()

    _QML_EFFORT_LADDER = ("none", "minimal", "low")

    # ---- PTT priority over an in-flight AI request ---------------------------
    # Every AI turn gets a generation number. The CopilotToolLoop thread learns
    # its number on its first API call. A PTT press while a turn is still running
    # abandons that turn: its generation goes stale, so its remaining API calls,
    # tool calls, streamed sentences and final reply are all dropped instead of
    # arriving late. (.95 used to refuse the new command: "Copilot is busy".)
    def _qml_copilot_thread_gen(self):
        """Generation of the AI turn running on this thread (None off the AI thread)."""
        if threading.current_thread().name != "CopilotToolLoop":
            return None
        tls = HeadlessBridgeApp._QML_PLOT_TLS
        gen = getattr(tls, "copilot_gen", None)
        if gen is None:
            gen = int(getattr(self, "_qml_copilot_gen", 0) or 0)
            tls.copilot_gen = gen
        return gen

    def _qml_copilot_stale(self):
        gen = self._qml_copilot_thread_gen()
        return gen is not None and gen != int(getattr(self, "_qml_copilot_gen", 0) or 0)

    def _qml_abandon_copilot(self, why):
        if not bool(getattr(self, "copilot_busy", False)):
            return False
        self._qml_copilot_gen = int(getattr(self, "_qml_copilot_gen", 0) or 0) + 1
        self.copilot_busy = False
        self.copilot_voice_reply_pending = False
        self.copilot_status = "Ready"
        self._qml_stream_spoken = ""
        try:
            stamp = time.strftime("%H:%M:%S")
            self.copilot_history.append(f"{stamp}  COPILOT: previous request dropped ({why}).")
        except Exception:
            pass
        print(f"[VOICE] PTT priority // in-flight AI request dropped ({why})", flush=True)
        return True

    def _qml_openai_inner(self, key, payload, timeout=60):
        """Copilot / API requests over the kept-alive connection.

        Voice turns (a PTT reply is pending and this is the Copilot loop) also get
        the lowest reasoning effort the model accepts (tried in order none ->
        minimal -> low, remembered) and a streamed reply: complete sentences go to
        the voice as they arrive, before the whole answer is written.
        """
        self._qml_copilot_thread_gen()
        if self._qml_copilot_stale():
            raise RuntimeError("AI request superseded by a newer PTT command")
        voice = bool(getattr(self, "copilot_voice_reply_pending", False)) and threading.current_thread().name == "CopilotToolLoop"
        payload = dict(payload)
        timing = getattr(self, "_qml_ptt_timing", None) if voice else None
        if voice:
            effort = getattr(self, "_qml_voice_effort", None) or self._QML_EFFORT_LADDER[0]
            payload["reasoning"] = dict(payload.get("reasoning") or {}, effort=effort)
            if isinstance(timing, dict):
                timing["effort"] = effort
                timing.setdefault("ai_start", float(getattr(self, "voice_latency_copilot_start_mono", 0.0) or time.monotonic()))
                timing["ai_calls"] = int(timing.get("ai_calls", 0)) + 1
        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        try:
            if voice and self._QML_STREAM_AI and not _HTTPS.disabled:
                return self._qml_stream_response(payload, headers, timeout, timing)
            _status, raw = _HTTPS.post(legacy.AI_ENDPOINT, json.dumps(payload).encode("utf-8"), headers, timeout)
            data = json.loads(raw.decode("utf-8"))
            if isinstance(timing, dict) and not timing.get("ai_first_text"):
                timing["ai_first_text"] = time.monotonic()
            return data
        except _urlerror.HTTPError as exc:
            if voice and exc.code == 400:
                try:
                    detail = exc.read().decode("utf-8", errors="replace")
                except Exception:
                    detail = ""
                low = detail.lower()
                effort = payload.get("reasoning", {}).get("effort")
                if ("reasoning" in low or "effort" in low) and effort in self._QML_EFFORT_LADDER[:-1]:
                    nxt = self._QML_EFFORT_LADDER[self._QML_EFFORT_LADDER.index(effort) + 1]
                    self._qml_voice_effort = nxt
                    print(f"[VOICE] AI model refused reasoning effort '{effort}', using '{nxt}' for voice turns", flush=True)
                    return self._qml_openai_inner(key, payload, timeout)
                raise _QmlHttpError(exc.url, exc.code, exc.msg, exc.hdrs, _io.BytesIO(detail.encode("utf-8")))
            raise

    def _qml_stream_response(self, payload, headers, timeout, timing):
        """Stream one Responses API call; speak finished sentences early when the
        reply has no tool call (so far). Returns the same dict as a normal call."""
        body = json.dumps(dict(payload, stream=True)).encode("utf-8")
        conn, host, resp = _HTTPS.open(legacy.AI_ENDPOINT, body, dict(headers, Accept="text/event-stream"), timeout)
        if resp.status >= 400:
            data = resp.read()
            _HTTPS.done(host, conn, resp, reusable=False)
            raise _QmlHttpError(legacy.AI_ENDPOINT, resp.status, resp.reason, resp.headers, _io.BytesIO(data))
        text = ""
        spoken_upto = 0
        saw_call = False
        final = None
        can_speak = self._voice_level_value() >= 1 and not self._wizard_runtime_paused()
        try:
            data_lines = []
            while True:
                line = resp.readline()
                if not line:
                    break
                line = line.decode("utf-8", errors="replace").rstrip("\r\n")
                if line.startswith("data:"):
                    data_lines.append(line[5:].lstrip())
                    continue
                if line != "" or not data_lines:
                    continue
                raw = "\n".join(data_lines)
                data_lines = []
                if raw == "[DONE]":
                    break
                try:
                    ev = json.loads(raw)
                except Exception:
                    continue
                kind = str(ev.get("type") or "")
                if kind == "response.output_item.added" and str((ev.get("item") or {}).get("type")) == "function_call":
                    saw_call = True
                elif kind == "response.output_text.delta":
                    text += str(ev.get("delta") or "")
                    if isinstance(timing, dict) and not timing.get("ai_first_text"):
                        timing["ai_first_text"] = time.monotonic()
                    if can_speak and not saw_call:
                        # speak every finished sentence (". ! ?" followed by a space)
                        m = None
                        for m in re.finditer(r"[.!?][\"')\]]*\s+", text[spoken_upto:]):
                            pass
                        if m is not None:
                            end = spoken_upto + m.end()
                            chunk = " ".join(text[spoken_upto:end].split())
                            if chunk:
                                self._qml_stream_say(chunk)
                                if isinstance(timing, dict):
                                    timing["streamed"] = True
                            spoken_upto = end
                elif kind in ("response.completed", "response.incomplete"):
                    final = ev.get("response") or {}
                    break
                elif kind in ("response.failed", "error"):
                    err = (ev.get("response") or {}).get("error") or ev.get("error") or ev
                    raise RuntimeError(f"AI stream failed: {err}")
        finally:
            _HTTPS.done(host, conn, resp, reusable=final is not None)
        if final is None:
            raise RuntimeError("AI stream ended without a completed response.")
        return final

    def _qml_stream_say(self, sentence):
        if self._qml_copilot_stale():
            return
        prev = str(getattr(self, "_qml_stream_spoken", "") or "")
        self._qml_stream_spoken = (prev + " " + sentence).strip()
        try:
            self.voice_engine.say(sentence)
        except Exception:
            pass

    # ---------- instant commands: common cockpit phrases skip the AI entirely
    _FAST_PREFIX = re.compile(r"^(?:(?:bridge|computer|ship|okay|ok|hey|please|can you|could you|go ahead and)\s+)+")
    _FAST_SUFFIX = re.compile(r"(?:\s+(?:please|now|right now|for me|thanks|thank you))+$")
    _FAST_PHRASES = {
        "dock": ("dock", "request docking", "dock the ship", "dock us", "start docking", "docking request",
                 "docking protocol", "request docking permission", "request to dock"),
        "cancel": ("cancel", "abort", "cancel that", "cancel automation", "stop automation", "stop all automation",
                   "abort abort", "cancel command", "stop the command"),
        "threat": ("target highest threat", "target the highest threat", "highest threat", "target threat",
                   "target the biggest threat"),
        "powerplant": ("target power plant", "target the power plant", "target their power plant", "power plant",
                       "target powerplant", "target the powerplant"),
        "best": ("find best target", "find the best target", "best target", "find me a target", "find a target",
                 "find me the best target"),
        "egress": ("escape area", "emergency escape", "emergency egress", "bug out", "escape escape"),
        "fighter1": ("deploy fighter", "launch fighter", "deploy fighter one", "deploy fighter 1",
                     "launch fighter one", "launch fighter 1", "deploy the fighter"),
        "fighter2": ("deploy fighter two", "deploy fighter 2", "launch fighter two", "launch fighter 2",
                     "deploy second fighter", "deploy the second fighter"),
        "recall": ("recall fighter", "recall fighters", "recall the fighter", "dock fighter", "fighter dock",
                   "bring the fighter home"),
        "firegroup": ("next fire group", "cycle fire group", "fire group", "switch fire group", "change fire group"),
        "refuel": ("refuel", "refuel the ship", "fill the tank", "refuel us"),
        "repair": ("repair", "repair the ship", "repair us", "fix the ship"),
        "rearm": ("rearm", "rearm the ship", "restock ammo", "rearm us"),
        "home": ("go home", "take me home", "plot route home", "plot a route home", "plot home", "route home",
                 "plot course home", "set course home"),
        "bm1": ("plot bookmark one", "plot bookmark 1", "go to bookmark one", "go to bookmark 1",
                "bookmark one", "bookmark 1"),
        "bm2": ("plot bookmark two", "plot bookmark 2", "go to bookmark two", "go to bookmark 2",
                "bookmark two", "bookmark 2"),
        "jettison_stolen": ("jettison stolen cargo", "jettison the stolen cargo", "dump stolen cargo",
                            "dump the stolen cargo", "drop stolen cargo", "drop the stolen cargo",
                            "jettison hot cargo", "dump hot cargo", "dump the hot cargo", "jettison stolen goods",
                            "dump stolen goods", "get rid of the stolen cargo", "get rid of stolen cargo"),
        "jettison_all": ("jettison all cargo", "jettison all the cargo", "jettison cargo", "jettison the cargo",
                         "dump all cargo", "dump all the cargo", "dump cargo", "dump the cargo",
                         "jettison everything", "dump everything"),
        "jettison_confirm": ("confirm jettison", "confirm", "confirmed", "yes jettison", "yes jettison it",
                             "jettison it", "dump it", "yes dump it", "do it", "yes do it", "yes"),
    }
    _FAST_CONFIRM = {
        "dock": "Requesting docking.", "cancel": "Cancelled. Controls are yours.",
        "threat": "Targeting the highest threat.", "powerplant": "Targeting the power plant.",
        "best": "Finding the best target.", "egress": "Escaping the area.",
        "fighter1": "Deploying fighter one.", "fighter2": "Deploying fighter two.", "recall": "Recalling fighter.",
        "firegroup": "Next fire group.", "refuel": "Refuelling.", "repair": "Repairing.", "rearm": "Rearming.",
    }

    def _qml_fast_intent(self, prompt):
        raw = " ".join(str(prompt or "").strip().lower().split())
        clean = " ".join(re.sub(r"[^a-z0-9 ]+", " ", raw).split())
        clean = self._FAST_PREFIX.sub("", clean)
        clean = self._FAST_SUFFIX.sub("", clean).strip()
        if not clean:
            return None
        for intent, phrases in self._FAST_PHRASES.items():
            if clean in phrases:
                return intent
        m = re.match(r"^(?:plot (?:a )?(?:route|course) to|set (?:a )?course (?:for|to)|take me to|route to|plot to|jump to) (.+)$", clean)
        if m:
            return ("plot", m.group(1).strip())
        return None

    def _qml_known_system(self, spoken_name):
        """Only plot locally when the heard name matches a system the Bridge already
        knows (route, home, bookmarks). Anything else goes to the AI, which can search."""
        want = re.sub(r"[^a-z0-9]+", "", str(spoken_name or "").lower())
        if not want:
            return None
        names = []
        try:
            values = _load_nav_memories()
            names += [values.get("home", ""), values.get("bookmark1", ""), values.get("bookmark2", "")]
        except Exception:
            pass
        try:
            names += [str(r.get("system") or "") for r in list(self._travel_upcoming_route_entries() or [])]
        except Exception:
            pass
        for n in names:
            if n and re.sub(r"[^a-z0-9]+", "", n.lower()) == want:
                return n
        return None

    def _qml_run_fast_intent(self, intent, prompt):
        """Run an instant command. Returns the spoken confirmation, or None to let the AI handle it."""
        s = self.state_data
        docked = bool(s.flag("Docked"))
        name = intent[0] if isinstance(intent, tuple) else intent
        if name == "jettison_confirm" and not self._qml_jettison_pending_live():
            return None  # a plain "yes" / "confirm" with nothing pending goes to the AI
        needs_binds = name not in ("cancel",)
        if needs_binds and not bool(self._qml_live_elite_bindings()):
            return "I can't do that yet. Elite key binds aren't loaded."
        if name == "dock":
            if docked:
                return "We're already docked."
            self.start_docking_protocol()
        elif name == "cancel":
            self.cancel_current_command("Voice command")
        elif name == "threat":
            self.start_target_highest_threat()
        elif name == "powerplant":
            self.start_target_power_plant()
        elif name == "best":
            self.start_find_best_target()
        elif name == "egress":
            if docked:
                return None
            try:
                self.key_sender.focus_elite()
                time.sleep(0.12)
            except Exception:
                pass
            self.start_emergency_egress()
        elif name in ("fighter1", "fighter2"):
            n = 1 if name == "fighter1" else 2
            if not _fighter_deploy_preflight(self, n):
                return "I can't deploy a fighter right now."
            self.start_deploy_fighter(n)
        elif name == "recall":
            if not _fighter_recall_preflight(self):
                return "There's no fighter to recall."
            self.start_recall_fighter()
        elif name == "firegroup":
            def cycle_fire_group():
                binding = self._native_binding("CycleFireGroupNext")
                self._native_tap(binding, pause=0.10)
                self.native_command_status = "Fire Group: cycled to next group."
            self._native_begin("Cycle Fire Group", cycle_fire_group)
        elif name in ("refuel", "repair", "rearm"):
            if not docked:
                return "We need to be docked for that."
            self._run_single_station_service_now(name)
        elif name in ("home", "bm1", "bm2"):
            slot = {"home": "home", "bm1": "bookmark1", "bm2": "bookmark2"}[name]
            target = _sanitize_nav_memory_value(_load_nav_memories().get(slot, ""))
            if not target:
                return f"{'Home' if slot == 'home' else 'That bookmark'} isn't set yet."
            self.nav_quick_route(target)
            return f"Plotting a route to {target}."
        elif name in ("jettison_stolen", "jettison_all"):
            return self._qml_jettison_request("stolen" if name == "jettison_stolen" else "all")
        elif name == "jettison_confirm":
            return self._qml_jettison_confirm()
        elif name == "plot":
            target = self._qml_known_system(intent[1])
            if not target:
                return None
            self.nav_quick_route(target)
            return f"Plotting a route to {target}."
        else:
            return None
        return self._FAST_CONFIRM.get(name, "Done.")

    # ---- Jettison cargo (voice / AI, always with a spoken confirm) -----------
    # Uses Elite's "Jettison All Cargo" key, which .95 keeps off the generic AI
    # key path on purpose. This command is the one exception and it never runs
    # without "confirm" within 20 seconds. Picking single stolen rows out of a
    # mixed hold needs the right-panel inventory and is not done yet: with legal
    # cargo aboard, the stolen request explains that and offers the full dump.
    _QML_JETTISON_CONFIRM_S = 20.0

    def _qml_cargo_summary(self):
        total = stolen = mission = 0
        stolen_names = []
        for item in list(getattr(self.state_data, "cargo", []) or []):
            if not isinstance(item, dict):
                continue
            try:
                count = max(0, int(item.get("Count", 0) or 0))
                hot = max(0, min(count, int(item.get("Stolen", 0) or 0)))
            except Exception:
                continue
            total += count
            stolen += hot
            if item.get("MissionID"):
                mission += count
            if hot:
                stolen_names.append(str(item.get("Name_Localised") or item.get("Name") or "cargo").strip().lower())
        return {"total": total, "stolen": stolen, "legal": total - stolen, "mission": mission, "stolen_names": stolen_names}

    @staticmethod
    def _qml_tons(n):
        return f"{n} ton" if n == 1 else f"{n} tons"

    def _qml_jettison_pending_live(self):
        pending = getattr(self, "_qml_jettison_pending", None)
        return isinstance(pending, dict) and time.monotonic() < float(pending.get("until", 0.0))

    def _qml_jettison_request(self, scope):
        """First step: describe what would go and ask for a confirm. Returns the spoken line."""
        self._qml_jettison_pending = None
        c = self._qml_cargo_summary()
        if c["total"] <= 0:
            return "The hold is empty."
        if scope == "stolen":
            if c["stolen"] <= 0:
                return "No stolen cargo aboard."
            if c["legal"] > 0:
                extra = ", including mission cargo" if c["mission"] else ""
                return (f"You have {self._qml_tons(c['stolen'])} stolen and {self._qml_tons(c['legal'])} legal{extra}. "
                        "I can't pick out just the stolen cargo yet. Say jettison all cargo to dump the whole hold.")
            names = c["stolen_names"]
            what = names[0] if len(names) == 1 else (", ".join(names[:-1]) + " and " + names[-1] if len(names) <= 3 else f"{len(names)} kinds")
            self._qml_jettison_pending = {"scope": "stolen", "total": c["total"], "until": time.monotonic() + self._QML_JETTISON_CONFIRM_S}
            return f"{self._qml_tons(c['stolen'])} of stolen cargo aboard: {what}. Say confirm to jettison it."
        extra = ""
        if c["mission"]:
            extra = " That includes mission cargo."
        elif c["stolen"] and c["legal"]:
            extra = f" {self._qml_tons(c['legal'])} of it is legal."
        self._qml_jettison_pending = {"scope": "all", "total": c["total"], "until": time.monotonic() + self._QML_JETTISON_CONFIRM_S}
        return f"That dumps all {self._qml_tons(c['total'])}.{extra} Say confirm to jettison it."

    def _qml_jettison_confirm(self):
        pending = getattr(self, "_qml_jettison_pending", None)
        self._qml_jettison_pending = None
        if not isinstance(pending, dict) or time.monotonic() >= float(pending.get("until", 0.0)):
            return "Nothing is waiting to be jettisoned."
        c = self._qml_cargo_summary()
        if c["total"] <= 0:
            return "The hold is already empty."
        if pending.get("scope") == "stolen" and c["legal"] > 0:
            return "Legal cargo is aboard now, so I stopped. Say jettison all cargo if you want the whole hold gone."
        if c["total"] > int(pending.get("total", 0)):
            return "The cargo changed since you asked. Ask me again."
        s = self.state_data
        if s.flag("Docked") or s.flag("Landed"):
            return "We can't jettison cargo while docked or landed."
        if s.flag("Supercruise") or s.flag("FSD Jump"):
            return "Drop to normal space first, then ask again."
        if not s.flag("In Main Ship"):
            return "That only works from the main ship."
        if not self.bindings.keyboard_binding("EjectAllCargo"):
            return self._no_key_message("EjectAllCargo", "Jettison All Cargo")
        self._native_begin("Jettison Cargo", self._qml_jettison_worker)
        return "Jettisoning cargo."

    def _qml_jettison_worker(self):
        s = self.state_data
        self._native_prepare_cockpit("Jettison Cargo")
        binding = self._native_binding("EjectAllCargo")
        before = self._qml_cargo_summary()["total"]
        self.native_command_status = f"Jettison Cargo: dumping {self._qml_tons(before)}..."
        self._native_tap(binding, 0.15)
        dropped = self._wait_for(lambda: self._qml_cargo_summary()["total"] < before, 3.0, 0.05)
        if not dropped:
            # Some control setups need the key held; one held press, then stop.
            self._native_command_log("Jettison Cargo | no cargo change after a tap; trying one 1 s hold")
            self._native_cancel_guard()
            self.key_sender.send_binding_hold(binding, 1.0)
            dropped = self._wait_for(lambda: self._qml_cargo_summary()["total"] < before, 3.0, 0.05)
        after = self._qml_cargo_summary()["total"]
        if dropped:
            self.native_command_status = f"Jettison Cargo: {self._qml_tons(before - after)} jettisoned."
            self._native_command_log(f"SUCCESS Jettison Cargo | {before} -> {after}")
            self._qml_say_command("Cargo jettisoned.", "jettison-done")
        else:
            self.native_command_status = "Jettison Cargo: key sent, but Elite still reports the cargo aboard."
            self._native_command_log(f"SENT Jettison Cargo | no cargo change | {before}")
            self._qml_say_command("I pressed jettison, but the cargo is still aboard.", "jettison-failed")

    def _copilot_jettison_cargo_tool(self, args):
        scope = str((args or {}).get("scope") or "stolen").strip().lower()
        scope = "all" if scope == "all" else "stolen"
        line = self._qml_jettison_request(scope)
        return {"ok": True, "awaiting_confirm": self._qml_jettison_pending_live(), "say_this": line,
                "note": "Nothing has been jettisoned. The commander must say 'confirm' within 20 seconds."}

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
        self._wizard_ptt_test_armed = int(getattr(self, "_wizard_pending_step", -1)) == self._WIZARD_PTT_STEP
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
        if not self._wizard_runtime_paused():
            self._qml_abandon_copilot("PTT pressed")
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
        # Open the HTTPS connections while the pilot is still talking.
        threading.Thread(target=lambda: (_HTTPS.warm(legacy.TRANSCRIBE_ENDPOINT)), daemon=True, name="EliteBridge-NetWarm").start()
        return super()._start_ptt_recording(source)

    def _stop_ptt_recording(self):
        if self._wizard_runtime_paused() and bool(getattr(self, "_wizard_ptt_test_recording", False)):
            try:
                self._wizard_ptt_test_stop.set()
            except Exception:
                pass
            return
        was_recording = bool(getattr(self, "voice_input_recording", False))
        result = super()._stop_ptt_recording()
        if was_recording:
            # Short chirp on release: the Bridge heard you and is working on it.
            try:
                self._ui_sfx_play("ui_confirm")
            except Exception:
                pass
        return result

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

    # Hull size as a stand-in for bounty value. Keys are the ship name with
    # everything but letters / digits removed; both the displayed names
    # (Ship_Localised) and Elite's internal names are listed.
    _HULL_SCORES = {
        "anaconda": 100,
        "python": 96, "pythonmkii": 96, "pythonmk2": 96, "pythonnx": 96,
        "federalcorvette": 95, "federationcorvette": 95,
        "imperialcutter": 94, "cutter": 94,
        "type10defender": 93, "type9military": 93,
        "ferdelance": 90,
        "federalassaultship": 88, "federationdropshipmkii": 88,
        "federalgunship": 87, "federationgunship": 87,
        "kraitmkii": 86, "kraitmk2": 86,
        "mamba": 85, "corsair": 84,
        "alliancechallenger": 83, "typex3": 83,
        "alliancechieftain": 82, "typex": 82,
        "alliancecrusader": 80, "typex2": 80,
        "imperialclipper": 79, "empiretrader": 79,
        "federaldropship": 78, "federationdropship": 78,
        "pantherclippermkii": 78, "panthermkii": 78,
        "type9heavy": 76, "type9": 76,
        "vulture": 74,
        "kraitphantom": 70, "kraitlight": 70,
        "aspexplorer": 62, "asp": 62,
        "type8transporter": 60, "type8": 60, "caspianexplorer": 60,
        "type7transporter": 58, "type7": 58,
        "imperialcourier": 56, "empirecourier": 56,
        "type11prospector": 55, "belugaliner": 55, "belugalinercruiser": 55,
        "cobramkv": 54, "cobramkiii": 52, "cobramkiv": 52,
        "mandalay": 50,
        "vipermkiv": 48, "kestrelmkii": 47, "vipermkiii": 46, "viper": 46,
        "diamondbackexplorer": 45, "diamondbackxl": 45, "keelback": 45, "independanttrader": 45,
        "aspscout": 40, "diamondbackscout": 40, "diamondback": 40, "orca": 40,
        "imperialeagle": 31, "empireeagle": 31, "eaglemkii": 30, "eagle": 30, "dolphin": 30,
        "type6transporter": 25, "type6": 25,
        "adder": 22, "sidewinder": 20, "sidewindermki": 20, "hauler": 18,
    }

    @classmethod
    def _qml_target_hull_score(cls, ship_name):
        key = re.sub(r"[^a-z0-9]+", "", str(ship_name or "").casefold())
        return int(cls._HULL_SCORES.get(key, 35 if key else 0))

    # Ships that are never bounty targets even before a full scan.
    _AUTHORITY_TOKENS = ("authority", "security", "police", "navy", "defence force", "defense force")

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
        faction = str(getattr(s, "target_faction", "-") or "-").strip()
        who = (pilot + " " + faction).casefold()
        authority = any(tok in who for tok in self._AUTHORITY_TOKENS)
        clean = legal_key == "clean" or authority
        wanted = legal_key == "wanted" and not authority
        hull_score = self._qml_target_hull_score(ship)
        # A confirmed bounty is worth a lot: a known WANTED Vulture (114) beats an
        # unscanned Anaconda (100), a known WANTED Cobra (92) does not.
        score = hull_score + (40 if wanted else 0)
        return {
            "step": int(step),
            "signature": self._qml_target_signature(),
            "key": key,
            "strong": bool(strong),
            "ship": ship,
            "pilot": pilot,
            "faction": faction,
            "authority": authority,
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

    @staticmethod
    def _qml_cycle_period(seq):
        """Smallest repeat length of the hull sequence seen while cycling targets.

        Elite cycles contacts in a repeating order, so once the hull pattern has
        repeated (plus one confirming step) every contact has been seen. A pattern
        made of one hull only proves nothing (three Pythons look like one), so it
        needs at least two different hulls."""
        n = len(seq)
        for p in range(2, n // 2 + 1):
            if n < 2 * p + 1:
                break
            if len(set(seq[:p])) < 2:
                continue
            if all(seq[i] == seq[i + p] for i in range(n - p)):
                return p
        return None

    def _qml_restore_target(self, original_sig, cycle, limit):
        """Cycle back to the ship the pilot had locked before the sweep."""
        s = self.state_data
        if not original_sig or original_sig[1] in ("", "-"):
            return False
        for _ in range(max(1, int(limit))):
            if self._qml_target_signature() == original_sig:
                return True
            before_rev = int(getattr(s, "target_revision", 0) or 0)
            self._native_tap(cycle, 0.07)
            self._wait_for(lambda: int(getattr(s, "target_revision", 0) or 0) > before_rev, 0.78, 0.035)
            time.sleep(0.06)
        return self._qml_target_signature() == original_sig

    def _find_best_target_worker(self):
        s = self.state_data
        if s.flag("Docked") or s.flag("Supercruise") or s.flag("FSD Jump") or not s.flag("In Main Ship"):
            raise RuntimeError("Best-target sweep is only available in normal-space main-ship flight.")
        self._native_prepare_cockpit("Find Best Target")
        cycle = self._native_binding("CycleNextTarget")
        original_sig = self._qml_target_signature()

        # Survey: cycle through contacts until the cycle is proven complete (a
        # strong identity seen again, or the hull pattern repeating), or 18 taps.
        max_contacts = 18
        observations = []
        seq = []
        anchor_key = None
        anchor_passes = 0
        period = None

        def remember(row):
            nonlocal anchor_key, anchor_passes
            if row is None:
                return
            observations.append(row)
            seq.append(re.sub(r"[^a-z0-9]+", "", str(row["ship"]).casefold()))
            if row["strong"]:
                if anchor_key is None:
                    anchor_key = row["key"]
                    anchor_passes = 1
                elif row["key"] == anchor_key:
                    anchor_passes += 1

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
            if anchor_key is not None and row["strong"] and row["key"] == anchor_key and anchor_passes >= 2 and step >= 3:
                completed_cycle = True
                # the gap between the two sightings of the same named ship is one full cycle
                hits = [i for i, r in enumerate(observations) if r["strong"] and r["key"] == anchor_key]
                if len(hits) >= 2 and hits[-1] - hits[-2] >= 1:
                    period = hits[-1] - hits[-2]
                break
            period = self._qml_cycle_period(seq)
            if period:
                completed_cycle = True
                break

        # One entry per contact. With a proven hull cycle the last `period`
        # observations are exactly the contacts in range; otherwise strong
        # identities are merged and same-hull unknowns are kept apart.
        strong_best = {}
        for row in observations:
            if row["strong"]:
                prior = strong_best.get(row["key"])
                if prior is None or row["scan_stage"] > prior["scan_stage"] or (row["wanted"] and not prior["wanted"]) or (row["clean"] and not prior["clean"]):
                    strong_best[row["key"]] = row
        if period:
            window = observations[-period:]
            contacts = []
            used = set()
            for row in window:
                if row["strong"]:
                    if row["key"] in used:
                        continue
                    used.add(row["key"])
                    contacts.append(strong_best.get(row["key"], row))
                else:
                    contacts.append(row)
        else:
            contacts = [r for r in observations if not r["strong"]] + list(strong_best.values())

        # Likely wings: several ships of the same hull, or several ships flying
        # for the same (non-police) faction. Elite doesn't report wings, so this is
        # an estimate. Each extra wingmate costs 18 points (max 45): a lone ship wins.
        hull_count = {}
        for r in contacts:
            hk = re.sub(r"[^a-z0-9]+", "", str(r["ship"]).casefold())
            hull_count[hk] = hull_count.get(hk, 0) + 1
        faction_count = {}
        for r in contacts:
            f = str(r.get("faction") or "-").strip().casefold()
            if f not in ("", "-") and not r.get("authority"):
                faction_count[f] = faction_count.get(f, 0) + 1
        for r in contacts:
            hk = re.sub(r"[^a-z0-9]+", "", str(r["ship"]).casefold())
            f = str(r.get("faction") or "-").strip().casefold()
            group = max(hull_count.get(hk, 1), faction_count.get(f, 1) if f not in ("", "-") else 1)
            r["group"] = group
            penalty = min(45, 18 * (group - 1))
            r["rank_score"] = -9999 if r["clean"] else int(r["score"]) - penalty

        valid = [r for r in contacts if not r["clean"] and int(r["rank_score"]) > 0]
        valid.sort(key=lambda r: (int(r["rank_score"]), bool(r["wanted"]), int(r["scan_stage"])), reverse=True)

        try:
            ranked = sorted(contacts, key=lambda r: (int(r["rank_score"]), bool(r["wanted"])), reverse=True)
            self._qml_sweep_contacts = [{
                "ship": str(r.get("ship") or "-"), "pilot": str(r.get("pilot") or "-"),
                "legal": ("AUTHORITY" if r.get("authority") else str(r.get("legal") or "UNKNOWN").upper()),
                "score": int(r.get("rank_score", 0)), "group": int(r.get("group", 1)),
                "eligible": (not r.get("clean")) and int(r.get("rank_score", 0)) > 0, "best": False,
            } for r in ranked[:12]]
            self._qml_sweep_time = time.strftime("%H:%M:%S")
        except Exception:
            pass
        survey_bits = [f"{self._qml_best_target_row_label(r)}{'x' + str(r['group']) if r.get('group', 1) > 1 else ''}" for r in sorted(contacts, key=lambda r: r["step"])[:18]]
        survey_text = "; ".join(survey_bits) if survey_bits else "no ship contacts"
        cycle_text = (f"hull-cycle {period}" if period else "loop-confirmed") if completed_cycle else "bounded-full-sweep"
        self._native_command_log(f"BEST TARGET SURVEY | {cycle_text} | taps={len(observations)} | {survey_text}")
        try:
            self._qml_best_target_history.append(f"{time.strftime('%H:%M:%S')}  SURVEY | {cycle_text} | {survey_text}")
        except Exception:
            pass

        if not valid:
            restored = self._qml_restore_target(original_sig, cycle, len(observations) + 4)
            self.native_command_status = "Find Best Target: no eligible ship in range." + (" Your target is back." if restored else "")
            self._qml_say_sweep_result("No eligible target in range." + (" Your target is back." if restored else ""))
            self._native_command_log(f"BEST TARGET | no eligible candidate | restored_original={restored}")
            return

        # Reacquire the winner. A candidate that turns out CLEAN (or police) on
        # the way is dropped and the next one is tried.
        current_best = valid[0]
        taps = 0
        max_reacquire_taps = max(len(observations), period or 0) + 6
        found = None
        while taps <= max_reacquire_taps and valid:
            row_now = self._qml_observe_target_candidate(-1, settle=0.06)
            if row_now is not None:
                if row_now["clean"]:
                    same = (current_best["strong"] and row_now["strong"] and row_now["key"] == current_best["key"]) or \
                           ((not current_best["strong"]) and row_now["ship"].casefold() == current_best["ship"].casefold() and current_best.get("group", 1) == 1)
                    if same:
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
            restored = self._qml_restore_target(original_sig, cycle, len(observations) + 4)
            self.native_command_status = (f"Find Best Target: surveyed {len(contacts)} contacts, but the best one couldn't be locked again."
                                          + (" Your target is back." if restored else ""))
            self._qml_say_sweep_result(f"Best target was {current_best['ship']}, but I lost the lock." + (" Your target is back." if restored else ""))
            self._native_command_log(
                f"BEST TARGET NOT REACQUIRED | candidates={len(valid)} contacts={len(contacts)} taps={taps} restored_original={restored}"
            )
            return

        legal_suffix = ""
        if str(found.get("legal") or "UNKNOWN").upper() not in {"UNKNOWN", "-"}:
            legal_suffix = f" • {str(found['legal']).upper()}"
        group_suffix = f" • likely in a group of {current_best.get('group')}" if int(current_best.get("group", 1)) > 1 else ""
        self.native_command_status = f"Best target found: {found['ship']}{legal_suffix}{group_suffix}."
        spoken_bits = [f"Best target: {found['ship']}"]
        if str(found.get("legal") or "UNKNOWN").upper() not in {"UNKNOWN", "-"}:
            spoken_bits.append(str(found["legal"]).lower())
        if int(current_best.get("group", 1)) > 1:
            spoken_bits.append(f"likely in a group of {int(current_best.get('group'))}")
        self._qml_say_sweep_result(", ".join(spoken_bits) + ".")
        try:
            for c in list(getattr(self, "_qml_sweep_contacts", []) or []):
                c["best"] = c["ship"].casefold() == str(found["ship"]).casefold() and (
                    str(found.get("pilot") or "-") in ("", "-") or c["pilot"].casefold() == str(found.get("pilot")).casefold())
                if c["best"]:
                    break
        except Exception:
            pass
        self._native_command_log(
            f"BEST TARGET | ship={found['ship']} legal={found.get('legal','UNKNOWN')} rank_score={current_best.get('rank_score')} group={current_best.get('group')} contacts={len(contacts)} reacquire_taps={taps}"
        )
        try:
            self._qml_best_target_history.append(
                f"{time.strftime('%H:%M:%S')}  SELECT | {found['ship']} | {found.get('legal','UNKNOWN')} | score={current_best.get('rank_score')} | group={current_best.get('group')} | taps={taps}"
            )
        except Exception:
            pass

    def _qml_say_sweep_result(self, text):
        """The one spoken line of a Find Best Target sweep (callouts are muted while it runs)."""
        try:
            self._voice_say("LOW", text, kind="COMBAT", key=f"best-target:{time.monotonic():.3f}", cooldown=0)
        except Exception:
            pass

    # ---- Command ownership: the newest pilot command wins -------------------
    # .95 ignored a command that arrived while another one was running ("BUSY").
    # Every caller of _native_begin is a pilot action (button, hotkey, voice, AI
    # tool); the only automatic caller, the clear-and-jump-after-launch handoff,
    # checks for a free cockpit itself. So: cancel what is running, wait for it
    # to let go (same 2.5 s bound Emergency Egress uses), then start the new one.
    # Emergency Egress is the exception: only CANCEL stops it.
    _QML_PREEMPT_WAIT = 2.5

    def _qml_say_command(self, text, key):
        try:
            self._voice_say("LOW", text, kind="COMMAND", key=key, cooldown=4.0)
        except Exception:
            pass

    def _qml_release_cockpit(self, new_name):
        """Stop the running command / station service so new_name can start.
        Returns True when the cockpit is free."""
        if self.native_command_busy:
            prior = str(self.native_command_name or "-")
            self._qml_last_cancel_mono = time.monotonic()
            self.native_command_cancel_reason = f"replaced by {new_name}"
            self.native_command_cancel_event.set()
            self.native_command_status = f"{new_name}: stopping {prior} first..."
            self._native_command_log(f"PREEMPT {prior} -> {new_name}")
            deadline = time.monotonic() + self._QML_PREEMPT_WAIT
            while self.native_command_busy and time.monotonic() < deadline:
                time.sleep(0.03)
            if self.native_command_busy:
                self.native_command_status = f"BUSY: {new_name} not started; {prior} has not let go of the controls yet."
                self._native_command_log(f"PREEMPT FAILED {prior} -> {new_name} | owner still active")
                return False
        if self.station_automation_busy:
            self._qml_last_cancel_mono = time.monotonic()
            self.station_automation_generation += 1
            self.station_automation_status = f"Stopping station maintenance for {new_name}..."
            self._station_automation_log(f"Cancelled for {new_name}")
            self._native_command_log(f"PREEMPT station maintenance -> {new_name}")
            if not self.station_automation_worker_done.wait(timeout=self._QML_PREEMPT_WAIT):
                self.native_command_status = f"BUSY: {new_name} not started; station maintenance has not let go of the controls yet."
                return False
            # Same release .95's Emergency Egress does: the worker has finished,
            # the result drain will still log its row later.
            self.station_automation_busy = False
            self.station_automation_current_service = "-"
        return True

    # ---- Route plotting ownership -------------------------------------------
    # .95 plots a route as a chain of Tk after() steps that runs outside the
    # command lock, so CANCEL could not stop it, it could press keys on top of
    # another command, and a second plot ran alongside the first. Each plot now
    # gets a generation: every after() step scheduled from inside the chain is
    # tagged with it, and a step whose generation is no longer live is dropped.
    # The .95 steps themselves are unchanged.
    _QML_PLOT_TLS = threading.local()

    # Only the route plotter's own steps may carry a plot generation. .95 calls
    # self.update() inside nav_portable_route_current, which runs other pending
    # callbacks (the main poll() loop among them) inside the plot's context; if
    # those were tagged, cancelling a plot would kill the poll loop and the
    # Bridge would stop reading Status.json (2026-10-07 bug: FSD charging and
    # Galaxy Map never confirmed). Match by function name instead.
    _QML_PLOT_STEP = re.compile(r"(_covas_|_portable_|_qml_open_galaxy_map|nav_portable_route_current)")

    @classmethod
    def _qml_is_plot_step(cls, func):
        name = getattr(func, "__qualname__", None) or getattr(getattr(func, "__func__", None), "__qualname__", "") or ""
        return bool(cls._QML_PLOT_STEP.search(str(name)))

    def after(self, ms, func=None, *args):
        if func is not None and threading.current_thread().name == "CopilotToolLoop" and self._qml_copilot_stale():
            return None  # finish/fail/UI hand-offs of an abandoned AI turn
        gen = getattr(HeadlessBridgeApp._QML_PLOT_TLS, "gen", 0)
        if gen and callable(func) and self._qml_is_plot_step(func):
            inner = func
            pending = self.__dict__.setdefault("_qml_plot_pending", {})
            pending[gen] = pending.get(gen, 0) + 1
            self.__dict__.setdefault("_qml_plot_chain_seen", set()).add(gen)

            def func(*a, _inner=inner, _gen=gen):
                left = pending.get(_gen, 1) - 1
                if left > 0:
                    pending[_gen] = left
                else:
                    pending.pop(_gen, None)
                if _gen != getattr(self, "_qml_plot_live", 0):
                    return None
                tls = HeadlessBridgeApp._QML_PLOT_TLS
                prev = getattr(tls, "gen", 0)
                tls.gen = _gen
                try:
                    return _inner(*a)
                finally:
                    tls.gen = prev
        return super().after(ms, func, *args)

    def _covas_navigation_distance_and_timing(self, current_system, target_system):
        # Runs on the plot's EDSM timing thread; tag that thread so its hand-off
        # back to Tk belongs to the plot that started it.
        gen = int(getattr(self, "_qml_plot_live", 0) or 0)
        HeadlessBridgeApp._QML_PLOT_TLS.gen = gen
        self.__dict__.setdefault("_qml_plot_lookup", set()).add(gen)
        return super()._covas_navigation_distance_and_timing(current_system, target_system)

    def _qml_plot_active(self):
        live = int(getattr(self, "_qml_plot_live", 0) or 0)
        if not live:
            return False
        if int(self.__dict__.get("_qml_plot_pending", {}).get(live, 0)) > 0:
            return True
        # still waiting on the EDSM distance lookup that starts the chain
        return live in self.__dict__.get("_qml_plot_lookup", set()) \
            and live not in self.__dict__.get("_qml_plot_chain_seen", set())

    def _qml_cancel_route_plot(self, reason):
        if not self._qml_plot_active():
            self._qml_plot_live = 0
            return False
        self._qml_plot_live = 0
        try:
            self.nav_log(f"Route plot cancelled ({reason}). The Galaxy Map may still be open.")
        except Exception:
            pass
        return True

    # ---- Galaxy Map must really be open before any map keys go out ----------
    # .95 pressed the map key in the same instant it focused Elite (the key could
    # be lost), then after 5 s without GuiFocus=6 it carried on and sent zoom /
    # UI / Enter / held select into the cockpit, where they can hit fire groups.
    # Now: let focus settle, press the map key, wait for GuiFocus 6, press it
    # once more if needed, otherwise stop with nothing else sent.
    _QML_MAP_SETTLE_MS = 300

    def _covas_begin_route(self, text, current_system, galaxy_already_open, distance_ly, zoom_wait_time, timing_error):
        if galaxy_already_open:
            return super()._covas_begin_route(text, current_system, galaxy_already_open, distance_ly, zoom_wait_time, timing_error)
        if not self._nav_ready():
            return
        if timing_error:
            self.nav_log(f"COVAS timing lookup note: {timing_error}. Using {zoom_wait_time}s fallback wait.")
        elif distance_ly > 0:
            self.nav_log(f"COVAS timing: {current_system} \u2192 {text} = {distance_ly:,.2f} LY; map-travel wait={zoom_wait_time}s.")
        else:
            self.nav_log(f"COVAS timing: distance unresolved; map-travel wait={zoom_wait_time}s.")
        try:
            title = self.key_sender.focus_elite()
            galaxy = self._nav_binding_required("GalaxyMapOpen")
        except Exception as exc:
            self.nav_log(f"COVAS path failed to start: {exc}")
            return
        self.nav_log(f"Route plot: Elite focused ({title}); opening the Galaxy Map.")
        self.after(self._QML_MAP_SETTLE_MS, lambda: self._qml_open_galaxy_map(text, galaxy, zoom_wait_time, 1))

    def _qml_gui_focus(self):
        try:
            return int((getattr(self.state_data, "status", {}) or {}).get("GuiFocus", -1))
        except Exception:
            return -1

    def _qml_open_galaxy_map(self, text, galaxy, zoom_wait_time, attempt):
        if not self._portable_still_ready("open Galaxy Map"):
            return
        gui = self._qml_gui_focus()
        if gui == 6:
            self.nav_log("Route plot: Galaxy Map already open.")
            self._covas_after_map_ready(text, galaxy, False, zoom_wait_time)
            return
        try:
            self.key_sender.send_binding(galaxy)
        except Exception as exc:
            self.nav_log(f"COVAS path failed opening the Galaxy Map: {exc}")
            return
        self.nav_log(f"Route plot: Galaxy Map key sent (try {attempt}); waiting for Elite to confirm it is open.")
        deadline = time.monotonic() + legacy.COVAS_GALAXY_OPEN_TIMEOUT_SECONDS
        self._qml_map_attempt = attempt
        self.after(100, lambda: self._covas_wait_for_map(text, galaxy, zoom_wait_time, deadline))

    def _covas_wait_for_map(self, text, galaxy, zoom_wait_time, deadline):
        if not self._portable_still_ready("wait for Galaxy Map"):
            return
        if self._qml_gui_focus() == 6:
            self.nav_log("COVAS path: Galaxy Map GuiFocus confirmed.")
            self._covas_after_map_ready(text, galaxy, False, zoom_wait_time)
            return
        if time.monotonic() < deadline:
            self.after(100, lambda: self._covas_wait_for_map(text, galaxy, zoom_wait_time, deadline))
            return
        attempt = int(getattr(self, "_qml_map_attempt", 1) or 1)
        if attempt < 2:
            self.nav_log("Route plot: the Galaxy Map did not open; focusing Elite and trying once more.")
            try:
                self.key_sender.focus_elite()
            except Exception:
                pass
            self.after(self._QML_MAP_SETTLE_MS, lambda: self._qml_open_galaxy_map(text, galaxy, zoom_wait_time, attempt + 1))
            return
        self.nav_log(f"ROUTE NOT PLOTTED: the Galaxy Map did not open (GuiFocus={self._qml_gui_focus()}). No other keys were sent.")
        self._qml_say_command("The galaxy map didn't open. Route not plotted.", "plot-map-failed")

    # navigation + cockpit command steps also go to logs\commands.log (diagnostics)
    def _qml_command_file_log(self, kind, text):
        try:
            root = Path(legacy.BRIDGE_DATA_DIR) / "logs"
            root.mkdir(parents=True, exist_ok=True)
            path = root / "commands.log"
            if path.exists() and path.stat().st_size > 1_000_000:
                prev = root / "commands.log.1"
                try:
                    prev.unlink()
                except Exception:
                    pass
                path.rename(prev)
            with open(path, "a", encoding="utf-8") as fh:
                fh.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')}  {kind}  {text}\n")
        except Exception:
            pass

    def nav_log(self, text):
        self._qml_command_file_log("NAV", text)
        return super().nav_log(text)

    def _native_command_log(self, text):
        self._qml_command_file_log("CMD", text)
        return super()._native_command_log(text)

    def nav_portable_route_current(self):
        if self.egress_phase != "IDLE":
            self.nav_log("Route not plotted: Emergency Egress has the cockpit controls. Say cancel first.")
            self._qml_say_command("Emergency escape has the controls. Say cancel first.", "egress-owns")
            return
        # Nothing to plot: .95 only writes a log line for these, so say it out loud too
        # (every input: buttons, voice, AI). No keys are sent either way.
        try:
            dest = str(self._destination_text() or "").strip()
            st = self.state_data
            if dest and self._same_system_name(getattr(st, "system", ""), dest):
                self._qml_say_command(f"You're already in {getattr(st, 'system', dest)}.", "route-already-here")
                return super().nav_portable_route_current()
            if dest and (self._same_system_name(getattr(st, "nav_target_system", ""), dest)
                         or self._same_system_name(getattr(st, "nav_route_destination", ""), dest)):
                self._qml_say_command(f"Route is already set to {getattr(st, 'nav_route_destination', '') or getattr(st, 'nav_target_system', '') or dest}.", "route-already-set")
                return super().nav_portable_route_current()
        except Exception:
            pass
        if self._qml_plot_active():
            self._qml_cancel_route_plot("replaced by a new route")
        if (self.native_command_busy or self.station_automation_busy) and not self._qml_release_cockpit("Plot Route"):
            self.nav_log(str(self.native_command_status))
            return
        gen = int(getattr(self, "_qml_plot_seq", 0) or 0) + 1
        self._qml_plot_seq = gen
        self._qml_plot_live = gen
        tls = HeadlessBridgeApp._QML_PLOT_TLS
        prev = getattr(tls, "gen", 0)
        tls.gen = gen
        try:
            return super().nav_portable_route_current()
        finally:
            tls.gen = prev

    # ---- Stale route file ----------------------------------------------------
    # When Elite didn't rewrite NavRoute.json (same-destination replot), .95's
    # route list is the old route. Everything that reads the upcoming route
    # (scoop look-ahead, fuel planning, the AI's route context, the screens) then
    # only gets what Elite actually told us: the next system. Jump counts come from
    # FSDTarget. Back to the full list as soon as Elite writes the file again.
    def _qml_raw_upcoming_route_entries(self):
        return super()._travel_upcoming_route_entries()

    def _qml_route_stale(self):
        return _route_file_is_stale(self.state_data, self._qml_raw_upcoming_route_entries())

    def _travel_upcoming_route_entries(self):
        raw = super()._travel_upcoming_route_entries()
        if not _route_file_is_stale(self.state_data, raw):
            return raw
        s = self.state_data
        cls = self._travel_normalize_star_class(getattr(s, "nav_target_star_class", "-"))
        return [{"system": str(getattr(s, "nav_target_system", "-") or "-"), "star_class": cls,
                 "scoopable": self._travel_star_is_scoopable(cls) if cls not in ("", "-") else False,
                 "star_pos": None}]

    def _travel_fuel_intelligence(self):
        result = super()._travel_fuel_intelligence()
        try:
            if isinstance(result, dict) and self._qml_route_stale():
                rem = getattr(self.state_data, "nav_target_remaining_jumps", None)
                if isinstance(rem, int):
                    result["remaining_route_jumps"] = rem
                result["route_reachable_without_scoop"] = None
                result["route_details"] = "Elite did not save the full route; only the next jump is known."
                msg = str(result.get("message") or "")
                msg = re.sub(r"\s*Current \d+-jump route is projected reachable without scooping\.", "", msg)
                result["message"] = (msg + " Elite did not save the full route, so only the next jump is checked.").strip()
        except Exception:
            pass
        return result

    # ---- Docking diagnostics -------------------------------------------------
    # Auto dock sometimes gets lost in the left panel (2026-10-07) and worked the
    # next time. While Docking Protocol runs, every key tap is logged with how long
    # it really took and Elite's GuiFocus before / after, and a probe measures how
    # late the Bridge reads Status.json (poll gap) and how late threads wake up
    # (stall). Logging only: nothing about the command's behaviour changes.
    _QML_DIAG_COMMANDS = {"Docking Protocol"}

    def poll_status(self):
        now = time.monotonic()
        last = self.__dict__.get("_qml_poll_mono")
        self._qml_poll_mono = now
        if last is not None and self.__dict__.get("_qml_diag_on"):
            self._qml_diag_poll_gap = max(float(self.__dict__.get("_qml_diag_poll_gap", 0.0)), now - last)
        return super().poll_status()

    def _native_tap(self, binding, pause=0.10):
        if not self.__dict__.get("_qml_diag_on"):
            return super()._native_tap(binding, pause)
        t0 = time.monotonic()
        g0 = self._qml_gui_focus()
        try:
            return super()._native_tap(binding, pause)
        finally:
            try:
                action = str((binding or {}).get("action") or "?")
                poll_age = time.monotonic() - float(self.__dict__.get("_qml_poll_mono", t0) or t0)
                self._native_command_log(f"DIAG {self.native_command_name} | tap {action} | {int((time.monotonic() - t0) * 1000)} ms (asked {int(float(pause or 0) * 1000)}) "
                                         f"| GuiFocus {g0} -> {self._qml_gui_focus()} | last status read {poll_age:.2f} s ago")
            except Exception:
                pass

    def _qml_diag_probe(self, name, generation):
        stall = 0.0
        try:
            while self.native_command_busy and int(self.native_command_generation) == generation:
                t = time.monotonic()
                time.sleep(0.02)
                stall = max(stall, time.monotonic() - t - 0.02)
        finally:
            gap = float(self.__dict__.get("_qml_diag_poll_gap", 0.0))
            self._qml_diag_on = False
            self._native_command_log(f"DIAG {name} | summary | slowest Status.json read gap {gap:.2f} s (normal 0.5) | worst thread wake-up delay {int(stall * 1000)} ms")

    def _native_begin(self, name, worker):
        name = str(name)
        if name in self._QML_DIAG_COMMANDS and self.egress_phase == "IDLE" and not (self.native_command_busy and str(self.native_command_name) == name):
            before = int(getattr(self, "native_command_generation", 0) or 0)
            result = self._qml_native_begin(name, worker)
            gen = int(getattr(self, "native_command_generation", 0) or 0)
            if gen > before and self.native_command_busy:
                self._qml_diag_poll_gap = 0.0
                self._qml_diag_on = True
                threading.Thread(target=self._qml_diag_probe, args=(name, gen), daemon=True, name="DockDiag").start()
            return result
        return self._qml_native_begin(name, worker)

    def _qml_native_begin(self, name, worker):
        name = str(name)
        if self.egress_phase == "IDLE":
            if self.native_command_busy and str(self.native_command_name) == name:
                self.native_command_status = f"BUSY: {name} is already running."
                return
            if self._qml_plot_active():
                self._qml_cancel_route_plot(f"replaced by {name}")
            if (self.native_command_busy or self.station_automation_busy) and not self._qml_release_cockpit(name):
                return
        else:
            self._qml_say_command("Emergency escape has the controls. Say cancel first.", "egress-owns")
        if name == "Auto Launch":
            self._qml_launch_started_mono = time.monotonic()
        return super()._native_begin(name, worker)

    def cancel_current_command(self, reason="Pilot cancel"):
        self._qml_last_cancel_mono = time.monotonic()
        self._qml_jettison_pending = None
        launch_running = bool(self.native_command_busy) and str(self.native_command_name) == "Auto Launch"
        handoff = bool(self.session_rules.get("clear_and_jump_after_auto_launch", False))
        result = super().cancel_current_command(reason)
        # Route plotting runs outside the command lock; CANCEL stops it too.
        plot_stopped = self._qml_cancel_route_plot(reason)
        if result and launch_running and handoff:
            self._native_command_log("SESSION RULE | Auto Launch cancelled -> Clear Station + FSD handoff dropped")
            self._qml_say_command("Clear and jump cancelled too.", "handoff-cancelled")
        return bool(result or plot_stopped)

    def _session_rule_clear_and_jump_after_launch(self, attempts=0):
        # A CANCEL (or a newer command) after this launch started drops the handoff.
        started = float(getattr(self, "_qml_launch_started_mono", 0.0) or 0.0)
        if float(getattr(self, "_qml_last_cancel_mono", 0.0) or 0.0) > started > 0.0:
            self._native_command_log("SESSION RULE SKIP | launch was cancelled or replaced")
            self._qml_say_command("Clear and jump cancelled too.", "handoff-cancelled")
            return
        return super()._session_rule_clear_and_jump_after_launch(attempts)

    def _copilot_execute_bridge_command_tool(self, args):
        # A command that replaced a running one is "accepted"; .95's check only
        # compared owner names and would report the replacement as refused.
        before_gen = int(getattr(self, "native_command_generation", 0) or 0)
        result = super()._copilot_execute_bridge_command_tool(args)
        try:
            cmd = str((args or {}).get("command") or "")
            if isinstance(result, dict) and not result.get("ok") and "error" not in result \
                    and cmd not in {"cancel_current_command", "emergency_egress", "cancel_egress"} \
                    and int(getattr(self, "native_command_generation", 0) or 0) > before_gen \
                    and bool(self.native_command_busy):
                result["ok"] = True
        except Exception:
            pass
        return result

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
                self._wizard_pending_step = max(0, min(self._WIZARD_LAST, int(initial_step)))
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
            step = max(0, min(self._WIZARD_LAST, int(step)))
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
            self._native_set_status(f"Guided setup resynced // page {step + 1}/{self._WIZARD_LAST + 1} // narration unchanged.")
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

    # Setup wizard v2 (2026-10, claude/wizard-redesign.md): one path for everyone,
    # AI is an add-on at the end. 0 NAME, 1 ELITE, 2 ELITE KEYS, 3 CONTROLS, 4 SOUND,
    # 5 BRIDGE SCREEN (2+ screens only), 6 ELITE SCREEN + OVERLAY (optional, off by default), 7 READY |
    # AI add-on: 8 COST, 9 LIMITS ON OPENAI'S SITE, 10 KEY, 11 PUSH TO TALK.
    _WIZARD_LAST = 11
    _WIZARD_PTT_STEP = 11

    def _wizard_elite_case(self):
        """RUNNING / FILES (journal found, game closed) / NONE, plus last-known names."""
        s = self.state_data
        def _known(v):
            v = _valid_text(v, "")
            return "" if v in ("-", "UNKNOWN", "Unknown") else v
        cmdr = _known(getattr(s, "commander", ""))
        ship = _known(getattr(s, "ship", ""))
        try:
            pretty = self._pretty_ship_name(ship) if ship else ""
            ship = "" if pretty in ("", "-") else pretty
        except Exception:
            ship = ship.replace("_", " ")
        system = _known(getattr(s, "system", ""))
        state = str(getattr(self, "_qml_elite_state", "") or "")
        if state == "CONNECTED":
            return "RUNNING", cmdr, ship, system
        if state == "MENU":
            return "MENU", cmdr, ship, system
        if cmdr:
            return "FILES", cmdr, ship, system
        return "NONE", cmdr, ship, system

    def _wizard_page_text(self, step):
        step = max(0, min(self._WIZARD_LAST, int(step)))
        name = self._commander_address()
        if step == 1:
            case, cmdr, ship, system = self._wizard_elite_case()
            # the system name is left out on purpose: the voice engine can't say catalogue names
            # like long catalogue names smoothly (2026-10-10). The screen still shows it.
            where = f" Flying the {ship}" if ship else ""
            if case == "RUNNING":
                return f"Found you, {cmdr}." + (f"{where}." if where else "") + " That's you, up top."
            if case == "MENU":
                return "Elite is up, at the main menu. Load into the game when you're ready and I'll pick up your ship by myself."
            if case == "FILES":
                last = f" Last time, {cmdr}" + (f", in the {ship}" if ship else "") + "."
                return "Found your Elite files." + last + " Elite isn't running. That's fine. Start it any time and I'll pick it up."
            return ("I can't find Elite yet. Start Elite and load into your ship once, then press Look Again. "
                    "You can skip this and set up sound and controls first.")
        if step == 2:
            try:
                rows, missing = self._setup_elite_binding_rows()
            except Exception:
                rows, missing = [], []
            if not rows and not missing:
                return "I can't read your Elite keys yet. Start Elite once, then press Look Again. You can do this later."
            if missing:
                n = len(missing)
                return (f"Elite is missing {n} key{'s' if n != 1 else ''} I need. "
                        "Set them in Elite, under Options, Controls. Everything else works without them. You can do this later.")
            return "Your Elite keys are all set."
        if step == 7 and str(os.environ.get("OPENAI_API_KEY") or "").strip():
            return (f"All set, {name}. Pick how you want to fly: Bridge Basic on the left, or the AI co pilot on the right, "
                    "which is already set up. Bridge Basic is free, and the AI adds talking to your ship.")
        pages = {
            0: "Welcome to Elite AI Bridge. What should I call you? Type a name, then press Next.",
            3: "The deck at the bottom is your controls. Click a key and the Bridge does it for you. Cancel always stops it.",
            4: "Can you hear me? This is my voice. You can change how I sound later in Setup. If you can't hear me, press Wrong Speakers.",
            5: ("You have more than one screen. Where should the Bridge go? Click a screen and I'll move there. "
                "Not sure which is which? Press Identify and each screen shows its number."),
            6: ("Now the in game overlay, and it's up to you. It's a small panel over the game with what the Bridge is doing "
                "and what the AI said. Clicks go straight through to the game, and it steps aside while the Bridge is in front. "
                "If you have more than one screen, pick the one Elite is on and the overlay shows up there, so you can see it. Then turn it on, or leave it off. "
                "You can change it any time in Setup, Display."),
            7: ("All set, {name}. Pick how you want to fly. On the left, Bridge Basic is free: the deck keys, automation, alerts, the overlay and every page. "
                "On the right, the AI co pilot adds everything on the left, plus talking to your ship: ask questions and give orders by voice. "
                "It uses your own OpenAI account, and each question costs fractions of a penny. You can add it later in Setup."),
            8: "The AI runs on OpenAI. Each question costs fractions of a penny, and you set the limits on their site, so it can't surprise you.",
            9: "On OpenAI's site, buy prepaid credit and turn auto recharge off. You can also set a monthly budget there. When the credit runs out, the AI stops, and the Bridge will tell you.",
            10: "Your key is like a password for your OpenAI account. Make a key on OpenAI and copy it. Then click the box, paste it in, and press Verify.",
            11: "Last one. Hold your talk button and say hello.",
        }
        return pages[step].format(name=name)

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
            step = max(0, min(self._WIZARD_LAST, int(step)))
        except Exception:
            step = 0
        if step == self._WIZARD_PTT_STEP:
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
        self._native_set_status(f"Guided setup page {step + 1}/{self._WIZARD_LAST + 1} // page-specific narration queued.")

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
            (0, "", ("flight deck", "overview", "live screen", "home screen")),
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
        elif any(word in raw for word in ("flight deck", "live", "home screen", "overview", "bridge modules")):
            page = 0

        if page is None:
            try:
                page = max(0, min(11, int(getattr(self, "_qml_ui_context_page", 0) or 0)))
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

        # Instant commands: common cockpit phrases run locally, no AI round trip.
        # The departure phrases below keep their own state-aware handling.
        fast = self._qml_fast_intent(prompt) if self._direct_departure_intent(prompt) is None else None
        if fast is not None:
            # A running command has to be stopped first (up to 2.5 s). Say the
            # confirmation now so the pilot hears it straight away.
            fname = fast[0] if isinstance(fast, tuple) else fast
            pre_spoken = None
            if fname in self._FAST_CONFIRM and fname != "cancel" and bool(getattr(self, "copilot_voice_reply_pending", False)) \
                    and (bool(getattr(self, "native_command_busy", False)) or bool(getattr(self, "station_automation_busy", False))):
                pre_spoken = self._FAST_CONFIRM[fname]
                try:
                    self.voice_engine.say(pre_spoken)
                except Exception:
                    pre_spoken = None
            try:
                text = self._qml_run_fast_intent(fast, prompt)
            except Exception as exc:
                text = f"That didn't work: {exc}"
            if text is not None and pre_spoken is not None and text == pre_spoken:
                self.copilot_voice_reply_pending = False   # already said it
            if text is not None:
                self.copilot_busy = True
                self.copilot_last_prompt = prompt
                self.copilot_input_var.set("")
                t = getattr(self, "_qml_ptt_timing", None)
                if isinstance(t, dict):
                    t["fast"] = True
                name = fast[0] if isinstance(fast, tuple) else fast
                self.refresh_copilot_widgets()
                self.finish_copilot_command({
                    "prompt": prompt, "text": text, "trace": [f"instant_command({name})"],
                    "api_calls": 0, "input_tokens": 0, "output_tokens": 0,
                })
                return

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
                    # A running command is replaced by _native_begin; only Emergency Egress blocks.
                    if self.egress_phase != "IDLE":
                        raise RuntimeError("cockpit controls are busy with Emergency Egress")
                    if not self.bindings.keyboard_binding("UseBoostJuice"):
                        raise RuntimeError(self._no_key_message("UseBoostJuice", "Boost"))
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
                "name": "jettison_cargo",
                "description": (
                    "Start a cargo jettison when the commander asks to dump/jettison stolen cargo (scope stolen) or the whole hold (scope all). "
                    "This never jettisons anything by itself: it returns a line asking the commander to say 'confirm'. Read that line back exactly."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {"scope": {"type": "string", "enum": ["stolen", "all"]}},
                    "required": ["scope"],
                    "additionalProperties": False
                },
                "strict": False
            },
            {
                "type": "function",
                "name": "search_res_sites",
                "description": (
                    "Search for nearby Resource Extraction Sites (Low, Standard, High or Hazardous), combat areas. Use this only when the commander asks to actually find/search for a RES site. "
                    "For how-to/help questions about RES Finder, use show_bridge_workspace instead. The Bridge automatically opens Combat > RES Finder while a real search runs."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "type": {"type": "string", "enum": ["LOW", "STANDARD", "HIGH", "HAZ"], "description": "RES danger level to search for. HIGH suits most pilots; LOW and STANDARD have fewer pirates; HAZ has no police."},
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
                        "page": {"type": "string", "enum": ["FLIGHT DECK", "OVERVIEW", "LIVE", "NAVIGATION", "COMBAT", "TRADE", "COLONIZATION", "COMMANDER", "AI", "AUDIO", "SETUP", "DISPLAY", "CONTROLS", "AUTOMATION", "STATUS", "SOUND"]},
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
        if self._qml_copilot_stale():
            return {"ok": False, "error": "This request was replaced by a newer PTT command; nothing was done."}
        return self._qml_execute_copilot_tool(name, args, action_mode)

    def _qml_execute_copilot_tool(self, name, args, action_mode):
        if name == "jettison_cargo":
            return self._copilot_jettison_cargo_tool(args)
        if name == "show_bridge_workspace":
            page_name = str((args or {}).get("page") or "OVERVIEW").strip().upper()
            page_map = {"FLIGHT DECK":0, "FLIGHT_DECK":0, "OVERVIEW":0, "LIVE":0, "NAVIGATION":1, "COMBAT":2, "TRADE":3, "COLONIZATION":4, "COMMANDER":5, "AI":6, "AUDIO":7, "SETUP":8, "DISPLAY":9, "CONTROLS":10, "AUTOMATION":11, "STATUS":8, "SOUND":7}
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
    # ASK FIRST was dropped (step 24): the AI does what you asked, CANCEL stops it.
    "ai_tool_mode": "Auto Navigation",
    "ai_smart_auto": False,
    # Optional pilot-authored context sent with each AI request. This is deliberately
    # context, not a replacement system prompt, so core Bridge behavior stays intact.
    "ai_context": "",
    "ai_context_seeded": False,
    "hotkey_overrides": {},
}


_HOTKEY_MOD_BITS = {"CTRL": 0x0002, "CONTROL": 0x0002, "ALT": 0x0001, "SHIFT": 0x0004, "WIN": 0x0008}
_HOTKEY_FREE_VKS = set(range(0x7C, 0x88))  # F13..F24: fine without a modifier (HOTAS software uses them)


def _hotkey_mods_from_display(display):
    bits = 0
    for part in str(display or "").split("+")[:-1]:
        bits |= _HOTKEY_MOD_BITS.get(part.strip().upper(), 0)
    return bits


class QmlGlobalHotkeys(legacy.BridgeGlobalHotkeys):
    """Same listener as the engine, with two fixes:
    1. Registers the modifiers the key actually shows. The engine always used
       Ctrl+Alt+Shift, so a key set to "F5" really fired on Ctrl+Alt+Shift+F5.
    2. stop() waits for the old listener to release its keys, so the next one can
       register them (before, new keys raced the old ones and came up blocked)."""

    def _run(self):
        import ctypes.wintypes
        user32 = ctypes.WinDLL("user32", use_last_error=True)
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.GetCurrentThreadId.restype = ctypes.wintypes.DWORD
        self.thread_id = int(kernel32.GetCurrentThreadId())
        id_to_command = {}
        base_id = 0x4B00
        for offset, (command_id, display, vk, _label) in enumerate(self.specs):
            hotkey_id = base_id + offset
            mods = _hotkey_mods_from_display(display)
            if not mods and int(vk) not in _HOTKEY_FREE_VKS:
                mods = legacy.BRIDGE_HOTKEY_MODIFIERS  # never grab a plain key from the game
            ctypes.set_last_error(0)
            ok = bool(user32.RegisterHotKey(None, hotkey_id, mods | self.MOD_NOREPEAT, int(vk)))
            if ok:
                self.registered[command_id] = display
                id_to_command[hotkey_id] = command_id
            else:
                self.failures[command_id] = {"display": display, "error": int(ctypes.get_last_error() or 0)}
        good = len(self.registered)
        self.status = f"{good}/{len(self.specs)} global Bridge hotkeys registered."
        if self.failures:
            self.status += " Some shortcuts are already in use by Windows or another app."
        self._ready.set()
        msg = ctypes.wintypes.MSG()
        try:
            while True:
                result = int(user32.GetMessageW(ctypes.byref(msg), None, 0, 0))
                if result <= 0:
                    break
                if int(msg.message) == self.WM_HOTKEY:
                    command_id = id_to_command.get(int(msg.wParam))
                    if command_id:
                        self.output_queue.put(command_id)
        finally:
            for hotkey_id in list(id_to_command):
                try:
                    user32.UnregisterHotKey(None, hotkey_id)
                except Exception:
                    pass

    def stop(self):
        super().stop()
        t = self.thread
        if t is not None and t.is_alive() and t is not threading.current_thread():
            t.join(1.0)


if os.name == "nt":
    legacy.BridgeGlobalHotkeys = QmlGlobalHotkeys


_ELITE_MOD_NAMES = {"Key_LeftControl": "CTRL", "Key_RightControl": "CTRL", "Key_LeftAlt": "ALT", "Key_RightAlt": "ALT",
                    "Key_LeftShift": "SHIFT", "Key_RightShift": "SHIFT", "Key_LeftWin": "WIN", "Key_RightWin": "WIN"}


def _chord_norm(mods, key):
    order = {"CTRL": 0, "ALT": 1, "SHIFT": 2, "WIN": 3}
    return "+".join(sorted({m for m in mods if m}, key=lambda m: order.get(m, 9)) + [str(key).upper().replace(" ", "")])


def _elite_key_name(key):
    k = str(key or "")
    if k.startswith("Key_"):
        k = k[4:]
    k = k.upper()
    if k.startswith("NUMPAD_") and k[7:].isdigit():
        return "NUM" + k[7:]
    return {"PAGEUP": "PAGEUP", "PAGEDOWN": "PAGEDOWN", "SPACEBAR": "SPACE", "RETURN": "ENTER", "UPARROW": "UP",
            "DOWNARROW": "DOWN", "LEFTARROW": "LEFT", "RIGHTARROW": "RIGHT"}.get(k, k)


def _elite_keyboard_chords(app):
    """{normalized chord: Elite action} for every keyboard bind in the active Elite profile. Read only."""
    out = {}
    try:
        root = getattr(app.bindings, "root", None)
        if root is None:
            return out
        for elem in root:
            for slot in ("Primary", "Secondary"):
                node = elem.find(slot)
                if node is None or node.attrib.get("Device") != "Keyboard" or not node.attrib.get("Key"):
                    continue
                mods = [_ELITE_MOD_NAMES.get(m.attrib.get("Key"), "") for m in node.findall("Modifier") if m.attrib.get("Device") == "Keyboard"]
                out.setdefault(_chord_norm(mods, _elite_key_name(node.attrib.get("Key"))), str(elem.tag))
    except Exception:
        pass
    return out


def _bridge_display_norm(display):
    parts = [p.strip() for p in str(display or "").split("+") if p.strip()]
    if not parts:
        return ""
    return _chord_norm([p.upper() for p in parts[:-1]], parts[-1])


def _elite_action_words(tag):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", str(tag or "")).replace("_", " ").strip()


def _qml_hotkey_display_safe(display, vk):
    """A saved key with no modifier (old builds allowed it) shows what is really registered."""
    if not _hotkey_mods_from_display(display) and int(vk or 0) not in _HOTKEY_FREE_VKS:
        key = str(display or "").split("+")[-1].strip() or str(display or "")
        return "Ctrl+Alt+Shift+" + key
    return str(display)


def _qml_apply_hotkey_specs(app, overrides=None):
    """Apply adapter-owned Bridge hotkey overrides without changing protected engine defaults."""
    overrides = overrides if isinstance(overrides, dict) else {}
    specs = []
    for command_id, default_display, default_vk, label in legacy.BRIDGE_HOTKEY_SPECS:
        item = overrides.get(command_id) if isinstance(overrides, dict) else None
        if isinstance(item, dict) and item.get("cleared"):
            continue  # the player removed this key
        display = str((item or {}).get("display") or default_display)
        vk = int((item or {}).get("vk") or default_vk)
        specs.append((command_id, _qml_hotkey_display_safe(display, vk), vk, label))
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
        cleared = bool(isinstance(override, dict) and override.get("cleared"))
        hotkey = "" if cleared else _qml_hotkey_display_safe(str((override or {}).get("display") or default_hotkey), int((override or {}).get("vk") or default_vk))
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
            "hotkeyState": "NOT SET" if cleared else ("READY" if command_id in registered else ("CONFLICT" if command_id in failures else "NOT REGISTERED")),
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
        mode = str(data.get("ai_tool_mode") or "Auto Navigation").strip()
        if mode not in ("Suggest Only", "Auto Navigation"):
            mode = "Auto Navigation"          # includes the retired "Ask Before Acting"
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
            self.app.ai_tool_mode_var.set(str(self.setup_overrides.get("ai_tool_mode", "Auto Navigation")))
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

    # ---- Colonization WHERE TO BUY (retro redesign) -------------------------
    # Buy-side market search for one commodity, nearest first, up to 30 rows with
    # data age, so the pilot sees all the options (market data can be stale).
    # Uses the same MarketSearchEngine the AI's search_market tool uses. The old
    # colonization_find_supply command (Trade route finder handoff) is unchanged.
    COLONY_SUPPLY_MAX_LY = 100

    def _run_colony_supply_search(self, commodity, need):
        app = self.app
        system = str(getattr(app.state_data, "system", "") or "").strip()
        self.colony_supply_commodity = commodity
        if not system or system == "-":
            self.colony_supply_status = "SUPPLY SEARCH NEEDS YOUR CURRENT SYSTEM // IS ELITE RUNNING?"
            return
        if getattr(self, "colony_supply_busy", False):
            return
        self.colony_supply_busy = True
        self.colony_supply_status = f"SEARCHING MARKETS FOR {commodity.upper()}..."

        def worker():
            rows_out = []
            try:
                local_market = None
                try:
                    local_market = app._local_market_snapshot_for_search(commodity)
                except Exception:
                    local_market = None
                rows = app.market_search_engine.search(
                    system, commodity, "BUY", 1, self.COLONY_SUPPLY_MAX_LY, 14, True,
                    local_market=local_market, origin_coords=getattr(app.state_data, "system_pos", None))
                rows = sorted(rows or [], key=lambda r: float(r.get("distance_ly") if r.get("distance_ly") is not None else 1e9))
                for r in rows[:30]:
                    age_s = legacy.market_age_seconds(r.get("updated_at"))
                    stock = "inf" if r.get("infinite_volume") else int(r.get("volume") or r.get("stock") or 0)
                    rows_out.append({
                        "station": str(r.get("station") or "-"),
                        "system": str(r.get("system") or "-"),
                        "ly": float(r.get("distance_ly") or 0.0),
                        "ls": int(round(float(r.get("arrival_ls") or 0))) if r.get("arrival_ls") is not None else -1,
                        "pad": legacy.BridgeApp._market_pad_label(r.get("pad")),
                        "stock": -1 if stock == "inf" else stock,
                        "price": int(r.get("price") or r.get("buy_price") or 0),
                        "age": legacy.market_age_text(r.get("updated_at")),
                        "ageHours": -1.0 if age_s is None else round(float(age_s) / 3600.0, 2),
                    })
                self.colony_supply_rows = rows_out
                self.colony_supply_status = (f"{len(rows_out)} STATIONS SELL {commodity.upper()} // NEAREST FIRST // YOU NEED {int(need):,} T"
                                             if rows_out else f"NO STATIONS FOUND SELLING {commodity.upper()} WITHIN {self.COLONY_SUPPLY_MAX_LY} LY")
            except Exception as exc:
                self.colony_supply_rows = []
                self.colony_supply_status = f"SUPPLY SEARCH FAILED // {str(exc)[:120].upper()}"
            finally:
                self.colony_supply_busy = False

        threading.Thread(target=worker, daemon=True, name="ColonySupplySearch").start()

    def _colony_my_sites(self, snap):
        scanner = getattr(self, "colony_site_scanner", None)
        if scanner is None:
            scanner = self.colony_site_scanner = _ColonySiteScanner(legacy.JOURNAL_DIR)
            self._colony_site_next = 0.0
        now = time.monotonic()
        if not scanner.busy and now >= getattr(self, "_colony_site_next", 0.0):
            self._colony_site_next = now + (10.0 if scanner.done else 1.0)
            threading.Thread(target=scanner.scan, daemon=True, name="ColonySiteScan").start()
        rows = scanner.rows() if scanner.done else []
        snap["colonizationMySites"] = rows
        if not scanner.done:
            snap["colonizationMySitesStatus"] = "READING YOUR JOURNALS..."
        else:
            systems = len({r["system"].lower() for r in rows})
            building = sum(1 for r in rows if r["status"] == "BUILDING")
            unsure = sum(1 for r in rows if r["status"] in ("NOT SEEN", "GONE"))
            snap["colonizationMySitesStatus"] = (f"{len(rows)} SITE{'S' if len(rows) != 1 else ''} IN {systems} SYSTEM{'S' if systems != 1 else ''} // {building} STILL BUILDING"
                                                 + (f" // {unsure} NOT SEEN OR GONE" if unsure else "") + f" // FROM {scanner.files_read} JOURNAL FILES"
                                                 if rows else f"NO CONSTRUCTION SITES FOUND IN {scanner.files_read} JOURNAL FILES // DOCK AT ONE TO ADD IT")

    # ---- Commander page ------------------------------------------------------
    # Game titles for every ladder. Combat-style ladders run 0..13 (the last five
    # are Elite I to V); the navies run 0..14.
    _RANK_LADDERS = [
        ("Combat", "COMBAT", ["Harmless", "Mostly Harmless", "Novice", "Competent", "Expert", "Master", "Dangerous", "Deadly"], True),
        ("Trade", "TRADE", ["Penniless", "Mostly Penniless", "Peddler", "Dealer", "Merchant", "Broker", "Entrepreneur", "Tycoon"], True),
        ("Explore", "EXPLORATION", ["Aimless", "Mostly Aimless", "Scout", "Surveyor", "Trailblazer", "Pathfinder", "Ranger", "Pioneer"], True),
        ("Soldier", "MERCENARY", ["Defenceless", "Mostly Defenceless", "Rookie", "Soldier", "Gunslinger", "Warrior", "Gladiator", "Deadeye"], True),
        ("Exobiologist", "EXOBIOLOGY", ["Directionless", "Mostly Directionless", "Compiler", "Collector", "Cataloguer", "Taxonomist", "Ecologist", "Geneticist"], True),
        ("CQC", "CQC ARENA", ["Helpless", "Mostly Helpless", "Amateur", "Semi Professional", "Professional", "Champion", "Hero", "Legend"], True),
        ("Federation", "FEDERAL NAVY", ["None", "Recruit", "Cadet", "Midshipman", "Petty Officer", "Chief Petty Officer", "Warrant Officer", "Ensign",
                                        "Lieutenant", "Lieutenant Commander", "Post Commander", "Post Captain", "Rear Admiral", "Vice Admiral", "Admiral"], False),
        ("Empire", "IMPERIAL NAVY", ["None", "Outsider", "Serf", "Master", "Squire", "Knight", "Lord", "Baron", "Viscount", "Count", "Earl",
                                     "Marquis", "Duke", "Prince", "King"], False),
    ]
    _NAVY_REP = {"Federation": "Federation", "Empire": "Empire"}

    @classmethod
    def _rank_names(cls, base, elite):
        return list(base) + (["Elite", "Elite I", "Elite II", "Elite III", "Elite IV", "Elite V"] if elite else [])

    def _commander_ranks(self, s):
        ranks = dict(getattr(s, "ranks", {}) or {})
        progress = dict(getattr(s, "rank_progress", {}) or {})
        rep = dict(getattr(s, "qml_reputation", {}) or {})
        out = []
        for key, label, base, elite in self._RANK_LADDERS:
            names = self._rank_names(base, elite)
            top = len(names) - 1
            known = key in ranks
            try:
                rank = max(0, min(top, int(ranks.get(key, 0) or 0)))
            except Exception:
                rank = 0
            try:
                pct = max(0, min(100, int(round(float(progress.get(key, 0) or 0)))))
            except Exception:
                pct = 0
            if not known:
                state = "unknown"
            elif rank >= top:
                state = "max"
            elif rank == 0 and pct == 0:
                state = "new"
            elif not elite and pct >= 100:
                state = "ready"          # navy ranks need a promotion mission
            else:
                state = "normal"
            row = {"key": key, "label": label, "rank": rank, "top": top, "pct": 100 if state == "max" else pct,
                   "name": names[rank].upper(), "next": names[rank + 1].upper() if rank < top else "",
                   "first": names[0].upper(), "last": names[-1].upper(), "elite": bool(elite), "eliteFrom": 8 if elite else -1,
                   "state": state, "rep": None}
            if key in self._NAVY_REP and rep.get(self._NAVY_REP[key]) is not None:
                try:
                    row["rep"] = round(float(rep[self._NAVY_REP[key]]), 1)
                except Exception:
                    pass
            out.append(row)
        return out

    def _commander_extras(self, snap):
        app = self.app
        s = app.state_data
        snap["commanderRanks"] = self._commander_ranks(s)
        snap["commanderRanksKnown"] = bool(getattr(s, "ranks", None))
        promo = getattr(s, "qml_promotion", None) or {}
        label = ""
        for key, lab, base, elite in self._RANK_LADDERS:
            if key == promo.get("key"):
                names = self._rank_names(base, elite)
                try:
                    label = f"{lab} // {names[max(0, min(len(names) - 1, int(promo.get('rank') or 0)))].upper()}"
                except Exception:
                    label = lab
        snap["commanderPromotionSerial"] = int(promo.get("serial", 0) or 0)
        snap["commanderPromotionKey"] = str(promo.get("key") or "")
        snap["commanderPromotionText"] = label

        # career: Elite's own totals from the Statistics event (written at login)
        st = getattr(s, "qml_statistics", None) or {}
        def g(section, field):
            try:
                v = (st.get(section) or {}).get(field)
                return None if v is None else float(v)
            except Exception:
                return None
        credits = getattr(s, "credits", None)
        snap["commanderStatsKnown"] = bool(st)
        snap["commanderCredits"] = float(credits) if credits is not None else -1.0
        snap["commanderNetWorth"] = g("Bank_Account", "Current_Wealth") if st else -1.0
        played = g("Exploration", "Time_Played")
        snap["commanderCareer"] = [
            {"label": "TRADE PROFIT", "value": g("Trading", "Market_Profits"), "unit": "CR"},
            {"label": "BOUNTY HUNTING", "value": g("Combat", "Bounty_Hunting_Profit"), "unit": "CR"},
            {"label": "EXPLORATION", "value": g("Exploration", "Exploration_Profits"), "unit": "CR"},
            {"label": "MINING", "value": g("Mining", "Mining_Profits"), "unit": "CR"},
            {"label": "SYSTEMS VISITED", "value": g("Exploration", "Systems_Visited"), "unit": ""},
            {"label": "JUMPS", "value": g("Exploration", "Total_Hyperspace_Jumps"), "unit": ""},
            {"label": "SHIPS OWNED", "value": g("Bank_Account", "Owned_Ship_Count"), "unit": ""},
            {"label": "TIME PLAYED", "value": (played / 3600.0) if played is not None else None, "unit": "H"},
        ] if st else []
        try:
            snap["commanderOddStats"] = _qml_odd_stats(s)
        except Exception:
            snap["commanderOddStats"] = []
        rep = dict(getattr(s, "qml_reputation", {}) or {})
        bits = [f"MISSIONS {len(getattr(s, 'missions', {}) or {})} ACTIVE",
                f"MODE {_valid_text(getattr(s, 'game_mode', '-')).upper()}"]
        power = _valid_text(getattr(s, "power", "-"))
        if power != "-":
            bits.append(f"POWER {power.upper()}")
        for k in ("Alliance", "Independent"):
            if rep.get(k) is not None:
                try:
                    bits.append(f"{k.upper()} REP {int(round(float(rep[k])))}")
                except Exception:
                    pass
        snap["commanderLine"] = " // ".join(bits)

        # ship
        snap["shipIdent"] = str(getattr(s, "qml_ship_ident", "") or "").upper()
        try:
            snap["shipRebuy"] = int(getattr(s, "qml_rebuy", 0) or 0)
        except Exception:
            snap["shipRebuy"] = 0
        # where the commander is: SHIP / SRV / FOOT (Status.json flags; Flags2 bit 0 = on foot)
        try:
            st = s.status or {}
            f2 = int(st.get("Flags2", 0) or 0)
            snap["pilotPlace"] = "FOOT" if (f2 & 1) else ("SRV" if s.flag("In SRV") else "SHIP")
        except Exception:
            snap["pilotPlace"] = "SHIP"
        # overlay activity: AI credits flag and how the last cockpit command ended
        snap["aiCreditsOut"] = bool(getattr(app, "_qml_ai_credits_out", False))
        snap["commandOutcome"] = "" if getattr(app, "native_command_busy", False) else str(getattr(app, "native_command_status", "") or "")
        snap["serviceOutcome"] = "" if getattr(app, "station_automation_busy", False) else str(getattr(app, "station_automation_status", "") or "")
        rows = list(getattr(s, "qml_loadout", None) or [])
        snap["shipLoadout"] = rows
        snap["shipLoadoutKey"] = _qml_loadout_key(rows) if rows else []
        # fuel scooping: rate from the main tank level over the last few seconds
        try:
            scooping = bool(s.flag("Scooping Fuel"))
            fuel = (s.status or {}).get("Fuel") or {}
            main = float(fuel.get("FuelMain")) if isinstance(fuel, dict) and fuel.get("FuelMain") is not None else None
            cap = float(getattr(s, "fuel_capacity_main", 0.0) or 0.0)
            hist = getattr(self, "_qml_scoop_hist", [])
            now = time.monotonic()
            if scooping and main is not None:
                hist = [h for h in hist if now - h[0] < 4.0] + [(now, main)]
            else:
                hist = []
            self._qml_scoop_hist = hist
            rate = 0.0
            if len(hist) >= 2 and hist[-1][0] - hist[0][0] >= 0.8:
                rate = max(0.0, (hist[-1][1] - hist[0][1]) / (hist[-1][0] - hist[0][0]))
            snap["shipScooping"] = scooping
            snap["scoopRate"] = round(rate, 3)
            snap["scoopFullSec"] = int(round((cap - main) / rate)) if (rate > 0.001 and cap > 0 and main is not None) else -1
        except Exception:
            snap["shipScooping"] = False
            snap["scoopRate"] = 0.0
            snap["scoopFullSec"] = -1
        try:
            snap["shipJumpRange"] = round(float(getattr(s, "max_jump_range", 0) or 0), 2)
        except Exception:
            snap["shipJumpRange"] = 0.0

        # full cargo hold
        rows = []
        for item in list(getattr(s, "cargo", []) or []):
            if not isinstance(item, dict):
                continue
            try:
                qty = max(0, int(item.get("Count", 0) or 0))
                stolen = max(0, int(item.get("Stolen", 0) or 0))
            except Exception:
                continue
            if qty <= 0:
                continue
            raw = str(item.get("Name") or "").lower()
            rows.append({"name": str(legacy.pretty_name(item.get("Name_Localised") or item.get("Name") or "Cargo")).upper(),
                         "qty": qty, "stolen": stolen, "drones": raw == "drones"})
        rows.sort(key=lambda r: (-r["qty"], r["name"]))
        snap["commanderCargoAll"] = rows

    def _colony_page_extras(self, snap):
        try:
            self._colony_my_sites(snap)
        except Exception:
            snap["colonizationMySites"] = []
        snap["colonizationSupplyRows"] = list(getattr(self, "colony_supply_rows", []) or [])
        snap["colonizationSupplyBusy"] = bool(getattr(self, "colony_supply_busy", False))
        snap["colonizationSupplyStatus"] = str(getattr(self, "colony_supply_status", "") or "")
        snap["colonizationSupplyCommodity"] = str(getattr(self, "colony_supply_commodity", "") or "")
        # cargo aboard that the current project doesn't need
        needed = set()
        for row in list(snap.get("colonizationRequirementRows") or []):
            if int(row.get("remaining", 0) or 0) > 0:
                needed.add(legacy.market_commodity_key(row.get("name") or ""))
        wrong = []
        for item in list(getattr(self.app.state_data, "cargo", []) or []):
            try:
                if int(item.get("Count", 0) or 0) <= 0 or item.get("Name", "").lower() == "drones":
                    continue
                key = legacy.market_commodity_key(item.get("Name_Localised") or item.get("Name") or "")
                if needed and key not in needed:
                    wrong.append(legacy.pretty_name(item.get("Name_Localised") or item.get("Name") or "cargo"))
            except Exception:
                continue
        snap["colonizationWrongCargo"] = ", ".join(wrong[:3]).upper()

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
                    allowed = {"dock", "launch", "clear", "cancel", "nav_plot", "nav_memory_plot", "nav_memory_set", "nav_memory_capture", "combat_mode", "combat_enter", "combat_leave", "combat_threat", "combat_powerplant", "combat_best_target", "combat_egress", "combat_toggle_pips", "combat_toggle_subsystem", "combat_res_low", "combat_res_std", "combat_res_high", "combat_res_haz", "combat_res_all", "combat_res_plot", "combat_res_plot_index", "combat_fighter_1", "combat_fighter_2", "combat_fighter_recall", "combat_wing_target_1", "combat_wing_target_2", "combat_wing_target_3", "combat_navlock_1", "combat_navlock_2", "combat_navlock_3", "combat_firegroup_next", "trade_buy", "trade_sell", "trade_start", "trade_pause", "trade_config", "trade_route_search", "trade_route_use_index", "trade_best_search", "trade_best_use_index", "trade_learn_recent", "trade_trip_reset", "colonization_project_use_index", "colonization_find_supply", "colonization_supply_search", "save_data", "journal", "diagnostic", "cmdr_refresh", "mic_test", "hearing_test", "mic_hearing_check", "voice_test", "wizard_ptt_test", "ptt_map", "voice_toggle_input_mode", "voice_cycle_level", "voice_cycle_attention", "voice_set_attention", "ai_cycle_tool_mode", "ai_toggle_smart_auto", "ai_toggle_launch_rule", "ai_approve", "ai_reject", "clear_rules", "ai_usage_reset", "audio_rescan", "setup_preflight", "setup_binds", "setup_api_key_set", "setup_api_key_verify", "setup_setting", "station_refuel", "station_repair", "station_rearm", "control_bind", "control_bind_row", "control_clear", "control_clear_row", "control_cancel", "control_copy_hotkey", "control_set_hotkey", "control_clear_hotkey", "control_restore_hotkeys", "control_keyboard_capture_begin", "control_keyboard_capture_end", "control_conflict_ack", "ui_cue", "wizard_open", "wizard_close", "wizard_music_start", "wizard_music_stop", "wizard_runtime_gate", "wizard_narrate", "wizard_narrate_page_1", "wizard_narrate_page_2", "wizard_narrate_page_3", "wizard_narrate_page_4", "wizard_narrate_page_5", "wizard_narrate_page_6", "wizard_narrate_page_7", "page_help_start", "page_help_stop", "orientation_intro", "orientation_stopped", "orientation_complete", "ui_context", "sfx_select", "sfx_set_enabled", "sfx_import_path", "sfx_test", "sfx_reset", "audio_set_level", "audio_set_device", "voice_set_tuning"}
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
                        # "master" = all sound effects on / off (Setup > Sound), same setting as .95's checkbox
                        if key not in legacy.SFX_SPECS and not (command == "sfx_set_enabled" and key == "master"):
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
                            value = str(value or "Auto Navigation").strip()
                            if value == "Ask Before Acting":
                                value = "Auto Navigation"
                            if value not in ("Suggest Only", "Auto Navigation"):
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
                        if page < 0 or page > 12:
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
                        page = max(0, min(11, page))
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
                    if command in ("combat_res_low", "combat_res_std", "combat_res_high", "combat_res_haz", "combat_res_all"):
                        for key in ("radius_ly", "max_ls"):
                            if key in data:
                                item[key] = str(data.get(key) or "").strip()[:20]
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
                    if command == "colonization_supply_search":
                        commodity = str(data.get("commodity") or "").strip()[:180]
                        if not commodity:
                            self._json(400, {"ok": False, "error": "commodity required"})
                            return
                        item["commodity"] = commodity
                        item["quantity"] = str(data.get("quantity") or "0").strip()[:20]
                    if command == "colonization_find_supply":
                        commodity = str(data.get("commodity") or "").strip()[:180]
                        if not commodity:
                            self._json(400, {"ok": False, "error": "commodity required"})
                            return
                        item["commodity"] = commodity
                        for key in ("quantity", "max_ly", "max_ls", "min_runs"):
                            if key in data:
                                item[key] = str(data.get(key) or "").strip()[:80]
                    if command in {"control_set_hotkey", "control_clear_hotkey", "control_keyboard_capture_begin", "control_bind", "control_clear", "control_copy_hotkey"}:
                        action = str(data.get("action") or "").strip()
                        if action not in {row[0] for row in legacy.BRIDGE_HOTKEY_SPECS}:
                            self._json(400, {"ok": False, "error": f"valid Bridge command required: {action!r}"})
                            return
                        item["action"] = action
                        if command == "control_set_hotkey":
                            item["display"] = str(data.get("display") or "").strip()[:60]
                            try:
                                item["vk"] = int(data.get("vk") or 0)
                            except Exception:
                                item["vk"] = 0
                    if command in ("wizard_open", "wizard_narrate"):
                        # The screen number was never copied into the queued item, so every
                        # wizard_open / wizard_narrate arrived as page 1 (why v1 used one
                        # command name per page). Setup wizard v2 sends it in the payload.
                        try:
                            item["step"] = max(0, min(10, int(data.get("step", 0) or 0)))
                        except Exception:
                            item["step"] = 0
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
            self._trade_page_extras(snap)
            try:
                self._colony_page_extras(snap)
            except Exception:
                pass
            try:
                self._commander_extras(snap)
            except Exception:
                pass
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
        return len(self._trade_loop_sells())

    def _trade_loop_sells(self) -> list:
        """Ledger SELL rows that match the configured loop (commodity + sell station), oldest first."""
        if self.app is None:
            return []
        try:
            cfg = self.app._trade_loop_config()
            wanted = str(cfg.get("commodity_key") or "")
            sell_system = str(cfg.get("sell_system") or "").strip().casefold()
            sell_station = str(cfg.get("sell_station") or "").strip().casefold()
            rows = list(getattr(self.app.state_data.trade_ledger, "rows", []) or [])
            count = []
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
                count.append(row)
            return count
        except Exception:
            return []

    # ---- Trade trip odometer: always counting, reset when you like ---------
    _TRADE_TRIP_FILE = "qml_trade_trip.json"

    def _trade_trip_start(self) -> str:
        if not hasattr(self, "_trade_trip_started"):
            started = ""
            try:
                data = json.loads((Path(legacy.BRIDGE_DATA_DIR) / self._TRADE_TRIP_FILE).read_text(encoding="utf-8"))
                started = str(data.get("started") or "")
            except Exception:
                started = ""
            self._trade_trip_started = started
        return self._trade_trip_started

    def _trade_trip_reset(self):
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        self._trade_trip_started = stamp
        try:
            root = Path(legacy.BRIDGE_DATA_DIR)
            root.mkdir(parents=True, exist_ok=True)
            (root / self._TRADE_TRIP_FILE).write_text(json.dumps({"started": stamp}), encoding="utf-8")
        except Exception:
            pass
        try:
            self.app._native_set_status("Trade trip reset. Counting from now.")
        except Exception:
            pass

    def _trade_trip_extras(self, snap):
        start = self._trade_trip_start()
        rows = list(getattr(self.app.state_data.trade_ledger, "rows", []) or [])
        trip = [r for r in rows if not start or str(r.get("timestamp") or "") >= start]
        sells = [r for r in trip if str(r.get("type") or "").upper() == "SELL"]
        snap["tradeTripProfit"] = int(sum(int(r.get("profit") or 0) for r in sells if r.get("profit") is not None))
        snap["tradeTripSales"] = len(sells)
        try:
            snap["tradeTripTons"] = int(sum(int(r.get("qty") or 0) for r in sells))
        except Exception:
            snap["tradeTripTons"] = 0
        loop_sells = self._trade_loop_sells()
        snap["tradeTripCycles"] = len([r for r in loop_sells if not start or str(r.get("timestamp") or "") >= start])
        label = "SINCE THIS SESSION'S FIRST TRADE"
        if start:
            try:
                import calendar
                t = time.localtime(calendar.timegm(time.strptime(start, "%Y-%m-%dT%H:%M:%SZ")))
                label = "SINCE " + time.strftime("%b %d ", t).upper() + time.strftime("%I:%M %p", t).lstrip("0")
            except Exception:
                label = "SINCE LAST RESET"
        snap["tradeTripSince"] = label

    def _trade_page_extras(self, snap):
        """Trade page (retro redesign) extras: run earnings, last sale, cargo aboard, leg length."""
        try:
            self._trade_trip_extras(snap)
        except Exception:
            snap.setdefault("tradeTripProfit", 0)
        try:
            sells = self._trade_loop_sells()
            run_rows = sells[max(0, int(self.trade_run_baseline_sells)):]
            snap["tradeRunProfit"] = int(sum(int(r.get("profit") or 0) for r in run_rows if r.get("profit") is not None))
            last = None
            for row in reversed(list(getattr(self.app.state_data.trade_ledger, "rows", []) or [])):
                if str(row.get("type") or "").upper() == "SELL":
                    last = row
                    break
            if last is not None and last.get("profit") is not None:
                snap["tradeLastSale"] = f"{int(last.get('profit') or 0):+,} CR // {last.get('time') or '-'}"
            else:
                snap["tradeLastSale"] = "-"
        except Exception:
            snap["tradeRunProfit"] = 0
            snap["tradeLastSale"] = "-"
        try:
            snap["tradeAboard"] = int(self.app._trade_loop_configured_commodity_aboard() or 0)
        except Exception:
            snap["tradeAboard"] = 0
        stolen = 0
        for item in list(getattr(self.app.state_data, "cargo", []) or []):
            try:
                stolen += max(0, int((item or {}).get("Stolen", 0) or 0))
            except Exception:
                pass
        snap["tradeStolenAboard"] = stolen
        snap["tradeLegLy"] = float(getattr(self, "trade_active_leg_ly", 0.0) or 0.0)
        snap["tradeActiveRestricted"] = bool(getattr(self, "trade_active_restricted", False))

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
                        for name in ("commands.log", "commands.log.1"):
                            cmd_log = Path(getattr(legacy, "BRIDGE_DATA_DIR")) / "logs" / name
                            if cmd_log.exists():
                                zf.write(cmd_log, arcname=f"logs/{name}")
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
                elif command == "mic_hearing_check":
                    def _run_mic_hearing_when_idle(attempt=0):
                        try:
                            self.app._stop_ptt_recording()
                        except Exception:
                            pass
                        if bool(getattr(self.app, "voice_input_recording", False)) and attempt < 25:
                            self.app.after(80, lambda: _run_mic_hearing_when_idle(attempt + 1))
                            return
                        self.app._qml_mic_check_start()
                    self.app.after(0, _run_mic_hearing_when_idle)
                    self.app._native_set_status("Mic check started // listening 5 seconds // push to talk not needed // nothing is run.")
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
                elif command == "sfx_set_enabled" and str(item.get("key") or "") == "master":
                    enabled = bool(item.get("enabled", True))
                    self.app.sfx_enabled_var.set(enabled)
                    self.app._sfx_apply_settings(save=True)
                    self.app._native_set_status(f"Sound effects // {'ON' if enabled else 'OFF'}")
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
                            nonlocal detail
                            if ok:
                                try:
                                    if requested_command == "setup_api_key_set":
                                        _set_windows_user_api_key(candidate)
                                    # First working key on this install (2026-10-08): turn on
                                    # "AI speaks up on its own" for trade + missions (their defaults are
                                    # already on); travel + docking stays off (too chatty). Existing
                                    # users' choices are never touched.
                                    first_key = (not str(self.setup_overrides.get("api_verified_fingerprint") or "")
                                                 and not float(self.setup_overrides.get("api_verified_at") or 0.0))
                                    if first_key:
                                        try:
                                            self.app.ai_auto_var.set(True)
                                            self.setup_overrides["ai_smart_auto"] = True
                                            detail = (str(detail or "").rstrip() + " The AI will also comment on your trades and missions on"
                                                      " its own; change that in Setup > Automation.")
                                        except Exception:
                                            pass
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
                                mode = str(value or "Auto Navigation").strip()
                                if mode not in ("Suggest Only", "Auto Navigation"):
                                    mode = "Auto Navigation"
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
                    def _kb_begin(action=action):
                        try:
                            old = getattr(self.app, "bridge_hotkeys", None)
                            if old:
                                old.stop()  # waits until Windows has let go of the keys
                            self.app._qml_kb_capture_armed = action
                            self.app._qml_kb_capture_error = ""
                            print(f"[CONTROL MAP] keyboard capture armed action={action} // global shortcuts suspended", flush=True)
                        except Exception as exc:
                            self.app._qml_kb_capture_armed = ""
                            self.app._qml_kb_capture_error = f"COULDN'T START // {exc}"
                            print(f"[CONTROL MAP] keyboard capture suspend failed: {exc}", flush=True)
                    self.app.after(0, _kb_begin)
                elif command == "control_keyboard_capture_end":
                    def _kb_end():
                        self.app._qml_kb_capture_armed = ""
                        try:
                            # always put the shortcuts back, whatever state the listener is in
                            _qml_apply_hotkey_specs(self.app, dict(self.setup_overrides.get("hotkey_overrides") or {}))
                            print("[CONTROL MAP] keyboard capture ended // global shortcuts restored", flush=True)
                        except Exception as exc:
                            print(f"[CONTROL MAP] keyboard capture restore failed: {exc}", flush=True)
                    self.app.after(0, _kb_end)
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
                        self.app._qml_kb_capture_armed = ""
                        overrides = dict(self.setup_overrides.get("hotkey_overrides") or {})
                        try:
                            if action not in valid or vk <= 0 or not display:
                                raise ValueError("Invalid Bridge hotkey")
                            if not _hotkey_mods_from_display(display) and vk not in _HOTKEY_FREE_VKS:
                                raise ValueError("ADD CTRL OR ALT // A PLAIN KEY WOULD STOP WORKING IN ELITE")
                            want = _bridge_display_norm(display)
                            # another Bridge command already on this key?
                            for cid, ddisp, dvk, dlabel in legacy.BRIDGE_HOTKEY_SPECS:
                                if cid == action:
                                    continue
                                ov = overrides.get(cid) if isinstance(overrides.get(cid), dict) else {}
                                if ov.get("cleared"):
                                    continue
                                other = _qml_hotkey_display_safe(str(ov.get("display") or ddisp), int(ov.get("vk") or dvk))
                                if _bridge_display_norm(other) == want:
                                    raise ValueError(f"{display.upper()} IS ALREADY USED BY {str(dlabel).upper()}")
                            # Elite already uses it? A Bridge shortcut would take the key away from the game.
                            elite = _elite_keyboard_chords(self.app).get(want)
                            if elite:
                                raise ValueError(f"ELITE ALREADY USES {display.upper()} FOR {_elite_action_words(elite).upper()}")
                            overrides[action] = {"display": display, "vk": vk}
                            self.setup_overrides["hotkey_overrides"] = overrides
                            self._save_setup_overrides()
                            self.app._qml_kb_capture_error = ""
                            self.app._qml_kb_capture_done = {"action": action, "ok": True, "text": display.upper(), "at": time.time()}
                            self.app._native_set_status(f"Bridge shortcut updated // {self.app._controller_action_label(action)} // {display}")
                        except Exception as exc:
                            self.app._qml_kb_capture_error = str(exc).upper()
                            self.app._qml_kb_capture_done = {"action": action, "ok": False, "text": str(exc).upper(), "at": time.time()}
                            self.app._native_set_status(f"Bridge shortcut not changed // {exc}")
                        finally:
                            try:
                                _qml_apply_hotkey_specs(self.app, overrides if overrides else dict(self.setup_overrides.get("hotkey_overrides") or {}))
                            except Exception as exc:
                                print(f"[CONTROL MAP] shortcut re-register failed: {exc}", flush=True)
                    self.app.after(0, _set_hotkey)
                elif command == "control_clear_hotkey":
                    action = str(item.get("action") or "").strip()
                    def _clear_hotkey():
                        self.app._qml_kb_capture_armed = ""
                        try:
                            overrides = dict(self.setup_overrides.get("hotkey_overrides") or {})
                            overrides[action] = {"cleared": True}
                            self.setup_overrides["hotkey_overrides"] = overrides
                            self._save_setup_overrides()
                            self.app._qml_kb_capture_done = {"action": action, "ok": True, "text": "CLEARED", "at": time.time()}
                            self.app._native_set_status(f"Bridge shortcut cleared // {self.app._controller_action_label(action)}")
                        except Exception as exc:
                            self.app._native_set_status(f"Bridge shortcut clear failed // {exc}")
                        finally:
                            _qml_apply_hotkey_specs(self.app, dict(self.setup_overrides.get("hotkey_overrides") or {}))
                    self.app.after(0, _clear_hotkey)
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
                        values = ["Suggest Only", "Auto Navigation"]
                        current = str(self.app.ai_tool_mode_var.get() or "Auto Navigation").strip()
                        try: idx = values.index(current)
                        except ValueError: idx = 1
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
                elif command == "colonization_supply_search":
                    commodity = str(item.get("commodity") or "").strip()
                    try:
                        need = max(0, int(float(item.get("quantity") or 0)))
                    except Exception:
                        need = 0
                    if commodity:
                        self._run_colony_supply_search(commodity, need)
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
                    try: max_leg = max(5, min(500, int(float(item.get("max_leg_ly") or max_ly))))
                    except Exception: max_leg = max_ly
                    self.app.loop_search_radius_var.set(str(max_ly))
                    self.app.loop_search_max_leg_var.set(str(max_leg))
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
                        self.trade_active_leg_ly = float(pair.get("leg_ly") or 0)
                        self.trade_active_restricted = bool(pair.get("known_prohibited", False))
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
                        self.trade_active_leg_ly = float(pair.get("leg_ly") or 0)
                        self.trade_active_restricted = False
                        try: self.app.refresh_trade_loop_widgets()
                        except Exception: pass
                elif command == "trade_trip_reset":
                    self._trade_trip_reset()
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
                elif command in {"combat_res_low", "combat_res_std", "combat_res_high", "combat_res_haz", "combat_res_all"}:
                    want_haz = command == "combat_res_haz"
                    self.app.res_search_high_var.set(not want_haz)
                    self.app.res_search_haz_var.set(want_haz)
                    try:
                        self.app.intra_res_client.want = {
                            "combat_res_low": ["Low"], "combat_res_std": ["Standard"], "combat_res_high": ["High"],
                            "combat_res_haz": ["Hazardous"], "combat_res_all": ["Low", "Standard", "High", "Hazardous"],
                        }[command]
                    except Exception:
                        pass
                    # Combat page search row (step 25): SEARCH WITHIN 25-200 LY, SITE WITHIN 2.5K / 5K / 10K / ANY LS.
                    # Defaults 50 LY / 10,000 LS (the old fixed values). ANY = the engine's 500,000 LS ceiling.
                    try:
                        radius = max(1.0, min(250.0, float(item.get("radius_ly") or 50)))
                    except Exception:
                        radius = 50.0
                    try:
                        max_ls = max(100.0, min(500000.0, float(item.get("max_ls") or 10000)))
                    except Exception:
                        max_ls = 10000.0
                    self.app.res_search_radius_var.set(f"{radius:g}")
                    self.app.res_search_max_ls_var.set(f"{max_ls:g}")
                    self.app.find_nearby_res()
                elif command in {"combat_res_plot", "combat_res_plot_index"}:
                    rows = list(getattr(self.app, "res_search_results", []) or [])
                    eligible = []
                    for source_index, candidate in enumerate(rows):
                        try:
                            candidate_ls = float(candidate.get("res_ls", -1))
                        except Exception:
                            candidate_ls = -1
                        if 0 <= candidate_ls <= _qml_res_ls_limit(self.app):
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
