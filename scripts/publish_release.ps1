<#
.SYNOPSIS
    Local OTA Release Publisher for VIP Smock POS
.DESCRIPTION
    Builds the Flutter application (Android APK or Windows Desktop), uploads the
    installer to the Supabase Storage bucket 'app-releases', and registers the
    new version in public.app_versions.
.EXAMPLE
    .\scripts\publish_release.ps1 -Platform android -Version "1.1.0" -BuildNumber 15 -Notes "ميزة جديدة لتسوية عهدة السائقين"
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('android', 'windows')]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [int]$BuildNumber,

    [Parameter(Mandatory = $false)]
    [string]$AppType = 'staff_app',

    [Parameter(Mandatory = $false)]
    [switch]$IsMandatory,

    [Parameter(Mandatory = $false)]
    [string]$Notes = "• تحسينات عامة في الأداء والواجهة"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Gold
Write-Host "  VIP SMOCK - PRIVATE OTA RELEASE PUBLISHER               " -ForegroundColor Gold
Write-Host "==========================================================" -ForegroundColor Gold
Write-Host "Target Platform : $Platform"
Write-Host "App Type        : $AppType"
Write-Host "Version         : $Version (#$BuildNumber)"
Write-Host "Mandatory       : $IsMandatory"
Write-Host "----------------------------------------------------------"

# 1. Load Supabase Environment Variables or prompts
$supabaseUrl = $env:SUPABASE_URL
$serviceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY

if (-not $supabaseUrl) {
    $supabaseUrl = Read-Host "Enter Supabase Project URL (e.g. https://xxx.supabase.co)"
}
if (-not $serviceRoleKey) {
    $serviceRoleKey = Read-Host "Enter Supabase Service Role Key"
}

# 2. Build the Project
if ($Platform -eq 'android') {
    Write-Host "[1/3] Building Android Release APK..." -ForegroundColor Cyan
    flutter build apk --release --build-name=$Version --build-number=$BuildNumber

    $filePath = "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $filePath)) {
        throw "APK build output not found at $filePath"
    }

    $fileName = "${AppType}_v${Version}_b${BuildNumber}.apk"
    $contentType = "application/vnd.android.package-archive"
    $storageFolder = "android"
}
elseif ($Platform -eq 'windows') {
    Write-Host "[1/3] Building Windows Desktop Release..." -ForegroundColor Cyan
    flutter build windows --release --build-name=$Version --build-number=$BuildNumber

    $winReleaseDir = "build\windows\x64\runner\Release"
    if (-not (Test-Path $winReleaseDir)) {
        throw "Windows build directory not found at $winReleaseDir"
    }

    $fileName = "${AppType}_windows_v${Version}_b${BuildNumber}.zip"
    $filePath = Join-Path "build" $fileName
    Write-Host "Compressing Windows Release into $fileName..." -ForegroundColor Cyan
    Compress-Archive -Path "$winReleaseDir\*" -DestinationPath $filePath -Force

    $contentType = "application/zip"
    $storageFolder = "windows"
}

$fileSize = (Get-Item $filePath).Length
$fileSizeMB = [math]::Round($fileSize / (1024 * 1024), 2)
Write-Host "Build complete: $fileName ($fileSizeMB MB)" -ForegroundColor Green

# 3. Upload to Supabase Storage
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

# 4. Insert into public.app_versions table
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
Write-Host "Release registered successfully! All devices will now see this update." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Gold
