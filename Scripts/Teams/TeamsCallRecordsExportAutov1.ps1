param(
    [datetime]$StartTime,
    [datetime]$EndTime,
    [string]$OrganizerUpn = $null
)

# Načítanie env súboru
$envPath = "D:\findrik\PowerShell\Scripts\Teams\.env"
if (Test-Path $envPath) {
    Get-Content $envPath | Where-Object { $_ -and $_ -notmatch '^#' } | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
    
    if (-not $env:EXPORT_DIR) {
        [System.Environment]::SetEnvironmentVariable("EXPORT_DIR", "C:\Skripty\Teams\Export", "Process")
    }
    
    Write-Host "Environment variables loaded from $envPath"
}
else {
    Write-Error "Env file not found: $envPath"
    exit 1
}

# Nastavenie parametrov
if ([string]::IsNullOrEmpty($OrganizerUpn)) {
    $OrganizerUpn = $env:DEFAULT_ORGANIZER
}

if (-not $StartTime) {
    $StartTime = (Get-Date).AddDays(-1).Date
}

if (-not $EndTime) {
    $EndTime = (Get-Date).Date.AddDays(1).AddSeconds(-1)
}

$ClientId = $env:CLIENT_ID
$TenantId = $env:TENANT_ID
$ClientSecret = $env:CLIENT_SECRET
$ExportDir = $env:EXPORT_DIR

if (-not (Test-Path $ExportDir)) {
    New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $ExportDir "TeamsCallRecords_AppOnly.log"
$CsvFile = Join-Path $ExportDir ("TeamsCallRecords_AppOnly_{0}_{1:yyyyMMdd}_{2:yyyyMMdd}.csv" -f `
    ($OrganizerUpn -replace "@", "_"), $StartTime, $EndTime)

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[AppOnly] $ts $Message"
    $entry | Out-File -FilePath $LogFile -Encoding UTF8 -Append
    Write-Host $entry
}

Write-Log "Starting app-only export. Organizer=$OrganizerUpn"

# Načítanie Microsoft.Graph
try {
    Remove-Module Microsoft.Graph -ErrorAction SilentlyContinue
    Remove-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
    Import-Module Microsoft.Graph -ErrorAction Stop
    Write-Log "Loaded Microsoft.Graph module"
}
catch {
    Write-Log "Error loading Microsoft.Graph: $_"
    Write-Log "Please install module: Install-Module Microsoft.Graph -Force"
    exit 1
}

# PRI POJENIE K MICROSOFT GRAPH
try {
    Write-Log "Connecting to Microsoft Graph..."
    
    # METÓDA 1: Moderný spôsob s Credential parametrom
    $SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($ClientId, $SecureSecret)
    
    Connect-MgGraph `
        -TenantId $TenantId `
        -ClientSecretCredential $Credential `
        -Scopes "https://graph.microsoft.com/.default"
    
    Write-Log "Connected to Microsoft Graph successfully"
    
    # Overiť pripojenie
    $context = Get-MgContext
    Write-Log "Connected as App: $($context.ClientId)"
    Write-Log "TenantId: $($context.TenantId)"
    Write-Log "Scopes: $($context.Scopes -join ', ')"
    
}
catch {
    Write-Log "Error connecting with ClientSecretCredential: $_"
    
    # METÓDA 2: Skúsiť iný formát
    try {
        Write-Log "Trying alternative connection format..."
        
        # Reset connection
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        
        # Skúsiť bez ClientSecretCredential parametra
        Connect-MgGraph `
            -TenantId $TenantId `
            -ClientId $ClientId `
            -ClientSecret (ConvertTo-SecureString $ClientSecret -AsPlainText -Force) `
            -Scopes "https://graph.microsoft.com/.default"
        
        Write-Log "Connected using ClientSecret parameter"
    }
    catch {
        Write-Log "Error with alternative method: $_"
        
        # METÓDA 3: Device Code Flow (pre testovanie)
        try {
            Write-Log "Trying Device Code Flow for testing..."
            Disconnect-MgGraph -ErrorAction SilentlyContinue
            
            Connect-MgGraph `
                -ClientId $ClientId `
                -Scopes "CallRecords.Read.All", "OnlineMeetings.Read.All", "Reports.Read.All" `
                -UseDeviceAuthentication
            
            Write-Log "Connected using Device Code Flow"
        }
        catch {
            Write-Log "All connection methods failed"
            Write-Log "Please check your .env file parameters and App Registration in Azure AD"
            exit 1
        }
    }
}

# ZÍSKANIE ZÁZNAMOV
Write-Log "Fetching call records..."
try {
    $allRecords = @()
    
    # Získanie všetkých záznamov
    Write-Log "Calling Get-MgCommunicationCallRecord..."
    $records = Get-MgCommunicationCallRecord -All -ErrorAction Stop
    
    $totalCount = 0
    $matchingCount = 0
    
    foreach ($rec in $records) {
        $totalCount++
        
        if ($totalCount % 50 -eq 0) {
            Write-Log "Processed $totalCount records..."
        }
        
        # Kontrola organizátora
        if ($rec.Organizer -and $rec.Organizer.Identity -and $rec.Organizer.Identity.User) {
            $org = $rec.Organizer.Identity.User.Id
            
            if ($org -and ($org -ieq $OrganizerUpn)) {
                $start = [datetime]$rec.StartDateTime
                
                # Kontrola časového rozsahu
                if ($start -ge $StartTime -and $start -le $EndTime) {
                    $matchingCount++
                    
                    # Výpočet trvania
                    $duration = $null
                    if ($rec.EndDateTime -and $rec.StartDateTime) {
                        $endTime = [datetime]$rec.EndDateTime
                        $startTime = [datetime]$rec.StartDateTime
                        $duration = New-TimeSpan -Start $startTime -End $endTime
                    }
                    
                    $allRecords += [pscustomobject]@{
                        Id            = $rec.Id
                        OrganizerUpn  = $org
                        StartDateTime = $rec.StartDateTime
                        EndDateTime   = $rec.EndDateTime
                        Modalities    = if ($rec.Modalities) { $rec.Modalities -join "," } else { "" }
                        CallType      = $rec.Type
                        Duration      = if ($duration) { $duration.ToString("hh\:mm\:ss") } else { "" }
                        Participants  = if ($rec.Participants) { $rec.Participants.Count } else { 0 }
                    }
                }
            }
        }
    }
    
    Write-Log "Total records processed: $totalCount"
    Write-Log "Matching records found: $matchingCount"
    
    if ($matchingCount -gt 0) {
        # Export do CSV
        $allRecords | Export-Csv -Path $CsvFile -Encoding UTF8 -NoTypeInformation
        Write-Log "Export complete: $CsvFile ($matchingCount records)"
        
        # Vypísať prvých 5 záznamov pre kontrolu
        Write-Log "Sample records:"
        $allRecords | Select-Object -First 5 | ForEach-Object {
            Write-Log "  $($_.StartDateTime) - $($_.CallType) (Duration: $($_.Duration))"
        }
    }
    else {
        Write-Log "No records found for organizer '$OrganizerUpn' between $StartTime and $EndTime"
        
        # Vytvoriť prázdny súbor s hlavičkou
        [PSCustomObject]@{
            Id            = $null
            OrganizerUpn  = $null
            StartDateTime = $null
            EndDateTime   = $null
            Modalities    = $null
            CallType      = $null
            Duration      = $null
            Participants  = $null
        } | Export-Csv -Path $CsvFile -Encoding UTF8 -NoTypeInformation
        
        Write-Log "Created empty CSV file: $CsvFile"
    }
    
}
catch {
    Write-Log "Error fetching records: $_"
    Write-Log "StackTrace: $($_.ScriptStackTrace)"
}

# ODHLÁSENIE
try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Write-Log "Disconnected from Microsoft Graph"
}
catch {
    Write-Log "Error disconnecting: $_"
}

Write-Log "Script completed"