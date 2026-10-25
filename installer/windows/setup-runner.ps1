<#
.SYNOPSIS
    One-time setup & verification for the VIP Smock self-hosted runner + Inno Setup.
    Run this on your Windows runner machine (e.g. C:\Users\fethi\actions-runner).

.DESCRIPTION
    - Generates a GUID for the Inno Setup AppId
    - Verifies the GitHub Actions self-hosted runner is configured & running
    - Verifies Inno Setup compiler (ISCC.exe) is installed
    - Verifies Flutter is available (optional)
    - Verifies the Inno Setup template exists in the repo

.NOTES
    Run in PowerShell. No Administrator required unless installing software.
#>

$ErrorActionPreference = "Stop"

Write-Host "=== VIP Smock Runner & Inno Setup Verification ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Generate a GUID for the Inno Setup AppId
# ---------------------------------------------------------------------------
$guid = [guid]::NewGuid()
Write-Host "`n[GUID] Generated AppId:" -ForegroundColor Green
Write-Host "  $guid" -ForegroundColor Yellow
Write-Host "  -> Paste this into installer/windows/vip.iss.template where it says <<GUID>>"

# ---------------------------------------------------------------------------
# 2. Verify GitHub Actions self-hosted runner
# ---------------------------------------------------------------------------
$runnerDir = "C:\users\fethi\actions-runner"
Write-Host "`n[Runner] Checking $runnerDir ..."

if (-not (Test-Path $runnerDir)) {
    Write-Warning "  Runner directory NOT found."
} else {
    Write-Host "  Directory exists." -ForegroundColor Green

    $runnerFile = Join-Path $runnerDir ".runner"
    $credFile   = Join-Path $runnerDir ".credentials"

    if (Test-Path $runnerFile) {
        Write-Host "  .runner exists (configured)." -ForegroundColor Green
        try {
            $cfg = Get-Content $runnerFile | ConvertFrom-Json
            Write-Host "    Agent : $($cfg.agentName)"
            Write-Host "    Repo  : $($cfg.gitHubUrl)"
            Write-Host "    Work  : $($cfg.workFolder)"
        } catch {
            Write-Warning "    Could not parse .runner JSON"
        }
    } else {
        Write-Warning "  .runner NOT found - runner not configured."
    }

    if (Test-Path $credFile) {
        Write-Host "  .credentials exists." -ForegroundColor Green
    } else {
        Write-Warning "  .credentials NOT found."
    }

    $listener = Get-Process -Name "Runner.Listener" -ErrorAction SilentlyContinue
    if ($listener) {
        Write-Host "  Runner.Listener is running (PID $($listener.Id))." -ForegroundColor Green
    } else {
        Write-Warning "  Runner.Listener is NOT running."
        Write-Host "    Start it with: cd `"$runnerDir`" ; .\run.cmd"
    }
}

# ---------------------------------------------------------------------------
# 3. Verify Inno Setup
# ---------------------------------------------------------------------------
$isccPaths = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 5\ISCC.exe",
    "C:\Program Files\Inno Setup 5\ISCC.exe"
)

Write-Host "`n[Inno Setup] Searching for ISCC.exe ..."
$isccFound = $null
foreach ($path in $isccPaths) {
    if (Test-Path $path) {
        $isccFound = $path
        Write-Host "  Found: $path" -ForegroundColor Green
        break
    }
}

if (-not $isccFound) {
    Write-Warning "  Inno Setup compiler (ISCC.exe) not found."
    Write-Host "  Download from: https://jrsoftware.org/is.php" -ForegroundColor Yellow
    Write-Host "  Install, then re-run this script."
} else {
    # ISCC /? exits non-zero; just confirm the binary exists
    Write-Host "  Compiler ready." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 4. Verify Flutter (optional)
# ---------------------------------------------------------------------------
Write-Host "`n[Flutter] Checking ..."
$flutterPaths = @(
    "$env:USERPROFILE\flutter\bin\flutter.bat",
    "C:\src\flutter\bin\flutter.bat",
    "C:\flutter\bin\flutter.bat"
)
$flutterFound = $null
foreach ($p in $flutterPaths) {
    if (Test-Path $p) {
        $flutterFound = $p
        Write-Host "  Found: $p" -ForegroundColor Green
        break
    }
}
if (-not $flutterFound) {
    Write-Warning "  Flutter not found at common paths."
    Write-Host "  The workflow uses subosito/flutter-action to install Flutter automatically."
}

# ---------------------------------------------------------------------------
# 5. Verify Inno Setup template in repo
# ---------------------------------------------------------------------------
$templatePath = "C:\Users\fethi\Desktop\vipSmock\vip\installer\windows\vip.iss.template"
Write-Host "`n[Template] Checking $templatePath ..."
if (Test-Path $templatePath) {
    Write-Host "  Template exists." -ForegroundColor Green
} else {
    Write-Warning "  Template not found."
    Write-Host "  Create installer/windows/vip.iss.template in your repo."
}

# ---------------------------------------------------------------------------
# 6. Summary & next steps
# ---------------------------------------------------------------------------
Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Replace <<GUID>> in vip.iss.template with: $guid"
Write-Host "2. If Inno Setup is missing, install it from https://jrsoftware.org/is.php"
Write-Host "3. Make sure the runner is running: cd `"$runnerDir`" ; .\run.cmd"
Write-Host "4. Trigger the 'Build and Release' workflow on GitHub (Actions tab)."
Write-Host "   Pick a Windows target (e.g. staff_windows)."
