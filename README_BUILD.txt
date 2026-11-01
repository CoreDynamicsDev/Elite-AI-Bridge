ELITE AI BRIDGE 2.0.5 - INSTALLER SOURCE

This source package contains the 2.0.5 build: the 2.0 retro redesign, setup wizard,
guided tours, in-game overlay and the Supertonic local voice, the 2.0.1 fixes
(ELITE lamp at the main menu, old colony sites) and update notice, the 2.0.2 FLEET view
on the Commander page, the 2.0.3 changes (update check on every start, working voice
pitch, small-screen fixes on Setup > Status), the 2.0.4 changes (OLD SCHOOL AMBER
screen theme, startup sound, setup wizard waits for the opening animation) and the 2.0.5
changes (Mining and Engineering pages, docking and route plot fixes, launcher with a runtime
check). Python bytecode caches are not part of the release source.

COMPILE ON WINDOWS
1. Install Inno Setup 6 if it is not already installed.
2. Double-click BUILD_INSTALLER.bat.
3. Finished installer: Output\Elite_AI_Bridge_Setup_2.0.5.exe

TEST BEFORE UPLOAD
Install the generated EXE on a Windows user account that has never run the Bridge
and check:
- The setup wizard runs from the first screen to READY.
- The ship voice speaks (Setup > Status shows the voice as ready).
- The taskbar and shortcuts show the Elite AI Bridge icon.
- With an OpenAI key: paste it in the wizard, push to talk and get an answer.

Do not replace the public release until the generated installer has passed that test.

SOURCE RUN
RUN_CURRENT_SOURCE.bat launches the same source the installer packages, using the
Bridge's own runtime. RUN_SPLASH_PREVIEW.bat plays the boot splash on its own.

SHORTCUTS
The Start menu and desktop shortcuts run START_HERE.bat, minimized. It checks that the
Bridge's runtime is there and starts frontend\main.py with the runtime's own pythonw.exe
(signed by the Python Software Foundation), or opens the repair window if the runtime is
missing. "Repair Elite AI Bridge" in the Start menu runs the full check and rebuild.
There is no launcher program of our own.
