#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LocalCodex.Common.psm1')

function Get-LocalCodexOpenZim {
    param([Parameter(Mandatory)] $Settings)
    $library = [Environment]::ExpandEnvironmentVariables($Settings.KnowledgeSettings.libraryRoot)
    if (-not (Test-Path -LiteralPath $library -PathType Container)) { throw "Bibliotheque ZIM absente : $library. Utilisez le parcours Knowledge." }
    $uv = (Get-Command uv.exe -ErrorAction Stop).Source
    $toolRoot = (Invoke-LocalCodexProcess $uv @('tool','dir')).Output.Trim()
    $python = Join-Path $toolRoot 'openzim-mcp\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'OpenZIM MCP absent ; lancer Install.' }
    $directories = @(Get-ChildItem -LiteralPath $library -File -Recurse -Filter '*.zim' | Select-Object -ExpandProperty DirectoryName -Unique)
    if ($directories.Count -eq 0) { $directories = @($library) }
    $bridge = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\OpenZimCompatServer.py'
    if ($Settings.openzim.mode -ne 'compatibility') { throw 'Le mode MCP direct doit etre valide avant activation.' }
    [pscustomobject]@{ command = $python; args = @($bridge) + $directories }
}

function Test-LocalCodexOpenZim {
    param([Parameter(Mandatory)] $Settings)
    $server = Get-LocalCodexOpenZim $Settings
    Invoke-LocalCodexProcess $server.command (@($server.args[0], '--self-test') + @($server.args | Select-Object -Skip 1)) -TimeoutSeconds 60
}

Export-ModuleMember -Function Get-LocalCodexOpenZim,Test-LocalCodexOpenZim
