# Source Code

This repository contains the readable source used to build Elite AI Bridge. The public source is published directly in the repository rather than only as a compiled executable.

## Source layout

- `src/Elite AI Bridge/backend/` - backend services, game-data handling, automation, voice/AI integration, and supporting resources.
- `src/Elite AI Bridge/frontend/` - PySide6/QML application UI, startup logic, overlay, and boot splash.
- `src/Elite AI Bridge/assets/` - application assets used at runtime.
- `src/Elite AI Bridge/docs/` - runtime documentation and notices.
- `installer/` - Inno Setup definition and Windows build helpers.
- `branding/` - project branding assets.
- `docs/` - public project documentation and notices.

## Release relationship

The source in `main` is the current development baseline. Tagged releases identify the source state associated with a published installer. For release 1.0.1, use the corresponding 1.0.1 tag or release commit.

Compiled installers belong in GitHub Releases, not in the source tree. Virtual environments, diagnostics, logs, and build output do not belong in the public repository.
