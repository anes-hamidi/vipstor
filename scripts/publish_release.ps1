<#
.SYNOPSIS
    Build and publish a VIP Smock app release (Staff / Customer).

.DESCRIPTION
    Builds the selected app for Android, Windows, or Web, packages the
    artifact, uploads it to Supabase Storage ('app-releases'), and registers
    the release in public.app_versions so devices can pick it up.

    Safety features:
      - Fails on non-zero native exit codes (never publishes a stale binary).
      - Deletes stale build outputs before building.
      - Refuses to publish a build_number that is not greater than the latest.
      - Verifies the produced APK versionName/versionCode when aapt is available.
      - Sends UTF-8 JSON (Arabic release notes survive Windows PowerShell 5.1).
      - Checks artifact size against the Supabase per-file limit before upload.
      - Uses curl.exe for large uploads with retries.
      - Verifies that the uploaded object is publicly reachable.

.PARAMETER BuildNumber
    Monotonic build number (Android versionCode). If omitted, the script reads
    the latest published build from app_versions and uses (latest + 1).

.PARAMETER MinSupportedBuild
    Clients with a build number below this value are forced to update.

.PARAMETER AndroidAbi
    Which ABI to embed in the APK. 'universal' builds one APK for all ABIs
    (larger). The other values build a single-ABI APK (smaller).

.PARAMETER MaxUploadMB
    Supabase per-file upload limit for your plan. Free = 50, Pro = 500.

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
    Example: EA:F6:0F:E4:31:1A:B4:38:69:50:E2:01:42:FE:96:9E:EB:20:88:1C:C8:93:31:E6:E8:67:3D:59:47:E2:A9:4C

.PARAMETER AllowDebugSigning
    Allow an Android release signed with the debug keystore. This is unsafe:
    debug keystores are machine-specific, so OTA installs from another machine
    fail with INSTALL_FAILED_UPDATE_INCOMPATIBLE.

.EXAMPLE
    .\scripts\publish_release.ps1 -AppType staff_app -Platform android -Version 1.1.0
    .\scripts\publish_release.ps1 -AppType staff_app -Platform windows -Version 1.1.0 -MinSupportedBuild 2 -IsMandatory
    .\scripts\publish_release.ps1 -AppType customer_app -Platform web -Version 1.1.0
    .\scripts\publish_release.ps1 -AppType staff_app -Platform android -Version 1.1.0 -AndroidAbi universal -MaxUploadMB 500
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

function Get-AppConstantValue {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $constantsPath = Join-Path $RepoRoot 'packages\core\lib\constants\app_constants.dart'
    if (-not (Test-Path -LiteralPath $constantsPath)) { return $null }

    $text = Get-Content -LiteralPath $constantsPath -Raw
    $pattern = [regex]::Escape($Name) + "\s*=\s*['""]([^'""]+)['""]"
    $match = [regex]::Match($text, $pattern)
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Get-SupabaseUrlFromAppConstants {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    return Get-AppConstantValue -RepoRoot $RepoRoot -Name 'supabaseUrl'
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
Write-Host ('Upload limit    : {0} MB' -f $MaxUploadMB)
Write-Host ('Source path     : {0}' -f $appDir)
Write-Host '----------------------------------------------------------'

# -----------------------------------------------------------------------------
# 2. Supabase credentials
#    SUPABASE_URL is optional: when the environment variable is missing it is
#    read from packages/core/lib/constants/app_constants.dart.
#    The service role key is never accepted as a parameter (it would leak into
#    shell history and the process list). Use an environment variable or the
#    secure prompt. The anon key in app_constants.dart cannot publish releases.
# -----------------------------------------------------------------------------
$needsSupabase = (-not $SkipDatabase) -or (-not $SkipUpload)
$supabaseUrl = $null
$serviceRoleKey = $null

if ($needsSupabase) {
    $supabaseUrl = $env:SUPABASE_URL
    $serviceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY

    if ([string]::IsNullOrWhiteSpace($supabaseUrl)) {
        $supabaseUrl = Get-SupabaseUrlFromAppConstants -RepoRoot $repoRoot
        if ($supabaseUrl) {
            Write-Ok ('Supabase URL auto-detected from app_constants.dart: {0}' -f $supabaseUrl)
        }
    }

    if ([string]::IsNullOrWhiteSpace($supabaseUrl)) {
        if ($env:CI -eq 'true' -or -not [Environment]::UserInteractive) {
            throw 'SUPABASE_URL is not set and could not be read from packages/core/lib/constants/app_constants.dart.'
        }
        $supabaseUrl = Read-Host 'Enter Supabase Project URL (for example https://xxx.supabase.co)'
    }

    $supabaseUrl = $supabaseUrl.Trim().TrimEnd('/')
    if ($supabaseUrl -notmatch '^https?://[^/]+$') {
        throw ('Invalid SUPABASE_URL: {0}. Use the project base URL only.' -f $supabaseUrl)
    }
    if ($supabaseUrl -match '/rest/v1$') {
        throw 'SUPABASE_URL must not include /rest/v1. Use the project base URL only.'
    }

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
    $anonKey = Get-AppConstantValue -RepoRoot $repoRoot -Name 'supabaseAnonKey'
    if ($anonKey -and $serviceRoleKey -eq $anonKey) {
        throw 'SUPABASE_SERVICE_ROLE_KEY contains the anon key from app_constants.dart. Publishing requires the service_role key from Supabase Project Settings > API.'
    }

    Write-Ok ('Supabase project: {0}' -f $supabaseUrl)
}

function Invoke-SupabaseRest {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $false)][object]$Body = $null,
        [Parameter(Mandatory = $false)][string]$Prefer
    )

    $headers = @{
        'apikey'        = $serviceRoleKey
        'Authorization' = ('Bearer ' + $serviceRoleKey)
        'Accept'        = 'application/json'
    }
    if ($Prefer) { $headers['Prefer'] = $Prefer }

    $request = @{
        Uri        = $Uri
        Method     = $Method
        Headers    = $headers
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
        return Invoke-RestMethod @request
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
                    throw 'apksigner was not found, so -AllowedSignerSha256 could not be verified. Install the Android SDK build-tools or omit the pin.'
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

            Invoke-NativeCommand -Command $flutterCmd.Source -Arguments @(
                'build', 'windows', '--release',
                ('--build-name=' + $Version),
                ('--build-number=' + $BuildNumber)
            ) -WorkingDirectory $appDir

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
    throw ('Artifact is {0:N2} MB, above the {1} MB upload limit. Supabase Free allows 50 MB per file. Use a smaller ABI (-AndroidAbi arm64-v8a), reduce the app size, or pass -MaxUploadMB only if your plan allows it.' -f $fileSizeMB, $MaxUploadMB)
}

# -----------------------------------------------------------------------------
# 7. Upload to Supabase Storage
# -----------------------------------------------------------------------------
$objectPath = ('{0}/{1}' -f $storageFolder, $fileName)
$uploadUri = ('{0}/storage/v1/object/app-releases/{1}' -f $supabaseUrl, $objectPath)
$publicUrl = ('{0}/storage/v1/object/public/app-releases/{1}' -f $supabaseUrl, $objectPath)

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
                '-H', ('Authorization: Bearer ' + $serviceRoleKey),
                '-H', ('Content-Type: ' + $ContentType),
                '-H', 'x-upsert: true',
                '--upload-file', $Path
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
        'apikey'        = $serviceRoleKey
        'Authorization' = ('Bearer ' + $serviceRoleKey)
        'x-upsert'      = 'true'
    }

    try {
        Invoke-RestMethod -Uri $Uri -Method Post -Headers $headers -ContentType $ContentType -InFile $Path -TimeoutSec 900 | Out-Null
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
else {
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



