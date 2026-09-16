#requires -Version 5.1

Set-StrictMode -Version Latest

# region Catalogue des modeles
function Get-LocalAiModelProfiles {
    <#
    Les seuils sont volontairement conservateurs. Ils ne representent pas une
    compatibilite absolue : la taille du contexte et le dechargement CPU peuvent
    encore modifier la consommation reelle.
    #>
    return @(
        [pscustomobject]@{
            Choice = '1'; Name = 'gpt-oss:20b'; DisplayName = 'GPT-OSS 20B'
            MinimumVramGB = 10; PreferredVramGB = 16; MinimumRamGB = 32
            HybridRamGB = 48; CapabilityRank = 70
        }
        [pscustomobject]@{
            Choice = '2'; Name = 'qwen2.5-coder:14b-instruct-q5_K_M'; DisplayName = 'Qwen2.5-Coder 14B'
            MinimumVramGB = 10; PreferredVramGB = 16; MinimumRamGB = 24
            HybridRamGB = 32; CapabilityRank = 80
        }
        [pscustomobject]@{
            Choice = '3'; Name = 'qwen3.5-code-agent:9b-32k'; DisplayName = 'Qwen 3.5 Agent 9B 32K'
            MinimumVramGB = 6; PreferredVramGB = 10; MinimumRamGB = 16
            HybridRamGB = 24; CapabilityRank = 60
        }
        [pscustomobject]@{
            Choice = '4'; Name = 'devstral-small-2:24b-instruct-2512-q4_K_M'; DisplayName = 'Devstral Small 2 24B'
            MinimumVramGB = 16; PreferredVramGB = 24; MinimumRamGB = 32
            HybridRamGB = 64; CapabilityRank = 90
        }
    )
}
# endregion Catalogue des modeles

# region Detection materielle
function Get-SystemRamGB {
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        return [math]::Round(([double] $computer.TotalPhysicalMemory / 1GB), 1)
    }
    catch {
        try {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
            $computerInfo = [Microsoft.VisualBasic.Devices.ComputerInfo]::new()
            return [math]::Round(([double] $computerInfo.TotalPhysicalMemory / 1GB), 1)
        }
        catch {
            return $null
        }
    }
}

function Get-VideoMemoryInfo {
    $nvidiaCommand = Get-Command 'nvidia-smi.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $nvidiaCandidates = @($nvidiaCommand | ForEach-Object { $_.Source })
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        $nvidiaCandidates += Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $nvidiaCandidates += Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    }
    $nvidiaPath = $nvidiaCandidates |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1

    if ($nvidiaPath) {
        try {
            $memoryValuesMB = @(& $nvidiaPath '--query-gpu=memory.total' '--format=csv,noheader,nounits' 2>$null |
                ForEach-Object {
                    $parsedValue = 0.0
                    if ([double]::TryParse(
                        ([string] $_).Trim(),
                        [Globalization.NumberStyles]::Float,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref] $parsedValue
                    )) {
                        $parsedValue
                    }
                })
            if ($memoryValuesMB.Count -gt 0) {
                $largestMemoryMB = ($memoryValuesMB | Measure-Object -Maximum).Maximum
                return [pscustomobject]@{
                    VramGB = [math]::Round(([double] $largestMemoryMB / 1024), 1)
                    Source = 'nvidia-smi'
                    Reliable = $true
                }
            }
        }
        catch {
            # WMI reste disponible si le pilote NVIDIA ne repond pas.
        }
    }

    try {
        $registryMemoryValues = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Video' -ErrorAction Stop |
            Get-ChildItem -ErrorAction SilentlyContinue |
            ForEach-Object {
                $adapterProperties = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if ($null -ne $adapterProperties) {
                    $memoryProperty = $adapterProperties.PSObject.Properties['HardwareInformation.qwMemorySize']
                    if ($null -ne $memoryProperty -and [double] $memoryProperty.Value -gt 0) {
                        [double] $memoryProperty.Value
                    }
                }
            })
        if ($registryMemoryValues.Count -gt 0) {
            $largestMemoryBytes = ($registryMemoryValues | Measure-Object -Maximum).Maximum
            return [pscustomobject]@{
                VramGB = [math]::Round(([double] $largestMemoryBytes / 1GB), 1)
                Source = 'registre Windows'
                Reliable = $true
            }
        }
    }
    catch {
        # Certaines politiques Windows interdisent la lecture de ces cles.
    }

    try {
        $adapter = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $null -ne $_.AdapterRAM -and [double] $_.AdapterRAM -gt 0 } |
            Sort-Object { [double] $_.AdapterRAM } -Descending |
            Select-Object -First 1
        if ($null -ne $adapter) {
            return [pscustomobject]@{
                VramGB = [math]::Round(([double] $adapter.AdapterRAM / 1GB), 1)
                Source = 'Windows WMI (estimation)'
                Reliable = $false
            }
        }
    }
    catch {
        # L'assistant peut continuer avec une recommandation fondee sur la RAM.
    }

    return [pscustomobject]@{ VramGB = $null; Source = 'indisponible'; Reliable = $false }
}

function Get-LocalAiHardwareProfile {
    $videoMemory = Get-VideoMemoryInfo
    return [pscustomobject]@{
        RamGB = Get-SystemRamGB
        VramGB = $videoMemory.VramGB
        VramSource = $videoMemory.Source
        VramReliable = $videoMemory.Reliable
    }
}
# endregion Detection materielle

# region Recommandation
function Get-LocalAiRecommendation {
    param(
        [Parameter(Mandatory)] [ValidateRange(0, 4096)] [double] $RamGB,
        [Parameter()] [AllowNull()] [Nullable[double]] $VramGB
    )

    # Windows peut reserver une petite partie de la RAM. Une tolerance de 5 %
    # evite ainsi de classer 31,1 Go comme insuffisants pour un seuil de 32 Go.
    $ramToleranceFactor = 0.95
    $results = foreach ($profile in Get-LocalAiModelProfiles) {
        $status = 'Deconseille'
        $reason = "necessite au moins $($profile.MinimumRamGB) Go de RAM"
        $meetsMinimumRam = $RamGB -ge ($profile.MinimumRamGB * $ramToleranceFactor)
        $meetsHybridRam = $RamGB -ge ($profile.HybridRamGB * $ramToleranceFactor)

        if ($meetsMinimumRam) {
            if ($null -eq $VramGB) {
                $status = 'Possible'
                $reason = 'VRAM non detectee ; evaluation prudente fondee sur la RAM'
            }
            elseif ($VramGB -ge $profile.PreferredVramGB) {
                $status = 'Recommande'
                $reason = "marge VRAM adaptee (cible $($profile.PreferredVramGB) Go)"
            }
            elseif ($VramGB -ge $profile.MinimumVramGB) {
                $status = 'Possible'
                $reason = 'fonctionnement possible, avec moins de marge pour le contexte'
            }
            elseif ($meetsHybridRam) {
                $status = 'Possible'
                $reason = 'dechargement partiel en RAM probable ; performances reduites'
            }
            else {
                $reason = "VRAM insuffisante (minimum prudent $($profile.MinimumVramGB) Go)"
            }
        }

        [pscustomobject]@{
            Choice = $profile.Choice
            Name = $profile.Name
            DisplayName = $profile.DisplayName
            Status = $status
            Reason = $reason
            PreferredVramGB = $profile.PreferredVramGB
            MinimumRamGB = $profile.MinimumRamGB
            CapabilityRank = $profile.CapabilityRank
        }
    }

    $recommended = $results |
        Where-Object Status -EQ 'Recommande' |
        Sort-Object CapabilityRank -Descending |
        Select-Object -First 1
    if ($null -eq $recommended) {
        # Sans correspondance ideale, le choix le plus leger limite le risque
        # de timeout et de saturation lors d'un premier lancement.
        $recommended = $results |
            Where-Object Status -EQ 'Possible' |
            Sort-Object PreferredVramGB, MinimumRamGB |
            Select-Object -First 1
    }

    return [pscustomobject]@{
        Models = @($results)
        RecommendedChoice = if ($null -ne $recommended) { $recommended.Choice } else { $null }
        RecommendedModel = if ($null -ne $recommended) { $recommended.Name } else { $null }
    }
}
# endregion Recommandation

Export-ModuleMember -Function @(
    'Get-LocalAiHardwareProfile',
    'Get-LocalAiModelProfiles',
    'Get-LocalAiRecommendation'
)
