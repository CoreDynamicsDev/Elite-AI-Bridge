Elite AI Bridge v0.12.95 - Hero Recovery

V0.12.95 HERO RECOVERY
- Rebased Hero mode on the stable v0.12.93 implementation after the v0.12.94 visual regression.
- Removed the filler phrases from the Hero shell and stripped the random scratch/dash texture from active instrument faces.
- Quick Action button labels are now live Canvas text instead of baked shell artwork, preventing stray/overlapping characters.
- Moved the Bridge IDLE/message block upward so it no longer crowds the ship schematic.
- Added a dedicated Mandalay top-view wireframe schematic plus cleaner Mandalay display naming.
- Retained Hero animations, resolution-aware presets, standard responsive GUI fallback, and all proven cockpit automation unchanged.

V0.12.95 HERO CONSOLE REFINEMENT
- Hero AUTO now selects among 1366x768, 1600x900, 1920x1080, 2560x1440, 3840x2160, and 5120x2880.
- WINDOWED respects the usable desktop; BORDERLESS/FULLSCREEN may use the monitor's full native resolution.
- Hero size can be manually overridden under Preferences > Display / Window Mode.
- Hero animations are optional and include a subtle LIVE lamp pulse, ship-bay diagnostic sweep, and hover outline.
- Long Hero text is now constrained per instrument with ellipsis so station names, AI messages, routes, events, and status text cannot run into neighboring panels.
- The Clear Station quick-action face now uses the shorter CLEAR + FSD label to avoid clipping.


- Added an optional fixed-layout HERO LIVE console intended as a one-shot test of the much more cinematic industrial-machine look.
- HERO LIVE uses a rendered 1600x900 machine-face shell with a matched 1366x768 compact shell for smaller displays.
- Live Commander/ship/system/station state, ship health, Bridge command state, route, alerts, events, PTT/Luna state and AI usage remain dynamic over the rendered shell.
- HERO LIVE quick controls call the same proven Docking Protocol, Auto Launch, Clear Station + FSD and Cancel Current functions as the normal GUI.
- Hardware controls use clickable Canvas hit regions with hover cursors and pressed-state flashes; ESC returns to the standard GUI.
- Left-side Hero module controls return to the standard interface and open the selected module, so legacy/development pages remain available.
- The Hero ship bay remains a generic green schematic placeholder for now and is ready for the per-ship wireframe asset pack next.
- The existing responsive Industrial Console remains intact as the fallback UI; no flight automation logic was rewritten.

Elite AI Bridge v0.12.91 - Industrial Console Pass

- Industrial console shell: stronger metal bezel, vents, fasteners, wear-toned framing, and physical switch assemblies.
- Live dashboard rebalanced: smaller ship schematic viewport and more room for operational status / events.
- Left module rail now uses physical control-bank styling with lamps and secondary labels.
- Quick actions and utility controls use reusable hardware-style switch assemblies.
- Ship schematic viewport is prepared for future per-ship green wireframe assets; no fake ship art is bundled yet.
- Existing docking, launch, FSD, Dynamic PIPs, station service, AI, HOTAS, and voice logic is unchanged.

Elite AI Bridge v0.12.91 - GUI Cleanup & Display Modes

V0.12.91 CHANGE
- Removed canned trade/navigation quick-command buttons from AI Brain. Trade/navigation workflows now stay in their dedicated modules; AI Brain focuses on AI command, permissions, cost/usage, response history, and reasoning state.
- Removed Docking Protocol, Auto Launch, and Clear Station + FSD duplicates from Combat. The underlying commands remain available to Live, HOTAS/Stream Deck, and Luna.
- Added vertical scrolling to the legacy Combat page so the full toolset remains reachable before its later retro redesign.
- Added persistent Display / Window Mode settings: WINDOWED, BORDERLESS, and FULLSCREEN.
- BORDERLESS fills the usable desktop area without normal OS window chrome; FULLSCREEN uses application fullscreen.
- Added F11 toggle between Fullscreen and Windowed plus Reset Window Size.
- Windowed geometry and selected display mode persist in the normal Bridge preference file.
- No flight automation, Dynamic PIP, docking, station-service, AI execution, or voice-control behavior was rewritten.

PREVIOUS BUILD NOTES


V0.12.89 CHANGE
- Replaced the native 19-tab main strip with a retro left-side module rail.
- Grouped legacy pages under LIVE, NAVIGATION, COMBAT, TRADE, COLONIZATION, COMMANDER, AI & VOICE, AUDIO, and SETUP.
- Added contextual submodule controls for Trade, Commander, and Setup pages.
- Rebuilt the application header and command-owner strip as part of the dark retro shell.
- Added responsive typography: the finished shell and Live dashboard scale with window size/maximization.
- Made interactive controls visibly raised/physical with distinct active, warning, and cancel states.
- Removed the duplicate Live title, duplicate mini ship schematic, and Support/Data card.
- Moved diagnostic/file utilities behind the always-visible TOOLS control.
- Live keeps the dynamic green schematic bay ready for per-ship wireframe artwork later.
- No docking, Auto Launch, Clear Station + FSD, Dynamic PIP, station-service, AI command, or voice automation logic was rewritten.

V0.12.88 CHANGE
- First production-style Live dashboard pass based on the selected retro-industrial direction.
- New dark olive/black command-deck layout with phosphor green, amber warnings, red critical states, recessed panels and technical typography.
- Live identity strip: commander, current ship, system, station and flight state.
- Live ship-status panel: hull, shields, fuel, PIPs, cargo, FSD, landing gear and hardpoints.
- Central Bridge state now surfaces IDLE, LISTENING, AI THINKING, AI SPEAKING, command ownership, station service and Emergency Egress.
- Ship schematic area is wired to the current ship name and intentionally uses a generic technical placeholder until per-ship green wireframe art is added.
- Added Live system-health indicators for telemetry, Luna, PTT, audio, controllers, bindings, Dynamic PIPs, station services and session rules.
- Added Live recent-events, alert, destination, Voice/AI, session AI usage/cost and quick-action panels.
- Proven automation logic is unchanged; this build is a presentation-layer redesign of Live.

V0.12.87 CHANGE
---------------
LIVE SUPPORT / DATA EXPORT CLEANUP
----------------------------------
- Moved Live-tab diagnostic controls above the expanding Decision History area so they remain visible on smaller windows and common Windows display scaling.
- Added SAVE DATA FILE to write the complete Bridge diagnostic snapshot directly to a timestamped .txt file for troubleshooting/sharing.
- COPY DIAGNOSTIC remains available for clipboard workflows.
- OPEN JOURNAL FOLDER remains beside the diagnostic controls and now reports a visible error if Windows cannot open the folder.

CUSTOM SOUND LIBRARY ACCESS
---------------------------
- Sound Effects now includes OPEN CUSTOM SOUND LIBRARY, which opens the managed %LOCALAPPDATA%\EliteAIBridge\Sounds\Custom folder containing imported replacement WAV files.
- Imported sounds still remain independent of the original FModel/extraction location and survive Bridge ZIP upgrades.

NO FLIGHT-AUTOMATION CHANGES
----------------------------
- This build deliberately leaves the proven docking, departure, PIP, station-service and AI command-execution logic unchanged.

V0.12.86 CHANGE
---------------
COCKPIT PREFLIGHT GUI
----------------------
- Replaced the text-heavy startup overview with a dark cockpit-style systems panel.
- Preflight health is presented as concise status cards with green READY states, red required failures, amber waiting states, and blue/gray informational or intentionally-disabled states.
- The primary panel covers Elite telemetry, required PTT, microphone, audio output, AI/Luna, controllers, Elite bindings, Bridge controls, Dynamic PIPs, station services, and temporary AI session rules.
- Raw setup/binding diagnostics are hidden behind DETAILS instead of dominating the startup experience.
- ENTER BRIDGE, SETUP and DETAILS are the primary controls; SKIP INTRO remains available for development/testing.
- Healthy preflight remains visible for ten seconds after startup audio completes; warnings do not auto-dismiss. Opening DETAILS cancels the auto-close countdown.
- Startup voice remains gated until the complete intro sound finishes.


V0.12.85 CHANGE
---------------
PTT LATENCY TELEMETRY
---------------------
- Mic / PTT now shows the last end-to-end voice timing sample after a spoken Copilot request.
- Timing is broken into capture finalization after PTT release, transcription, Luna/tool processing, TTS startup, and total PTT-release-to-first-spoken-audio time.
- The voice worker reports actual playback start, so TTS timing includes local Supertonic synthesis/queue delay instead of stopping at "speech queued."
- Diagnostics also record transcription request count, captured audio seconds, failures, and the last transcription API duration.

STARTUP OVERVIEW READABILITY
----------------------------
- A healthy startup overview now remains visible for about six seconds after the intro audio finishes instead of closing after roughly two seconds.
- CONTINUE still dismisses it immediately; incomplete required setup still keeps the overview open.

AI USAGE / COST
---------------
- Interactive Copilot now has a dedicated AI Usage / Cost panel for the current Bridge session.
- It shows API calls, input/output tokens, the current configured LLM cost estimate, and average tokens per call.
- Voice transcription calls and total audio seconds are shown separately so microphone/API usage is not hidden inside the Luna estimate.
- Cost text is explicitly labeled as an estimate based on Bridge's configured token rates, not an OpenAI billing statement.
- No AI context was removed in this build; the goal is to measure real usage before optimizing a workflow that is currently behaving well.

V0.12.84 CHANGE
---------------
MIC LEVEL POLISH
----------------
- Live microphone level is now displayed on a speech-friendly logarithmic/dB-style scale instead of raw PCM percentage.
- Normal headset speech that previously looked like 1-2% can now display in the useful middle of the meter with GOOD / LOW / STRONG / CLIPPING guidance.
- Microphone audio itself is not boosted or altered; this is a display/readability change only.
- TEST MIC LEVEL and TEST AI HEARING now report a dBFS-style peak and a plain-language signal-health label.

FIRST-RUN SETUP / PREFLIGHT
---------------------------
- Added a dedicated Setup / Preflight tab. Normal day-to-day startup still lands on Live.
- Push-to-Talk is a required setup check and exposes the existing Command Map / HOTAS binding workflow.
- Preflight checks the active Elite keyboard preset without editing it and lists missing required interface, throttle, boost, landing-gear, FSD and Dynamic-PIP controls.
- Preflight also reports microphone/audio support, OpenAI API-key readiness, Bridge global-hotkey registration, connected controllers and live Elite telemetry.
- Setup provides direct controls to rescan Elite bindings/audio and test microphone, transcription and voice output.

STARTUP OVERVIEW
----------------
- Startup overview now links directly to Setup / Preflight and Command Map / PTT.
- Voice remains gated until the complete startup SFX ends.
- When required setup is healthy, the completed preflight remains visible briefly after the intro so the pilot can actually read it, then closes automatically.
- When required setup is incomplete, the overview stays open and points to Setup / Preflight instead of silently disappearing.

DEFAULT AUDIO TUNING
--------------------
- Fresh-install defaults follow the current development tuning: voice 50%, speech speed 1.07x and SFX 50%. Existing saved preferences still win on upgrades.

V0.12.83 CHANGE
---------------
VOICE & AUDIO WORKBENCH
-----------------------
- Voice/audio controls moved out of the long Preferences page into a dedicated top-level Voice & Audio tab.
- Voice & Audio contains separate Mic / PTT, Voice, and Sound Effects tabs so the SFX editor is always directly reachable without scrolling.
- Voice and cockpit SFX now share one selected Bridge Audio Output device. Older two-output preferences migrate automatically.
- Mic / PTT adds a live level meter during PTT, Always Listen, and manual tests.
- TEST MIC LEVEL records locally for five seconds only to measure signal; no audio is uploaded.
- TEST AI HEARING records five seconds and sends only that test clip to transcription, then displays exactly what was recognized. It never executes the phrase as a Bridge command.
- TEST VOICE OUTPUT exercises the current TTS path independently, making input, transcription, and output failures easy to isolate.
- Voice pipeline status now shows required PTT mapping, microphone state, last transcript, and current Copilot state.
- Startup/preflight now shows the selected shared audio output.

V0.12.82 CHANGE
---------------
STARTUP AUDIO / PREFLIGHT
-------------------------
- Startup voice is gated until the actual startup WAV duration has completed instead of using a fixed delay.
- Custom long startup WAV files are supported; a failsafe prevents a broken playback state from muting voice indefinitely.
- Optional startup overview shows PTT readiness, voice/listen mode, Dynamic PIPs, station-service toggles and startup-audio state while Bridge telemetry initializes behind it.
- SKIP INTRO stops the startup SFX and releases queued voice immediately.
- Push-to-Talk is shown as a REQUIRED setup control; the overview remains visibly incomplete until a HOTAS PTT control is mapped or the pilot explicitly closes it.

VOICE INPUT / AUDIO DEVICES
---------------------------
- Added Push-to-Talk voice input. HOTAS bindings are true hold-to-talk; the fixed keyboard/Stream Deck shortcut is Ctrl+Alt+Shift+V.
- Added optional ALWAYS LISTEN mode. It uses a local amplitude/silence gate before creating an audio transcription request, so idle microphone audio does not generate AI calls.
- Preferences now lists microphone/input, Supertonic voice output and SFX output devices with System Default fallback and RESCAN AUDIO.
- If a saved device disappears, Bridge falls back to System Default rather than silently losing audio.
- Supertonic and Bridge SFX honor the selected output device. Windows System.Speech fallback still follows the Windows default output device.
- Voice input is transcribed and then sent through the existing Copilot command path; spoken PTT/Always Listen requests receive the concise Copilot result through Bridge TTS.

COCKPIT COMMAND OWNERSHIP / CANCELLATION
-----------------------------------------
- Long native cockpit commands remain single-owner: a second ordinary automation is refused instead of being stacked.
- Added cancellation tokens and CANCEL CURRENT so a cancelled worker stops at safe checkpoints instead of waking later and sending stale inputs.
- Station maintenance also checks cancellation between input/confirmation stages.
- Emergency Egress has higher priority: it requests cancellation of a lower-priority cockpit/station automation and waits for ownership to be physically released before proceeding.
- The session rule Auto Launch -> Clear Station + FSD now waits for its own Auto Launch worker to exit before handing off; it does not overlap another cockpit command.

AI COMMAND ACCESS
-----------------
- Interactive Copilot can now invoke a narrow allowlist of existing tested Bridge workflows when the commander explicitly asks: Auto Launch, Docking Protocol, Clear Station + FSD, cancel current command, Emergency Egress/cancel, highest threat, power plant and Combat Mode.
- AI-triggered workflows use the same ownership/cancellation gates as HOTAS, Stream Deck and GUI commands. The AI cannot invent raw-key macros through this interface.
- Voice-input mode can also be changed through the existing Bridge settings tool.

V0.12.81 CHANGE
---------------
AI SETTINGS CONTROL
-------------------
- Interactive Copilot can read current Bridge preferences with get_bridge_settings.
- Explicit user requests can persistently change Dynamic PIPs, voice verbosity/volume/speed, SFX enable/volume, startup-sound enable, and voice-attention mode.
- Settings changes use the same internal preference setters and automation.json as the GUI; the AI does not click controls or edit config files directly.
- Dynamic PIPs enabled/disabled is now persisted across Bridge restarts.
- Bridge writes a final Preferences/Audio snapshot on clean exit as an extra persistence safety net.
- Imported/custom startup audio remains in %LOCALAPPDATA%\EliteAIBridge\Sounds\Custom and therefore survives ZIP/version upgrades on the same machine.

SESSION RULES
-------------
- Added temporary current-process rule: clear_and_jump_after_auto_launch.
- A request such as "for the rest of this session, always clear and jump after Auto Launch" can enable it through the Copilot.
- After a confirmed Undocked event from Auto Launch, the rule hands off to the existing Clear Station + FSD command.
- Session rules are intentionally not written to disk and clear when Bridge exits.

V0.12.80 CHANGE
---------------
STATION SAFETY HOLD
-------------------
- Docking Protocol immediately applies 4 SYS / 2 ENG / 0 WEP and holds that Dynamic PIP mode until Docked or command failure.
- Auto Launch immediately applies 4/2/0 and holds it until Mass Lock has been observed after Undocked and then clears.
- Normal Dynamic PIPs cannot insert a CRUISE profile while either station-safety hold is active.
- Generic undocked Mass Lock still selects 4/2/0.
- Clear Station + FSD remains the explicit exception and immediately takes 2 SYS / 4 ENG / 0 WEP for the departure boost sequence.
- DockingGranted itself does not send any PIP inputs.

STATION SERVICE VOICE TIMING
----------------------------
- When automatic station services are enabled, the Docked announcement is shortened to: "Docking complete. Ship services starting."
- The actual service worker start plays the existing automation confirmation SFX without queueing a second start sentence.
- The existing completion cue and "Ship services complete." announcement remain unchanged.
- With station automation disabled, the normal detailed station/system Docked announcement remains unchanged.

V0.12.79 CHANGE
- Simplified Station Safety PIPs: undocked main ship + FSD Mass Locked => 4 SYS / 2 ENG / 0 WEP.
- Auto Launch and Docking Protocol apply 4/2/0 immediately when their command starts.
- Removed DockingGranted-specific/two-stage Station Safety PIP writes.
- Clear Station + FSD explicitly overrides Station Safety with the proven 2 SYS / 4 ENG / 0 WEP cruise preset.
- When Mass Lock clears, existing Dynamic PIPs resumes normal mode selection.


V0.12.78 CHANGE
---------------
VERIFIED STATION SAFETY RESET
-----------------------------
- Station Safety remains 4 SYS / 2 ENG / 0 WEP while Elite's launch/docking automation owns the ship.
- Station Safety now sends Reset Power Distribution by itself, then waits for Status.json to prove neutral 2/2/2 before sending any ENG/SYS profile taps.
- If neutral 2/2/2 is not verified, Bridge sends no profile taps and does not retry automatically. This prevents a swallowed reset from compounding into mixed PIP values.
- After a verified reset, the existing 4/2 Station Safety tap sequence is sent and still receives the normal final Status.json verification.
- Normal CRUISE / WEAPONS / COMBAT / RECOVERY / EGRESS PIP logic and cadence remain unchanged.

STATION SERVICE AUDIO FEEDBACK
------------------------------
- At the start of Refuel / Repair / Rearm automation, Bridge plays the existing automation confirmation cue and says: "Ship services underway. Stand by."
- When all enabled station services finish, Bridge plays the confirmation cue again and says: "Ship services complete."
- A safely aborted service run instead says: "Ship services aborted. Check Bridge status."
- Existing SFX and Voice Announcements master settings are respected. No extra station-menu input is added for feedback.
- The existing GUI automation banner continues to show the active Refuel / Repair / Rearm step and elapsed time.


V0.12.77 CHANGE
---------------
STATION SAFETY PIP CADENCE
--------------------------
- The Station Safety target remains 4 SYS / 2 ENG / 0 WEP.
- One docking test landed at 3 SYS / 3 ENG / 0 WEP, which is exactly one SYS tap short of the intended preset.
- Only STATION_SAFETY key cadence is slowed slightly (reset settle 0.09s; distributor taps 0.07s) to reduce dropped inputs during DockingComputer transitions.
- Normal CRUISE / WEAPONS / COMBAT / RECOVERY / EGRESS PIP timings and logic are unchanged.
- Verification behavior is unchanged: Bridge reports a mismatch but does not spam retries.

FASTER DOCK SERVICE START
-------------------------
- Initial dock settle reduced from 2.0s to 1.5s.
- Station-service confirmation deadline now includes the menu-anchor choreography, preventing valid RefuelAll events from being misclassified just because journal delivery arrives near the end of the wait.
- Inter-service pause reduced from 0.35s to 0.20s.
- Refuel/Repair/Rearm selection logic, menu anchoring, confirmation waits and no-retry safety behavior are otherwise unchanged.


V0.12.76 CHANGE
---------------
STATION SAFETY PIPS
-------------------
- Adds a temporary STATION SAFETY Dynamic PIP mode at 4 SYS / 2 ENG / 0 WEP while Elite's docking/launch automation owns the ship.
- Docking approach/boost logic is untouched. Station Safety arms only after DockingGranted, then releases when Docked or docking is cancelled/failed.
- Auto Launch arms Station Safety without changing the existing launch-menu sequence. After Undocked, the 4/2 preset is applied as soon as the native Auto Launch command releases cockpit ownership.
- Auto Launch Station Safety has no timer-based release. It requires a real observed Mass Locked TRUE -> FALSE transition before normal Dynamic PIPs resume.
- A brief false Mass Locked sample immediately after Undocked therefore cannot prematurely drop the shield-biased profile.
- Clear Station + FSD is an explicit Bridge flight-control takeover. If Station Safety is still active, Bridge restores the proven CRUISE 2 SYS / 4 ENG / 0 WEP profile before the existing mass-lock boost sequence.
- Station Safety does nothing when Dynamic PIPs are disabled. Existing CRUISE, WEAPONS, COMBAT, RECOVERY and EGRESS rules are otherwise unchanged.
- Dynamic PIP history/diagnostics now show Station Safety arm, apply, release, context and mass-lock evidence.


V0.12.75 CHANGE
---------------
DOCK-TIME REFUEL RELIABILITY
----------------------------
- Auto Refuel no longer asks live fuel telemetry whether a refuel is "needed" before clicking the station service.
- If Auto Refuel is enabled and the docked station offers refueling, Bridge selects Refuel exactly once for that docking.
- This avoids Status/Fuel timing races where Elite can still accept a small RefuelAll even though Bridge briefly sees a full tank.
- A genuinely full tank is harmless: Bridge sends one Refuel selection, waits briefly for an optional RefuelAll confirmation, never retries, and the dock token prevents another automatic pass.

ROUTE-AWARE CLEAR STATION + FSD
-------------------------------
- Clear Station + FSD no longer fails just because no route is plotted.
- With a plotted route/FSD target, the existing landing-gear + throttle + mass-lock boost sequence still prepares a hyperspace/FSD start.
- With no plotted route, the exact same safe departure sequence now clears station mass lock and then sends the dedicated Elite Supercruise binding.
- The no-route path deliberately does NOT use the combined FSD toggle, preventing route ambiguity.
- If a route appears mid-sequence during a no-route Supercruise departure, Bridge stops before FSD activation and asks the pilot to run the command again.
- The GUI/Command Map wording is now Clear Station + FSD: route plotted = jump; no route = Supercruise.


V0.12.72 CHANGE
- Station maintenance now queues Refuel for any measurable fuel deficit whenever Refuel is enabled and the station offers the service.
- Removed the old 0.05 t minimum-deficit cutoff. A partial tank is now always topped off before departure.
- Clear Station + Jump departure mechanics are unchanged from v0.12.71 while route-target behavior continues to be tested separately.

V0.12.71 CHANGE
---------------
COLONIZATION SCOPE CLARITY
--------------------------
- Largest-commodity load math now explicitly says the load count is for that commodity only.
- The same line also shows a separate theoretical full-load count for the entire remaining project at the current ship cargo capacity.
- Completion pace now explicitly says ENTIRE PROJECT and states the total outstanding tonnage used for its trip estimate.

ACTIVE CLEAR STATION + JUMP
---------------------------
- Clear Station + Jump no longer passively waits for station mass lock to disappear.
- After Undocked and cockpit control are available, it retracts landing gear if Status.json says gear is down.
- It commands 100% throttle before clearance boosts.
- While FSD Mass Locked remains true, it sends telemetry-driven departure boosts on a conservative 4.25 second cadence.
- When mass lock clears, it holds briefly, rechecks the plotted target and safety gates, then starts the FSD.
- Eight boosts is the hard safety ceiling so a bad/stale telemetry state cannot create an endless boost loop.
- Diagnostic output now includes the Landing Gear Toggle binding for field verification.

V0.12.70 CHANGE
---------------
COMMAND MAP / STREAM DECK
-------------------------
- The Controller / HOTAS window is now the unified Bridge Command Map.
- Every Bridge action shows its fixed Windows shortcut for Stream Deck / keyboard use beside any direct HOTAS binding.
- Global hotkey registration state is visible per row.
- Added COPY STREAM DECK HOTKEY for the selected action.
- Preferences now labels this control COMMAND MAP / HOTAS instead of hiding the keyboard layer behind the controller page.
- The Combat-page HOTKEY MAP button now opens the full command map.

AUTO LAUNCH TEST ACCESS
-----------------------
- Navigation now has a Departure / Docking Live Tests section.
- AUTO LAUNCH (LIVE TEST) is visible there and runs the real Auto Launch command.
- DOCKING PROTOCOL (LIVE TEST) and the Command Map are beside it for the same workflow.
- The live native-command status is shown on the Navigation page.

AI SPEECH THROUGH BRIDGE TTS
----------------------------
- AI `spoken_text` is now actually queued through the Bridge voice engine after a successful AI analysis.
- The configured Supertonic/Windows engine, selected voice, volume, speed, pitch and character remain the single speech path.
- Voice Announcements OFF remains the master mute; LOW/MED/HIGH allow AI speech.

COLONIZATION LOAD CLARITY
-------------------------
- Replaced the ambiguous “up to X t is one full ship load” wording.
- Load planning now explicitly names the current ship cargo capacity and calculates the approximate number of full loads required for the largest remaining commodity.
- The number follows the currently loaded ship, so a 40 t Mandalay no longer looks like Bridge is claiming 40 t is a game-wide maximum.

V0.12.69 CHANGE
---------------
BOOST-FIRST DOCKING PROTOCOL
----------------------------
- Docking Protocol now sends one boost FIRST, then coasts briefly, zeros throttle and checks docking range by requesting permission.
- The initial menu-first range probe from v0.12.67 is removed.
- If docking is granted after that first boost, no additional boost is sent.
- A DockingDenied reason indicating Distance/too far permits another boost/retry.
- Three boosts total is the hard ceiling. Non-distance denials stop immediately and zero throttle.
- Fresh No Fire Zone telemetry may shorten the coast, but stale NFZ state is never used as a blocking gate.

AUTO LAUNCH COMMAND
-------------------
- Added standalone AUTO LAUNCH Bridge command.
- Global Stream Deck-friendly shortcut: Ctrl+Alt+Shift+L.
- Uses the docked station menu because Elite has no dedicated Auto Launch key binding.
- Anchors the vertical docked menu from the top, moves to Launch, selects once, then waits for real Undocked telemetry.
- No blind retry is sent if Elite does not confirm departure.
- Available through the same controller-binding registry as other Bridge commands.

DYNAMIC PIP MACRO CORRECTION
----------------------------
- Fixed CRUISE 2 SYS / 4 ENG / 0 WEP. The previous reset -> ENG x4 -> SYS x2 sequence could land at 3/3/0.
- CRUISE now uses reset -> SYS x2 -> ENG x3.
- RECOVERY 4 SYS / 2 ENG / 0 WEP uses the mirrored reset -> ENG x2 -> SYS x3 sequence.
- Combat/Weapons/Egress priorities are otherwise unchanged.

COLONIZATION COMPLETION PACE
----------------------------
- Confirmed ColonisationContribution deliveries are now grouped by dock visit into observed hauling trips.
- Multiple commodity contribution clicks during one visit count as one trip, not several.
- The Colonization page shows average tons per observed trip and an estimated trips remaining against the current outstanding construction tonnage.
- Once multiple real trips exist, Bridge also estimates average cycle minutes and approximate time remaining at the recent pace.
- Pace samples persist with each MarketID construction project and use only confirmed contribution telemetry.
- Estimates adapt naturally when cargo capacity/ship choice changes because they follow actual delivered tonnage rather than a fixed configured capacity.


V0.12.68 CHANGE
---------------
DYNAMIC FLIGHT PIPS
-------------------
- Quiet normal-space main-ship flight with hardpoints retracted uses 2 SYS / 4 ENG / 0 WEP.
- Deploying hardpoints from a quiet state prepares the weapon capacitor with 1 SYS / 1 ENG / 4 WEP. Hardpoints alone do not start combat automation.
- Active combat and fully scanned WANTED-target pre-arm retain the proven 1 SYS / 1 ENG / 4 WEP combat profile.
- After a real combat encounter goes quiet for the existing 45-second combat timeout, Bridge enters a 90-second RECOVERY window at 4 SYS / 2 ENG / 0 WEP, even if hardpoints remain deployed.
- If shields are still actually DOWN when that timer expires, RECOVERY continues until Elite reports Shields Up.
- Elite does not expose a trustworthy own-ship shield percentage here, so Bridge does not invent one.
- PIP profiles are applied once on meaningful state transitions. Manual pilot changes are respected until the next state transition rather than being constantly overwritten.
- Dynamic ship PIPs are explicitly limited to In Main Ship normal-space context so future SRV/Rhino/Nomad behavior can be designed separately.

SAFER EMERGENCY EGRESS
-----------------------
- Emergency Egress now checks the native Hardpoints status flag.
- If hardpoints are deployed, Bridge sends the bound Deploy/Retract Hardpoints toggle once before starting the existing escape sequence.
- If hardpoints are already retracted, no hardpoint toggle is sent.
- Egress then keeps the proven 1 SYS / 4 ENG / 1 WEP, full-throttle, one-boost, optional-chaff and mass-lock-clear/supercruise behavior.
- Missing hardpoint binding blocks Egress only when hardpoints actually need to be retracted, preventing an accidental jump attempt with guns still deployed.

V0.12.67 CHANGE
---------------
SMART DOCKING PROTOCOL
----------------------
- Docking Protocol now probes Request Docking immediately before sending any boost.
- If docking is granted/requested while already in range, NO BOOST is sent.
- Boost is authorized only after a fresh DockingDenied response whose reason indicates Distance/too far.
- After a distance denial, Bridge uses short boost/coast steps and re-probes instead of waiting 30 seconds for a No Fire Zone event.
- Fresh No Fire Zone telemetry can accelerate a retry, but is no longer a long blocking gate.
- Standalone Request Docking was removed from the user-facing buttons/global hotkeys/controller actions. The request helper remains internal to Docking Protocol.
- Old saved HOTAS Request Docking mappings are ignored/pruned from the active action set.

HIGH VOICE SHIP SCANS
---------------------
- HIGH voice now gives one concise callout for every completed ship scan.
- Callouts emphasize ship type, System Authority/police status when applicable, CLEAN/WANTED status, and bounty when present.
- NPC pilot names are intentionally omitted from routine scan speech.
- Target-lock tracking prevents progressive subsystem ShipTargeted rows from repeating the same scan announcement.

COLONIZATION PARSER FIX
-----------------------
- Fixed the local `pct` variable shadowing the global percentage helper inside journal processing.
- This caused intermittent `cannot access local variable pct` journal-reader errors before the construction-depot event was encountered.
- Colonization project tracking and the silent-startup protection from v0.12.66 remain intact.

V0.12.64 CHANGE
---------------
COLONIZATION INTELLIGENCE
-------------------------
- Added a Colonization tab driven by explicit Elite journal events.
- Tracks ColonisationConstructionDepot progress, complete/failed state, MarketID, required/provided/remaining commodity amounts and per-unit payment data.
- Highlights total outstanding tonnage and the largest remaining commodity need.
- Tracks this commander's exact ColonisationContribution deliveries for the current journal, both total and by commodity.
- Tracks beacon/claim/release events and persists known construction snapshots under LocalAppData so the last known project state survives Bridge restarts.

CLEAR STATION + JUMP
--------------------
- Added a new Bridge command and HOTAS/global-hotkey-bindable action: Clear Station & Jump (default global hotkey Ctrl+Alt+Shift+J).
- Captures the live plotted FSD target/route, waits for Undocked, cockpit focus, and FSD Mass Lock clear, holds briefly for stable clearance, sends full throttle once, then sends one FSD start.
- Rechecks the route immediately before FSD start and aborts if the target changed, Elite lost foreground, interdiction begins, overheating is reported, or Status.json does not confirm FSD charging/jump.
- No blind timed 'leave station then jump' macro and no automatic FSD retry.

COCKPIT CONTROL OWNERSHIP
-------------------------
- Added a persistent top status banner showing CONTROL READY, COMMAND RUNNING, AUTOMATION QUEUED, or AUTOMATION RUNNING.
- While station Refuel/Repair/Rearm automation owns station UI controls, ordinary Bridge commands are rejected instead of stacking keystrokes on top of it.
- Station maintenance likewise waits behind an active Bridge command.
- The banner identifies the active command/service and elapsed run time so the pilot can tell when Bridge is in the middle of a sequence.

FUEL / TRAVEL VOICE CLEANUP
---------------------------
- Every newly targeted non-scoopable star now gets an important voice warning.
- When NavRoute has useful star-class data, Bridge can occasionally summarize roughly the next three stars, e.g. next star scoopable followed by two non-scoopable stars.
- Multi-star fuel chatter is deliberately throttled; all-scoopable stretches stay quiet.
- Routine jump-start speech no longer repeats the destination system name immediately before arrival. Intermediate jumps now use short phrases such as 'Jump initiated'; arrival remains the normal place to name the system.

AUDIO FOUNDATION RETAINED
-------------------------
- Per-event SFX Test / Browse-Import / Reset Default / Enable controls remain from v0.12.63.
- Custom sounds remain copied into %LOCALAPPDATA%\EliteAIBridge\Sounds\Custom.
- The retro-futurist bundled sound pack and voice-attention cue remain unchanged in this build.

V0.12.60 CHANGE
---------------
DOCKING RESPONSE FIX
--------------------
- The left-panel tab sweep now stops on ANY fresh Elite docking response, not only DockingRequested.
- DockingDenied, DockingGranted, DockingRequested and DockingCancelled all prove the Bridge reached the station's Request Docking control.
- This fixes the out-of-range case where Elite emits DockingDenied directly (for example, approach within 7500 m) without first logging DockingRequested.
- A denial now stops the sweep immediately instead of sending repeated docking requests across later tabs.
- Request Docking and Docking Protocol share the same corrected docking helper, so both commands receive the fix.
- v0.12.59 tab-sweep navigation is otherwise retained. No combat, voice-DSP, controller-binding, or trade-loop behavior was changed in this patch.

V0.12.57 FOUNDATION RETAINED
----------------------------
- Direct Bridge bindings for controller/HOTAS digital buttons and POV/hat directions. Analog axes are intentionally not triggers yet.
- Preferences > Bridge Controls provides game-style BIND / REBIND / CLEAR controls.
- Controller mappings trigger the same proven Bridge command handlers as the global keyboard/Stream Deck hotkeys.
- Bindings persist at %LOCALAPPDATA%\EliteAIBridge\controller_bindings.json.
- Device matching uses SDL device GUID + product name rather than transient Joystick 1 / Joystick 2 numbering.
- Identical ambiguous devices are not guessed.
- Preferences > Commander Profile provides the separate "Call me" identity for Bridge/TTS.


V0.12.56 CHANGE
---------------
VOICE PITCH + METALLIC / SHIMMER
--------------------------------
- Added independent Supertonic Pitch / Tone control: VERY DEEP, DEEP, NORMAL, HIGH.
- Pitch changes are conservative and preserve the spoken clip duration so pitch does not secretly become a second speech-speed control.
- Added METALLIC character: resonant short-delay/comb coloration, presence shaping and light machine modulation.
- Added SHIMMER character: brighter spectral shaping, close doubling and a light airy upper layer.
- Pitch and character can be freely combined, for example DEEP + METALLIC or NORMAL + SHIMMER.
- Character outputs remain RMS loudness-matched so preset changes emphasize timbre rather than volume.
- The optional Supertonic setup now installs the local audio-DSP helper used for pitch shifting.
- Supertonic startup warm-up also warms the pitch DSP path to reduce the first pitch-change delay.

V0.12.55 CHANGE
---------------
VOICE RESPONSE + CHARACTER PASS
--------------------------------
- TEST VOICE is now intentionally short: "Voice systems online, Commander."
- Added a separate TEST NUMBERS button for the exact/rounded credit formatter.
- Supertonic now pre-warms on the background voice worker at Bridge startup when available, reducing the first spoken-call startup delay.
- Voice character DSP was rebuilt to make presets audibly distinct at high Effect Strength.
- CLEAN remains untouched.
- BRIDGE now uses stronger presence shaping, compression and subtle doubling.
- RADIO now uses a true narrow communications band, stronger saturation, quantization and short squelch-style edge clicks.
- COMMAND now uses darker spectral shaping, heavier compression and layered machine-weight modulation.
- SYNTH now uses stronger chorus/delay and modulation for an obvious synthetic character.
- Processed Supertonic presets are RMS-matched to the clean source before Bridge volume is applied, so changing character should not mainly sound louder or quieter.
- Spoken credit rules from v0.12.54 remain unchanged: exact below 100,000 CR, natural rounded speech at/above 100,000 CR.

V0.12.54 CHANGE
---------------
VOICE CLARITY + CHARACTER
-------------------------
- Spoken credit values below 100,000 CR stay exact.
- Spoken credit values at/above 100,000 CR are rounded into clearer thousands/millions/billions. On-screen and log values remain exact.
- Credit-heavy announcements are spoken slightly slower to keep number words from running together.
- Added Supertonic voice-character presets: CLEAN, BRIDGE, RADIO, COMMAND, SYNTH.
- Added Effect Strength 0-100%.
- Effects are applied locally to Supertonic PCM with NumPy. No extra audio plugin/package is required.
- Windows TTS fallback remains clean/unfiltered.

VOICE ENGINE CONTROLS
- Voice announcements still use OFF / LOW / MED / HIGH chatter profiles.
- Added engine selection: AUTO / SUPERTONIC / WINDOWS.
- AUTO prefers Supertonic and automatically falls back to Windows System.Speech if Supertonic is unavailable or fails.
- Added voice selection. Supertonic exposes its 10 built-in voices: M1-M5 and F1-F5. WINDOWS lists installed System.Speech voices.
- Added Bridge-only Volume slider from 0-100%. This does not change Windows master volume.
- Added Speech Speed slider from 0.70x-2.00x.
- Added Supertonic quality steps 5-12; 8 is the balanced default.
- TEST VOICE uses the currently selected engine, voice, volume, speed and quality.
- Voice settings persist in the normal Elite AI Bridge automation preferences file.
- Speech remains on a background worker and never owns game automation decisions.

SUPERTONIC DURING DEVELOPMENT
-----------------------------
The large Supertonic runtime/model files are intentionally NOT bundled in this development ZIP.
This keeps each Bridge build small while features are still changing.

To enable Supertonic on this development build:
1. Run Setup_Supertonic_Optional.bat once (rerun it for v0.12.56 if you used an older setup, so the pitch DSP helper is installed).
2. It installs the free local Python package plus voice DSP helper and downloads the Supertonic 3 model cache (roughly 400 MB) outside this Bridge folder.
3. Start Elite AI Bridge.
4. Open Preferences > Voice Announcements.
5. Select AUTO or SUPERTONIC, choose M1-M5 or F1-F5, then click TEST VOICE.

If Supertonic is not installed, AUTO simply uses the Windows voice engine. The Bridge remains fully usable.
For the final/self-contained release, the plan is to ship the Supertonic runtime/model assets with the Bridge so this separate setup step disappears.

VOICE LEVELS
------------
LOW
- Confirmed positive NPC crew wage deductions, including matched voucher context when available.
- Confirmed interdiction / interdiction escape.
- Ship destruction.
- Stolen-cargo pickup warning.

MED
- Everything in LOW.
- Route-ready and arrival announcements.
- Docking permission / denial.
- Station arrival, for example: "Arrived at Onnes Orbital in Epomana. Docking complete."
- Mission completion / failure and journal-reported reward when present.

HIGH
- Everything in MED.
- Jump / en-route travel play-by-play and undocking.
- Supercruise exit, touchdown and liftoff.
- Fully scanned target identification, legal state and bounty when supplied by Elite.
- Bounty kills and combat bonds.
- Material pickups and held total when known.
- Cargo / salvage pickups and Powerplay merit callouts.

Crew pay speech is intentionally delayed about one second so a same-moment RedeemVoucher event can enrich the spoken announcement instead of producing two competing callouts.

V0.12.51 CHANGE
---------------
CREW VOUCHER CORRELATION
- RedeemVoucher events retain Type, net Amount, Faction/Factions, and broker percentage in diagnostics.
- A positive NpcCrewPaidWage remains the ONLY trigger for a crew-pay alert.
- When Elite writes NpcCrewPaidWage and RedeemVoucher at the same journal moment, the existing alert is enriched with the exact voucher type and journal-reported net voucher amount.
- Both journal orders are supported: wage then voucher, or voucher then wage.
- No crew percentage is calculated because RedeemVoucher.Amount is not treated as a guaranteed pre-crew gross value.
- Zero-credit crew wage events remain ignored.

V0.12.49 CHANGE
---------------
The experimental visual shield-reading/OCR/Auto-SCB subsystem was removed completely. Native Elite shield state and scanned-target shield telemetry remain available.

RETAINED CORE SYSTEMS
---------------------
- Dynamic PIPs with WANTED-target combat pre-arm.
- Auto Heavy Power Plant targeting.
- Auto Chaff with LOW / MED / HIGH profiles.
- Target and Material Intelligence.
- Collector / salvage awareness and stolen-cargo warnings.
- Confirmed NPC crew pay and voucher correlation.
- Emergency Egress.
- Fighter, wing, docking and Bridge global-hotkey actions.
- Nearby RES Finder.
- Navigation, trade-loop, EDDN, history and AI/copilot systems.

AUTO HEAVY POWER PLANT TARGETS
------------------------------
For a fully scanned WANTED target, the optional Auto Heavy Power Plant system recognizes:
- Anaconda
- Fer-de-Lance
- Federal Dropship
- Federal Assault Ship
- Federal Gunship
- Federal Corvette
- Imperial Cutter
- Type-10 Defender

DEFAULT GLOBAL BRIDGE HOTKEYS
-----------------------------
Target Power Plant:       Ctrl + Alt + Shift + P
Target Highest Threat:    Ctrl + Alt + Shift + T
Ensure Combat Mode:       Ctrl + Alt + Shift + C
Docking Protocol:         Ctrl + Alt + Shift + D
Request Docking:          Ctrl + Alt + Shift + R
Assist Wing 1 / 2 / 3:    Ctrl + Alt + Shift + 1 / 2 / 3
Deploy Fighter 1 / 2:     Ctrl + Alt + Shift + 4 / 5
Recall Fighter:           Ctrl + Alt + Shift + 6
Wing Nav Lock 1 / 2 / 3:  Ctrl + Alt + Shift + 7 / 8 / 9
Emergency Egress:         Ctrl + Alt + Shift + E
Cancel Egress:            Ctrl + Alt + Shift + X

NOTE
----
An old %LOCALAPPDATA%\EliteAIBridge\visual_hud.json file from earlier builds may remain on disk. v0.12.62 does not read or use it.


v0.12.62 SOUND EFFECTS FOUNDATION
- Independent cockpit SFX on/off and volume controls in Preferences.
- Original replaceable PCM WAV starter pack in Sounds\.
- TEST SOUND selector for every mapped cue.
- Interdiction, docking granted/denied, danger, route-ready, crew-pay, startup, and station-automation confirmation cues.
- Priority handling prevents low-priority chirps from piling over urgent alarms.
- Replace any Sounds\*.wav file with a standard PCM WAV of the same filename to customize it.


v0.12.62 Retro Audio Pass
- Reworked original sound pack toward analog/cassette/relay late-70s sci-fi control-room character.
- Added Voice Attention Cue: OFF / IMPORTANT / MOST. Default IMPORTANT.
- IMPORTANT stays sparse and skips events that already have dedicated alarm/docking/combat sounds.
- Added Sounds\attention.wav. All bundled WAVs are original generated assets with no third-party samples.

COLONIZATION INTELLIGENCE (v0.12.64)
--------------------------------------
- New Colonization tab driven by Elite journal telemetry.
- Tracks construction progress and all required/provided commodities from ColonisationConstructionDepot.
- Tracks exact commander deliveries from ColonisationContribution.
- Shows remaining tonnage, cargo aboard, Payment values, and largest outstanding requirement.
- Tracks beacon, system claim, and claim-release events.
- Last-known project snapshots persist in %LOCALAPPDATA%\EliteAIBridge\colonization_projects.json.
- Intelligence only: no hauling automation is enabled.


CLEAR STATION & JUMP (v0.12.64)
----------------------------------
- New state-aware VoiceAttack replacement command: Clear Station & Jump.
- Global hotkey: Ctrl+Alt+Shift+J. It is also available to direct HOTAS/controller binding.
- Requires an existing Elite route/FSD target. It does not plot or guess a destination.
- May be armed while docked; waits for Undocked, cockpit focus, and real FSD Mass Locked clearance.
- After a brief clear-state hold, commands Throttle 100% and sends exactly one Hyperspace/FSD start.
- Confirms FSD Charging / FSD Jump from Status.json. No blind retries.
- Stops before FSD start on interdiction, overheating, route changes, lost foreground, or open panels.


v0.12.75 timer-only station maintenance tuning:
- Dock settle wait reduced from 3.0s to 2.0s.
- Refuel journal confirmation wait reduced from 3.0s to 2.0s.
- Repair/Rearm journal confirmation waits reduced from 8.0s to 3.0s each.
- No service logic or menu choreography changed.