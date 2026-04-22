param(
  [switch]$SkipPubGet,
  [switch]$SkipBuild,
  [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installerDir = Join-Path $repoRoot 'tool\installer'
$issPath = Join-Path $installerDir 'balance-desk.iss'
$outputDir = Join-Path $repoRoot 'build\windows\installer'
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'

function Resolve-IsccPath {
  $command = Get-Command iscc.exe -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }

  $registryKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
    'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1'
  )

  foreach ($key in $registryKeys) {
    try {
      $installLocation = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallLocation
      if ($installLocation) {
        $candidate = Join-Path $installLocation 'ISCC.exe'
        if (Test-Path $candidate) {
          return $candidate
        }
      }
    } catch {
    }
  }

  $candidates = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 5\ISCC.exe',
    'C:\Program Files\Inno Setup 5\ISCC.exe'
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

Push-Location $repoRoot
try {
  if (-not $SkipPubGet) {
    Write-Host 'Resolving Flutter dependencies...'
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
      throw 'flutter pub get failed.'
    }
  }

  if (-not $SkipBuild) {
    Write-Host 'Building Windows release...'
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
      throw 'flutter build windows --release failed.'
    }
  }

  if (-not (Test-Path -LiteralPath $releaseDir)) {
    throw "Release output folder was not found: $releaseDir"
  }

  if (-not $SkipInstaller) {
    if (-not (Test-Path -LiteralPath $issPath)) {
      throw "Inno Setup script not found: $issPath"
    }

    $isccPath = Resolve-IsccPath
    if ($null -eq $isccPath) {
      Write-Host ''
      Write-Host 'Inno Setup compiler (ISCC.exe) was not found.' -ForegroundColor Yellow
      Write-Host 'Install Inno Setup and ensure ISCC.exe is on PATH, then re-run:'
      Write-Host ".\tool\build_windows_installer.ps1 -SkipBuild"
      return
    }

    Write-Host 'Building Windows setup (Inno Setup)...'
    & $isccPath $issPath
    if ($LASTEXITCODE -ne 0) {
      throw 'ISCC failed to build the setup.'
    }

    $setup = Get-ChildItem -LiteralPath $outputDir -Filter *.exe -File |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1

    if ($null -eq $setup) {
      throw "No setup exe was found in $outputDir."
    }

    Write-Host ''
    Write-Host 'Windows setup ready:' -ForegroundColor Green
    Write-Host $setup.FullName
  }
} finally {
  Pop-Location
}
