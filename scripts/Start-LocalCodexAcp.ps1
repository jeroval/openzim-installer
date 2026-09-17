#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string] $StateDirectory)
$ErrorActionPreference = 'Stop'
$release = Get-Content -LiteralPath (Join-Path $StateDirectory 'releases.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $release.active) { throw 'Aucun profil actif. Executer Configure.' }
$env:HERMES_HOME = $release.active.home
& $release.active.executable acp
exit $LASTEXITCODE
