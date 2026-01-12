#requires -Modules Microsoft.Graph

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Paths & Logging

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptRoot 'Logs'
$LogFile = Join-Path $LogDir ("TeamsCallExport_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = "[AppOnly] {0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Level, $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

#endregion

#region Load .env (INLINE – NO MODULE)

$EnvPath = Join-Path $ScriptRoot '.env'

if (-not (Test-Path $EnvPath)) {
    Write-Log "Env file not found: $EnvPath" 'ERROR'
    throw
}

Get-Content $EnvPath | ForEach-Object {
    if ($_ -match '^\s*#' -or [string]::IsNullOrWhiteSpace($_)) {
        return
    }

    if ($_ -match '^\s*([^=\s]+)\s*=\s*(.*)\s*$') {
        [Environment]::SetEnvironmentVariable(
            $matches[1],
            $matches[2],
            'Process'
        )
    }
}

Write-Log "Environment variables loaded from $EnvPath"

#endregion

#region Validate Required Environment Variables

$requiredVars = @(
    'TENANT_ID',
    'CLIENT_ID',
    'CLIENT_SECRET',
    'EXPORT_DIR'
)

foreach ($var in $requiredVars) {
    $value = (Get-Item "Env:$var" -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Log "Missing required environment variable: $var" 'ERROR'
        throw "Missing required environment variable: $var"
    }
}

#endregion

#region Prepare Export Directory

if (-not (Test-Path $env:EXPORT_DIR)) {
    New-Item -ItemType Directory -Path $env:EXPORT_DIR -Force | Out-Null
    Write-Log "Created export directory: $($env:EXPORT_DIR)"
}

#endregion

#region Connect to Microsoft Graph (App-Only)

try {
    Write-Log "Connecting to Microsoft Graph (App-Only)"

    Import-Module Microsoft.Graph.Authentication -Force
    # Select-MgProfile -Name "v1.0"

    $secureSecret = ConvertTo-SecureString $env:CLIENT_SECRET -AsPlainText -Force
    $clientSecretCredential = New-Object System.Management.Automation.PSCredential (
        $env:CLIENT_ID,
        $secureSecret
    )

    Connect-MgGraph `
        -TenantId $env:TENANT_ID `
        -ClientSecretCredential $clientSecretCredential `
        -NoWelcome

    $ctx = Get-MgContext
    if (-not $ctx -or -not $ctx.TenantId) {
        throw "Graph context validation failed"
    }

    Write-Log "Connected to Microsoft Graph. TenantId=$($ctx.TenantId)"
}
catch {
    Write-Log "Microsoft Graph connection failed: $_" 'ERROR'
    throw
}

#endregion

#region Fetch Teams Call Records

try {
    Write-Log "Fetching Teams Call Records"

    $records = @()
    $response = Get-MgCommunicationCallRecord
    #$response = Get-MgCommunicationCallRecord -PageSize 100
    $records += $response

    while ($response.'@odata.nextLink') {
        $response = Invoke-MgGraphRequest `
            -Method GET `
            -Uri $response.'@odata.nextLink'

        $records += $response.value
    }

    Write-Log "Fetched $($records.Count) call records"
}
catch {
    Write-Log "Error fetching call records: $_" 'ERROR'
    throw
}

#endregion

#region Export to CSV

try {
    $exportFile = Join-Path $env:EXPORT_DIR (
        "TeamsCallRecords_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date)
    )

    $records | Select-Object `
        Id,
    StartDateTime,
    EndDateTime,
    Type,
    Modalities,
    Organizer |
    Export-Csv -Path $exportFile -NoTypeInformation -Encoding UTF8

    Write-Log "Export completed: $exportFile"
}
catch {
    Write-Log "Export failed: $_" 'ERROR'
    throw
}

#endregion

#region Cleanup

Disconnect-MgGraph | Out-Null
Write-Log "Disconnected from Microsoft Graph"
Write-Log "Script completed successfully"

#endregion
