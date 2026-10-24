# Changelog

## 2.0.4 - 2026-10-24

### New
- OLD SCHOOL AMBER screen theme: Setup > Display > SCREEN EFFECTS > THEME. Green stays the
  default. Only the screens change (text, glass, grain, lists, ship art, shield, route map,
  setup wizard, overlay and the opening animation); keys, lamps and plates stay the same.
  Danger stays red, and heads-up messages turn yellow so they still stand out.
- Startup sound: original sound effects timed to the opening animation, played at the
  SOUND EFFECTS level. Switch it off in Setup > Sound (STARTUP SOUND), or hear it with the
  STARTUP SOUND key.

### Fixes
- The setup wizard no longer starts talking while the opening animation is still playing.

## 2.0.3 - 2026-10-17

### Changed
- Update check runs each time the Bridge starts and every 6 hours while it is open (was at
  most once a day). The Setup > Status switch is now called CHECK FOR UPDATES.

### Fixes
- Voice pitch: DEEP, VERY DEEP and HIGH now work on installed copies (done with numpy, no
  extra download).
- Setup > Status on 1366x768: text no longer runs under the name box or the wizard switch.

## 2.0.2 - 2026-10-17

### New
- Fleet: on the Commander page, switch ODD STATS to FLEET to see where every stored ship
  is, nearest first, with station, system and value; ships in transit show when they
  arrive. Pick one and PLOT: SHIP plots a route to it. Read from the game journal, as of
  your last shipyard visit.

## 2.0.1 - 2026-10-16

### New
- Update notice: once a day the Bridge asks GitHub if a newer version is out. When one is,
  a slow amber lamp and an UPDATE tag appear next to the version under the title (click it to
  open Setup > Status), and Setup > Status shows the release notes with a DOWNLOAD key that
  opens the release page. Nothing is downloaded or installed by itself; CHECK DAILY turns it off.

### Fixes
- ELITE lamp shows amber AT MAIN MENU until you load in, instead of green with empty ship data.
- Colonization, My Sites: sites not visited in 30 days show NOT SEEN instead of BUILDING
  forever, and releasing a system claim clears that system's sites.

## 2.0.0 - 2026-10-10

A complete redesign of Elite AI Bridge.

### New
- Retro command deck interface: Flight Deck, Combat, Trade, Navigation, Colonization,
  Commander and Setup, rebuilt from scratch.
- Setup wizard: Elite, your keys, controls, sound, which screen the Bridge and the overlay
  go on, and an optional AI add-on run with the OpenAI key typed or pasted into a normal box.
- Guided tours: every page has a short spoken tour on its ? key.
- Bounty Hunting: finds Resource Extraction Sites by danger level, with search range and
  site distance controls.
- Commander odd stats, cargo and loadout views in the Flight Deck event log.
- In-game overlay: off until you turn it on, goes on the screen you pick, and steps aside
  while the Bridge window is in front on the same screen.
- Ship voice says plainly when Elite has no keyboard key for something you asked for, and
  where to set one.
- Bug reporting from Setup > Status: a support file, then GitHub or email.

### Install and safety
- The installer shows a checklist with live progress while it prepares the runtime.
- The Bridge opens fullscreen.
- Shortcuts run the runtime's own Python (signed by the Python Software Foundation);
  there is no VBScript or custom launcher.
- Every runtime package is pinned to an exact, tested version.
- Full SIL Open Font License text included with the bundled fonts.

## 1.0.1 - 2026-09-30
Maintenance and startup release: Supertonic voice backend restored, boot sequence added,
cleaner shutdown and documentation updates.

## 1.0.0 - 2026-09-27
First public release.
