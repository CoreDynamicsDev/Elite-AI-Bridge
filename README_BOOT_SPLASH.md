# Elite AI Bridge Boot Splash

The boot splash is the CRT start-up screen shown while the Bridge loads. It is
presentation only: it does not claim real subsystem readiness.

- Drawn live in `Elite AI Bridge/frontend/boot_splash.py`, scaled to the screen it opens on.
- Normal start-up holds the splash for a minimum time so the backend and the voice
  engine can settle on slower first launches.

## Testing

Use `RUN_SPLASH_PREVIEW.bat` to play the splash on its own (needs the Bridge runtime,
so run the Bridge once first).

Use `RUN_CURRENT_SOURCE.bat` to launch the full source build.
