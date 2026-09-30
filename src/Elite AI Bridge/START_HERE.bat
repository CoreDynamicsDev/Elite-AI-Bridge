@echo off
setlocal
cd /d "%~dp0"
set "EAB_ROOT=%LOCALAPPDATA%\EliteAIBridge"
set "EAB_RUNTIME=%EAB_ROOT%\runtime\.venv"
set "EAB_READY=%EAB_ROOT%\runtime\.ready"
set "EAB_PY=%EAB_RUNTIME%\Scripts\python.exe"
set "NEED_SETUP=0"

echo ============================================
echo         ELITE AI BRIDGE 1.0.1 TEST
echo ============================================
echo.

if not exist "%EAB_READY%" set "NEED_SETUP=1"
if not exist "%EAB_PY%" set "NEED_SETUP=1"

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
) else (
    rem Normal exit: close the launcher window automatically.
)
exit /b %EAB_EXIT%
