<#
.SYNOPSIS
    LogHelper Adapter Module
.DESCRIPTION
    Adapter pre kompatibilitu medzi starým LogHelper modulom a novými skriptmi
.VERSION
    1.0
.AUTHOR
    TaurisIT
#>

function Initialize-LogSystem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,
        
        [Parameter(Mandatory = $true)]
        [string]$EventSource
    )
    
    # Store for later use
    $global:LogHelper_EventSource = $EventSource
    $global:LogHelper_LogDirectory = $LogDirectory
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        Write-Verbose "Created log directory: $LogDirectory"
    }
    
    Write-Verbose "Log system initialized for: $EventSource"
}

function Write-IntuneLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level,
        
        [string]$EventSource = $global:LogHelper_EventSource
    )
    
    # Map log levels
    $eventType = switch ($Level) {
        'INFO' { 'Information' }
        'SUCCESS' { 'Information' }
        'WARN' { 'Warning' }
        'ERROR' { 'Error' }
        'DEBUG' { 'Information' }
        default { 'Information' }
    }
    
    # Format log file name
    $logFile = Join-Path $global:LogHelper_LogDirectory "IPcheck_$(Get-Date -Format 'yyyyMMdd').log"
    
    # Call original Write-CustomLog function
    if (Get-Command Write-CustomLog -ErrorAction SilentlyContinue) {
        Write-CustomLog -Message $Message -EventSource $EventSource -Type $eventType -LogFileName $logFile
    }
    else {
        # Fallback if Write-CustomLog not available
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp [$Level] $Message"
        
        # Write to file
        Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
        
        # Also write to console
        $color = switch ($Level) {
            'ERROR' { 'Red' }
            'WARN' { 'Yellow' }
            'SUCCESS' { 'Green' }
            default { 'White' }
        }
        Write-Host $logEntry -ForegroundColor $color
    }
}

function Clear-OldLogs {
    param(
        [int]$RetentionDays = 30
    )
    
    $LogDirectory = $global:LogHelper_LogDirectory
    
    if (Test-Path $LogDirectory) {
        try {
            $oldLogs = Get-ChildItem -Path $LogDirectory -Filter *.log | Where-Object {
                $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays)
            }
            
            if ($oldLogs.Count -gt 0) {
                Write-Verbose "Removing $($oldLogs.Count) old log files (> $RetentionDays days)"
                $oldLogs | Remove-Item -Force
            }
        }
        catch {
            Write-Warning "Failed to clear old logs: $_"
        }
    }
}

function Send-IntuneAlert {
    param(
        [string]$Message,
        [string]$Severity,
        [string]$EventSource
    )
    
    # Map severity to log level
    $level = switch ($Severity) {
        'Error' { 'ERROR' }
        'Warning' { 'WARN' }
        default { 'INFO' }
    }
    
    # Log as error
    Write-IntuneLog -Message "ALERT: $Message" -Level $level -EventSource $EventSource
}

Export-ModuleMember -Function Initialize-LogSystem, Write-IntuneLog, Clear-OldLogs, Send-IntuneAlert