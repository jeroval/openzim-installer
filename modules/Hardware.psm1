#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LocalAi.Hardware.psm1')

function Get-LocalCodexHardware {
    $legacy = Get-LocalAiHardwareProfile
    $errors = @()
    $cpu = $null; $os = $null; $gpu = @(); $disk = $null
    try { $cpu = @(Get-CimInstance Win32_Processor -ErrorAction Stop) }
    catch { $errors += "CPU : $($_.Exception.Message)" }
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop }
    catch { $errors += "OS : $($_.Exception.Message)" }
    try { $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object Name,AdapterCompatibility,DriverVersion) }
    catch { $errors += "GPU : $($_.Exception.Message)" }
    try { $disk = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | Select-Object DeviceID,Size,FreeSpace) }
    catch { $errors += "Disque : $($_.Exception.Message)" }
    [pscustomobject]@{
        cpu = $cpu | Select-Object Name,Architecture,NumberOfCores,NumberOfLogicalProcessors
        ramTotalGB = $legacy.RamGB
        ramAvailableGB = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { $null }
        gpu = $gpu; vramGB = $legacy.VramGB; vramSource = $legacy.VramSource
        vramReliable = $legacy.VramReliable
        backend = if ($legacy.VramSource -eq 'nvidia-smi') { 'NVIDIA detecte ; offload a mesurer' } else { 'a mesurer avec Ollama' }
        os = if ($os) { $os.Caption } else { [Environment]::OSVersion.ToString() }
        architecture = $env:PROCESSOR_ARCHITECTURE
        disks = $disk; delegation = $false; errors = $errors
    }
}

Export-ModuleMember -Function Get-LocalCodexHardware
