<#
.SYNOPSIS
    Build and publish a VIP Smock app release (Staff / Customer).

.DESCRIPTION
    Builds the selected app for Android, Windows, or Web, packages the
    artifact, publishes it to GitHub Releases (default), and registers the
    release in public.app_versions so devices can pick it up.

    Hosting:
      Release binaries no longer need to live in Supabase Storage. The default
      host is GitHub Releases, which has no 50 MB Free-tier cap and no egress
      charges. Supabase keeps only the app_versions row (a few hundred bytes).
      Use -ReleaseHost supabase to restore the old behavior.

    Safety features:
      - Fails on non-zero native exit codes (never publishes a stale binary).
      - Deletes stale build outputs before building.
      - Refuses to publish a build_number that is not greater than the latest.
      - Verifies the produced APK versionName/versionCode when aapt is available.
      - Verifies the APK signing certificate; android/key.properties pins it via signerSha256.
      - Sends UTF-8 JSON (Arabic release notes survive Windows PowerShell 5.1).
      - Checks artifact size against the selected host's per-file limit before upload.
      - Uses curl.exe for large uploads with retries.
      - Verifies that the published artifact is publicly reachable.

    Supabase configuration:
      The Flutter apps read SUPABASE_URL and SUPABASE_ANON_KEY through
      String.fromEnvironment. This script resolves both values from an
      environment variable or .env at the repository root. There is no
      compiled fallback. Both values are passed to every build as
      --dart-define, so the app and the release row always point at the same
      project.

          # .env (git-ignored)
          SUPABASE_URL=https://<project>.supabase.co
          SUPABASE_ANON_KEY=<anon public key>
          SUPABASE_SERVICE_ROLE_KEY=<service role key>

      Existing environment variables win, so CI secrets are never overridden
      by a local .env file. The anon key is public and safe to embed. The
      service key is only used for release publishing and is never passed to
      Flutter. Both legacy service_role JWTs and new sb_secret_... keys are
      supported; opaque keys are sent only in the apikey header because
      Supabase rejects them in Authorization.

    GitHub configuration (default release host):
      The repository must be PUBLIC, because the in-app updater downloads the
      asset without credentials. Create a token with "Contents: Read and write"
      (fine-grained) or the "repo" scope (classic) and expose it as
      GITHUB_TOKEN / GH_TOKEN, or add it to .env at the repository root:

          # .env (git-ignored)
          GITHUB_TOKEN=github_pat_...

      The repository is auto-detected from the git origin remote. Override it
      with -GitHubRepo owner/name. Each build is published as its own GitHub
      release tagged "<app>-<platform>-v<version>-b<build>", and the asset's
      browser_download_url is written to app_versions.download_url.

.PARAMETER BuildNumber
    Monotonic build number (Android versionCode). If omitted, the script reads
    the latest published build from app_versions and uses (latest + 1).

.PARAMETER MinSupportedBuild
    Clients with a build number below this value are forced to update.

.PARAMETER AndroidAbi
    Which ABI to embed in the APK. 'universal' builds one APK for all ABIs
    (larger). The other values build a single-ABI APK (smaller).

.PARAMETER ReleaseHost
    Where the artifact is stored: 'github' (default) or 'supabase'.
    GitHub Releases has no 50 MB Free-tier cap and no egress charges.
    Supabase Storage keeps the legacy behavior (Free plan caps at 50 MB per
    file and 1 GB total).

.PARAMETER GitHubRepo
    Repository that receives the release, as owner/name. Defaults to the
    origin remote of the current git repository.

.PARAMETER GitHubToken
    Token with permission to create releases and upload assets. Defaults to
    GITHUB_TOKEN, then GH_TOKEN. Never pass this on a shared shell history;
    prefer the environment variable or .env.

.PARAMETER GitHubTag
    Override the release tag. Defaults to
    "<app>-<platform>-v<version>-b<build>".

.PARAMETER MaxUploadMB
    Per-file upload limit for the selected host. Defaults to 2048 MB on GitHub
    and 50 MB on Supabase (Free plan). Pro allows 500 MB on Supabase.

.PARAMETER NotesFile
    Optional UTF-8 text file with release notes. Overrides -Notes.

.PARAMETER SkipDatabase
    Build/package/upload without reading or writing app_versions.

.PARAMETER SkipUpload
    Build/package only. Requires -SkipDatabase.

.PARAMETER SkipBuild
    Reuse the already-packaged artifact (for retrying a failed upload).

.PARAMETER AllowRebuild
    Allow replacing the artifact for the latest existing build number.
    Devices already on that build will NOT be prompted to update.

.PARAMETER AllowedSignerSha256
    Pin the APK signing certificate by its SHA-256 fingerprint. When set, the
    script fails if the produced APK is signed by a different key, which
    prevents CI runners from silently using their own debug keystore.
    When omitted, the signerSha256 entry from android/key.properties is used
    as the pin if that file defines one.
    Example: EA:F6:0F:E4:31:1A:B4:38:69:50:E2:01:42:FE:96:9E:EB:20:88:1C:C8:93:31:E6:E8:67:3D:59:47:E2:A9:4C

.PARAMETER AllowDebugSigning
    Allow an Android release signed with the debug keystore. This is unsafe:
    debug keystores are machine-specific, so OTA installs from another machine
    fail with INSTALL_FAILED_UPDATE_INCOMPATIBLE.

.EXAMPLE
    .\scripts\publish_release.ps1 -AppType staff_app -Platform android -Version 1.1.0
    .\scripts\publish_release.ps1 -AppType staff_app -Platform windows -Version 1.1.0 -MinSupportedBuild 2 -IsMandatory
    .\scripts\publish_release.ps1 -AppType customer_app -Platform web -Version 1.1.0
    .\scripts\publish_release.ps1 -AppType staff_app -Platform android -Version 1.1.0 -ReleaseHost supabase -MaxUploadMB 500
    .\scripts\publish_release.ps1 -AppType staff_app -Platform android -Version 1.1.0 -GitHubRepo anes-hamidi/vipstor
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('staff_app', 'customer_app')]
    [string]$AppType,

    [Parameter(Mandatory = $true)]
    [ValidateSet('android', 'windows', 'web')]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 2100000000)]
    [int]$BuildNumber = 0,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 2100000000)]
    [int]$MinSupportedBuild = 1,

    [Parameter(Mandatory = $false)]
    [switch]$IsMandatory,

    [Parameter(Mandatory = $false)]
    [string]$Notes = 'General performance improvements and bug fixes',

    [Parameter(Mandatory = $false)]
    [string]$NotesFile,

    [Parameter(Mandatory = $false)]
    [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal')]
    [string]$AndroidAbi = 'arm64-v8a',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 2048)]
    [int]$MaxUploadMB = 50,

    [Parameter(Mandatory = $false)]
    [ValidateSet('github', 'supabase')]
    [string]$ReleaseHost = 'github',

    [Parameter(Mandatory = $false)]
    [string]$GitHubRepo,

    [Parameter(Mandatory = $false)]
    [string]$GitHubToken,

    [Parameter(Mandatory = $false)]
    [string]$GitHubTag,

    [Parameter(Mandatory = $false)]
    [string]$AllowedSignerSha256,

    [Parameter(Mandatory = $false)]
    [string]$WebBaseHref,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDatabase,

    [Parameter(Mandatory = $false)]
    [switch]$SkipUpload,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild,

    [Parameter(Mandatory = $false)]
    [switch]$AllowRebuild,

    [Parameter(Mandatory = $false)]
    [switch]$AllowDebugSigning,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

trap {
    Write-Host ''
    Write-Host ('RELEASE FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray
    }
    exit 1
}

$script:StartedAt = Get-Date

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message) -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host ('  OK    {0}' -f $Message) -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host ('  WARN  {0}' -f $Message) -ForegroundColor Yellow
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $false)][string]$WorkingDirectory = (Get-Location).Path
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $Command @Arguments
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
        if ($exitCode -ne 0) {
            throw ("'{0} {1}' failed with exit code {2}." -f $Command, ($Arguments -join ' '), $exitCode)
        }
    }
    finally {
        Pop-Location
    }
}

function Get-ZipEntryNames {
    param([Parameter(Mandatory = $true)][string]$ZipPath)

    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        return @($archive.Entries | ForEach-Object { $_.FullName })
    }
    finally {
        $archive.Dispose()
    }
}

function New-ZipFromDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force
    }
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $SourceDirectory,
        $DestinationPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )
}

function Test-PublicUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $status = & $curl.Source -sS -o NUL -w '%{http_code}' -I -L $Url
        if ($LASTEXITCODE -ne 0) { return $false }
        $statusCode = [int]$status
        if ($statusCode -eq 200) { return $true }
        if ($statusCode -eq 405) {
            $rangeStatus = & $curl.Source -sS -o NUL -w '%{http_code}' -L -r 0-0 $Url
            if ($LASTEXITCODE -ne 0) { return $false }
            return ([int]$rangeStatus -eq 200 -or [int]$rangeStatus -eq 206)
        }
        return $false
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 60
        return ($response.StatusCode -eq 200)
    }
    catch {
        return $false
    }
}

function Get-SupabaseProjectRef {
    param([Parameter(Mandatory = $false)][string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    if ($Url -match '^https?://([a-z0-9]+)\.supabase\.(co|in)$') { return $Matches[1] }
    return $null
}

function Get-SupabaseJwtProjectRef {
    param([Parameter(Mandatory = $false)][string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key)) { return $null }
    $parts = $Key.Split('.')
    if ($parts.Count -lt 2) { return $null }

    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    while ($payload.Length % 4 -ne 0) { $payload += '=' }

    try {
        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
        $claims = $json | ConvertFrom-Json
        if ($claims.PSObject.Properties.Name -contains 'ref') { return [string]$claims.ref }
    }
    catch { }

    return $null
}

function Test-SupabaseJwtKey {
    param([Parameter(Mandatory = $false)][string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    return ($Key.Split('.').Count -eq 3)
}

function Import-DotEnvFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][switch]$PreserveExisting
    )

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    $loaded = @()
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { continue }

        $name = $Matches[1]
        $value = $Matches[2].Trim()

        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            else {
                # Allow "KEY=value # comment" for unquoted values.
                $value = ($value -replace '\s+#.*$', '').Trim()
            }
        }

        if ([string]::IsNullOrWhiteSpace($value)) { continue }

        if ($PreserveExisting -and -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            continue
        }

        if (($name -in @('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY')) -and
            ($value -match 'REPLACE[_-]?ME|YOUR[_-]|CHANGEME')) {
            throw ('The .env value for {0} is still a placeholder. Fill in the real value from Supabase Project Settings > API.' -f $name)
        }

        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        $loaded += $name
    }

    return $loaded
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

# -----------------------------------------------------------------------------
# 1. Validate the app/platform matrix and inputs
# -----------------------------------------------------------------------------
$appMatrix = @{
    staff_app    = @('android', 'windows')
    customer_app = @('android', 'web')
}

if ($appMatrix[$AppType] -notcontains $Platform) {
    throw ("{0} does not support platform '{1}'. Allowed: {2}." -f $AppType, $Platform, ($appMatrix[$AppType] -join ', '))
}

if ($SkipUpload -and -not $SkipDatabase) {
    throw '-SkipUpload requires -SkipDatabase (the database row would point at a file that was never uploaded).'
}

if ($SkipBuild -and $SkipUpload -and $SkipDatabase) {
    throw 'Nothing to do: -SkipBuild, -SkipUpload, and -SkipDatabase were all set.'
}

if ($WebBaseHref -and ($WebBaseHref -notmatch '^/.*/$')) {
    throw '-WebBaseHref must start and end with "/" (for example /app/).'
}

if ($NotesFile) {
    $notesPath = (Resolve-Path -LiteralPath $NotesFile).Path
    $Notes = Get-Content -LiteralPath $notesPath -Raw -Encoding UTF8
    if ($null -eq $Notes) { $Notes = '' }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot ('apps\' + $AppType)
if (-not (Test-Path -LiteralPath $appDir)) {
    throw ('Application directory not found: {0}' -f $appDir)
}

$platformDir = Join-Path $appDir $Platform
if (-not (Test-Path -LiteralPath $platformDir)) {
    throw ('The {0} runner directory does not exist: {1}' -f $Platform, $platformDir)
}

if ($ReleaseHost -eq 'github' -and -not $PSBoundParameters.ContainsKey('MaxUploadMB')) {
    # GitHub allows 2 GB per release asset. Leave headroom for the API limit.
    $MaxUploadMB = 2048
}

Write-Host '==========================================================' -ForegroundColor Yellow
Write-Host '  VIP SMOCK - RELEASE PUBLISHER (MULTI-APP)' -ForegroundColor Yellow
Write-Host '==========================================================' -ForegroundColor Yellow
Write-Host ('App target      : {0}' -f $AppType)
Write-Host ('Target platform : {0}' -f $Platform)
Write-Host ('Version         : {0}' -f $Version)
Write-Host ('Build number    : {0}' -f $(if ($BuildNumber -gt 0) { $BuildNumber } else { '(auto)' }))
Write-Host ('Min supported   : {0}' -f $MinSupportedBuild)
Write-Host ('Mandatory       : {0}' -f $IsMandatory.IsPresent)
Write-Host ('Android ABI     : {0}' -f $AndroidAbi)
Write-Host ('Release host    : {0}' -f $ReleaseHost)
Write-Host ('Upload limit    : {0} MB' -f $MaxUploadMB)
Write-Host ('Source path     : {0}' -f $appDir)
Write-Host '----------------------------------------------------------'

# Local development configuration. Existing environment variables win, so CI
# secrets are never overridden by a developer's .env file.
$dotEnvValues = @(Import-DotEnvFile -Path (Join-Path $repoRoot '.env') -PreserveExisting)
if ($dotEnvValues.Count -gt 0) {
    Write-Ok ('Loaded local configuration from .env: {0}' -f ($dotEnvValues -join ', '))
}

# -----------------------------------------------------------------------------
# 2. Supabase configuration
#    Environment variables win; otherwise .env in the repository root supplies
#    SUPABASE_URL and SUPABASE_ANON_KEY. There is no compiled fallback. Both
#    values are passed to Flutter as --dart-define, so the built app and the
#    release row cannot drift to different projects.
#    The service role key is never accepted as a parameter (it would leak into
#    shell history and the process list). Use an environment variable or the
#    secure prompt. It is never passed to Flutter.
# -----------------------------------------------------------------------------
$needsSupabase = (-not $SkipDatabase) -or ((-not $SkipUpload) -and $ReleaseHost -eq 'supabase')
$supabaseUrl = $env:SUPABASE_URL
$supabaseAnonKey = $env:SUPABASE_ANON_KEY
$serviceRoleKey = $null

if ((-not $SkipBuild -or $needsSupabase) -and [string]::IsNullOrWhiteSpace($supabaseUrl)) {
    if ($env:CI -eq 'true' -or -not [Environment]::UserInteractive) {
        throw 'SUPABASE_URL is not set. Add it to .env in the repository root or set it as an environment variable.'
    }
    $supabaseUrl = Read-Host 'Enter Supabase Project URL (for example https://xxx.supabase.co)'
}

if (-not $SkipBuild -and [string]::IsNullOrWhiteSpace($supabaseAnonKey)) {
    throw 'SUPABASE_ANON_KEY is not set. Add it to .env in the repository root or set it as an environment variable.'
}

if (-not [string]::IsNullOrWhiteSpace($supabaseAnonKey)) {
    $supabaseAnonKey = $supabaseAnonKey.Trim()
}

if (-not [string]::IsNullOrWhiteSpace($supabaseUrl)) {
    $supabaseUrl = $supabaseUrl.Trim().TrimEnd('/')
    if ($supabaseUrl -notmatch '^https?://[^/]+$') {
        throw ('Invalid SUPABASE_URL: {0}. Use the project base URL only.' -f $supabaseUrl)
    }
    if ($supabaseUrl -match '/rest/v1$') {
        throw 'SUPABASE_URL must not include /rest/v1. Use the project base URL only.'
    }
}

# Catch a half-finished project switch: the URL points at one project while a
# key still belongs to another. The ref claim exists in legacy JWT keys only;
# newer publishable keys skip this check.
$urlProjectRef = Get-SupabaseProjectRef -Url $supabaseUrl
$anonProjectRef = Get-SupabaseJwtProjectRef -Key $supabaseAnonKey
if ($urlProjectRef -and $anonProjectRef -and $urlProjectRef -ne $anonProjectRef) {
    throw ('SUPABASE_URL points to project "{0}" but SUPABASE_ANON_KEY belongs to project "{1}". Use the URL and anon key from the same Supabase project.' -f $urlProjectRef, $anonProjectRef)
}

if ($needsSupabase) {
    $serviceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY

    if ([string]::IsNullOrWhiteSpace($serviceRoleKey)) {
        if ($env:CI -eq 'true' -or -not [Environment]::UserInteractive) {
            throw 'SUPABASE_SERVICE_ROLE_KEY is not set. Set it as an environment variable (or a CI secret).'
        }
        try {
            $secureKey = Read-Host 'Enter Supabase Service Role Key' -AsSecureString
        }
        catch {
            throw 'Could not read the service role key interactively. Set SUPABASE_SERVICE_ROLE_KEY instead.'
        }
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        try {
            $serviceRoleKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    if ([string]::IsNullOrWhiteSpace($serviceRoleKey) -or $serviceRoleKey.Length -lt 40) {
        throw 'SUPABASE_SERVICE_ROLE_KEY looks invalid (too short).'
    }

    # The anon key is shipped inside the client app and cannot publish releases
    # (RLS + revoked anon/authenticated writes). Catch that mistake early.
    if ($serviceRoleKey -eq $supabaseAnonKey) {
        throw 'SUPABASE_SERVICE_ROLE_KEY contains the anon key. Publishing requires the service_role key from Supabase Project Settings > API.'
    }

    $serviceProjectRef = Get-SupabaseJwtProjectRef -Key $serviceRoleKey
    if ($urlProjectRef -and $serviceProjectRef -and $urlProjectRef -ne $serviceProjectRef) {
        throw ('SUPABASE_URL points to project "{0}" but SUPABASE_SERVICE_ROLE_KEY belongs to project "{1}". Use credentials from the same Supabase project.' -f $urlProjectRef, $serviceProjectRef)
    }

    Write-Ok ('Supabase project: {0}' -f $supabaseUrl)
}

# -----------------------------------------------------------------------------
# 2b. GitHub Releases configuration (default artifact host)
#     The repository must be public: the in-app updater downloads the asset
#     without credentials. The token is used only by this script.
# -----------------------------------------------------------------------------
$githubApiBase = 'https://api.github.com'
$githubUploadBase = 'https://uploads.github.com'
$githubRepoSlug = $null

function Resolve-GitHubRepoSlug {
    param([Parameter(Mandatory = $false)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $v = $Value.Trim()

    $remote = [regex]::Match($v, 'github\.com[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$')
    if ($remote.Success) { return ('{0}/{1}' -f $remote.Groups[1].Value, $remote.Groups[2].Value) }

    $slug = [regex]::Match($v, '^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$')
    if ($slug.Success) { return $v }

    return $null
}

if (-not $SkipUpload -and $ReleaseHost -eq 'github') {
    Write-Step 'GitHub Releases configuration'

    $repoCandidate = $GitHubRepo
    if ([string]::IsNullOrWhiteSpace($repoCandidate)) {
        # GitHub Actions provides this automatically (owner/repo).
        $repoCandidate = Resolve-GitHubRepoSlug -Value ([string]$env:GITHUB_REPOSITORY)
    }
    if ([string]::IsNullOrWhiteSpace($repoCandidate)) {
        $gitCmd = Get-Command git -ErrorAction SilentlyContinue
        if ($gitCmd) {
            $remoteUrl = (& $gitCmd.Source config --get remote.origin.url 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $repoCandidate = Resolve-GitHubRepoSlug -Value ([string]$remoteUrl)
            }
        }
    }
    else {
        $repoCandidate = Resolve-GitHubRepoSlug -Value $repoCandidate
    }

    if ([string]::IsNullOrWhiteSpace($repoCandidate)) {
        throw 'Could not determine the GitHub repository. Pass -GitHubRepo owner/name, or run from a clone whose origin is on GitHub.'
    }

    $repoMatch = [regex]::Match($repoCandidate, '^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$')
    if (-not $repoMatch.Success) {
        throw ('Invalid GitHub repository "{0}". Use owner/name.' -f $repoCandidate)
    }
    $githubRepoSlug = $repoCandidate

    if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
        foreach ($tokenVariable in @('GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_RELEASE_TOKEN')) {
            $tokenValue = [Environment]::GetEnvironmentVariable($tokenVariable)
            if (-not [string]::IsNullOrWhiteSpace($tokenValue)) {
                $GitHubToken = $tokenValue.Trim()
                break
            }
        }
    }

    if ($DryRun) {
        Write-Ok ('Repository: {0} (token check skipped for -DryRun)' -f $githubRepoSlug)
    }
    elseif ([string]::IsNullOrWhiteSpace($GitHubToken)) {
        throw 'No GitHub token found. Set GITHUB_TOKEN (Contents: Read and write) in .env or the environment, or pass -GitHubToken.'
    }
    else {
        Write-Ok ('Repository: {0}' -f $githubRepoSlug)
    }
}

if (-not $SkipBuild) {
    $dartDefines = @(
        ('--dart-define=SUPABASE_URL=' + $supabaseUrl),
        ('--dart-define=SUPABASE_ANON_KEY=' + $supabaseAnonKey)
    )
    Write-Ok ('Build configuration: SUPABASE_URL={0} (anon key supplied)' -f $supabaseUrl)
}

function Invoke-SupabaseRest {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $false)][object]$Body = $null,
        [Parameter(Mandatory = $false)][string]$Prefer
    )

    $headers = @{
        'apikey' = $serviceRoleKey
        'Accept' = 'application/json'
    }
    # Legacy service_role keys are JWTs and also work as Bearer tokens. New
    # sb_secret_... keys must be sent only in the apikey header; Supabase's
    # gateway rejects them when they appear in Authorization.
    if (Test-SupabaseJwtKey -Key $serviceRoleKey) {
        $headers['Authorization'] = ('Bearer ' + $serviceRoleKey)
    }
    if ($Prefer) { $headers['Prefer'] = $Prefer }

    $request = @{
        Uri        = $Uri
        Method     = $Method
        Headers    = $headers
        # Windows PowerShell 5.1 sends a browser-like default User-Agent.
        # Supabase rejects sb_secret_... keys from browser-like clients, so
        # identify the publisher explicitly.
        UserAgent  = 'vip-release-publisher/1.0'
        TimeoutSec = 60
    }

    if ($null -ne $Body) {
        # Windows PowerShell 5.1 encodes string bodies as ISO-8859-1/ASCII.
        # Sending UTF-8 bytes keeps Arabic release notes intact.
        $json = $Body | ConvertTo-Json -Depth 6 -Compress
        $request['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
        $request['ContentType'] = 'application/json; charset=utf-8'
    }

    try {
        $response = Invoke-RestMethod @request
    }
    catch {
        $detail = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $detail = $_.ErrorDetails.Message
        }
        elseif ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $detail = $reader.ReadToEnd()
                $reader.Dispose()
            }
            catch { }
        }
        throw ('Supabase {0} {1} failed: {2} {3}' -f $Method, $Uri, $_.Exception.Message, $detail)
    }

    if ($null -eq $response) { return }

    # Windows PowerShell 5.1 returns a JSON array as one pipeline object, so
    # @(Invoke-SupabaseRest ...) would produce a nested array whose [0] is the
    # array itself. Emit the items individually instead.
    if ($response -is [System.Collections.IEnumerable] -and $response -isnot [string]) {
        foreach ($item in $response) { Write-Output $item }
        return
    }

    Write-Output $response
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][object]$Body = $null
    )

    $headers = @{
        'Accept'               = 'application/vnd.github+json'
        'Authorization'        = ('Bearer ' + $GitHubToken)
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    $request = @{
        Uri        = ($githubApiBase + $Path)
        Method     = $Method
        Headers    = $headers
        UserAgent  = 'vip-release-publisher/1.0'
        TimeoutSec = 60
    }

    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 6 -Compress
        # Windows PowerShell 5.1 would encode a string body as ASCII.
        $request['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
        $request['ContentType'] = 'application/json; charset=utf-8'
    }

    try {
        $response = Invoke-RestMethod @request
    }
    catch {
        $detail = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        throw ('GitHub API {0} {1} failed: {2} {3}' -f $Method, $Path, $_.Exception.Message, $detail)
    }

    if ($null -eq $response) { return }

    # Windows PowerShell 5.1 returns a JSON array as one pipeline object, so
    # @(Invoke-GitHubApi ...) would produce a nested array. Emit items instead.
    if ($response -is [System.Collections.IEnumerable] -and $response -isnot [string]) {
        foreach ($item in $response) { Write-Output $item }
        return
    }

    Write-Output $response
}

function Get-GitHubReleaseByTag {
    param([Parameter(Mandatory = $true)][string]$Tag)

    $path = ('/repos/{0}/releases/tags/{1}' -f $githubRepoSlug, [uri]::EscapeDataString($Tag))
    try {
        return Invoke-GitHubApi -Method 'GET' -Path $path
    }
    catch {
        if ($_.Exception.Message -match '404|Not Found') { return $null }
        throw
    }
}

function New-GitHubRelease {
    param(
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$BodyText
    )

    $payload = [ordered]@{
        tag_name               = $Tag
        name                   = $Title
        body                   = $BodyText
        draft                  = $false
        prerelease             = $false
        generate_release_notes = $false
    }

    return Invoke-GitHubApi -Method 'POST' -Path ('/repos/{0}/releases' -f $githubRepoSlug) -Body $payload
}

function Send-GitHubReleaseAsset {
    param(
        [Parameter(Mandatory = $true)][object]$Release,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ContentType
    )

    $uri = ('{0}/repos/{1}/releases/{2}/assets?name={3}' -f `
            $githubUploadBase, $githubRepoSlug, $Release.id, [uri]::EscapeDataString($Name))

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $responseFile = [System.IO.Path]::GetTempFileName()
        try {
            $curlArgs = @(
                '-sS',
                '--retry', '3',
                '--retry-delay', '2',
                '-o', $responseFile,
                '-w', '%{http_code}',
                '-X', 'POST', $uri,
                '-H', ('Authorization: Bearer ' + $GitHubToken),
                '-H', 'Accept: application/vnd.github+json',
                '-H', 'X-GitHub-Api-Version: 2022-11-28',
                '-H', ('Content-Type: ' + $ContentType),
                '-H', 'User-Agent: vip-release-publisher/1.0',
                '--data-binary', ('@' + $Path)
            )

            $status = & $curl.Source @curlArgs
            $curlExit = $LASTEXITCODE
            $body = ''
            if (Test-Path -LiteralPath $responseFile) {
                $body = Get-Content -LiteralPath $responseFile -Raw
            }

            if ($curlExit -ne 0) {
                throw ('curl failed with exit code {0}: {1}' -f $curlExit, $body)
            }

            $statusCode = [int]$status
            if ($statusCode -lt 200 -or $statusCode -ge 300) {
                if ($statusCode -eq 422 -and $body -match 'already_exists') {
                    throw ('GitHub already has an asset named "{0}" on this release. Re-run with -AllowRebuild.' -f $Name)
                }
                throw ('GitHub asset upload failed with HTTP {0}: {1}' -f $statusCode, $body)
            }

            Write-Ok ('Uploaded with curl (HTTP {0})' -f $statusCode)
            return ($body | ConvertFrom-Json)
        }
        finally {
            Remove-Item -LiteralPath $responseFile -Force -ErrorAction SilentlyContinue
        }
    }

    $headers = @{
        'Authorization'        = ('Bearer ' + $GitHubToken)
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -ContentType $ContentType -InFile $Path -UserAgent 'vip-release-publisher/1.0' -TimeoutSec 900 | Out-Null
        Write-Ok 'Uploaded with Invoke-RestMethod (curl.exe not found)'
        return (Invoke-GitHubApi -Method 'GET' -Path ('/repos/{0}/releases/{1}/assets' -f $githubRepoSlug, $Release.id) |
                Where-Object { $_.name -eq $Name } |
                Select-Object -First 1)
    }
    catch {
        $detail = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        throw ('GitHub asset upload failed: {0} {1}' -f $_.Exception.Message, $detail)
    }
}

# -----------------------------------------------------------------------------
# 3. Preflight: check the latest published build BEFORE spending build time
# -----------------------------------------------------------------------------
$latestRelease = $null
$existingReleaseId = $null

if (-not $SkipDatabase) {
    Write-Step 'Checking the latest published build in app_versions...'

    $query = ('{0}/rest/v1/app_versions?select=id,version_name,build_number,download_url&app_type=eq.{1}&platform=eq.{2}&order=build_number.desc&limit=1' -f $supabaseUrl, $AppType, $Platform)
    try {
        $rows = @(Invoke-SupabaseRest -Method 'GET' -Uri $query)
    }
    catch {
        throw ('Could not read public.app_versions. Check SUPABASE_URL, the service role key, and that migration 00023_app_versions_and_storage.sql has been applied. Details: {0}' -f $_.Exception.Message)
    }

   if ($rows.Count -gt 0 -and $null -ne $rows[0] -and $rows[0].PSObject.Properties.Name -contains 'version_name') {
        $latestRelease = $rows[0]
        Write-Ok ('Latest published: v{0} (build {1})' -f $latestRelease.version_name, $latestRelease.build_number)
    }
    else {
        Write-Ok 'No release has been published for this app/platform yet.'
    }
}

if ($BuildNumber -eq 0) {
    if ($SkipDatabase) {
        throw '-BuildNumber is required when -SkipDatabase is used.'
    }
    if ($latestRelease) {
        $BuildNumber = [int]$latestRelease.build_number + 1
    }
    else {
        $BuildNumber = 1
    }
    if ($BuildNumber -gt 2100000000) {
        throw 'Build number overflow: the latest published build is already 2100000000.'
    }
    Write-Ok ('Auto-selected build number: {0}' -f $BuildNumber)
}

if ($MinSupportedBuild -gt $BuildNumber) {
    throw ('MinSupportedBuild ({0}) cannot be greater than BuildNumber ({1}); clients would be blocked with no newer release available.' -f $MinSupportedBuild, $BuildNumber)
}

if ($latestRelease) {
    $latestBuild = [int]$latestRelease.build_number
    if ($BuildNumber -lt $latestBuild) {
        throw ('BuildNumber {0} is lower than the latest published build {1}. Clients only update when build_number increases.' -f $BuildNumber, $latestBuild)
    }
    if ($BuildNumber -eq $latestBuild) {
        if (-not $AllowRebuild) {
            throw ('Build {0} is already published. Bump -BuildNumber, or pass -AllowRebuild to replace the artifact (devices already on build {0} will not be prompted).' -f $BuildNumber)
        }
        $existingReleaseId = [string]$latestRelease.id
        Write-Warn ('Replacing build {0} in place. Devices already running build {0} will NOT see an update prompt.' -f $BuildNumber)
    }
}

if ($DryRun) {
    Write-Step 'Dry run: no build, upload, or database write will be performed.'
    exit 0
}

# -----------------------------------------------------------------------------
# 4. Toolchain preflight
# -----------------------------------------------------------------------------
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    throw 'flutter was not found on PATH. Install the Flutter SDK and reopen the terminal.'
}

Write-Step 'Toolchain'
Invoke-NativeCommand -Command $flutterCmd.Source -Arguments @('--version') -WorkingDirectory $appDir
Write-Host ('  PowerShell      : {0}' -f $PSVersionTable.PSVersion)
Write-Ok ('Flutter         : {0}' -f $flutterCmd.Source)

if ($Platform -eq 'android') {
    $keyPropertiesPath = Join-Path $appDir 'android\key.properties'
    $hasReleaseKeystore = Test-Path -LiteralPath $keyPropertiesPath

    if ($hasReleaseKeystore) {
        Write-Ok 'Android signing: android/key.properties found (release keystore).'

        # Auto-pin the signer certificate: when key.properties carries a
        # signerSha256 entry, treat it as the expected signer unless the caller
        # passed -AllowedSignerSha256 explicitly. Publishing then fails on any
        # silent signing key change (regenerated keystore, wrong machine, etc.).
        if (-not $AllowedSignerSha256) {
            $keyPropertiesText = Get-Content -LiteralPath $keyPropertiesPath -Raw
            if ($keyPropertiesText -match '(?m)^\s*signerSha256\s*=\s*([0-9A-Fa-f:]{64,95})\s*$') {
                $AllowedSignerSha256 = $Matches[1]
                Write-Ok ('Android signing: signer pinned from key.properties ({0})' -f $AllowedSignerSha256)
            }
            else {
                Write-Warn 'android/key.properties has no signerSha256 entry; the APK signer will not be pinned. Add signerSha256=<certificate SHA-256> to catch accidental signing key changes.'
            }
        }
    }
    else {
        $gradleCandidates = @(
            (Join-Path $appDir 'android\app\build.gradle.kts'),
            (Join-Path $appDir 'android\app\build.gradle')
        ) | Where-Object { Test-Path -LiteralPath $_ }

        foreach ($gradleFile in $gradleCandidates) {
            $gradleText = Get-Content -LiteralPath $gradleFile -Raw
            # Matches both the old hardcoded release config and the conditional
            # fallback used in this repo (release -> debug when key.properties is absent).
            $usesDebugSigning = ($gradleText -match 'getByName\(\s*[''"]debug[''"]\s*\)') -or
                                ($gradleText -match 'signingConfigs\.debug') -or
                                ($gradleText -match 'signingConfig\s*=\s*signingConfigs\.debug')
            if ($usesDebugSigning) {
                Write-Warn 'Android release is signed with the debug keystore.'
                Write-Warn 'Debug keystores are machine-specific: APKs built on another machine or CI runner cannot be installed as an update (INSTALL_FAILED_UPDATE_INCOMPATIBLE), and users would have to uninstall (losing local data).'
                if (-not $AllowDebugSigning) {
                    throw 'Refusing to publish a debug-signed Android release. Configure android/key.properties, or pass -AllowDebugSigning to override.'
                }
                Write-Warn 'Continuing because -AllowDebugSigning was supplied.'
            }
        }
    }
}

if ($Platform -eq 'web' -and $WebBaseHref) {
    Write-Ok ('Web base href  : {0}' -f $WebBaseHref)
}

# -----------------------------------------------------------------------------
# 5. Compute artifact names
# -----------------------------------------------------------------------------
$fileName = $null
$filePath = $null
$contentType = $null
$storageFolder = $null

switch ($Platform) {
    'android' {
        $abiLabel = if ($AndroidAbi -eq 'universal') { 'universal' } else { $AndroidAbi }
        $fileName = ('{0}_{1}_v{2}_b{3}.apk' -f $AppType, $abiLabel, $Version, $BuildNumber)
        $filePath = Join-Path $appDir ('build\' + $fileName)
        $contentType = 'application/vnd.android.package-archive'
        $storageFolder = 'android'
    }
    'windows' {
        $fileName = ('{0}_windows_v{1}_b{2}.zip' -f $AppType, $Version, $BuildNumber)
        $filePath = Join-Path $appDir ('build\' + $fileName)
        $contentType = 'application/zip'
        $storageFolder = 'windows'
    }
    'web' {
        $fileName = ('{0}_web_v{1}_b{2}.zip' -f $AppType, $Version, $BuildNumber)
        $filePath = Join-Path $appDir ('build\' + $fileName)
        $contentType = 'application/zip'
        $storageFolder = 'web'
    }
}

$artifactDir = Split-Path -Parent $filePath
if (-not (Test-Path -LiteralPath $artifactDir)) {
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null
}

if ($SkipBuild) {
    Write-Step 'Skipping build (-SkipBuild)'
    if (-not (Test-Path -LiteralPath $filePath)) {
        throw ('Packaged artifact not found: {0}. Run once without -SkipBuild first.' -f $filePath)
    }
    Write-Ok ('Reusing artifact: {0}' -f $filePath)
}
else {
    if (Test-Path -LiteralPath $filePath) {
        Remove-Item -LiteralPath $filePath -Force
    }

    Write-Step ('Building {0} for {1} (v{2}, build {3})...' -f $AppType, $Platform, $Version, $BuildNumber)
    $buildStarted = Get-Date

    Invoke-NativeCommand -Command $flutterCmd.Source -Arguments @('pub', 'get') -WorkingDirectory $appDir

    switch ($Platform) {
        'android' {
            if ($AndroidAbi -ne 'universal') {
                Write-Warn ('This APK will contain only the {0} ABI. Devices with another ABI cannot install it.' -f $AndroidAbi)
            }

            # Remove old APKs so a failed build can never publish a stale binary.
            $flutterApkDir = Join-Path $appDir 'build\app\outputs\flutter-apk'
            if (Test-Path -LiteralPath $flutterApkDir) {
                Get-ChildItem -LiteralPath $flutterApkDir -Filter '*.apk' -File -ErrorAction SilentlyContinue |
                    Remove-Item -Force
            }

            $buildArgs = @(
                'build', 'apk', '--release',
                '--no-tree-shake-icons',
                ('--build-name=' + $Version),
                ('--build-number=' + $BuildNumber)
            )

            if ($AndroidAbi -ne 'universal') {
                $targetPlatform = @{
                    'arm64-v8a'   = 'android-arm64'
                    'armeabi-v7a' = 'android-arm'
                    'x86_64'      = 'android-x64'
                }[$AndroidAbi]
                $buildArgs += ('--target-platform=' + $targetPlatform)
            }

            $buildArgs += $dartDefines
            Invoke-NativeCommand -Command $flutterCmd.Source -Arguments $buildArgs -WorkingDirectory $appDir

            $rawApk = Join-Path $flutterApkDir 'app-release.apk'
            if (-not (Test-Path -LiteralPath $rawApk)) {
                $splitCandidate = Get-ChildItem -LiteralPath $flutterApkDir -Filter ('app-' + $AndroidAbi + '-release.apk') -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($splitCandidate) { $rawApk = $splitCandidate.FullName }
            }

            if (-not (Test-Path -LiteralPath $rawApk)) {
                $present = @(Get-ChildItem -LiteralPath $flutterApkDir -Filter '*.apk' -File -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty Name)
                throw ('APK output not found in {0}. Files present: {1}' -f $flutterApkDir, ($present -join ', '))
            }

            Copy-Item -LiteralPath $rawApk -Destination $filePath -Force

            # Verify the APK really contains the requested version. This catches
            # stale artifacts even if a tool silently skipped a step.
            $sdkRoot = $env:ANDROID_SDK_ROOT
            if ([string]::IsNullOrWhiteSpace($sdkRoot)) { $sdkRoot = $env:ANDROID_HOME }
            if ([string]::IsNullOrWhiteSpace($sdkRoot) -and $env:LOCALAPPDATA) {
                $sdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
            }

            $aapt = $null
            if ($sdkRoot -and (Test-Path -LiteralPath (Join-Path $sdkRoot 'build-tools'))) {
                $aapt = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending |
                    ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
                    Where-Object { Test-Path -LiteralPath $_ } |
                    Select-Object -First 1
            }

            if ($aapt) {
                $badging = & $aapt dump badging $filePath 2>$null
                if ($LASTEXITCODE -ne 0) {
                    throw 'aapt could not read the produced APK. The artifact may be corrupt.'
                }
                $packageLine = $badging | Where-Object { $_ -match '^package:' } | Select-Object -First 1
                if ($packageLine) {
                    $apkBuild = if ($packageLine -match "versionCode='(\d+)'") { [int]$Matches[1] } else { -1 }
                    $apkVersion = if ($packageLine -match "versionName='([^']+)'") { [string]$Matches[1] } else { '' }
                    if ($apkBuild -ne $BuildNumber) {
                        throw ('APK versionCode {0} does not match the requested build number {1}.' -f $apkBuild, $BuildNumber)
                    }
                    if ($apkVersion -ne $Version) {
                        throw ('APK versionName "{0}" does not match the requested version "{1}".' -f $apkVersion, $Version)
                    }
                    Write-Ok ('APK verified: versionName={0}, versionCode={1}' -f $apkVersion, $apkBuild)
                }
            }
            else {
                Write-Warn 'aapt not found; skipping APK versionName/versionCode verification.'
            }

            # Verify the actual signing certificate. This is what protects OTA:
            # an APK signed by a different key cannot install over the old app.
            $apksigner = $null
            if ($sdkRoot -and (Test-Path -LiteralPath (Join-Path $sdkRoot 'build-tools'))) {
                $apksigner = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending |
                    ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
                    Where-Object { Test-Path -LiteralPath $_ } |
                    Select-Object -First 1
            }

            if ($apksigner) {
                $certOutput = & $apksigner verify --print-certs $filePath
                if ($LASTEXITCODE -ne 0) {
                    throw 'apksigner could not verify the APK signature. The artifact may be unsigned or corrupt.'
                }

                $dnLine = $certOutput | Where-Object { $_ -match 'certificate DN' } | Select-Object -First 1
                $digestLine = $certOutput | Where-Object { $_ -match 'SHA-256 digest' } | Select-Object -First 1
                $signerDigest = ''
                # apksigner prints the digest without separators (64 hex chars), but
                # some versions print colon-separated pairs. Accept either form.
                if ($digestLine -match '([0-9A-Fa-f]{2}(?::?[0-9A-Fa-f]{2}){31})') { $signerDigest = $Matches[1] }

                if ($AllowedSignerSha256) {
                    $expected = ($AllowedSignerSha256 -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
                    $actual = ($signerDigest -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
                    if ([string]::IsNullOrEmpty($actual) -or $actual -ne $expected) {
                        throw ('APK signer SHA-256 is "{0}", but -AllowedSignerSha256 is "{1}". The signing key changed; existing devices will refuse this update.' -f $signerDigest, $AllowedSignerSha256)
                    }
                    Write-Ok ('APK signer matches the pinned SHA-256: {0}' -f $signerDigest)
                }
                elseif ($dnLine -match 'CN=Android Debug') {
                    Write-Warn ('APK is signed with the Android Debug certificate ({0}).' -f $signerDigest)
                    if (-not $AllowDebugSigning -and -not (Test-Path -LiteralPath (Join-Path $appDir 'android\key.properties'))) {
                        throw 'Refusing to publish a debug-signed APK. Configure a release keystore, pin it with -AllowedSignerSha256, or pass -AllowDebugSigning.'
                    }
                }
                else {
                    Write-Ok ('APK signer: {0}' -f $dnLine)
                }
            }
            else {
                if ($AllowedSignerSha256) {
                    throw 'apksigner was not found, so the pinned signer SHA-256 could not be verified. Install the Android SDK build-tools, or remove signerSha256 from android/key.properties (or omit -AllowedSignerSha256) to skip pinning.'
                }
                Write-Warn 'apksigner not found; skipping signature verification.'
            }
        }

        'windows' {
            # Remove the install output so removed plugins/files cannot leak
            # into the ZIP from an older build.
            $windowsBuildRoot = Join-Path $appDir 'build\windows'
            if (Test-Path -LiteralPath $windowsBuildRoot) {
                Get-ChildItem -LiteralPath $windowsBuildRoot -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        Remove-Item -LiteralPath (Join-Path $_.FullName 'runner\Release') -Recurse -Force -ErrorAction SilentlyContinue
                    }
            }

            Invoke-NativeCommand -Command $flutterCmd.Source -Arguments (@(
                'build', 'windows', '--release',
                ('--build-name=' + $Version),
                ('--build-number=' + $BuildNumber)
            ) + $dartDefines) -WorkingDirectory $appDir

            $releaseDirs = @(
                Get-ChildItem -LiteralPath $windowsBuildRoot -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { Join-Path $_.FullName 'runner\Release' } |
                    Where-Object { Test-Path -LiteralPath $_ }
            )
            if ($releaseDirs.Count -eq 0) {
                throw ('Windows release directory not found under {0}' -f $windowsBuildRoot)
            }
            $releaseDir = $releaseDirs[0]

            $exePath = Join-Path $releaseDir ($AppType + '.exe')
            if (-not (Test-Path -LiteralPath $exePath)) {
                throw ('Expected executable not found: {0}' -f $exePath)
            }

            Write-Host ('  Compressing {0}...' -f $releaseDir) -ForegroundColor DarkGray
            New-ZipFromDirectory -SourceDirectory $releaseDir -DestinationPath $filePath

            $entries = Get-ZipEntryNames -ZipPath $filePath
            $exePattern = '(^|[\\/])' + [regex]::Escape($AppType + '.exe') + '$'
            if (-not ($entries | Where-Object { $_ -match $exePattern })) {
                throw ('The Windows ZIP does not contain {0}.exe.' -f $AppType)
            }

            Write-Warn 'Windows updates are delivered as a ZIP. The in-app updater only opens the download URL; it cannot install a ZIP automatically. Use an MSIX/App Installer or an Inno Setup .exe for true OTA.'
        }

        'web' {
            Remove-Item -LiteralPath (Join-Path $appDir 'build\web') -Recurse -Force -ErrorAction SilentlyContinue

            $buildArgs = @(
                'build', 'web', '--release',
                ('--build-name=' + $Version),
                ('--build-number=' + $BuildNumber)
            )
            if ($WebBaseHref) { $buildArgs += ('--base-href=' + $WebBaseHref) }
            $buildArgs += $dartDefines

            Invoke-NativeCommand -Command $flutterCmd.Source -Arguments $buildArgs -WorkingDirectory $appDir

            $webDir = Join-Path $appDir 'build\web'
            if (-not (Test-Path -LiteralPath (Join-Path $webDir 'index.html'))) {
                throw ('Web build output is missing index.html: {0}' -f $webDir)
            }

            $versionFile = Join-Path $webDir 'version.json'
            if (Test-Path -LiteralPath $versionFile) {
                $versionInfo = Get-Content -LiteralPath $versionFile -Raw | ConvertFrom-Json
                if ([string]$versionInfo.version -ne $Version) {
                    throw ('Web version.json reports version "{0}", expected "{1}".' -f $versionInfo.version, $Version)
                }
                if ([string]$versionInfo.build_number -ne [string]$BuildNumber) {
                    throw ('Web version.json reports build "{0}", expected "{1}".' -f $versionInfo.build_number, $BuildNumber)
                }
                Write-Ok ('Web verified: version={0}, build={1}' -f $versionInfo.version, $versionInfo.build_number)
            }
            else {
                Write-Warn 'build/web/version.json not found; skipping web version verification.'
            }

            Write-Host ('  Compressing {0}...' -f $webDir) -ForegroundColor DarkGray
            New-ZipFromDirectory -SourceDirectory $webDir -DestinationPath $filePath

            $entries = Get-ZipEntryNames -ZipPath $filePath
            if (-not ($entries | Where-Object { $_ -match '(^|[\\/])index\.html$' })) {
                throw 'The web ZIP does not contain index.html.'
            }

            Write-Warn 'A web ZIP is not a deployment. Deploy build/web to your web host; registering the ZIP in app_versions only makes the in-app updater download it.'
        }
    }

    $buildMinutes = ((Get-Date) - $buildStarted).TotalMinutes
    Write-Ok ('Build completed in {0:N1} minutes' -f $buildMinutes)
}

# -----------------------------------------------------------------------------
# 6. Artifact checks: size and SHA-256
# -----------------------------------------------------------------------------
$fileSize = (Get-Item -LiteralPath $filePath).Length
$fileSizeMB = [math]::Round($fileSize / 1MB, 2)
$sha256 = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash

Write-Step 'Artifact'
Write-Host ('  Path            : {0}' -f $filePath)
Write-Host ('  Size            : {0} MB ({1} bytes)' -f $fileSizeMB, $fileSize)
Write-Host ('  SHA-256         : {0}' -f $sha256)

$maxBytes = [long]$MaxUploadMB * 1MB
if (-not $SkipUpload -and $fileSize -gt $maxBytes) {
    if ($ReleaseHost -eq 'supabase') {
        throw ('Artifact is {0:N2} MB, above the {1} MB upload limit. Supabase Free allows 50 MB per file. Use a smaller ABI (-AndroidAbi arm64-v8a), switch to -ReleaseHost github, or pass -MaxUploadMB only if your plan allows it.' -f $fileSizeMB, $MaxUploadMB)
    }
    throw ('Artifact is {0:N2} MB, above the {1} MB upload limit. Reduce the app size or raise -MaxUploadMB.' -f $fileSizeMB, $MaxUploadMB)
}

# -----------------------------------------------------------------------------
# 7. Publish the artifact
#    github   -> GitHub Releases (no 50 MB Free-tier cap, no egress charges)
#    supabase -> legacy Supabase Storage bucket 'app-releases'
# -----------------------------------------------------------------------------
$objectPath = $null
$uploadUri = $null
$publicUrl = $null

function Invoke-StorageUpload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ContentType
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $responseFile = [System.IO.Path]::GetTempFileName()
        try {
            $curlArgs = @(
                '-sS',
                '--retry', '3',
                '--retry-delay', '2',
                '-o', $responseFile,
                '-w', '%{http_code}',
                '-X', 'POST', $Uri,
                '-H', ('apikey: ' + $serviceRoleKey),
                '-H', ('Content-Type: ' + $ContentType),
                '-H', 'x-upsert: true',
                '-H', 'User-Agent: vip-release-publisher/1.0',
                '--upload-file', $Path
            )
            if (Test-SupabaseJwtKey -Key $serviceRoleKey) {
                $curlArgs += @('-H', ('Authorization: Bearer ' + $serviceRoleKey))
            }

            $status = & $curl.Source @curlArgs
            $curlExit = $LASTEXITCODE
            $body = ''
            if (Test-Path -LiteralPath $responseFile) {
                $body = Get-Content -LiteralPath $responseFile -Raw
            }

            if ($curlExit -ne 0) {
                throw ('curl failed with exit code {0}: {1}' -f $curlExit, $body)
            }
            $statusCode = [int]$status
            if ($statusCode -lt 200 -or $statusCode -ge 300) {
                if ($statusCode -eq 413) {
                    throw ('Storage rejected the upload as too large (HTTP 413). Raise the plan limit or shrink the artifact. Response: {0}' -f $body)
                }
                if ($body -match 'Bucket not found') {
                    throw ('Storage bucket "app-releases" was not found. Apply migration 00023_app_versions_and_storage.sql. Response: {0}' -f $body)
                }
                throw ('Storage upload failed with HTTP {0}: {1}' -f $statusCode, $body)
            }

            Write-Ok ('Uploaded with curl (HTTP {0})' -f $statusCode)
        }
        finally {
            Remove-Item -LiteralPath $responseFile -Force -ErrorAction SilentlyContinue
        }
        return
    }

    $headers = @{
        'apikey'   = $serviceRoleKey
        'x-upsert' = 'true'
    }
    if (Test-SupabaseJwtKey -Key $serviceRoleKey) {
        $headers['Authorization'] = ('Bearer ' + $serviceRoleKey)
    }

    try {
        Invoke-RestMethod -Uri $Uri -Method Post -Headers $headers -ContentType $ContentType -InFile $Path -UserAgent 'vip-release-publisher/1.0' -TimeoutSec 900 | Out-Null
        Write-Ok 'Uploaded with Invoke-RestMethod (curl.exe not found)'
    }
    catch {
        $detail = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        throw ('Storage upload failed: {0} {1}' -f $_.Exception.Message, $detail)
    }
}

if ($SkipUpload) {
    Write-Step 'Skipping upload (-SkipUpload)'
    Write-Ok ('Artifact kept at {0}' -f $filePath)
}
elseif ($ReleaseHost -eq 'github') {
    Write-Step 'Publishing to GitHub Releases...'

    # OTA downloads are unauthenticated, so a private repository cannot work.
    $repoInfo = Invoke-GitHubApi -Method 'GET' -Path ('/repos/{0}' -f $githubRepoSlug)
    if ($repoInfo.private -eq $true) {
        throw ('Repository {0} is private. GitHub release assets on a private repository cannot be downloaded by the app without a token. Use a public repository or -ReleaseHost supabase.' -f $githubRepoSlug)
    }

    if ([string]::IsNullOrWhiteSpace($GitHubTag)) {
        $GitHubTag = ('{0}-{1}-v{2}-b{3}' -f $AppType, $Platform, $Version, $BuildNumber)
    }
    $releaseTitle = ('{0} {1} v{2} (build {3})' -f $AppType, $Platform, $Version, $BuildNumber)
    $releaseBody = @(
        $Notes,
        '',
        '---',
        ('- App: `{0}`' -f $AppType),
        ('- Platform: `{0}`' -f $Platform),
        ('- Version: `{0}` (build {1})' -f $Version, $BuildNumber),
        ('- Min supported build: {0}' -f $MinSupportedBuild),
        ('- Mandatory: {0}' -f $IsMandatory.IsPresent),
        ('- SHA-256: `{0}`' -f $sha256),
        ('- Size: {0} MB' -f $fileSizeMB)
    ) -join "`n"

    $release = Get-GitHubReleaseByTag -Tag $GitHubTag
    if ($null -eq $release) {
        $release = New-GitHubRelease -Tag $GitHubTag -Title $releaseTitle -BodyText $releaseBody
        Write-Ok ('Created GitHub release {0} (id {1})' -f $GitHubTag, $release.id)
    }
    else {
        Write-Warn ('GitHub release {0} already exists; reusing it.' -f $GitHubTag)
    }

    # GitHub rejects a second asset with the same name (422 already_exists), so
    # remove the old one when a build number is republished with -AllowRebuild.
    $existingAssets = Invoke-GitHubApi -Method 'GET' -Path ('/repos/{0}/releases/{1}/assets' -f $githubRepoSlug, $release.id)
    foreach ($asset in $existingAssets) {
        if ([string]$asset.name -eq $fileName) {
            Invoke-GitHubApi -Method 'DELETE' -Path ('/repos/{0}/releases/assets/{1}' -f $githubRepoSlug, $asset.id) | Out-Null
            Write-Warn ('Deleted the previous asset {0} (id {1}).' -f $asset.name, $asset.id)
        }
    }

    $uploaded = Send-GitHubReleaseAsset -Release $release -Path $filePath -Name $fileName -ContentType $contentType
    if ($null -eq $uploaded -or [string]::IsNullOrWhiteSpace([string]$uploaded.browser_download_url)) {
        throw 'GitHub did not return a browser_download_url for the uploaded asset.'
    }
    $publicUrl = [string]$uploaded.browser_download_url

    Write-Host ('  Public URL      : {0}' -f $publicUrl)

    # GitHub's CDN can take a few seconds to serve a freshly uploaded asset.
    $reachable = $false
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        if (Test-PublicUrl -Url $publicUrl) { $reachable = $true; break }
        Start-Sleep -Seconds (2 * $attempt)
    }
    if (-not $reachable) {
        throw ('The release asset is not publicly reachable at {0}. Confirm the repository is public and the token can write releases.' -f $publicUrl)
    }
    Write-Ok 'Public URL is reachable.'
}
else {
    $objectPath = ('{0}/{1}' -f $storageFolder, $fileName)
    $uploadUri = ('{0}/storage/v1/object/app-releases/{1}' -f $supabaseUrl, $objectPath)
    $publicUrl = ('{0}/storage/v1/object/public/app-releases/{1}' -f $supabaseUrl, $objectPath)

    Write-Step 'Uploading to Supabase Storage (app-releases)...'
    Invoke-StorageUpload -Uri $uploadUri -Path $filePath -ContentType $contentType

    Write-Host ('  Public URL      : {0}' -f $publicUrl)
    if (-not (Test-PublicUrl -Url $publicUrl)) {
        throw ('The uploaded object is not publicly reachable at {0}. Check that the app-releases bucket is public and the storage SELECT policy exists (migration 00023).' -f $publicUrl)
    }
    Write-Ok 'Public URL is reachable.'
}

# -----------------------------------------------------------------------------
# 8. Register the release in public.app_versions
# -----------------------------------------------------------------------------
if ($SkipDatabase) {
    Write-Step 'Skipping database registration (-SkipDatabase)'
}
else {
    Write-Step 'Registering the release in public.app_versions...'

    $payload = [ordered]@{
        app_type            = $AppType
        platform            = $Platform
        version_name        = $Version
        build_number        = $BuildNumber
        min_supported_build = $MinSupportedBuild
        download_url        = $publicUrl
        release_notes       = $Notes
        is_mandatory        = $IsMandatory.IsPresent
        file_size_bytes     = [long]$fileSize
    }

    if ($existingReleaseId) {
        $dbUri = ('{0}/rest/v1/app_versions?id=eq.{1}' -f $supabaseUrl, $existingReleaseId)
        $result = @(Invoke-SupabaseRest -Method 'PATCH' -Uri $dbUri -Body $payload -Prefer 'return=representation')
    }
    else {
        $dbUri = ('{0}/rest/v1/app_versions' -f $supabaseUrl)
        $result = @(Invoke-SupabaseRest -Method 'POST' -Uri $dbUri -Body $payload -Prefer 'return=representation')
    }

    if ($result.Count -eq 0 -or $null -eq $result[0]) {
        throw 'The release was uploaded but the database did not return the created row.'
    }

    $row = $result[0]
    if ([int]$row.build_number -ne $BuildNumber) {
        throw ('Database row has build_number {0}, expected {1}.' -f $row.build_number, $BuildNumber)
    }
    if ([string]$row.download_url -ne $publicUrl) {
        throw ('Database row has download_url "{0}", expected "{1}".' -f $row.download_url, $publicUrl)
    }

    Write-Ok ('Registered release id {0} (v{1}, build {2}).' -f $row.id, $row.version_name, $row.build_number)

    $latestCheck = @(Invoke-SupabaseRest -Method 'GET' -Uri ('{0}/rest/v1/app_versions?select=build_number&app_type=eq.{1}&platform=eq.{2}&order=build_number.desc&limit=1' -f $supabaseUrl, $AppType, $Platform))
    if ($latestCheck.Count -gt 0 -and [int]$latestCheck[0].build_number -ne $BuildNumber) {
        Write-Warn ('The newest row for this app/platform is build {0}, not {1}. Another release may have been published concurrently.' -f $latestCheck[0].build_number, $BuildNumber)
    }
    else {
        Write-Ok 'This is now the latest release for this app/platform.'
    }
}

# -----------------------------------------------------------------------------
# 9. Summary
# -----------------------------------------------------------------------------
$elapsed = ((Get-Date) - $script:StartedAt).TotalMinutes

Write-Host ''
Write-Host '==========================================================' -ForegroundColor Yellow
Write-Host '  RELEASE COMPLETE' -ForegroundColor Green
Write-Host '==========================================================' -ForegroundColor Yellow
Write-Host ('  App / platform  : {0} / {1}' -f $AppType, $Platform)
Write-Host ('  Version         : {0} (build {1})' -f $Version, $BuildNumber)
Write-Host ('  Artifact        : {0}' -f $fileName)
Write-Host ('  Size            : {0} MB' -f $fileSizeMB)
Write-Host ('  SHA-256         : {0}' -f $sha256)
if (-not $SkipUpload) {
    Write-Host ('  Release host    : {0}' -f $ReleaseHost)
    Write-Host ('  Download URL    : {0}' -f $publicUrl)
}
Write-Host ('  Mandatory       : {0}' -f $IsMandatory.IsPresent)
Write-Host ('  Min supported   : {0}' -f $MinSupportedBuild)
Write-Host ('  Duration        : {0:N1} minutes' -f $elapsed)
Write-Host '==========================================================' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
if (-not $SkipDatabase) {
    Write-Host '  - Devices will see the update the next time they check for updates.'
}
if ($Platform -eq 'android') {
    Write-Host '  - Install the APK once on an old build to confirm the signature matches (no INSTALL_FAILED_UPDATE_INCOMPATIBLE).'
}
if ($Platform -eq 'windows') {
    Write-Host '  - The ZIP must be installed manually until an MSIX/Inno Setup installer is produced.'
}
if ($Platform -eq 'web') {
    Write-Host '  - Deploy the contents of build/web to your web host.'
}

exit 0



