<#
.SYNOPSIS
  Enhanced Uninstallation Script for IP Location Detection
.DESCRIPTION
  Odstráni všetky komponenty IP Location Detection systému
.VERSION
  3.0
.AUTHOR
  TaurisIT
#>

[CmdletBinding()]
param(
    [switch]$KeepLogs,
    [switch]$KeepRegistry,
    [switch]$Force
)

#region Configuration
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$ErrorActionPreference = "Stop"

$UninstallPaths = @{
    ScriptDir    = "C:\TaurisIT\IPcheck"
    LogDir       = "C:\TaurisIT\Log\IPcheck"
    RegistryPath = "HKLM:\SOFTWARE\TaurisIT\IPcheck"
    ModuleDir    = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
}
#endregion

#region Functions
function Write-UninstallLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"
    
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN' { 'Yellow' }
        'SUCCESS' { 'Green' }
        default { 'White' }
    }
    
    Write-Host $logMessage -ForegroundColor $color
    
    # Log to file if directory exists
    try {
        if (Test-Path $UninstallPaths.LogDir) {
            $logFile = Join-Path $UninstallPaths.LogDir "IPcheck_Uninstall.log"
            Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Silent fail
    }
}

function Confirm-Uninstall {
    if ($Force) {
        return $true
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  WARNING: Uninstall IP Location Detection" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This will remove:" -ForegroundColor White
    Write-Host "  - Scheduled task" -ForegroundColor White
    Write-Host "  - Script files from $($UninstallPaths.ScriptDir)" -ForegroundColor White
    
    if (-not $KeepLogs) {
        Write-Host "  - Log files from $($UninstallPaths.LogDir)" -ForegroundColor White
    }
    
    if (-not $KeepRegistry) {
        Write-Host "  - Registry data from $($UninstallPaths.RegistryPath)" -ForegroundColor White
    }
    
    Write-Host "  - LogHelper module" -ForegroundColor White
    Write-Host ""
    
    $response = Read-Host "Are you sure you want to continue? (yes/no)"
    
    return ($response -eq "yes")
}

function Remove-ScheduledTask {
    Write-UninstallLog -Message "Removing scheduled task..." -Level INFO
    
    try {
        $taskName = "TaurisIT-IPLocation-Detection"
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        
        if ($task) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-UninstallLog -Message "Scheduled task removed: $taskName" -Level SUCCESS
        }
        else {
            Write-UninstallLog -Message "Scheduled task not found (already removed?)" -Level INFO
        }
    }
    catch {
        Write-UninstallLog -Message "Failed to remove scheduled task: $_" -Level WARN
    }
}

function Remove-ScriptFiles {
    Write-UninstallLog -Message "Removing script files..." -Level INFO
    
    try {
        if (Test-Path $UninstallPaths.ScriptDir) {
            Remove-Item -Path $UninstallPaths.ScriptDir -Recurse -Force -ErrorAction Stop
            Write-UninstallLog -Message "Script directory removed: $($UninstallPaths.ScriptDir)" -Level SUCCESS
        }
        else {
            Write-UninstallLog -Message "Script directory not found" -Level INFO
        }
    }
    catch {
        Write-UninstallLog -Message "Failed to remove script directory: $_" -Level ERROR
        throw
    }
}

function Remove-LogFiles {
    if ($KeepLogs) {
        Write-UninstallLog -Message "Log files preserved (KeepLogs flag)" -Level INFO
        return
    }
    
    Write-UninstallLog -Message "Removing log files..." -Level INFO
    
    try {
        if (Test-Path $UninstallPaths.LogDir) {
            # Create final uninstall log entry
            $finalLog = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [INFO] IP Location Detection uninstalled"
            Add-Content -Path (Join-Path $UninstallPaths.LogDir "IPcheck_Uninstall.log") `
                -Value $finalLog -ErrorAction SilentlyContinue
            
            Remove-Item -Path $UninstallPaths.LogDir -Recurse -Force -ErrorAction Stop
            Write-UninstallLog -Message "Log directory removed: $($UninstallPaths.LogDir)" -Level SUCCESS
        }
        else {
            Write-UninstallLog -Message "Log directory not found" -Level INFO
        }
    }
    catch {
        Write-UninstallLog -Message "Failed to remove log directory: $_" -Level WARN
    }
}

function Remove-RegistryData {
    if ($KeepRegistry) {
        Write-UninstallLog -Message "Registry data preserved (KeepRegistry flag)" -Level INFO
        return
    }
    
    Write-UninstallLog -Message "Removing registry data..." -Level INFO
    
    try {
        if (Test-Path $UninstallPaths.RegistryPath) {
            Remove-Item -Path $UninstallPaths.RegistryPath -Recurse -Force -ErrorAction Stop
            Write-UninstallLog -Message "Registry data removed: $($UninstallPaths.RegistryPath)" -Level SUCCESS
        }
        else {
            Write-UninstallLog -Message "Registry path not found" -Level INFO
        }
    }
    catch {
        Write-UninstallLog -Message "Failed to remove registry data: $_" -Level WARN
    }
}

function Remove-Modules {
    Write-UninstallLog -Message "Removing modules..." -Level INFO
    
    try {
        if (Test-Path $UninstallPaths.ModuleDir) {
            Remove-Item -Path $UninstallPaths.ModuleDir -Recurse -Force -ErrorAction Stop
            Write-UninstallLog -Message "LogHelper module removed" -Level SUCCESS
        }
        else {
            Write-UninstallLog -Message "LogHelper module not found" -Level INFO
        }
    }
    catch {
        Write-UninstallLog -Message "Failed to remove module: $_" -Level WARN
    }
}

function Test-CleanUninstall {
    Write-UninstallLog -Message "Verifying uninstallation..." -Level INFO
    
    $remaining = @()
    
    # Check scheduled task
    $task = Get-ScheduledTask -TaskName "TaurisIT-IPLocation-Detection" -ErrorAction SilentlyContinue
    if ($task) {
        $remaining += "Scheduled task"
    }
    
    # Check script directory
    if (Test-Path $UninstallPaths.ScriptDir) {
        $remaining += "Script directory"
    }
    
    # Check logs (if not keeping)
    if (-not $KeepLogs -and (Test-Path $UninstallPaths.LogDir)) {
        $remaining += "Log directory"
    }
    
    # Check registry (if not keeping)
    if (-not $KeepRegistry -and (Test-Path $UninstallPaths.RegistryPath)) {
        $remaining += "Registry data"
    }
    
    
    if ($remaining.Count -gt 0) {
        Write-UninstallLog -Message "WARNING: Some components remain: $($remaining -join ', ')" -Level WARN
        return $false
    }
    else {
        Write-UninstallLog -Message "Clean uninstall verified" -Level SUCCESS
        return $true
    }
}
#endregion

#region Main Execution
try {
    Write-UninstallLog -Message "=== IP Location Detection Uninstallation Start ===" -Level INFO
    Write-UninstallLog -Message "Computer: $env:COMPUTERNAME" -Level INFO
    
    # Confirm uninstall
    if (-not (Confirm-Uninstall)) {
        Write-UninstallLog -Message "Uninstallation cancelled by user" -Level INFO
        exit 0
    }
    
    Write-Host ""
    
    # Remove components
    Remove-ScheduledTask
    Remove-ScriptFiles
    Remove-LogFiles
    Remove-RegistryData
    Remove-Modules
    
    # Verify
    Write-Host ""
    $cleanUninstall = Test-CleanUninstall
    
    Write-Host ""
    Write-UninstallLog -Message "=== Uninstallation Completed ===" -Level SUCCESS
    
    if ($KeepLogs) {
        Write-Host ""
        Write-Host "Log files preserved at: $($UninstallPaths.LogDir)" -ForegroundColor Yellow
    }
    
    if ($KeepRegistry) {
        Write-Host ""
        Write-Host "Registry data preserved at: $($UninstallPaths.RegistryPath)" -ForegroundColor Yellow
    }
    
    exit 0
}
catch {
    $errorMsg = $_.Exception.Message
    Write-UninstallLog -Message "UNINSTALLATION FAILED: $errorMsg" -Level ERROR
    
    if ($_.ScriptStackTrace) {
        Write-UninstallLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    }
    
    exit 1
}
#endregion