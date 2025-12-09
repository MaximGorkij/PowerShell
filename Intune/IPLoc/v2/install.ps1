<#
.SYNOPSIS
  Inštalačný skript pre IP Location Detection System
.DESCRIPTION
  Inštaluje všetky potrebné súbory a vytvorí Scheduled Task pre pravidelnú detekciu
  a automatickú remédiáciu, ak je potrebná
.VERSION
  1.4 - Simple and working version
.AUTHOR
  TaurisIT
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$TestOnly,
    [string]$InstallPath = "C:\TaurisIT\IPcheck"
)

#region Configuration
$ScriptName = "IPLocation-Installer"
$Paths = @{
    ScriptDir    = $InstallPath
    LogDir       = "C:\TaurisIT\Log\IPcheck"
    RegistryPath = "HKLM:\SOFTWARE\TaurisIT\IPcheck"
    TaskName     = "TaurisIT-IPLocation-Detection"
}
#endregion

#region Functions
function Write-InstallLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp [$Level] $Message" -ForegroundColor White
}

function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-Dirs {
    $directories = @($Paths.ScriptDir, $Paths.LogDir)
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-InstallLog -Message "Created directory: $dir" -Level "INFO"
            }
            catch {
                Write-InstallLog -Message "Failed to create directory $dir $_" -Level "ERROR"
                return $false
            }
        }
    }
    
    return $true
}

function Copy-Files {
    param([string]$SourceDir = $PSScriptRoot)
    
    Write-InstallLog -Message "Copying files..." -Level "INFO"
    
    # Copy all necessary files
    $files = Get-ChildItem -Path $SourceDir -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '\.(ps1|psm1|json)$' -and $_.Name -notmatch '^install\.ps1$'
    }
    
    foreach ($file in $files) {
        $destination = Join-Path $Paths.ScriptDir $file.Name
        
        if ($Force -or (-not (Test-Path $destination))) {
            try {
                Copy-Item -Path $file.FullName -Destination $destination -Force -ErrorAction Stop
                Write-InstallLog -Message "  Copied: $($file.Name)" -Level "DEBUG"
            }
            catch {
                Write-InstallLog -Message "  Failed: $($file.Name)" -Level "ERROR"
            }
        }
    }
    
    return $true
}

function New-ScheduledTask {
    Write-InstallLog -Message "Creating Scheduled Task with Auto-Remediation..." -Level "INFO"
    
    $taskName = $Paths.TaskName
    $scriptDir = $Paths.ScriptDir
    
    # Check if task already exists
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        if ($Force) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            Write-InstallLog -Message "Removed existing task" -Level "INFO"
        }
        else {
            Write-InstallLog -Message "Task already exists" -Level "WARN"
            return $true
        }
    }
    
    # Create a simple batch file that runs both detection and remediation
    $batchContent = @"
@echo off
echo [%date% %time%] Starting IP Location Detection...

cd /d "$scriptDir"

echo [%date% %time%] Running detection...
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "detection.ps1"

if %errorlevel% equ 1 (
    echo [%date% %time%] Remediation required, running remediation...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "remediation.ps1"
    if %errorlevel% equ 0 (
        echo [%date% %time%] Remediation successful
    ) else (
        echo [%date% %time%] Remediation failed
    )
) else (
    echo [%date% %time%] No remediation needed
)

echo [%date% %time%] Task completed
"@
    
    $batchPath = Join-Path $scriptDir "run_detection.bat"
    Set-Content -Path $batchPath -Value $batchContent -Encoding ASCII
    
    # Create the task using schtasks (most reliable)
    $schtasksCommand = "schtasks.exe /Create /TN `"$taskName`" /TR `"$batchPath`" /SC WEEKLY /D MON,TUE,WED,THU,FRI /ST 08:00 /RU SYSTEM /RL HIGHEST /F"
    
    try {
        $output = cmd.exe /c $schtasksCommand 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-InstallLog -Message "Scheduled Task created successfully" -Level "SUCCESS"
            
            # Verify
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($task) {
                Write-InstallLog -Message "Task: $($task.State), Schedule: Weekdays 8:00 AM" -Level "INFO"
            }
            
            return $true
        }
        else {
            Write-InstallLog -Message "Failed to create task: $output" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-InstallLog -Message "Error creating task: $_" -Level "ERROR"
        return $false
    }
}

function Test-Install {
    Write-InstallLog -Message "Testing installation..." -Level "INFO"
    
    # Check files
    $requiredFiles = @(
        "detection.ps1",
        "remediation.ps1", 
        "CommonFunctions.psm1",
        "GraphHelper.psm1",
        "IPLocationMap.json",
        "config.json"
    )
    
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $Paths.ScriptDir $file
        if (Test-Path $filePath) {
            Write-InstallLog -Message "✓ $file" -Level "SUCCESS"
        }
        else {
            Write-InstallLog -Message "✗ $file" -Level "ERROR"
        }
    }
    
    # Check task
    $task = Get-ScheduledTask -TaskName $Paths.TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-InstallLog -Message "✓ Scheduled Task" -Level "SUCCESS"
    }
    else {
        Write-InstallLog -Message "✗ Scheduled Task" -Level "ERROR"
    }
    
    return $true
}

function New-IntunePackage {
    Write-InstallLog -Message "Creating Intune package..." -Level "INFO"
    
    $packageDir = Join-Path $env:TEMP "Intune-IPLocation-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    try {
        # Create directory
        New-Item -Path $packageDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        
        # Copy ALL files from installation directory
        $files = Get-ChildItem -Path $Paths.ScriptDir -File | Where-Object {
            $_.Name -notmatch '^(install\.ps1|run_detection\.bat)$'
        }
        
        foreach ($file in $files) {
            Copy-Item -Path $file.FullName -Destination (Join-Path $packageDir $file.Name) -Force
            Write-InstallLog -Message "  Copied: $($file.Name)" -Level "DEBUG"
        }
        
        # Create setup script
        $setupScript = @'
<#
.SYNOPSIS
  Intune Setup Script
#>

try {
    $installerPath = Join-Path $PSScriptRoot "install.ps1"
    if (Test-Path $installerPath) {
        & powershell.exe -ExecutionPolicy Bypass -File "$installerPath" -Force
        exit 0
    }
    else {
        Write-Error "Installer not found"
        exit 1
    }
}
catch {
    Write-Error $_
    exit 1
}
'@
        
        Set-Content -Path (Join-Path $packageDir "setup.ps1") -Value $setupScript -Encoding UTF8
        
        # Create detection script for Intune
        $detectScript = @'
<#
.SYNOPSIS
  Intune Detection Script
#>

try {
    $registryPath = "HKLM:\SOFTWARE\TaurisIT\IPcheck"
    $taskName = "TaurisIT-IPLocation-Detection"
    
    if (-not (Test-Path $registryPath)) {
        Write-Host "Registry not found"
        exit 1
    }
    
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "Task not found"
        exit 1
    }
    
    Write-Host "IP Location Detection installed"
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
'@
        
        Set-Content -Path (Join-Path $packageDir "detect.ps1") -Value $detectScript -Encoding UTF8
        
        # Create uninstall script
        $uninstallScript = @'
<#
.SYNOPSIS
  Intune Uninstall Script
#>

try {
    $taskName = "TaurisIT-IPLocation-Detection"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    
    $registryPath = "HKLM:\SOFTWARE\TaurisIT\IPcheck"
    if (Test-Path $registryPath) {
        Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "Uninstalled"
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
'@
        
        Set-Content -Path (Join-Path $packageDir "uninstall.ps1") -Value $uninstallScript -Encoding UTF8
        
        # Show summary
        Write-InstallLog -Message "Package created: $packageDir" -Level "SUCCESS"
        
        $fileCount = (Get-ChildItem $packageDir -File).Count
        Write-Host "`n📦 Package contains $fileCount files:" -ForegroundColor Cyan
        Get-ChildItem $packageDir -File | ForEach-Object {
            Write-Host "  • $($_.Name)" -ForegroundColor Gray
        }
        
        Write-Host "`n📋 Next steps:" -ForegroundColor Yellow
        Write-Host "  1. Use IntuneWinAppUtil.exe" -ForegroundColor Gray
        Write-Host "  2. Command: .\IntuneWinAppUtil.exe -c `"$packageDir`" -s setup.ps1 -o .\Output" -ForegroundColor Gray
        Write-Host "  3. Upload generated .intunewin file to Intune" -ForegroundColor Gray
        
        # Open folder
        $open = Read-Host "`nOpen package folder? (Y/N)"
        if ($open -eq 'Y' -or $open -eq 'y') {
            Start-Process explorer.exe -ArgumentList $packageDir
        }
        
        return $true
    }
    catch {
        Write-InstallLog -Message "Failed to create package: $_" -Level "ERROR"
        return $false
    }
}
#endregion

#region Main Execution
try {
    Write-Host "" 
    Write-Host "=== IP Location Detection Installer ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check admin
    if (-not (Test-Admin)) {
        Write-InstallLog -Message "Run as Administrator" -Level "ERROR"
        exit 1
    }
    
    # Test mode
    if ($TestOnly) {
        Write-InstallLog -Message "Test mode" -Level "INFO"
        exit 0
    }
    
    # Installation steps
    Write-InstallLog -Message "Step 1: Creating directories..." -Level "INFO"
    if (-not (New-Dirs)) { throw "Failed to create directories" }
    
    Write-InstallLog -Message "Step 2: Copying files..." -Level "INFO"
    if (-not (Copy-Files)) { throw "Failed to copy files" }
    
    Write-InstallLog -Message "Step 3: Creating Scheduled Task..." -Level "INFO"
    if (-not (New-ScheduledTask)) { throw "Failed to create task" }
    
    Write-InstallLog -Message "Step 4: Testing..." -Level "INFO"
    Test-Install
    
    # Show summary
    Write-Host "`n✅ Installation completed successfully!" -ForegroundColor Green
    Write-Host "📁 Scripts: $($Paths.ScriptDir)" -ForegroundColor Gray
    Write-Host "📝 Logs: $($Paths.LogDir)" -ForegroundColor Gray
    Write-Host "🕐 Task: $($Paths.TaskName) (Weekdays 8:00 AM)" -ForegroundColor Gray
    Write-Host "⚙️  Auto-remediation: ENABLED" -ForegroundColor Green
    
    # Ask about Intune package
    Write-Host ""
    $create = Read-Host "Create Intune package? (Y/N)"
    if ($create -eq 'Y' -or $create -eq 'y') {
        New-IntunePackage
    }
    
    exit 0
}
catch {
    Write-InstallLog -Message "Installation failed: $_" -Level "ERROR"
    exit 1
}
#endregion