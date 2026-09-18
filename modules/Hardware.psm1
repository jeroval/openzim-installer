#requires -Version 5.1
Set-StrictMode -Version Latest
function Get-LocalCodexHardware {
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
    $ram = try { [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB, 1) }
    catch { $errors += "RAM : $($_.Exception.Message)"; $null }
    $vram = $null; $vramSource = 'indisponible'; $vramReliable = $false
    $nvidia = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nvidia) {
        $values = @(& $nvidia.Source '--query-gpu=memory.total' '--format=csv,noheader,nounits' 2>$null |
            ForEach-Object { if ($_ -match '^\s*(\d+)') { [double] $matches[1] } })
        if ($values.Count) {
            $vram = [math]::Round(($values | Measure-Object -Maximum).Maximum / 1024, 1)
            $vramSource = 'nvidia-smi'; $vramReliable = $true
        }
    }
    if ($null -eq $vram) {
        try {
            $values = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Video' -ErrorAction Stop |
                Get-ChildItem -ErrorAction SilentlyContinue | ForEach-Object {
                    $properties = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    $property = $properties.PSObject.Properties['HardwareInformation.qwMemorySize']
                    if ($property -and [double] $property.Value -gt 0) { [double] $property.Value }
                })
            if ($values.Count) {
                $vram = [math]::Round(($values | Measure-Object -Maximum).Maximum / 1GB, 1)
                $vramSource = 'registre Windows'; $vramReliable = $true
            }
        }
        catch { $errors += "VRAM : $($_.Exception.Message)" }
    }
    [pscustomobject]@{
        cpu = $cpu | Select-Object Name,Architecture,NumberOfCores,NumberOfLogicalProcessors
        ramTotalGB = $ram
        ramAvailableGB = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { $null }
        gpu = $gpu; vramGB = $vram; vramSource = $vramSource
        vramReliable = $vramReliable
        backend = if ($vramReliable) { 'GPU detecte ; offload a mesurer' } else { 'CPU ou iGPU ; a mesurer avec Ollama' }
        os = if ($os) { $os.Caption } else { [Environment]::OSVersion.ToString() }
        architecture = $env:PROCESSOR_ARCHITECTURE
        disks = $disk; delegation = $false; errors = $errors
    }
}

Export-ModuleMember -Function Get-LocalCodexHardware
