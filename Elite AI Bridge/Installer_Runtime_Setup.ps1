$ErrorActionPreference = "Stop"
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeRoot = Join-Path $env:LOCALAPPDATA "EliteAIBridge\runtime"
$VenvRoot = Join-Path $RuntimeRoot ".venv"
$VenvPython = Join-Path $VenvRoot "Scripts\python.exe"
$ReadyMarker = Join-Path $RuntimeRoot ".ready"
$LogRoot = Join-Path $env:LOCALAPPDATA "EliteAIBridge\logs"
$SetupLog = Join-Path $LogRoot "runtime_setup.log"
# 2.0.0: the installer window shows $StatusFile live and waits for $DoneFile ("OK" or "FAIL ...").
$StatusFile = Join-Path $LogRoot "runtime_status.txt"
$DoneFile = Join-Path $LogRoot "runtime_done.txt"

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
# Child Python processes write their output straight away, so the live status line keeps up.
$env:PYTHONUNBUFFERED = "1"
# Plain HTTPS downloads for the voice model: steady, visible progress in the cache folder
# (the default Xet transfer stalled with no output on a 2.0.0 test install).
$env:HF_HUB_DISABLE_XET = "1"
try { $Host.UI.RawUI.WindowTitle = "Elite AI Bridge: first-time setup" } catch {}
Remove-Item -Force -ErrorAction SilentlyContinue $StatusFile, $DoneFile
"[$(Get-Date -Format s)] Runtime setup starting" | Set-Content -Path $SetupLog

function Log([string]$Text) {
    Write-Host $Text
    "[$(Get-Date -Format s)] $Text" | Add-Content -Path $SetupLog
}

# One short line for the installer window (and the console when run from START_HERE.bat).
$script:LastStatus = ""
function Status([string]$Text) {
    if ($Text -eq $script:LastStatus) { return }
    $script:LastStatus = $Text
    Write-Host $Text
    try { Set-Content -Path $StatusFile -Value $Text -Encoding ASCII } catch {}
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

function Folder-MB([string]$Path) {
    try {
        if (-not (Test-Path $Path)) { return 0 }
        $sum = (Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if (-not $sum) { return 0 }
        return [int][math]::Round($sum / 1MB)
    } catch { return 0 }
}

# Runs a program in the background, calls $Watch every 1.5 s while it runs, then copies
# its output into the setup log. Returns the exit code. $ArgLine is one pre-quoted string.
function Run-Watched([string]$Exe, [string]$ArgLine, [scriptblock]$Watch, [int]$StallSec = 0) {
    $out = Join-Path $LogRoot "step_out.txt"
    $err = Join-Path $LogRoot "step_err.txt"
    Remove-Item -Force -ErrorAction SilentlyContinue $out, $err
    $p = Start-Process -FilePath $Exe -ArgumentList $ArgLine -NoNewWindow -PassThru `
         -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle   # keeps ExitCode readable after exit (Windows PowerShell quirk)
    $script:Stalled = $false
    $lastProgress = $null
    $lastChange = Get-Date
    while (-not $p.HasExited) {
        $progress = $null
        try { $progress = & $Watch $out } catch {}
        if ($StallSec -gt 0) {
            if ($progress -ne $lastProgress) { $lastProgress = $progress; $lastChange = Get-Date }
            elseif (((Get-Date) - $lastChange).TotalSeconds -gt $StallSec) {
                Log "No progress for $StallSec seconds; stopping this step."
                try { Stop-Process -Id $p.Id -Force } catch {}
                $script:Stalled = $true
                break
            }
        }
        Start-Sleep -Milliseconds 1500
    }
    if ($script:Stalled) { $null = $p.WaitForExit(15000) } else { $p.WaitForExit() }
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) { Get-Content -Path $f -ErrorAction SilentlyContinue | Add-Content -Path $SetupLog }
    }
    return $p.ExitCode
}

# Last "Collecting / Downloading / Installing" line pip printed, shortened for one status line.
function Pip-Line([string]$OutFile) {
    if (-not (Test-Path $OutFile)) { return "" }
    $lines = Get-Content -Path $OutFile -Tail 40 -ErrorAction SilentlyContinue
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $l = ([string]$lines[$i]).Trim()
        if ($l -match '^Downloading (\S+?)-\d.*?\(([^)]+)\)') { return "downloading $($Matches[1]) ($($Matches[2]))" }
        if ($l -match '^Collecting (\S+)') { return "checking $($Matches[1] -replace '[<>=!~;\[].*$','')" }
        if ($l -match '^Installing collected packages') { return "installing (this part can take a minute)" }
    }
    return ""
}

try {
    # A previous failed setup can leave python.exe behind even though half the packages
    # are missing. Never trust the existence of python.exe alone.
    if ((Test-Path $VenvRoot) -and -not (Test-Path $ReadyMarker)) {
        Log "Incomplete runtime from an earlier attempt detected. Rebuilding it cleanly..."
        Remove-Item -Recurse -Force $RuntimeRoot
    }
    New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null

    Status "Step 1 of 4: Looking for Python..."
    $Python = Find-Python
    if (-not $Python) {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) { throw "Python 3.12+ is required and Windows Package Manager is unavailable." }
        Log "Python 3.12 was not found. Installing it with winget..."
        Status "Step 1 of 4: Installing Python 3.12 (about 30 MB)..."
        & winget install --id Python.Python.3.12 --exact --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -ne 0) { throw "Python installation failed." }
        $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
        $Python = Find-Python
        if (-not $Python) { throw "Python installed but is not yet available. Restart Windows and run setup again." }
    }

    if (-not (Test-Path $VenvPython)) {
        Log "Creating the private Bridge runtime in $VenvRoot"
        Status "Step 1 of 4: Creating the Bridge's private runtime..."
        if ($Python[0] -eq "py") { & py $Python[1] -m venv $VenvRoot }
        else { & python -m venv $VenvRoot }
        if ($LASTEXITCODE -ne 0) { throw "Could not create the private Bridge runtime." }
    }

    Log "Updating pip..."
    Status "Step 2 of 4: Preparing the installer for components..."
    $code = Run-Watched $VenvPython "-m pip install --disable-pip-version-check --upgrade pip" { param($o) }
    if ($code -ne 0) { throw "Could not prepare pip." }

    Log "Installing Elite AI Bridge components..."
    Status "Step 2 of 4: Downloading components (about 300 MB)..."
    $req = Join-Path $InstallRoot "requirements.txt"
    # 2.0.0: exact versions. constraints.txt pins every package the runtime pulls in, so a new
    # release of any of them can't change (or break) an install.
    $con = Join-Path $InstallRoot "constraints.txt"
    $pinArg = ""
    if (Test-Path $con) { $pinArg = " -c `"$con`"" }
    $pipStart = Get-Date
    $code = Run-Watched $VenvPython "-m pip install --disable-pip-version-check --progress-bar off -r `"$req`"$pinArg" {
        param($o)
        $what = Pip-Line $o
        $mb = Folder-MB $VenvRoot
        $line = "Step 2 of 4: Downloading and installing components"
        if ($what) { $line += ": $what" }
        if ($mb -gt 0) { $line += ". $mb MB installed so far." }
        Status $line
    }
    if ($code -ne 0) { throw "A required Bridge component failed to install." }

    Log "Validating installed components..."
    Status "Step 3 of 4: Checking the components..."
    $code = Run-Watched $VenvPython "-c `"import PySide6, zmq, pygame, sounddevice, supertonic; print('Runtime imports OK')`"" { param($o) }
    if ($code -ne 0) { throw "The runtime installed, but one or more required modules cannot be imported." }

    Log "Preparing Supertonic neural voice. The first setup can pause here while the model downloads..."
    Status "Step 4 of 4: Downloading the ship's voice..."
    $hf = $env:HF_HOME
    if (-not $hf) { $hf = Join-Path $env:USERPROFILE ".cache\huggingface" }
    $hfStart = Folder-MB $hf
    $code = Run-Watched $VenvPython "-c `"from supertonic import TTS; TTS(model='supertonic-3', auto_download=True); print('Supertonic neural voice ready.')`"" {
        param($o)
        $mb = (Folder-MB $hf) - $hfStart
        if ($mb -gt 0) { Status "Step 4 of 4: Downloading the ship's voice: $mb MB so far..." }
        else { Status "Step 4 of 4: Downloading the ship's voice: starting..." }
        $mb
    } 240
    if ($script:Stalled) { throw "The ship's voice download stopped making progress for 4 minutes." }
    if ($code -ne 0) { throw "Supertonic installed, but its neural voice model could not be prepared." }

    "ready" | Set-Content -Path $ReadyMarker
    Status "All set. Elite AI Bridge is ready."
    Log "Runtime setup completed successfully."
    try { Set-Content -Path $DoneFile -Value "OK" -Encoding ASCII } catch {}
    exit 0
}
catch {
    $msg = $_.Exception.Message
    Log "SETUP FAILED: $msg"
    Status "Setup failed: $msg"
    try { Set-Content -Path $DoneFile -Value "FAIL $msg" -Encoding ASCII } catch {}
    exit 1
}
