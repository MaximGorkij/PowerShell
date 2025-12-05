<#
.SYNOPSIS
    Zapisuje udalosti do textoveho logu a Windows Event Logu.

.DESCRIPTION
    Funkcia zabezpecuje logovanie sprav do vlastneho .txt suboru a do systemoveho Event Logu.
    Automaticky vytvara Event Source, ak neexistuje. Cisti stare logy starsie ako 30 dni.

.AUTHOR
    Marek Findrik

.CREATED
    2025-09-05

.VERSION
    1.5.0

.NOTES
    - Logy sa ukladaju do: C:\TaurisIT\Log
    - Event Log pouziva nazov: "IntuneScript"
    - EventId: dynamicky podla typu spravy
    - Stare logy (>30 dni) sa automaticky odstrauju
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

    # Cistenie starych logov (>30 dni)
    Get-ChildItem -Path $LogDirectory -Filter *.txt | Where-Object {
        $_.LastWriteTime -lt (Get-Date).AddDays(-30)
    } | Remove-Item -Force

    # OPRAVA: Pridanie cesty k log súboru
    $LogFilePath = Join-Path $LogDirectory $LogFileName
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

    # Dynamicke EventId podla typu
    switch ($Type) {
        "Information" { $EventId = 1000 }
        "Warning" { $EventId = 2000 }
        "Error" { $EventId = 3000 }
        default { $EventId = 9999 }
    }

    # Zapis do Event Logu
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType $Type -EventId $EventId -Message $Message
    }
    catch {
        "$Timestamp - ERROR: Cannot write to Event Log. $_" | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
    }
}

function Write-IntuneLog {
    <#
    .SYNOPSIS
        Spätne kompatibilná funkcia pre existujúce skripty
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',

        [string]$LogFile = "IntuneScripts.log",
        [string]$EventSource = "IntuneScripts"
    )

    $Type = switch ($Level) {
        'INFO' { 'Information' }
        'WARN' { 'Warning' }
        'ERROR' { 'Error' }
        'SUCCESS' { 'Information' }
        default { 'Information' }
    }

    Write-CustomLog -Message $Message -EventSource $EventSource -LogFileName $LogFile -Type $Type
}

Export-ModuleMember -Function Write-CustomLog, Write-IntuneLog