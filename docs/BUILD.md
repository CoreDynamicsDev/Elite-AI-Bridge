# Elite AI Bridge 1.0.1 Build Instructions

The public repository is organized so the complete readable application source
lives under src/Elite AI Bridge/, while the Windows installer definition and
build helper live under installer/.

## Local Windows build

1. Install Inno Setup 6.
2. Clone or extract this repository.
3. Run installer\BUILD_INSTALLER.bat.
4. The finished installer is written to:
   installer\Output\Elite_AI_Bridge_Setup_1.0.1.exe

The installer definition already points at the public src\Elite AI Bridge\
payload. Do not copy the application into the installer directory.

## GitHub Actions build

The repository also contains a Windows GitHub Actions build at
.github/workflows/build-installer.yml.

A push to main that changes application, installer, documentation, license, or
workflow files builds the installer on a Windows runner. The workflow uploads
the compiled installer and its SHA-256 checksum as an Actions artifact.

## Release verification

Before publishing a Windows installer release:

- install the generated EXE on a clean Windows test machine;
- verify the Bridge starts normally;
- verify the private runtime setup completes;
- verify Supertonic is available;
- verify normal shutdown does not leave the Bridge backend running;
- verify the CRT boot splash holds for at least 15 seconds;
- verify the overlay behavior in Borderless/Windowed mode;
- review the checksum before publishing.

Compiled installers and build output do not belong in the source repository.
