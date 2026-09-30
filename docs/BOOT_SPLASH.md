# Elite AI Bridge CRT Boot Splash

The boot splash is a presentation layer that appears before the main Bridge UI.

## Pass 3 changes

- Uses the source artwork's native 1672x941 coordinate system.
- Fits the artwork uniformly to the selected display without stretching or cropping.
- Runtime drawing uses one shared scale and centered offsets, so text and progress bars stay aligned on different resolutions.
- Removed the baked progress percentages and step counter from the artwork so runtime values are drawn only once.
- Corrected the 11 system-status rows plus 4 control-interface rows.
- Corrected the OK field alignment.
- Kept vessel/network values inside their bracket fields using compact values.
- Removed the old translucent value backing layer.
- Progress rails and fills use the actual rail positions in the artwork.
- Splash remains presentation-only. It does not claim real subsystem readiness.
- Normal Bridge startup holds the splash for a minimum of 15 seconds before allowing the handoff, giving the backend and Supertonic voice engine time to settle on slower first launches.

## Testing

Use `RUN_SPLASH_INSPECTION.bat` to launch only the splash for 120 seconds.

Use `RUN_CURRENT_SOURCE.bat` to launch the full source build.

Do not build the installer until the source launch is visually verified on Windows.
