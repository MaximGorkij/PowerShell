<#
.SYNOPSIS
  Enhanced Installation Script for IP Location Detection
.DESCRIPTION
  Inštaluje všetky potrebné súbory, moduly a scheduled task
  
  IMPROVEMENTS:
  - Module installation
  - Configuration validation
  - Health check integration
  - Better error handling
  
.VERSION
  3.0 - Enhanced installation
.AUTHOR
  TaurisIT
#>

[CmdletBinding()]
param(
    [switch]$SkipScheduledTask,
    [switch]$ValidateOnly
)

#region Configuration
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$ErrorActionPreference = "Stop"

$InstallPaths = @{
    ScriptDir = "C:\TaurisIT\IPcheck"
    LogDir    = "C:\TaurisIT\Log\IPcheck"
    ModuleDir = "C:\Program Files\WindowsPowerShell\Modules"
}

$RequiredFiles = @(
    "detection.ps1",
    "remediation.ps1",
    "IPLocationMap.json",
    "config.json",
    "CommonFunctions.psm1",
    "GraphHelper.psm1",
    "LogHelperAdapter.psm1"
)
#endregion

#region Functions
function Write-InstallLog {
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
    
    # Log to file
    try {
        $logFile = Join-Path $InstallPaths.LogDir "IPcheck_Install.log"
        if (-not (Test-Path $InstallPaths.LogDir)) {
            New-Item -ItemType Directory -Path $InstallPaths.LogDir -Force | Out-Null
        }
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    }
    catch {
        # Silent fail
    }
}

function Test-Prerequisites {
    Write-InstallLog -Message "Checking prerequisites..." -Level INFO
    
    $issues = @()
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $issues += "PowerShell 5.0 or higher required (current: $($PSVersionTable.PSVersion))"
    }
    
    # Check admin rights
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        $issues += "Administrator rights required"
    }
    
    # Check required files
    foreach ($file in $RequiredFiles) {
        if (-not (Test-Path (Join-Path $PSScriptRoot $file))) {
            $issues += "Missing required file: $file"
        }
    }
    
    if ($issues.Count -gt 0) {
        Write-InstallLog -Message "Prerequisites check failed:" -Level ERROR
        foreach ($issue in $issues) {
            Write-InstallLog -Message "  - $issue" -Level ERROR
        }
        return $false
    }
    
    Write-InstallLog -Message "Prerequisites check passed" -Level SUCCESS
    return $true
}

function Install-Directories {
    Write-InstallLog -Message "Creating directories..." -Level INFO
    
    foreach ($path in $InstallPaths.Values) {
        try {
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
                Write-InstallLog -Message "Created: $path" -Level SUCCESS
            }
            else {
                Write-InstallLog -Message "Already exists: $path" -Level INFO
            }
        }
        catch {
            Write-InstallLog -Message "Failed to create $path : $_" -Level ERROR
            throw
        }
    }
}

function Install-Files {
    Write-InstallLog -Message "Installing files..." -Level INFO
    
    try {
        # Copy all files to script directory
        $filesToCopy = Get-ChildItem -Path $PSScriptRoot -File | Where-Object { 
            $_.Name -in $RequiredFiles -or $_.Name -eq ".env"
        }
        
        foreach ($file in $filesToCopy) {
            $destination = Join-Path $InstallPaths.ScriptDir $file.Name
            Copy-Item -Path $file.FullName -Destination $destination -Force
            Write-InstallLog -Message "Copied: $($file.Name)" -Level SUCCESS
        }
        
        # Check LogHelper module
        $logHelperSource = Join-Path $PSScriptRoot "LogHelper.psm1"
        if (Test-Path $logHelperSource) {
            # Install LogHelper to module directory
            $logHelperDest = Join-Path $InstallPaths.ModuleDir "LogHelper"
            if (-not (Test-Path $logHelperDest)) {
                New-Item -ItemType Directory -Path $logHelperDest -Force | Out-Null
            }
            Copy-Item -Path $logHelperSource -Destination (Join-Path $logHelperDest "LogHelper.psm1") -Force
            Write-InstallLog -Message "Installed: LogHelper module" -Level SUCCESS
        }
        else {
            Write-InstallLog -Message "Note: LogHelper.psm1 not found in source, assuming already installed" -Level INFO
        }
        
    }
    catch {
        Write-InstallLog -Message "Failed to install files: $_" -Level ERROR
        throw
    }
}

function Install-ScheduledTask {
    if ($SkipScheduledTask) {
        Write-InstallLog -Message "Scheduled task installation skipped" -Level INFO
        return
    }
    
    Write-InstallLog -Message "Creating scheduled task..." -Level INFO
    
    try {
        $taskName = "TaurisIT-IPLocation-Detection"
        $detectionScript = Join-Path $InstallPaths.ScriptDir "detection.ps1"
        
        # Remove existing task if exists
        $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-InstallLog -Message "Removed existing scheduled task" -Level INFO
        }
        
        # Create task action
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$detectionScript`""
        
        # Create triggers
        $triggers = @()
        
        # Daily at 7:30 AM
        $triggers += New-ScheduledTaskTrigger -Daily -At "7:30 AM"
        
        # At logon
        $triggers += New-ScheduledTaskTrigger -AtLogOn
        
        # At startup
        $triggers += New-ScheduledTaskTrigger -AtStartup
        
        # Create principal (run as SYSTEM)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -RunOnlyIfNetworkAvailable -MultipleInstances IgnoreNew
        
        # Register task
        Register-ScheduledTask -TaskName $taskName `
            -Action $action `
            -Trigger $triggers `
            -Principal $principal `
            -Settings $settings `
            -Description "Detects device location based on IP address and updates Entra ID" `
            -Force | Out-Null
        
        Write-InstallLog -Message "Scheduled task created: $taskName" -Level SUCCESS
        
        # Verify task
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        Write-InstallLog -Message "Task state: $($task.State)" -Level INFO
    }
    catch {
        Write-InstallLog -Message "Failed to create scheduled task: $_" -Level ERROR
        throw
    }
}

function Test-Installation {
    Write-InstallLog -Message "Validating installation..." -Level INFO
    
    $issues = @()
    
    # Check directories
    foreach ($path in $InstallPaths.Values) {
        if (-not (Test-Path $path)) {
            $issues += "Missing directory: $path"
        }
    }
    
    # Check files
    foreach ($file in $RequiredFiles) {
        $filePath = Join-Path $InstallPaths.ScriptDir $file
        if (-not (Test-Path $filePath)) {
            $issues += "Missing file: $file"
        }
    }
    
    # Check scheduled task
    if (-not $SkipScheduledTask) {
        $task = Get-ScheduledTask -TaskName "TaurisIT-IPLocation-Detection" -ErrorAction SilentlyContinue
        if (-not $task) {
            $issues += "Scheduled task not found"
        }
    }
    
    # Check modules
    $logHelperPath = Join-Path $InstallPaths.ModuleDir "LogHelper\LogHelper.psm1"
    if (-not (Test-Path $logHelperPath)) {
        Write-InstallLog -Message "Warning: LogHelper module not found in module directory" -Level WARN
        # Not a critical issue - adapter will handle fallback
    }
    
    if ($issues.Count -gt 0) {
        Write-InstallLog -Message "Installation validation failed:" -Level ERROR
        foreach ($issue in $issues) {
            Write-InstallLog -Message "  - $issue" -Level ERROR
        }
        return $false
    }
    
    Write-InstallLog -Message "Installation validation passed" -Level SUCCESS
    return $true
}

function Show-InstallationSummary {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  IP Location Detection - Installation" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Script Directory: " -NoNewline
    Write-Host $InstallPaths.ScriptDir -ForegroundColor Green
    Write-Host "Log Directory: " -NoNewline
    Write-Host $InstallPaths.LogDir -ForegroundColor Green
    Write-Host ""
    Write-Host "Scheduled Task: " -NoNewline
    if ($SkipScheduledTask) {
        Write-Host "SKIPPED" -ForegroundColor Yellow
    }
    else {
        $task = Get-ScheduledTask -TaskName "TaurisIT-IPLocation-Detection" -ErrorAction SilentlyContinue
        if ($task) {
            Write-Host "INSTALLED ($($task.State))" -ForegroundColor Green
        }
        else {
            Write-Host "NOT FOUND" -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Configure .env file with Graph API credentials" -ForegroundColor White
    Write-Host "  2. Review config.json settings" -ForegroundColor White
    Write-Host "  3. Test with: .\detection.ps1" -ForegroundColor White
    Write-Host "  4. Run health check: .\health-check.ps1" -ForegroundColor White
    Write-Host ""
}
#endregion

#region Main Execution
try {
    Write-InstallLog -Message "=== IP Location Detection Installation Start ===" -Level INFO
    Write-InstallLog -Message "Version: 3.0 (Enhanced)" -Level INFO
    Write-InstallLog -Message "Computer: $env:COMPUTERNAME" -Level INFO
    
    # Check prerequisites
    if (-not (Test-Prerequisites)) {
        Write-InstallLog -Message "Installation aborted due to failed prerequisites" -Level ERROR
        exit 1
    }
    
    if ($ValidateOnly) {
        Write-InstallLog -Message "Validation only mode - installation skipped" -Level INFO
        exit 0
    }
    
    # Install
    Install-Directories
    Install-Files
    Install-ScheduledTask
    
    # Validate
    if (-not (Test-Installation)) {
        Write-InstallLog -Message "Installation completed with errors" -Level WARN
        exit 1
    }
    
    Write-InstallLog -Message "=== Installation Completed Successfully ===" -Level SUCCESS
    
    Show-InstallationSummary
    
    exit 0
}
catch {
    $errorMsg = $_.Exception.Message
    Write-InstallLog -Message "INSTALLATION FAILED: $errorMsg" -Level ERROR
    
    if ($_.ScriptStackTrace) {
        Write-InstallLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    }
    
    exit 1
}
#endregion