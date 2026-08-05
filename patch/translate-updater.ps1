$ErrorActionPreference = "Stop"

function Write-UpdateLog {
    param([string]$Message)
    Write-Host "[translate-db] $Message"
}

function Resolve-GamePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path -Path $PSScriptRoot -ChildPath $Path
}

function Get-RemoteHeaders {
    param(
        [string]$Url,
        [int]$TimeoutSeconds
    )

    try {
        return Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec $TimeoutSeconds
    } catch {
        return $null
    }
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }

    return $content | ConvertFrom-Json
}

function Save-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $Value | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-Sha256 {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ManifestNeedsDownload {
    param(
        [object]$Manifest,
        [object]$State,
        [string]$DatabasePath
    )

    if (-not (Test-Path -LiteralPath $DatabasePath)) {
        return $true
    }

    if ($Manifest.version -and ($null -eq $State -or $State.version -ne $Manifest.version)) {
        return $true
    }

    if ($Manifest.sha256) {
        $localHash = Get-Sha256 -Path $DatabasePath
        return $localHash -ne $Manifest.sha256.ToString().ToLowerInvariant()
    }

    return $false
}

function Test-DirectNeedsDownload {
    param(
        [object]$Headers,
        [object]$State,
        [string]$DatabasePath,
        [string]$Url
    )

    if (-not (Test-Path -LiteralPath $DatabasePath)) {
        return $true
    }

    if ($null -eq $Headers) {
        return $false
    }

    $etag = $Headers.Headers["ETag"]
    $lastModified = $Headers.Headers["Last-Modified"]

    if ($etag -and ($null -eq $State -or $State.url -ne $Url -or $State.etag -ne $etag)) {
        return $true
    }

    if ($lastModified -and ($null -eq $State -or $State.url -ne $Url -or $State.lastModified -ne $lastModified)) {
        return $true
    }

    return $false
}

function Install-Database {
    param(
        [string]$Url,
        [string]$DatabasePath,
        [int]$TimeoutSeconds,
        [bool]$KeepBackup,
        [string]$ExpectedSha256
    )

    $tempPath = "$DatabasePath.download"
    $backupPath = "$DatabasePath.bak"

    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force
    }

    Invoke-WebRequest -Uri $Url -OutFile $tempPath -UseBasicParsing -TimeoutSec $TimeoutSeconds

    if ($ExpectedSha256) {
        $actualSha256 = Get-Sha256 -Path $tempPath
        if ($actualSha256 -ne $ExpectedSha256.ToLowerInvariant()) {
            Remove-Item -LiteralPath $tempPath -Force
            throw "downloaded translate.db hash mismatch"
        }
    }

    if ((Test-Path -LiteralPath $DatabasePath) -and $KeepBackup) {
        Copy-Item -LiteralPath $DatabasePath -Destination $backupPath -Force
    }

    Move-Item -LiteralPath $tempPath -Destination $DatabasePath -Force
}

try {
    $configPath = Join-Path -Path $PSScriptRoot -ChildPath "translate-source.json"
    $config = Read-JsonFile -Path $configPath

    if ($null -eq $config -or $config.enabled -ne $true) {
        exit 0
    }

    $mode = if ($config.mode) { $config.mode.ToString().ToLowerInvariant() } else { "manifest" }
    $timeoutSeconds = if ($config.timeoutSeconds) { [int]$config.timeoutSeconds } else { 20 }
    $configuredDbPath = if ($config.databasePath) { $config.databasePath } else { "translate.db" }
    $databasePath = Resolve-GamePath -Path $configuredDbPath
    $statePath = "$databasePath.update.json"
    $state = Read-JsonFile -Path $statePath
    $keepBackup = $config.keepBackup -ne $false

    if ($mode -eq "manifest") {
        if (-not $config.manifestUrl) {
            Write-UpdateLog "manifestUrl is empty; skipping update"
            exit 0
        }

        $manifest = (Invoke-WebRequest -Uri $config.manifestUrl -UseBasicParsing -TimeoutSec $timeoutSeconds).Content | ConvertFrom-Json
        if (-not $manifest.url) {
            throw "manifest does not contain a database url"
        }

        if (Test-ManifestNeedsDownload -Manifest $manifest -State $state -DatabasePath $databasePath) {
            Write-UpdateLog "downloading translate.db version $($manifest.version)"
            Install-Database -Url $manifest.url -DatabasePath $databasePath -TimeoutSeconds $timeoutSeconds -KeepBackup $keepBackup -ExpectedSha256 $manifest.sha256

            Save-JsonFile -Path $statePath -Value @{
                mode = "manifest"
                manifestUrl = $config.manifestUrl
                url = $manifest.url
                version = $manifest.version
                sha256 = $manifest.sha256
                updatedAt = (Get-Date).ToUniversalTime().ToString("o")
            }
        }

        exit 0
    }

    if ($mode -eq "direct") {
        if (-not $config.url) {
            Write-UpdateLog "url is empty; skipping update"
            exit 0
        }

        $headers = Get-RemoteHeaders -Url $config.url -TimeoutSeconds $timeoutSeconds
        if (Test-DirectNeedsDownload -Headers $headers -State $state -DatabasePath $databasePath -Url $config.url) {
            Write-UpdateLog "downloading translate.db"
            Install-Database -Url $config.url -DatabasePath $databasePath -TimeoutSeconds $timeoutSeconds -KeepBackup $keepBackup -ExpectedSha256 $config.sha256

            Save-JsonFile -Path $statePath -Value @{
                mode = "direct"
                url = $config.url
                etag = $(if ($headers) { $headers.Headers["ETag"] } else { $null })
                lastModified = $(if ($headers) { $headers.Headers["Last-Modified"] } else { $null })
                sha256 = $config.sha256
                updatedAt = (Get-Date).ToUniversalTime().ToString("o")
            }
        }

        exit 0
    }

    Write-UpdateLog "unknown mode '$mode'; skipping update"
} catch {
    Write-UpdateLog $_.Exception.Message
    Write-UpdateLog "starting OpenBatoru with the existing translate.db"
    exit 0
}
