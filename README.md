# Elite AI Bridge 1.0.1

Elite AI Bridge is an independent Windows companion application for **Elite Dangerous**. It combines live game/journal information, navigation, trade and combat tools, HOTAS/controller support, an in-game overlay, voice features, and an optional AI co-pilot in a cockpit-inspired interface.

## Public source

The **full readable application source for the 1.0.1 release is published in this repository**. The source is provided so the community can inspect what is distributed and build the application themselves.

This project is **source-available** under the project license in `LICENSE.txt`; it is not presented as an OSI-approved open-source license. Third-party components and intellectual property remain subject to their own terms.

## Download

Windows installers are published in the repository's **Releases** section. The current source baseline is **1.0.1**; use the release matching the source version you are reviewing.

## Source code

The application source is in `src/Elite AI Bridge/`.

**[Browse the application source on GitHub](https://github.com/CoreDynamicsDev/Elite-AI-Bridge/tree/main/src/Elite%20AI%20Bridge)**

Windows may warn about the installer because the executable is not currently code-signed. Only download releases from this GitHub repository.

## What it includes

- Live commander, ship, system and station information
- Navigation and route tools
- Trade and market tools
- Combat and target information
- Colonization tools
- HOTAS/controller support and custom bindings
- In-game HUD/chat overlay
- Push-to-Talk and voice commands
- Optional AI co-pilot
- Dynamic ship/target artwork
- Audio feedback and spoken responses
- CRT-style startup/boot sequence

## Building from source

The tested Windows build path is included in the repository. For the 1.0.1 source baseline:

1. Install **Python 3** and **Inno Setup 6** on Windows.
2. Extract or clone the repository.
3. Open `src/Elite AI Bridge/` and use the included source launcher for local testing.
4. The first run prepares the private runtime and installs the required packages, including Supertonic.
5. After the source build is verified, run `installer\BUILD_INSTALLER.bat` to compile the Windows installer.
6. The resulting installer is written to `Output\Elite_AI_Bridge_Setup_1.0.1.exe`.

See `docs/BUILD.md` and `docs/BOOT_SPLASH.md` for release-specific notes.

## AI co-pilot and OpenAI

AI features are optional. Core Bridge does not require an OpenAI API key.

If AI features are enabled, the user supplies their own OpenAI API account and API key. API usage is between the user and OpenAI and may incur charges according to the user's account and current OpenAI terms and pricing.

**Never publish an API key, password, token, or other secret in this repository, an issue, Reddit, Discord, or a support package.**

See `PRIVACY_AND_API_KEYS.md`.

## Support and feedback

- Use **GitHub Issues** for bugs, feature requests, and general feedback.
- Review diagnostic/support exports before sharing them publicly.
- Never include secrets or API keys in diagnostics.

## Support development

Elite AI Bridge is free to use. Voluntary support is appreciated: [Ko-fi](https://ko-fi.com/eliteaibridge).

## Independence and trademarks

Elite AI Bridge is an independent community project. It is not affiliated with, sponsored by, approved by, or endorsed by Frontier Developments plc or OpenAI.

Elite Dangerous and related names, marks, game content, and intellectual property belong to Frontier Developments plc and/or their respective rights holders. OpenAI and related marks belong to OpenAI and/or their respective rights holders.

See `DISCLAIMER.md`, `LICENSE.txt`, `PRIVACY_AND_API_KEYS.md`, and `THIRD_PARTY_NOTICES.md`.
