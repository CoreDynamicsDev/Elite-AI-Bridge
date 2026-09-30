ELITE AI BRIDGE 1.0.1 - CLEAN INSTALLER SOURCE

This source package contains the tested 1.0.1 build, including the Supertonic
voice dependency, process cleanup, minimized source launcher, and CRT boot splash.
Temporary splash-inspection files and Python bytecode caches are intentionally not
included in this release source package.

COMPILE ON WINDOWS
1. Install Inno Setup 6 if it is not already installed.
2. Extract this ZIP.
3. Double-click BUILD_INSTALLER.bat.
4. Finished installer: Output\Elite_AI_Bridge_Setup_1.0.1.exe

TEST BEFORE UPLOAD
Install the generated EXE and verify that Elite AI Bridge launches and diagnostics
report:
- Selected voice engine: SUPERTONIC
- Supertonic package available: True
- Last backend used: Supertonic

Do not replace the public release until the generated installer has passed that test.

BOOT SPLASH
-----------
The 1.0.1 build includes the animated CRT boot splash. RUN_CURRENT_SOURCE.bat
launches the same source path used by the installer runtime.
