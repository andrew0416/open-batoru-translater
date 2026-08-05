$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogPath = Join-Path -Path $PSScriptRoot -ChildPath "translate-updater.log"

function Write-UpdateLog {
    param([string]$Message)

    $line = "[translate-db] $Message"
    Write-Host $line
    try {
        Add-Content -LiteralPath $LogPath -Value ("{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $line) -Encoding UTF8
    } catch {
        # Logging must never block the game from starting.
    }
}

function Resolve-GamePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path -Path $PSScriptRoot -ChildPath $Path
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $content = $content.TrimStart([char]0xFEFF)
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

function Assert-SqliteDatabase {
    param([string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 16) {
            throw "translate.db is too small"
        }

        $buffer = New-Object byte[] 16
        [void]$stream.Read($buffer, 0, 16)
        $header = [System.Text.Encoding]::ASCII.GetString($buffer)
        if ($header -ne "SQLite format 3`0") {
            throw "translate.db is not a SQLite database"
        }
    } finally {
        $stream.Dispose()
    }
}

function Invoke-DownloadFile {
    param(
        [string]$Url,
        [string]$OutFile,
        [int]$TimeoutSeconds
    )

    $client = New-Object System.Net.WebClient
    try {
        $client.Headers.Add("User-Agent", "open-batoru-translate-updater")
        $client.Headers.Add("Cache-Control", "no-cache")
        $client.DownloadFile($Url, $OutFile)
    } finally {
        $client.Dispose()
    }
}

function Invoke-DownloadText {
    param(
        [string]$Url,
        [int]$TimeoutSeconds
    )

    $client = New-Object System.Net.WebClient
    try {
        $client.Encoding = [System.Text.Encoding]::UTF8
        $client.Headers.Add("User-Agent", "open-batoru-translate-updater")
        $client.Headers.Add("Cache-Control", "no-cache")
        return $client.DownloadString($Url).TrimStart([char]0xFEFF)
    } finally {
        $client.Dispose()
    }
}

function Get-Manifest {
    param(
        [string]$ManifestUrl,
        [int]$TimeoutSeconds
    )

    $json = Invoke-DownloadText -Url $ManifestUrl -TimeoutSeconds $TimeoutSeconds
    return $json | ConvertFrom-Json
}

function Test-NeedsDownload {
    param(
        [object]$Manifest,
        [object]$State,
        [string]$DatabasePath
    )

    if (-not (Test-Path -LiteralPath $DatabasePath)) {
        Write-UpdateLog "local translate.db was not found"
        return $true
    }

    if ($Manifest.sha256) {
        $localHash = Get-Sha256 -Path $DatabasePath
        $remoteHash = $Manifest.sha256.ToString().Trim().ToLowerInvariant()
        Write-UpdateLog "local sha256: $localHash"
        Write-UpdateLog "remote sha256: $remoteHash"
        return $localHash -ne $remoteHash
    }

    if ($Manifest.version) {
        $localVersion = if ($null -ne $State -and $State.version) { $State.version } else { "" }
        Write-UpdateLog "local version: $localVersion"
        Write-UpdateLog "remote version: $($Manifest.version)"
        return $localVersion -ne $Manifest.version
    }

    Write-UpdateLog "manifest has no sha256 or version; skipping update"
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

    Invoke-DownloadFile -Url $Url -OutFile $tempPath -TimeoutSeconds $TimeoutSeconds
    Assert-SqliteDatabase -Path $tempPath

    if ($ExpectedSha256) {
        $actualSha256 = Get-Sha256 -Path $tempPath
        $expected = $ExpectedSha256.ToString().Trim().ToLowerInvariant()
        if ($actualSha256 -ne $expected) {
            Remove-Item -LiteralPath $tempPath -Force
            throw "downloaded translate.db hash mismatch. expected=$expected actual=$actualSha256"
        }
    }

    if ((Test-Path -LiteralPath $DatabasePath) -and $KeepBackup) {
        Copy-Item -LiteralPath $DatabasePath -Destination $backupPath -Force
    }

    Move-Item -LiteralPath $tempPath -Destination $DatabasePath -Force
}

try {
    if (Test-Path -LiteralPath $LogPath) {
        Remove-Item -LiteralPath $LogPath -Force
    }

    $configPath = Join-Path -Path $PSScriptRoot -ChildPath "translate-source.json"
    $config = Read-JsonFile -Path $configPath

    if ($null -eq $config -or $config.enabled -ne $true) {
        Write-UpdateLog "updater is disabled"
        exit 0
    }

    $mode = if ($config.mode) { $config.mode.ToString().ToLowerInvariant() } else { "manifest" }
    if ($mode -ne "manifest") {
        Write-UpdateLog "only manifest mode is supported; current mode=$mode"
        exit 0
    }

    if (-not $config.manifestUrl) {
        Write-UpdateLog "manifestUrl is empty; skipping update"
        exit 0
    }

    $timeoutSeconds = if ($config.timeoutSeconds) { [int]$config.timeoutSeconds } else { 20 }
    $configuredDbPath = if ($config.databasePath) { $config.databasePath } else { "translate.db" }
    $databasePath = Resolve-GamePath -Path $configuredDbPath
    $statePath = "$databasePath.update.json"
    $state = Read-JsonFile -Path $statePath
    $keepBackup = $config.keepBackup -ne $false

    Write-UpdateLog "manifest: $($config.manifestUrl)"
    Write-UpdateLog "database: $databasePath"

    $manifest = Get-Manifest -ManifestUrl $config.manifestUrl -TimeoutSeconds $timeoutSeconds
    if (-not $manifest.url) {
        throw "manifest does not contain a database url"
    }

    if (-not (Test-NeedsDownload -Manifest $manifest -State $state -DatabasePath $databasePath)) {
        Write-UpdateLog "translate.db is already up to date"
        exit 0
    }

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

    Write-UpdateLog "translate.db updated"
} catch {
    Write-UpdateLog $_.Exception.Message
    Write-UpdateLog "starting OpenBatoru with the existing translate.db"
    exit 0
}
