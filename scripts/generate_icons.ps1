Add-Type -AssemblyName System.Drawing

function New-ResizedBitmap([System.Drawing.Image]$src, [int]$width, [int]$height) {
    $dest = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dest)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.DrawImage($src, 0, 0, $width, $height)
    $g.Dispose()
    return $dest
}

function Save-Png([System.Drawing.Image]$src, [int]$width, [int]$height, [string]$destPath) {
    $dir = [System.IO.Path]::GetDirectoryName($destPath)
    if (-not [System.IO.Directory]::Exists($dir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }
    $resized = New-ResizedBitmap $src $width $height
    $resized.Save($destPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $resized.Dispose()
    Write-Host "Generated PNG: $destPath ($width x $height)"
}

function Save-Ico([System.Drawing.Image]$src, [string]$destPath) {
    $dir = [System.IO.Path]::GetDirectoryName($destPath)
    if (-not [System.IO.Directory]::Exists($dir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $imagesData = @()

    foreach ($s in $sizes) {
        $resized = New-ResizedBitmap $src $s $s
        $ms = New-Object System.IO.MemoryStream
        $resized.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $resized.Dispose()
        $bytes = $ms.ToArray()
        $ms.Dispose()
        $imagesData += ,@($s, $bytes)
    }

    $fs = [System.IO.File]::Create($destPath)
    $bw = New-Object System.IO.BinaryWriter($fs)

    # 1. ICONDIR (6 bytes)
    $bw.Write([uint16]0)                  # Reserved (must be 0)
    $bw.Write([uint16]1)                  # Resource Type (1 for icon)
    $bw.Write([uint16]$imagesData.Count)  # Image count

    # 2. ICONDIRENTRY (16 bytes per image)
    $offset = 6 + ($imagesData.Count * 16)
    foreach ($item in $imagesData) {
        $s = $item[0]
        $bytes = $item[1]
        $iconWidthByte = if ($s -eq 256) { [byte]0 } else { [byte]$s }
        $iconHeightByte = if ($s -eq 256) { [byte]0 } else { [byte]$s }

        $bw.Write($iconWidthByte)             # Width
        $bw.Write($iconHeightByte)            # Height

        $bw.Write([byte]0)                    # Color count (0 = 256 or more)
        $bw.Write([byte]0)                    # Reserved
        $bw.Write([uint16]1)                  # Color Planes
        $bw.Write([uint16]32)                 # Bits per pixel
        $bw.Write([uint32]$bytes.Length)      # Size of image data
        $bw.Write([uint32]$offset)            # Offset of image data
        $offset += $bytes.Length
    }

    # 3. Image Data
    foreach ($item in $imagesData) {
        $bw.Write($item[1])
    }

    $bw.Flush()
    $bw.Close()
    $fs.Dispose()

    Write-Host "Generated ICO: $destPath (Multi-size: 16, 24, 32, 48, 64, 128, 256)"
}

$sourceIconPath = "c:\Users\fethi\Desktop\vipSmock\vip\assets\icons\Millora.png"
if (-not (Test-Path $sourceIconPath)) {
    Write-Error "Source icon not found at $sourceIconPath"
    exit 1
}

$src = [System.Drawing.Image]::FromFile($sourceIconPath)
Write-Host "Loaded source icon: $sourceIconPath ($($src.Width)x$($src.Height))"

# --------------------------------------------------------------------------
# 1. STAFF APP (apps/staff_app)
# --------------------------------------------------------------------------
Write-Host "`n--- Generating Icons for Staff App ---"
# Windows
Save-Ico $src "c:\Users\fethi\Desktop\vipSmock\vip\apps\staff_app\windows\runner\resources\app_icon.ico"

# Android mipmaps
Save-Png $src 48 48 "c:\Users\fethi\Desktop\vipSmock\vip\apps\staff_app\android\app\src\main\res\mipmap-mdpi\ic_launcher.png"
Save-Png $src 72 72 "c:\Users\fethi\Desktop\vipSmock\vip\apps\staff_app\android\app\src\main\res\mipmap-hdpi\ic_launcher.png"
Save-Png $src 96 96 "c:\Users\fethi\Desktop\vipSmock\vip\apps\staff_app\android\app\src\main\res\mipmap-xhdpi\ic_launcher.png"
Save-Png $src 144 144 "c:\Users\fethi\Desktop\vipSmock\vip\apps\staff_app\android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png"
Save-Png $src 192 192 "c:\Users\fethi\Desktop\vipSmock\vip\apps\staff_app\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png"

# --------------------------------------------------------------------------
# 2. CUSTOMER APP (apps/customer_app)
# --------------------------------------------------------------------------
Write-Host "`n--- Generating Icons for Customer App ---"
# Android mipmaps
Save-Png $src 48 48 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\android\app\src\main\res\mipmap-mdpi\ic_launcher.png"
Save-Png $src 72 72 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\android\app\src\main\res\mipmap-hdpi\ic_launcher.png"
Save-Png $src 96 96 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\android\app\src\main\res\mipmap-xhdpi\ic_launcher.png"
Save-Png $src 144 144 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png"
Save-Png $src 192 192 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png"

# Web icons
Save-Png $src 32 32 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\web\favicon.png"
Save-Png $src 192 192 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\web\icons\Icon-192.png"
Save-Png $src 512 512 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\web\icons\Icon-512.png"
Save-Png $src 192 192 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\web\icons\Icon-maskable-192.png"
Save-Png $src 512 512 "c:\Users\fethi\Desktop\vipSmock\vip\apps\customer_app\web\icons\Icon-maskable-512.png"

# --------------------------------------------------------------------------
# 3. ROOT REPO (vip) - for Android, Windows, Web, iOS, macOS
# --------------------------------------------------------------------------
Write-Host "`n--- Generating Icons for Root App ---"
# Windows
Save-Ico $src "c:\Users\fethi\Desktop\vipSmock\vip\windows\runner\resources\app_icon.ico"

# Android mipmaps
Save-Png $src 48 48 "c:\Users\fethi\Desktop\vipSmock\vip\android\app\src\main\res\mipmap-mdpi\ic_launcher.png"
Save-Png $src 72 72 "c:\Users\fethi\Desktop\vipSmock\vip\android\app\src\main\res\mipmap-hdpi\ic_launcher.png"
Save-Png $src 96 96 "c:\Users\fethi\Desktop\vipSmock\vip\android\app\src\main\res\mipmap-xhdpi\ic_launcher.png"
Save-Png $src 144 144 "c:\Users\fethi\Desktop\vipSmock\vip\android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png"
Save-Png $src 192 192 "c:\Users\fethi\Desktop\vipSmock\vip\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png"

# Web icons
Save-Png $src 32 32 "c:\Users\fethi\Desktop\vipSmock\vip\web\favicon.png"
Save-Png $src 192 192 "c:\Users\fethi\Desktop\vipSmock\vip\web\icons\Icon-192.png"
Save-Png $src 512 512 "c:\Users\fethi\Desktop\vipSmock\vip\web\icons\Icon-512.png"
Save-Png $src 192 192 "c:\Users\fethi\Desktop\vipSmock\vip\web\icons\Icon-maskable-192.png"
Save-Png $src 512 512 "c:\Users\fethi\Desktop\vipSmock\vip\web\icons\Icon-maskable-512.png"

# iOS icons
if (Test-Path "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset") {
    Save-Png $src 1024 1024 "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-1024x1024@1x.png"
    Save-Png $src 167 167   "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-83.5x83.5@2x.png"
    Save-Png $src 152 152   "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@2x.png"
    Save-Png $src 76 76     "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@1x.png"
    Save-Png $src 180 180   "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@3x.png"
    Save-Png $src 120 120   "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@2x.png"
    Save-Png $src 120 120   "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@3x.png"
    Save-Png $src 80 80     "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@2x.png"
    Save-Png $src 40 40     "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@1x.png"
    Save-Png $src 87 87     "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@3x.png"
    Save-Png $src 58 58     "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@2x.png"
    Save-Png $src 29 29     "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@1x.png"
    Save-Png $src 60 60     "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@3x.png"
    Save-Png $src 40 40     "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@2x.png"
    Save-Png $src 20 20     "c:\Users\fethi\Desktop\vipSmock\vip\ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@1x.png"
}

# macOS icons
if (Test-Path "c:\Users\fethi\Desktop\vipSmock\vip\macos\Runner\Assets.xcassets\AppIcon.appiconset") {
    Save-Png $src 16 16     "c:\Users\fethi\Desktop\vipSmock\vip\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_16.png"
    Save-Png $src 32 32     "c:\Users\fethi\Desktop\vipSmock\vip\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_32.png"
    Save-Png $src 64 64     "c:\Users\fethi\Desktop\vipSmock\vip\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_64.png"
    Save-Png $src 128 128   "c:\Users\fethi\Desktop\vipSmock\vip\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_128.png"
    Save-Png $src 256 256   "c:\Users\fethi\Desktop\vipSmock\vip\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_256.png"
    Save-Png $src 512 512   "c:\Users\fethi\Desktop\vipSmock\vip\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_512.png"
    Save-Png $src 1024 1024 "c:\Users\fethi\Desktop\vipSmock\vip\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_1024.png"
}

$src.Dispose()
Write-Host "`nAll platform icons successfully generated from Millora.png!"
