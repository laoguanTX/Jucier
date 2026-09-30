param([string]$SevenZipDirectory)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function Get-VerifiedDownload([string]$Url, [string]$File, [string]$ExpectedHash) {
    if ((Test-Path -LiteralPath $File) -and
        (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -eq $ExpectedHash) { return }
    $temporary = "$File.download"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $temporary -ConnectionTimeoutSeconds 30
    } catch {
        # Some local proxy configurations break TLS for release asset redirects.
        # Retry directly while retaining normal certificate validation.
        Invoke-WebRequest -Uri $Url -OutFile $temporary -NoProxy -ConnectionTimeoutSeconds 30
    }
    if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw "Checksum mismatch for $Url"
    }
    Move-Item -LiteralPath $temporary -Destination $File -Force
}

$destination = Join-Path $projectRoot 'assets/sevenzip/windows'
New-Item -ItemType Directory -Force -Path $destination | Out-Null

if ($SevenZipDirectory) {
    # Copy an existing full installation, including its codec DLL.
    foreach ($name in @('7z.exe', '7z.dll')) {
        Copy-Item -LiteralPath (Join-Path $SevenZipDirectory $name) -Destination $destination
    }
} else {
    $runtime = Get-Content -LiteralPath (Join-Path $projectRoot 'third_party/7zip/WINDOWS_RUNTIME.json') -Raw | ConvertFrom-Json
    $downloadDirectory = Join-Path $projectRoot 'third_party/7zip/downloads/windows'
    New-Item -ItemType Directory -Force -Path $downloadDirectory | Out-Null
    $bootstrap = Join-Path $downloadDirectory '7zr.exe'
    $installer = Join-Path $downloadDirectory $runtime.installer
    Get-VerifiedDownload "https://github.com/ip7z/7zip/releases/download/$($runtime.bootstrapRelease)/7zr.exe" $bootstrap $runtime.bootstrapSha256
    Get-VerifiedDownload "https://github.com/ip7z/7zip/releases/download/$($runtime.release)/$($runtime.installer)" $installer $runtime.installerSha256
    # Extract the installer payload without installing into Windows or changing
    # system-wide file associations. 7zr is only a bootstrap, not the runtime.
    & $bootstrap x $installer "-o$destination" -y '7z.exe' '7z.dll'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to extract the official 7-Zip runtime.' }
}
foreach ($name in @('7z.exe', '7z.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $destination $name))) { throw "Missing $name" }
}
& (Join-Path $destination '7z.exe') i
if ($LASTEXITCODE -ne 0) { throw '7-Zip runtime verification failed.' }
$licenses = Join-Path $projectRoot 'assets/sevenzip/licenses'
New-Item -ItemType Directory -Force -Path $licenses | Out-Null
Copy-Item -Path (Join-Path $projectRoot 'third_party/7zip/licenses/*.txt') -Destination $licenses
Write-Host "Windows x64 runtime prepared at $destination"
