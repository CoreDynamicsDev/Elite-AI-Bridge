# Building the Windows Installer

The official installer is built with **Inno Setup 6** on Windows.

1. Install Inno Setup 6.
2. Ensure this repository is checked out locally.
3. The installer definition uses the application payload from `src/Elite AI Bridge`.
4. Run `installer\BUILD_INSTALLER.bat`.
5. The release output is `Elite_AI_Bridge_Setup_1.0.1.exe`.

The official release installer should be attached to GitHub Releases rather than committed as a large binary to the source repository.

Before publishing a rebuilt installer, perform a clean-machine installation test.
