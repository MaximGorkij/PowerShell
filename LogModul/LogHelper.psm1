<#
.SYNOPSIS
    Zapisuje udalosti do textového logu a Windows Event Logu.

.DESCRIPTION
    Funkcia zabezpečuje logovanie správ do vlastného .txt súboru a do systémového Event Logu.
    Automaticky vytvára Event Source, ak neexistuje. Čistí staré logy staršie ako 30 dní.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-05

.VERSION
    1.5.0

.NOTES
    - Logy sa ukladajú do: C:\TaurisIT\Log
    - Event Log používa názov: "IntuneScript"
    - EventId: dynamicky podľa typu správy
    - Staré logy (>30 dní) sa automaticky odstraňujú
#>

function Write-CustomLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string]$EventSource,

        [string]$EventLogName = "IntuneScript",

        [Parameter(Mandatory = $true)]
        [string]$LogFileName,

        [ValidateSet("Information", "Warning", "Error")]
        [string]$Type = "Information"
    )

    $LogDirectory = "C:\TaurisIT\Log"
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    # Čistenie starých logov (>30 dní)
    Get-ChildItem -Path $LogDirectory -Filter *.txt | Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-30)
    } | Remove-Item -Force

    $LogFilePath = $LogFileName
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8

    # Vytvorenie Event Source, ak neexistuje
    if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
        try {
            New-EventLog -LogName $EventLogName -Source $EventSource
        }
        catch {
            "$Timestamp - ERROR: Cannot create Event Source '$EventSource'. $_" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
            return
        }
    }

    # Dynamické EventId podľa typu
    switch ($Type) {
        "Information" { $EventId = 1000 }
        "Warning" { $EventId = 2000 }
        "Error" { $EventId = 3000 }
        default { $EventId = 9999 }
    }

    # Zápis do Event Logu
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventId -Message $Message
    }
    catch {
        "$Timestamp - ERROR: Cannot write to Event Log. $_" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    }
}