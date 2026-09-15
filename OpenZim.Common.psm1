Set-StrictMode -Version Latest
$script:OpenZimLogPath = $null

function Initialize-OpenZimLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter()] [ValidateRange(1, 3650)] [int] $RetentionDays = 14,
        [Parameter()] [string] $Prefix = 'openzim'
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -LiteralPath $Directory -Filter "$Prefix-*.log" -File -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -LT $cutoff |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:OpenZimLogPath = Join-Path $Directory "$Prefix-$stamp-$PID.log"
    return $script:OpenZimLogPath
}

function Write-OpenZimLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('INFO', 'WARNING', 'ERROR')] [string] $Level,
        [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9_]+$')] [string] $Event,
        [Parameter(Mandatory)] [string] $Message,
        [Parameter()] [hashtable] $Data
    )

    if ([string]::IsNullOrWhiteSpace($script:OpenZimLogPath)) {
        return
    }

    $record = [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        level     = $Level
        event     = $Event
        message   = $Message
    }
    if ($null -ne $Data) {
        $record.data = $Data
    }

    $line = $record | ConvertTo-Json -Compress -Depth 10
    [IO.File]::AppendAllText(
        $script:OpenZimLogPath,
        $line + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

function Enter-OpenZimMutex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Scope,
        [Parameter()] [ValidateRange(0, 3600)] [int] $TimeoutSeconds = 0
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Scope.ToLowerInvariant())
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').Substring(0, 24)
    }
    finally {
        $sha.Dispose()
    }

    $mutex = [Threading.Mutex]::new($false, "Local\OpenZim-$hash")
    try {
        $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
    }
    catch [Threading.AbandonedMutexException] {
        $acquired = $true
    }

    if (-not $acquired) {
        $mutex.Dispose()
        throw "Une autre instance gere deja cette bibliotheque : $Scope"
    }

    return $mutex
}

function Exit-OpenZimMutex {
    [CmdletBinding()]
    param([Parameter()] [Threading.Mutex] $Mutex)

    if ($null -eq $Mutex) {
        return
    }
    try {
        $Mutex.ReleaseMutex()
    }
    finally {
        $Mutex.Dispose()
    }
}

Export-ModuleMember -Function Initialize-OpenZimLog, Write-OpenZimLog, Enter-OpenZimMutex, Exit-OpenZimMutex
