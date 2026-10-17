# Changelog

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
