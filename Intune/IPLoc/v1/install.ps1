<#
.SYNOPSIS
  Installation script for IP Location Detection
.VERSION
  1.1 - Pouziva LogHelper modul
#>

[CmdletBinding()]
param()

#region Config
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$LogModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$LogFile = "IPcheck_Install.log"
#endregion

#region Functions
function Initialize-Logging {
    <#
    .SYNOPSIS
        Inicializuje logovanie cez LogHelper modul
    #>
    try {
        if (Test-Path $LogModulePath) {
            Import-Module $LogModulePath -Force -ErrorAction Stop
            Write-Verbose "LogHelper modul uspesne naimportovany" -Verbose
            return $true
        }
        else {
            # Fallback logging
            Write-Host "WARNING: LogHelper modul nebol najdeny na $LogModulePath" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "ERROR: Nepodarilo sa importovat LogHelper: $_" -ForegroundColor Red
        return $false
    }
}

function Write-InstallLog {
    <#
    .SYNOPSIS
        Wrapper pre logovanie install skriptu
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"
    
    # Zapísať do konzoly
    Write-Host $logMessage
    
    # Pokúsiť sa zapísať cez LogHelper
    try {
        Write-IntuneLog -Message $Message -Level $Level -LogFile $LogFile -EventSource $ScriptName
    }
    catch {
        # Fallback na lokálny súbor
        try {
            $logDir = "C:\TaurisIT\Log\IPcheck"
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
            }
            Add-Content -Path (Join-Path $logDir $LogFile) -Value $logMessage -ErrorAction Stop
        }
        catch {
            # Len konzolový výstup
        }
    }
}
#endregion

#region Main Execution
try {
    # Inicializacia logovania
    $loggingInitialized = Initialize-Logging
    
    Write-InstallLog -Message "=== IP Location Detection Installation zaciatok ===" -Level INFO
    Write-InstallLog -Message "Script verzia: 1.1 (LogHelper integracia)" -Level INFO
    Write-InstallLog -Message "Computer: $env:COMPUTERNAME" -Level INFO
    Write-InstallLog -Message "Logging module: $(if ($loggingInitialized) {'OK'} else {'Failed'})" -Level INFO

    # Create directory for scripts
    $scriptDir = "C:\TaurisIT\IPcheck"
    $logDir = "C:\TaurisIT\Log\IPcheck"

    # Create directories
    Write-InstallLog -Message "Vytvaram adresare..." -Level INFO
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    Write-InstallLog -Message "Adresar vytvoreny: $scriptDir" -Level INFO
    
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Write-InstallLog -Message "Adresar vytvoreny: $logDir" -Level INFO

    # Copy all files
    Write-InstallLog -Message "Kopirujem subory..." -Level INFO
    Copy-Item -Path "$PSScriptRoot\*" -Destination $scriptDir -Force -Recurse
    Write-InstallLog -Message "Subory uspesne skopirovane do $scriptDir" -Level INFO

    # Create scheduled task for detection
    Write-InstallLog -Message "Vytvaram scheduled task..." -Level INFO
    
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-ExecutionPolicy Bypass -File `"$scriptDir\detection.ps1`""

    $trigger = New-ScheduledTaskTrigger -Daily -At "7:30 AM"

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName "TaurisIT-IPLocation-Detection" `
        -Action $action -Trigger $trigger -Principal $principal `
        -Description "Detects device location based on IP" -Force

    Write-InstallLog -Message "Scheduled task vytvoreny: TaurisIT-IPLocation-Detection" -Level SUCCESS

    Write-InstallLog -Message "=== Installation uspesne dokoncena ===" -Level SUCCESS
    Write-InstallLog -Message "Scripty nainstalovane v: $scriptDir" -Level INFO
    Write-InstallLog -Message "Logy budu ukladane do: $logDir" -Level INFO
    
    exit 0
}
catch {
    $errorMsg = $_.Exception.Message
    Write-InstallLog -Message "INSTALACNA CHYBA: $errorMsg" -Level ERROR
    
    if ($_.ScriptStackTrace) {
        Write-InstallLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    }
    
    exit 1
}
#endregion