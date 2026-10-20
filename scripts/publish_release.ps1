<#
.SYNOPSIS
    Local OTA Release Publisher for VIP Smock (Staff & Customer Apps)
.DESCRIPTION
    Builds the target separated Flutter application (Staff App or Customer App)
    for its supported platforms (Android APK, Windows ZIP, or Web bundle),
    uploads the installer to Supabase Storage ('app-releases'), and registers
    the release in public.app_versions.
.EXAMPLE
    .\scripts\publish_release.ps1 -AppType staff_app -Platform windows -Version "1.1.0" -BuildNumber 2
    .\scripts\publish_release.ps1 -AppType staff_app -Platform android -Version "1.1.0" -BuildNumber 2
    .\scripts\publish_release.ps1 -AppType customer_app -Platform android -Version "1.1.0" -BuildNumber 2
    .\scripts\publish_release.ps1 -AppType customer_app -Platform web -Version "1.1.0" -BuildNumber 2
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('staff_app', 'customer_app')]
    [string]$AppType,

    [Parameter(Mandatory = $true)]
    [ValidateSet('android', 'windows', 'web')]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [int]$BuildNumber,

    [Parameter(Mandatory = $false)]
    [switch]$IsMandatory,

    [Parameter(Mandatory = $false)]
    [string]$Notes = "General performance improvements and bug fixes"
)

$ErrorActionPreference = "Stop"

# 1. Enforce App Platform Matrix
if ($AppType -eq 'staff_app' -and $Platform -eq 'web') {
    throw "Staff App only supports 'windows' and 'android'."
}
if ($AppType -eq 'customer_app' -and $Platform -eq 'windows') {
    throw "Customer App only supports 'android' and 'web'."
}

$appDir = Join-Path $PSScriptRoot "..\apps\$AppType"
if (-not (Test-Path $appDir)) {
    throw "Target application directory not found: $appDir"
}

Write-Host "==========================================================" -ForegroundColor Gold
Write-Host "  VIP SMOCK - RELEASE PUBLISHER (MULTI-APP)               " -ForegroundColor Gold
Write-Host "==========================================================" -ForegroundColor Gold
Write-Host "App Target      : $AppType"
Write-Host "Target Platform : $Platform"
Write-Host "Version         : $Version (#$BuildNumber)"
Write-Host "Source Path     : $appDir"
Write-Host "----------------------------------------------------------"

# 2. Supabase Credentials
$supabaseUrl = $env:SUPABASE_URL
$serviceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY
if (-not $supabaseUrl) {
    $supabaseUrl = Read-Host "Enter Supabase Project URL (e.g. https://xxx.supabase.co)"
}
if (-not $serviceRoleKey) {
    $serviceRoleKey = Read-Host "Enter Supabase Service Role Key"
}

# 3. Build Inside the Dedicated App Directory
Push-Location $appDir
try {
    if ($Platform -eq 'android') {
        Write-Host "[1/3] Building Android Release APK for $AppType..." -ForegroundColor Cyan
        flutter build apk --release --split-per-abi --no-tree-shake-icons --build-name=$Version --build-number=$BuildNumber

        $rawFilePath = Join-Path $appDir "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
        if (-not (Test-Path $rawFilePath)) {
            $rawFilePath = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"
        }
        if (-not (Test-Path $rawFilePath)) {
            throw "APK build output not found at $rawFilePath"
        }

        $fileName = "${AppType}_v${Version}_b${BuildNumber}.apk"
        $filePath = Join-Path $appDir "build\$fileName"
        Copy-Item -Path $rawFilePath -Destination $filePath -Force

        $contentType = "application/vnd.android.package-archive"
        $storageFolder = "android"
    }
    elseif ($Platform -eq 'windows') {
        Write-Host "[1/3] Building Windows Desktop Release for $AppType..." -ForegroundColor Cyan
        flutter build windows --release --build-name=$Version --build-number=$BuildNumber

        $winReleaseDir = Join-Path $appDir "build\windows\x64\runner\Release"
        if (-not (Test-Path $winReleaseDir)) {
            throw "Windows build directory not found at $winReleaseDir"
        }

        $fileName = "${AppType}_windows_v${Version}_b${BuildNumber}.zip"
        $filePath = Join-Path $appDir "build\$fileName"
        Write-Host "Compressing Windows Release into $fileName..." -ForegroundColor Cyan
        Compress-Archive -Path "$winReleaseDir\*" -DestinationPath $filePath -Force

        $contentType = "application/zip"
        $storageFolder = "windows"
    }
    elseif ($Platform -eq 'web') {
        Write-Host "[1/3] Building Web Release for $AppType..." -ForegroundColor Cyan
        flutter build web --release --build-name=$Version --build-number=$BuildNumber

        $webReleaseDir = Join-Path $appDir "build\web"
        if (-not (Test-Path $webReleaseDir)) {
            throw "Web build directory not found at $webReleaseDir"
        }

        $fileName = "${AppType}_web_v${Version}_b${BuildNumber}.zip"
        $filePath = Join-Path $appDir "build\$fileName"
        Write-Host "Compressing Web distribution bundle into $fileName..." -ForegroundColor Cyan
        Compress-Archive -Path "$webReleaseDir\*" -DestinationPath $filePath -Force

        $contentType = "application/zip"
        $storageFolder = "web"
    }
}
finally {
    Pop-Location
}

$fileSize = (Get-Item $filePath).Length
$fileSizeMB = [math]::Round($fileSize / (1024 * 1024), 2)
Write-Host "Build complete: $fileName ($fileSizeMB MB)" -ForegroundColor Green

# 4. Upload to Supabase Storage
Write-Host "[2/3] Uploading installer to Supabase Storage ('app-releases')..." -ForegroundColor Cyan
$uploadUri = "$supabaseUrl/storage/v1/object/app-releases/$storageFolder/$fileName"
$publicDownloadUrl = "$supabaseUrl/storage/v1/object/public/app-releases/$storageFolder/$fileName"

$headers = @{
    "Authorization" = "Bearer $serviceRoleKey"
    "Content-Type"  = $contentType
    "x-upsert"      = "true"
}

Invoke-RestMethod -Uri $uploadUri -Method Post -Headers $headers -InFile $filePath
Write-Host "Uploaded successfully to: $publicDownloadUrl" -ForegroundColor Green

# 5. Insert / Upsert into public.app_versions
Write-Host "[3/3] Registering release in public.app_versions table..." -ForegroundColor Cyan
$dbUri = "$supabaseUrl/rest/v1/app_versions"

$body = @{
    app_type            = $AppType
    platform            = $Platform
    version_name        = $Version
    build_number        = $BuildNumber
    min_supported_build = 1
    download_url        = $publicDownloadUrl
    release_notes       = $Notes
    is_mandatory        = [bool]$IsMandatory
    file_size_bytes     = $fileSize
} | ConvertTo-Json

$dbHeaders = @{
    "apikey"        = $serviceRoleKey
    "Authorization" = "Bearer $serviceRoleKey"
    "Content-Type"  = "application/json"
    "Prefer"        = "return=minimal"
}

Invoke-RestMethod -Uri $dbUri -Method Post -Headers $dbHeaders -Body $body
Write-Host "Release registered successfully in database! Devices will now see this update." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Gold
