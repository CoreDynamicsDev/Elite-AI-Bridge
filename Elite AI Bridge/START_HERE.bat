@echo off
setlocal
cd /d "%~dp0"
rem Elite AI Bridge launcher (2.0.5). The Start Menu and desktop shortcuts run this
rem minimized. Normal start: check the runtime files are there, start the Bridge, close.
rem If the runtime is missing, reopen in a normal window and repair it.
rem "START_HERE.bat repair" (the Repair shortcut) is the full check plus diagnostic mode.
set "EAB_ROOT=%LOCALAPPDATA%\EliteAIBridge"
set "EAB_RUNTIME=%EAB_ROOT%\runtime\.venv"
set "EAB_READY=%EAB_ROOT%\runtime\.ready"
set "EAB_PY=%EAB_RUNTIME%\Scripts\python.exe"
set "EAB_PYW=%EAB_RUNTIME%\Scripts\pythonw.exe"
set "NEED_SETUP=0"

if not exist "%EAB_READY%" set "NEED_SETUP=1"
if not exist "%EAB_PY%" set "NEED_SETUP=1"
if not exist "%EAB_PYW%" set "NEED_SETUP=1"

if /i not "%~1"=="repair" (
    if "%NEED_SETUP%"=="1" (
        start "Elite AI Bridge Repair" "%ComSpec%" /c ""%~f0" repair"
        exit /b 0
    )
    start "" "%EAB_PYW%" "frontend\main.py"
    exit /b 0
)

rem ---------------------------------------------------------------- repair / diagnostic
set "EAB_REPAIR_RUN=1"
echo ============================================
echo      ELITE AI BRIDGE 2.0.5
echo ============================================
echo.

if "%NEED_SETUP%"=="0" (
    "%EAB_PY%" -c "import PySide6, zmq, pygame, sounddevice, supertonic" >nul 2>&1
    if errorlevel 1 set "NEED_SETUP=1"
)

if "%NEED_SETUP%"=="1" (
    echo Preparing/repairing the private runtime and Supertonic voice...
    echo This can take several minutes on the first clean run.
    echo Keep this window open. Progress will be shown here.
    echo.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Installer_Runtime_Setup.ps1"
    if errorlevel 1 (
        echo.
        echo SETUP FAILED.
        echo Log: %LOCALAPPDATA%\EliteAIBridge\logs\runtime_setup.log
        echo Leave this window open and send the last error.
        pause
        exit /b 1
    )
)

echo.
echo Launching Elite AI Bridge in diagnostic mode...
echo If the app closes, the actual Python error will remain in this window.
echo.
"%EAB_PY%" "frontend\main.py"
set "EAB_EXIT=%ERRORLEVEL%"
echo.
if not "%EAB_EXIT%"=="0" (
    echo ELITE AI BRIDGE EXITED WITH ERROR CODE %EAB_EXIT%.
    echo.
    pause
)
exit /b %EAB_EXIT%
