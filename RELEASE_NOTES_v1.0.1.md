# Elite AI Bridge 1.0.1

This release updates the original 1.0 installer with the tested 1.0.1 runtime and startup fixes.

## Highlights

- Restores and validates the Supertonic voice backend.
- Adds the CRT-style animated startup/boot sequence.
- Adds a 15-second minimum startup display so the first launch does not appear hung while the runtime initializes.
- Cleans up the backend process tree on normal shutdown.
- Normal source launcher runs minimized; diagnostic errors remain visible when needed.
- Improves startup and shutdown behavior around the Bridge/backend split.
- Keeps the public source tree aligned with the tested 1.0.1 installer source.

## AI / OpenAI

AI features remain optional. Users who enable them supply their own OpenAI API key and are responsible for their own API usage and billing. No developer API key is included.

## Overlay

The in-game overlay requires Elite Dangerous to run in Borderless or Windowed mode. Exclusive Fullscreen does not display the overlay.

## Verification

The source package includes `SHA256SUMS.txt` and Windows build instructions.
