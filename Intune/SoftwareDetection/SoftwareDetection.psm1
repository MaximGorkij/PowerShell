# Cesta k log súboru
$Script:LogFile = Join-Path $PSScriptRoot 'software-detection.log'

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp [$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $logEntry
}

function Get-InstalledSoftware {
    param (
        [string]$SoftwareName
    )
    $locations = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    
    foreach ($location in $locations) {
        Get-ItemProperty -Path $location -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -like "*$SoftwareName*" } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    }
}

function Find-Software {
    param (
        [string]$Name,
        [string]$RequiredVersion,
        [string]$Mode = 'Requirement'  # alebo 'Detection'
    )

    Write-Log -Message "Checking for '$Name' with required version '$RequiredVersion' in mode '$Mode'"

    $software = Get-InstalledSoftware -SoftwareName $Name

    if ($software) {
        Write-Log -Message "Installed version found: $($software.DisplayVersion)"
        
        if ($Mode -eq 'Requirement') {
            if ($software.DisplayVersion -eq $RequiredVersion) {
                Write-Log -Message "Requirement met — exiting with code 0"
                return $true
            } else {
                Write-Log -Message "Installed version '$($software.DisplayVersion)' does not match required version '$RequiredVersion'" -Level "WARNING"
                return $false
            }
        } else {
            Write-Log -Message "Detection mode — software found: $($software.DisplayName)"
            return $true
        }
    } else {
        Write-Log -Message "Software '$Name' not found" -Level "ERROR"
        return $false
    }
}