#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string] $LibraryRoot = 'C:\AI\Knowledge\ZIM',

    [Parameter()]
    [string] $ProjectDirectory = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$results = [Collections.Generic.List[object]]::new()

# region Construction du rapport de diagnostic
function Add-TestResult {
    param([string] $Test, [bool] $Success, [string] $Detail)
    $results.Add([pscustomobject]@{
        Test   = $Test
        Etat   = if ($Success) { 'OK' } else { 'ECHEC' }
        Detail = $Detail
    })
}

function Add-OptionalModelResult {
    param([string] $Test, [bool] $Present, [string] $ExpectedModel)
    $results.Add([pscustomobject]@{
        Test   = $Test
        Etat   = if ($Present) { 'PRESENT' } else { 'OPTIONNEL' }
        Detail = if ($Present) {
            "Modele detecte : $ExpectedModel"
        }
        else {
            "Modele non installe, sans incidence sur OpenZIM MCP : $ExpectedModel"
        }
    })
}
# endregion Construction du rapport de diagnostic

# region Verification des composants locaux
foreach ($commandName in @('winget.exe', 'uv.exe', 'uvx.exe', 'openzim-mcp.exe', 'curl.exe', 'ollama.exe')) {
    $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    Add-TestResult -Test $commandName -Success ($null -ne $command) -Detail $(
        if ($null -ne $command) { $command.Source } else { 'Commande introuvable' }
    )
}

$zimFiles = @(if (Test-Path -LiteralPath $LibraryRoot) {
    Get-ChildItem -LiteralPath $LibraryRoot -Filter '*.zim' -File -Recurse
})
Add-TestResult -Test 'Archives ZIM' -Success ($zimFiles.Count -gt 0) -Detail "$($zimFiles.Count) fichier(s) dans $LibraryRoot"

$mcpPath = Join-Path $ProjectDirectory '.vscode\mcp.json'
if (Test-Path -LiteralPath $mcpPath) {
    try {
        $mcp = Get-Content -LiteralPath $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $hasOpenZim = $null -ne $mcp.servers.PSObject.Properties['openzim']
        Add-TestResult -Test 'Configuration MCP' -Success $hasOpenZim -Detail $mcpPath
        if ($hasOpenZim) {
            $openZimServer = $mcp.servers.openzim
            $serverArguments = @($openZimServer.args)
            $usesCompatibilityBridge =
                $serverArguments.Count -gt 0 -and
                [IO.Path]::GetFileName($serverArguments[0]) -eq 'OpenZimCompatServer.py'
            $usesAdvancedMode =
                $serverArguments -contains '--mode' -and
                $serverArguments -contains 'advanced'

            if ($usesCompatibilityBridge) {
                $bridgePath = [string] $serverArguments[0]
                $bridgeReady = Test-Path -LiteralPath $bridgePath -PathType Leaf
                Add-TestResult `
                    -Test 'Compatibilite GPT-OSS' `
                    -Success $bridgeReady `
                    -Detail $(if ($bridgeReady) {
                        "Passerelle MCP simplifiee : $bridgePath"
                    } else {
                        "Passerelle introuvable : $bridgePath (relancez l option 5)"
                    })
                if ($bridgeReady) {
                    $bridgeCommand = [string] $openZimServer.command
                    if (-not (Test-Path -LiteralPath $bridgeCommand -PathType Leaf)) {
                        Add-TestResult `
                            -Test 'Acces reel OpenZIM' `
                            -Success $false `
                            -Detail "Interpreteur OpenZIM introuvable : $bridgeCommand"
                    }
                    else {
                        $bridgeArguments = @($bridgePath, '--self-test') +
                            @($serverArguments | Select-Object -Skip 1)
                        $previousErrorActionPreference = $ErrorActionPreference
                        $ErrorActionPreference = 'Continue'
                        try {
                            # Les journaux de demarrage normaux arrivent sur stderr.
                            # Ils ne doivent pas etre classes comme erreurs PowerShell.
                            $bridgeOutput = & $bridgeCommand @bridgeArguments 2>&1 | Out-String
                            $bridgeExitCode = $LASTEXITCODE
                            $bridgeSummary = @(
                                $bridgeOutput -split "`r?`n" |
                                    Where-Object { $_ -match '^(OK|ECHEC)\s*:' }
                            ) | Select-Object -Last 1
                            Add-TestResult `
                                -Test 'Acces reel OpenZIM' `
                                -Success ($bridgeExitCode -eq 0) `
                                -Detail $(if ($bridgeSummary) {
                                    $bridgeSummary
                                } else {
                                    "Auto-test termine avec le code $bridgeExitCode"
                                })
                        }
                        finally {
                            $ErrorActionPreference = $previousErrorActionPreference
                        }
                    }
                }
            }
            elseif ($usesAdvancedMode) {
                Add-TestResult `
                    -Test 'Compatibilite GPT-OSS' `
                    -Success $true `
                    -Detail 'Mode avance choisi : schemas complets reserves aux modeles compatibles'
            }
            else {
                Add-TestResult `
                    -Test 'Compatibilite GPT-OSS' `
                    -Success $false `
                    -Detail 'Ancienne configuration simple detectee : relancez l option 5'
            }
        }
    }
    catch {
        Add-TestResult `
            -Test 'Configuration MCP' `
            -Success $false `
            -Detail "Lecture ou diagnostic impossible : $($_.Exception.Message)"
    }
}
else {
    Add-TestResult -Test 'Configuration MCP' -Success $false -Detail "Fichier absent : $mcpPath (lancez l option 5 pour ce projet)"
}

$instructionsPath = Join-Path $ProjectDirectory '.github\copilot-instructions.md'
if (Test-Path -LiteralPath $instructionsPath) {
    $instructions = Get-Content -LiteralPath $instructionsPath -Raw -Encoding UTF8
    $hasManagedInstructions =
        $instructions.Contains('<!-- openzim-mcp:begin -->') -and
        $instructions.Contains('<!-- openzim-mcp:end -->') -and
        $instructions.Contains('openzim_list_archives')
    Add-TestResult -Test 'Instructions IA OpenZIM' -Success $hasManagedInstructions -Detail $instructionsPath
}
else {
    Add-TestResult -Test 'Instructions IA OpenZIM' -Success $false -Detail "Fichier absent : $instructionsPath (lancez l option 5 pour ce projet)"
}

$standardsPath = Join-Path $ProjectDirectory '.github\instructions\openzim-development-standards.instructions.md'
$startupPromptPath = Join-Path $ProjectDirectory '.github\prompts\verifier-openzim.prompt.md'
$guidePath = Join-Path $ProjectDirectory 'docs\ai\Guide-Bonnes-Pratiques-Code.md'
$agentsPath = Join-Path $ProjectDirectory 'AGENTS.md'
$standardsReady =
    (Test-Path -LiteralPath $standardsPath -PathType Leaf) -and
    (Test-Path -LiteralPath $startupPromptPath -PathType Leaf) -and
    (Test-Path -LiteralPath $guidePath -PathType Leaf) -and
    (Test-Path -LiteralPath $agentsPath -PathType Leaf)
Add-TestResult -Test 'Standards de code IA' -Success $standardsReady -Detail $(
    if ($standardsReady) {
        "Instructions, prompt de demarrage, guide et politique multi-agent installes dans $ProjectDirectory"
    }
    else {
        'Fichiers incomplets : relancez l option 5 pour ce projet'
    }
)

try {
    $ollama = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5
    $modelNames = @($ollama.models | ForEach-Object { $_.name })
    Add-TestResult -Test 'Serveur Ollama' -Success $true -Detail ($modelNames -join ', ')
    Add-OptionalModelResult `
        -Test 'GPT-OSS 20B (optionnel)' `
        -Present (@($modelNames -match '^gpt-oss:20b').Count -gt 0) `
        -ExpectedModel 'gpt-oss:20b'
    Add-OptionalModelResult `
        -Test 'Qwen2.5-Coder (optionnel)' `
        -Present (@($modelNames -match '^qwen2\.5-coder:14b-instruct-q5_K_M$').Count -gt 0) `
        -ExpectedModel 'qwen2.5-coder:14b-instruct-q5_K_M'
    Add-OptionalModelResult `
        -Test 'Devstral Agent 24B (optionnel)' `
        -Present (@($modelNames -match '^devstral-small-2:24b-instruct-2512-q4_K_M$').Count -gt 0) `
        -ExpectedModel 'devstral-small-2:24b-instruct-2512-q4_K_M'

    $toolCapableAlternative = @(
        $modelNames | Where-Object {
            $_ -match '(?i)(qwen3|devstral|qwen3-coder)'
        }
    ) | Select-Object -First 1
    if (@($modelNames -match '^gpt-oss:20b').Count -gt 0) {
        $results.Add([pscustomobject]@{
            Test   = 'Edition de code GPT-OSS'
            Etat   = 'ATTENTION'
            Detail = if ($toolCapableAlternative) {
                "Les gros patchs peuvent provoquer HTTP 500 dans Ollama. Alternative detectee : $toolCapableAlternative"
            }
            else {
                'Les gros patchs peuvent provoquer HTTP 500 dans Ollama. Utilisez des modifications courtes ou un modele agentique compatible.'
            }
        })
    }
}
catch {
    Add-TestResult -Test 'Serveur Ollama' -Success $false -Detail 'API locale inaccessible sur 127.0.0.1:11434'
}

$results | Format-Table -AutoSize -Wrap
if (@($results | Where-Object { $_.Etat -eq 'ECHEC' }).Count -gt 0) {
    exit 1
}
# endregion Verification des composants locaux
