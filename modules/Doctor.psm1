#requires -Version 5.1
Set-StrictMode -Version Latest
foreach ($module in @('LocalCodex.Common','Models','Hermes','OpenZim','Hardware')) { Import-Module (Join-Path $PSScriptRoot "$module.psm1") }

function Get-LocalCodexDoctor {
    param([Parameter(Mandatory)] $Settings, [Parameter(Mandatory)][string] $StateDirectory,
        [Parameter(Mandatory)][string] $ProjectDirectory)
    $results = [Collections.Generic.List[object]]::new()
    $paths = Get-LocalCodexHermesPaths $Settings $StateDirectory
    $candidatePath = Join-Path $StateDirectory 'candidate.json'
    $checks = [ordered]@{
        Git = { (Invoke-LocalCodexProcess (Get-Command git.exe -ErrorAction Stop).Source @('--version')).Output.Trim() }
        VSCode = {
            $code = Get-Command code.cmd -ErrorAction Stop
            $version = & $code.Source --version
            if ($LASTEXITCODE -ne 0) { throw 'VS Code ne repond pas.' }
            $version -join ' '
        }
        ACPClient = {
            $extensions = & (Get-Command code.cmd -ErrorAction Stop).Source --list-extensions --show-versions
            $client = @($extensions | Where-Object { $_ -like 'formulahendry.acp-client@*' })
            if ($LASTEXITCODE -ne 0 -or $client.Count -ne 1) { throw 'Installer le client VS Code formulahendry.acp-client.' }
            $client[0]
        }
        Hermes = { (Invoke-LocalCodexProcess $paths.Executable @('acp','--version') -Environment @{ HERMES_HOME = $paths.Home }).Output.Trim() }
        ACP = { (Invoke-LocalCodexProcess $paths.Executable @('acp','--check') -Environment @{ HERMES_HOME = $paths.Home }).Output.Trim() }
        Ollama = { (Invoke-LocalCodexOllama $Settings '/api/version').version }
        Qwen = {
            $candidate = Read-LocalCodexJson $candidatePath
            $details = Invoke-LocalCodexOllama $Settings '/api/show' @{ model = $candidate.model }
            if ('tools' -notin @($details.capabilities)) { throw 'Tool calling absent.' }
            if ($details.parameters -notmatch "(?m)^num_ctx\s+$($candidate.contextTokens)\s*$") { throw 'Contexte Ollama different du candidat.' }
            "$($candidate.model), contexte $($candidate.contextTokens)"
        }
        Configuration = {
            $candidate = Read-LocalCodexJson $candidatePath
            $config = Read-LocalCodexJson (Join-Path $paths.Home 'config.yaml')
            if ($config.model.default -ne $candidate.model -or $config.model.context_length -ne $candidate.contextTokens -or
                $config.model.provider -ne 'custom' -or $config.model.base_url -ne ($Settings.ollama.baseUrl.TrimEnd('/') + '/v1')) { throw 'Configuration Hermes et candidat incoherents.' }
            $vscode = Read-LocalCodexJson (Join-Path $ProjectDirectory '.vscode\settings.json')
            $launcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Start-LocalCodexAcp.ps1'
            if ($launcher -notin @($vscode.'acp.agents'.'Local-Codex'.args) -or
                $StateDirectory -notin @($vscode.'acp.agents'.'Local-Codex'.args)) { throw 'Configuration ACP incoherente.' }
            'Hermes / Ollama / ACP coherents'
        }
        OpenZimMCP = { (Test-LocalCodexOpenZim $Settings).Output.Trim() }
        ZimLibrary = {
            $library = [Environment]::ExpandEnvironmentVariables($Settings.KnowledgeSettings.libraryRoot)
            $archives = @(Get-ChildItem -LiteralPath $library -Filter '*.zim' -File -Recurse -ErrorAction Stop)
            if ($archives.Count -eq 0) { throw 'Bibliotheque vide.' }
            "$($archives.Count) archives"
        }
    }
    foreach ($name in $checks.Keys) {
        try { $detail = & $checks[$name]; $status = 'PASS' }
        catch { $detail = $_.Exception.Message; $status = 'FAIL' }
        $results.Add([pscustomobject]@{ name = $name; status = $status; detail = [string] $detail })
    }
    $results.Add([pscustomobject]@{ name = 'AgentScenario'; status = 'NOT_RUN'; detail = 'Executer Certify ; Doctor ne prouve pas les capacites agentiques.' })
    [pscustomobject]@{ generatedAtUtc = [datetime]::UtcNow.ToString('o'); checks = @($results.ToArray()); hardware = Get-LocalCodexHardware }
}

Export-ModuleMember -Function Get-LocalCodexDoctor
