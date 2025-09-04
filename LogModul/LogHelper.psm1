function Write-CustomLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$true)]
        [string]$EventSource,

        [string]$EventLogName = "IntuneScript",

        [Parameter(Mandatory=$true)]
        [string]$LogFileName,

        [ValidateSet("Information", "Warning", "Error")]
        [string]$Type = "Information"

    )

    $LogDirectory = "C:\TaurisIT\Log"
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force
    }

    $LogFilePath = $LogFileName

    # Log to text file
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8

    # Create event source if needed
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        try {
            New-EventLog -LogName $EventLogName -Source $EventSource
        } catch {
            "$Timestamp - ERROR: Cannot create Event Source '$EventSource'. $_" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
            return
        }
    }

    # Write to event log
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType Information -EventId 1000 -Message $Message
    } catch {
        "$Timestamp - ERROR: Cannot write to Event Log. $_" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    }
}