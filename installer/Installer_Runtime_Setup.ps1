$ErrorActionPreference = "Stop"
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeRoot = Join-Path $env:LOCALAPPDATA "EliteAIBridge\runtime"
$VenvRoot = Join-Path $RuntimeRoot ".venv"
$VenvPython = Join-Path $VenvRoot "Scripts\python.exe"
$ReadyMarker = Join-Path $RuntimeRoot ".ready"
$LogRoot = Join-Path $env:LOCALAPPDATA "EliteAIBridge\logs"
$SetupLog = Join-Path $LogRoot "runtime_setup.log"

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
"[$(Get-Date -Format s)] Runtime setup starting" | Set-Content -Path $SetupLog

function Log([string]$Text) {
    Write-Host $Text
    "[$(Get-Date -Format s)] $Text" | Add-Content -Path $SetupLog
}

function Find-Python {
    try {
        & py -3.12 -c "import sys; assert sys.version_info >= (3,12)" 2>$null
        if ($LASTEXITCODE -eq 0) { return @("py","-3.12") }
    } catch {}
    try {
        & python -c "import sys; assert sys.version_info >= (3,12)" 2>$null
        if ($LASTEXITCODE -eq 0) { return @("python","") }
    } catch {}
    return $null
}

# A previous failed setup can leave python.exe behind even though half the packages
# are missing. Never trust the existence of python.exe alone.
if ((Test-Path $VenvRoot) -and -not (Test-Path $ReadyMarker)) {
    Log "Incomplete runtime from an earlier attempt detected. Rebuilding it cleanly..."
    Remove-Item -Recurse -Force $RuntimeRoot
}

New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null

$Python = Find-Python
if (-not $Python) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { throw "Python 3.12+ is required and Windows Package Manager is unavailable." }
    Log "Python 3.12 was not found. Installing it with winget..."
    & winget install --id Python.Python.3.12 --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "Python installation failed." }
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    $Python = Find-Python
    if (-not $Python) { throw "Python installed but is not yet available. Restart Windows and run setup again." }
}

if (-not (Test-Path $VenvPython)) {
    Log "Creating the private Bridge runtime in $VenvRoot"
    if ($Python[0] -eq "py") { & py $Python[1] -m venv $VenvRoot }
    else { & python -m venv $VenvRoot }
    if ($LASTEXITCODE -ne 0) { throw "Could not create the private Bridge runtime." }
}

Log "Updating pip..."
& $VenvPython -m pip install --disable-pip-version-check --upgrade pip 2>&1 | Tee-Object -FilePath $SetupLog -Append
if ($LASTEXITCODE -ne 0) { throw "Could not prepare pip." }

Log "Installing Elite AI Bridge components..."
& $VenvPython -m pip install --disable-pip-version-check -r (Join-Path $InstallRoot "requirements.txt") 2>&1 | Tee-Object -FilePath $SetupLog -Append
if ($LASTEXITCODE -ne 0) { throw "A required Bridge component failed to install." }

Log "Validating installed components..."
& $VenvPython -c "import PySide6, zmq, pygame, sounddevice, supertonic; print('Runtime imports OK')" 2>&1 | Tee-Object -FilePath $SetupLog -Append
if ($LASTEXITCODE -ne 0) { throw "The runtime installed, but one or more required modules cannot be imported." }

Log "Preparing Supertonic neural voice. The first setup can pause here while the model downloads..."
& $VenvPython -c "from supertonic import TTS; TTS(model='supertonic-3', auto_download=True); print('Supertonic neural voice ready.')" 2>&1 | Tee-Object -FilePath $SetupLog -Append
if ($LASTEXITCODE -ne 0) { throw "Supertonic installed, but its neural voice model could not be prepared." }

"ready" | Set-Content -Path $ReadyMarker
Log "Runtime setup completed successfully."
