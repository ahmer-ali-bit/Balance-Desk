param(
  [string]$SourcePath = (Join-Path $PSScriptRoot '..\App Logo.png')
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function Get-ContentBounds {
  param(
    [System.Drawing.Bitmap]$Bitmap
  )

  $minX = $Bitmap.Width
  $minY = $Bitmap.Height
  $maxX = -1
  $maxY = -1

  for ($y = 0; $y -lt $Bitmap.Height; $y++) {
    for ($x = 0; $x -lt $Bitmap.Width; $x++) {
      $color = $Bitmap.GetPixel($x, $y)
      $signal = $color.R + $color.G + $color.B
      if ($color.A -ge 16 -and ($signal -ge 90 -or $color.G -ge 60)) {
        if ($x -lt $minX) { $minX = $x }
        if ($y -lt $minY) { $minY = $y }
        if ($x -gt $maxX) { $maxX = $x }
        if ($y -gt $maxY) { $maxY = $y }
      }
    }
  }

  if ($maxX -lt 0 -or $maxY -lt 0) {
    return [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
  }

  $paddingX = [Math]::Max(20, [int][Math]::Round(($maxX - $minX + 1) * 0.08))
  $paddingY = [Math]::Max(20, [int][Math]::Round(($maxY - $minY + 1) * 0.08))

  $left = [Math]::Max(0, $minX - $paddingX)
  $top = [Math]::Max(0, $minY - $paddingY)
  $right = [Math]::Min($Bitmap.Width - 1, $maxX + $paddingX)
  $bottom = [Math]::Min($Bitmap.Height - 1, $maxY + $paddingY)

  return [System.Drawing.Rectangle]::new(
    $left,
    $top,
    $right - $left + 1,
    $bottom - $top + 1
  )
}

function New-SquareBitmap {
  param(
    [System.Drawing.Bitmap]$SourceBitmap,
    [System.Drawing.Rectangle]$Crop,
    [int]$Size,
    [System.Drawing.Color]$BackgroundColor
  )

  $target = [System.Drawing.Bitmap]::new(
    $Size,
    $Size,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
  )
  $graphics = [System.Drawing.Graphics]::FromImage($target)

  try {
    $graphics.Clear($BackgroundColor)
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

    $usableSize = $Size * 0.9
    $scale = [Math]::Min($usableSize / $Crop.Width, $usableSize / $Crop.Height)
    $drawWidth = [Math]::Max(1, [int][Math]::Round($Crop.Width * $scale))
    $drawHeight = [Math]::Max(1, [int][Math]::Round($Crop.Height * $scale))
    $destX = [int][Math]::Round(($Size - $drawWidth) / 2)
    $destY = [int][Math]::Round(($Size - $drawHeight) / 2)

    $destRect = [System.Drawing.Rectangle]::new($destX, $destY, $drawWidth, $drawHeight)
    $graphics.DrawImage($SourceBitmap, $destRect, $Crop, [System.Drawing.GraphicsUnit]::Pixel)
  } finally {
    $graphics.Dispose()
  }

  return $target
}

function Save-Png {
  param(
    [System.Drawing.Bitmap]$Bitmap,
    [string]$Path
  )

  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
  }

  $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function New-IcoFile {
  param(
    [byte[][]]$Images,
    [int[]]$Sizes,
    [string]$Destination
  )

  $stream = [System.IO.File]::Create($Destination)
  $writer = [System.IO.BinaryWriter]::new($stream)

  try {
    $count = $Images.Count
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$count)

    $offset = 6 + (16 * $count)

    for ($index = 0; $index -lt $count; $index++) {
      $size = $Sizes[$index]
      $bytes = $Images[$index]

      $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
      $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
      $writer.Write([byte]0)
      $writer.Write([byte]0)
      $writer.Write([UInt16]1)
      $writer.Write([UInt16]32)
      $writer.Write([UInt32]$bytes.Length)
      $writer.Write([UInt32]$offset)

      $offset += $bytes.Length
    }

    foreach ($bytes in $Images) {
      $writer.Write($bytes)
    }
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceFullPath = if ([System.IO.Path]::IsPathRooted($SourcePath)) {
  [System.IO.Path]::GetFullPath($SourcePath)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $repoRoot $SourcePath))
}

if (-not (Test-Path -LiteralPath $sourceFullPath)) {
  throw "Source image not found: $sourceFullPath"
}

$sourceBitmap = [System.Drawing.Bitmap]::FromFile($sourceFullPath)
$background = [System.Drawing.Color]::FromArgb(255, 3, 16, 7)

try {
  $crop = Get-ContentBounds -Bitmap $sourceBitmap

  Copy-Item -LiteralPath $sourceFullPath -Destination (Join-Path $repoRoot 'assets\branding\balance-desk-logo-source.png') -Force

  $iconTargets = @(
    @{ Path = 'assets\branding\balance-desk-app-icon-1024.png'; Size = 1024 }
    @{ Path = 'android\app\src\main\res\mipmap-mdpi\ic_launcher.png'; Size = 48 }
    @{ Path = 'android\app\src\main\res\mipmap-hdpi\ic_launcher.png'; Size = 72 }
    @{ Path = 'android\app\src\main\res\mipmap-xhdpi\ic_launcher.png'; Size = 96 }
    @{ Path = 'android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png'; Size = 144 }
    @{ Path = 'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png'; Size = 192 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@1x.png'; Size = 20 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@2x.png'; Size = 40 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@3x.png'; Size = 60 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@1x.png'; Size = 29 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@2x.png'; Size = 58 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@3x.png'; Size = 87 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@1x.png'; Size = 40 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@2x.png'; Size = 80 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@3x.png'; Size = 120 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@2x.png'; Size = 120 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@3x.png'; Size = 180 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@1x.png'; Size = 76 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@2x.png'; Size = 152 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-83.5x83.5@2x.png'; Size = 167 }
    @{ Path = 'ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-1024x1024@1x.png'; Size = 1024 }
    @{ Path = 'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_16.png'; Size = 16 }
    @{ Path = 'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_32.png'; Size = 32 }
    @{ Path = 'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_64.png'; Size = 64 }
    @{ Path = 'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_128.png'; Size = 128 }
    @{ Path = 'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_256.png'; Size = 256 }
    @{ Path = 'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_512.png'; Size = 512 }
    @{ Path = 'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_1024.png'; Size = 1024 }
  )

  foreach ($target in $iconTargets) {
    $bitmap = New-SquareBitmap -SourceBitmap $sourceBitmap -Crop $crop -Size $target.Size -BackgroundColor $background
    try {
      Save-Png -Bitmap $bitmap -Path (Join-Path $repoRoot $target.Path)
    } finally {
      $bitmap.Dispose()
    }
  }

  $icoSizes = @(16, 24, 32, 48, 64, 128, 256)
  $icoImages = New-Object System.Collections.Generic.List[byte[]]
  foreach ($size in $icoSizes) {
    $bitmap = New-SquareBitmap -SourceBitmap $sourceBitmap -Crop $crop -Size $size -BackgroundColor $background
    try {
      $memoryStream = [System.IO.MemoryStream]::new()
      try {
        $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $icoImages.Add($memoryStream.ToArray())
      } finally {
        $memoryStream.Dispose()
      }
    } finally {
      $bitmap.Dispose()
    }
  }

  New-IcoFile -Images $icoImages.ToArray() -Sizes $icoSizes -Destination (Join-Path $repoRoot 'windows\runner\resources\app_icon.ico')
} finally {
  $sourceBitmap.Dispose()
}
