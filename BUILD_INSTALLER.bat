@echo off
setlocal
cd /d "%~dp0"
rem Find the Inno Setup compiler: version 6 or 7, all-users or just-me install.
set "ISCC="
for %%D in ("%ProgramFiles(x86)%\Inno Setup 6" "%ProgramFiles%\Inno Setup 6" "%LOCALAPPDATA%\Programs\Inno Setup 6" "%ProgramFiles(x86)%\Inno Setup 7" "%ProgramFiles%\Inno Setup 7" "%LOCALAPPDATA%\Programs\Inno Setup 7") do (
  if not defined ISCC if exist "%%~D\ISCC.exe" set "ISCC=%%~D\ISCC.exe"
)
if not defined ISCC (
  echo Inno Setup is not installed.
  echo Get it free from https://jrsoftware.org/isdl.php, install it, then run this file again.
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
echo Output\Elite_AI_Bridge_Setup_2.0.4.exe
pause
