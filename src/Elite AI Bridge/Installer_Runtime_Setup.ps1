$ErrorActionPreference = "Stop"
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvPython = Join-Path $InstallRoot ".venv\Scripts\python.exe"

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

$Python = Find-Python
if (-not $Python) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "Python 3.12+ is required and Windows Package Manager is unavailable."
    }
    & winget install --id Python.Python.3.12 --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "Python installation failed." }
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
    $Python = Find-Python
    if (-not $Python) { throw "Python installed but is not yet available. Restart Windows and run setup again." }
}

if (-not (Test-Path $VenvPython)) {
    if ($Python[0] -eq "py") { & py $Python[1] -m venv (Join-Path $InstallRoot ".venv") }
    else { & python -m venv (Join-Path $InstallRoot ".venv") }
    if ($LASTEXITCODE -ne 0) { throw "Could not create the private Bridge runtime." }
}
& $VenvPython -m pip install --disable-pip-version-check --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "Could not prepare pip." }
& $VenvPython -m pip install --disable-pip-version-check -r (Join-Path $InstallRoot "requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "A required Bridge component failed to install." }
