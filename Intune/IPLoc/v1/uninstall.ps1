<#
.SYNOPSIS
  Uninstallation script for IP Location Detection
.VERSION
  1.1 - Pouziva LogHelper modul
#>

[CmdletBinding()]
param()

#region Config
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$LogModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$LogFile = "IPcheck_Uninstall.log"
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

function Write-UninstallLog {
    <#
    .SYNOPSIS
        Wrapper pre logovanie uninstall skriptu
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
    
    Write-UninstallLog -Message "=== IP Location Detection Uninstallation zaciatok ===" -Level INFO
    Write-UninstallLog -Message "Script verzia: 1.1 (LogHelper integracia)" -Level INFO
    Write-UninstallLog -Message "Computer: $env:COMPUTERNAME" -Level INFO
    Write-UninstallLog -Message "Logging module: $(if ($loggingInitialized) {'OK'} else {'Failed'})" -Level INFO

    # Remove scheduled task
    Write-UninstallLog -Message "Odstranujem scheduled task..." -Level INFO
    try {
        Unregister-ScheduledTask -TaskName "TaurisIT-IPLocation-Detection" -Confirm:$false -ErrorAction Stop
        Write-UninstallLog -Message "Scheduled task uspesne odstraneny" -Level SUCCESS
    }
    catch {
        Write-UninstallLog -Message "Scheduled task neexistuje alebo sa nepodarilo odstranit: $_" -Level WARN
    }

    # Remove directories
    $scriptDir = "C:\TaurisIT\IPcheck"
    $logDir = "C:\TaurisIT\Log\IPcheck"

    Write-UninstallLog -Message "Odstranujem adresare..." -Level INFO
    
    if (Test-Path $scriptDir) {
        Remove-Item -Path $scriptDir -Recurse -Force -ErrorAction Stop
        Write-UninstallLog -Message "Adresar odstraneny: $scriptDir" -Level SUCCESS
    }
    else {
        Write-UninstallLog -Message "Adresar neexistuje: $scriptDir" -Level INFO
    }
    
    # Log adresar zachovavame pre historiu logov
    if (Test-Path $logDir) {
        Write-UninstallLog -Message "Log adresar zachovany pre historiu: $logDir" -Level INFO
    }

    Write-UninstallLog -Message "=== Uninstallation uspesne dokoncena ===" -Level SUCCESS
    Write-UninstallLog -Message "IP Location Detection uspesne odinstalovane" -Level INFO
    
    exit 0
}
catch {
    $errorMsg = $_.Exception.Message
    Write-UninstallLog -Message "ODINSTALACNA CHYBA: $errorMsg" -Level ERROR
    
    if ($_.ScriptStackTrace) {
        Write-UninstallLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    }
    
    exit 1
}
#endregion