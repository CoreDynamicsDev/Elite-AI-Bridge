@echo off
setlocal
cd /d "%~dp0"
set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (
  echo Inno Setup 6 is not installed.
  echo Install Inno Setup 6, then run this file again.
  pause
  exit /b 1
)
"%ISCC%" "Elite_AI_Bridge_Setup.iss"
if errorlevel 1 (
  echo Installer compilation failed.
  pause
  exit /b 1
)
echo.
echo COMPLETE:
echo Output\Elite_AI_Bridge_Setup_1.0.exe
pause
