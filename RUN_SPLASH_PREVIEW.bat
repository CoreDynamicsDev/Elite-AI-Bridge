@echo off
rem Plays the new boot splash on its own (no Bridge), using the Bridge's runtime.
set "EAB_PY=%LOCALAPPDATA%\EliteAIBridge\runtime\.venv\Scripts\python.exe"
if not exist "%EAB_PY%" (
    echo The Bridge runtime was not found. Run the Bridge once first.
    pause
    exit /b 1
)
"%EAB_PY%" "%~dp0Elite AI Bridge\frontend\splash_preview.py"
