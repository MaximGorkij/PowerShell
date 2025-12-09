#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Automaticky audit zariadeni medzi OCS Inventory (MySQL), Entra ID a Intune.

.DESCRIPTION
    Skript nacita zoznam zariadeni z OCS Inventory MySQL databazy, porovna ich s Entra ID a Intune zaznamami pomocou Microsoft Graph API.
    Vysledky ulozi do CSV reportu a textoveho logu. Bezi bez potreby akehokolvek vstupu pouzivatela.

.NOTES
    Autor: Marek Findrik (TaurisIT)
    Verzia: 2.3
#>

# ---------------------------------------------------------------------
# Import LogHelper modulu
# ---------------------------------------------------------------------
try {
    # Skusime najst LogHelper modul v standardnych umiestneniach
    $LogHelperPaths = @(
        "C:\TaurisIT\Scripts\Modules\LogHelper.psm1",
        "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1", 
        ".\LogHelper.psm1",
        "..\Modules\LogHelper.psm1"
    )
    
    $LogHelperLoaded = $false
    foreach ($path in $LogHelperPaths) {
        if (Test-Path $path) {
            try {
                Import-Module $path -Force -ErrorAction Stop
                Write-Host "LogHelper modul nacitany z: $path"
                $LogHelperLoaded = $true
                break
            }
            catch {
                Write-Warning "Nepodarilo sa nacitat LogHelper z $path : $($_.Exception.Message)"
            }
        }
    }
    
    if (-not $LogHelperLoaded) {
        throw "LogHelper modul nebol najdeny v ziadnom z standardnych umiestneni"
    }
}
catch {
    Write-Error "Kriticka chyba: Nepodarilo sa nacitat LogHelper modul. Skript nemozze pokracovat."
    exit 1
}

# ---------------------------------------------------------------------
# Nastavenia
# ---------------------------------------------------------------------
$SqlServer = "rkefs01"
$Database = "ocsweb"
$SqlUser = "ocs"
$SqlPass = "ocs"

#$TenantId = "ebf9edb5-a5f7-4d70-9a59-501865f222ee"
#$ClientId = "c5072861-a7e6-41f8-92e8-708a588abf30"
#$ClientSecret = "QAN8Q~o9kEcQRaw_~FNcEk_bh6yw6DlrLIH1DbBg"

$LogFolder = "C:\TaurisIT\Log\OCSIntuneAudit"
$ReportFolder = "C:\TaurisIT\Report\OCSIntuneAudit"
$EventLogName = "IntuneScript"
$EventSource = "OCSInventoryAudit"
$ScriptVersion = "2.3"

# ---------------------------------------------------------------------
# Inicializacia prostredia
# ---------------------------------------------------------------------
try {
    if (-not (Test-Path $LogFolder)) { 
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
        Write-CustomLog -Message "Log folder created: $LogFolder" -EventSource $EventSource -LogFileName (Join-Path $LogFolder "OCSIntuneAudit_$(Get-Date -Format 'yyyy-MM-dd').log")
    }
    
    if (-not (Test-Path $ReportFolder)) { 
        New-Item -ItemType Directory -Path $ReportFolder -Force | Out-Null
        Write-CustomLog -Message "Report folder created: $ReportFolder" -EventSource $EventSource -LogFileName (Join-Path $LogFolder "OCSIntuneAudit_$(Get-Date -Format 'yyyy-MM-dd').log")
    }

    $StartTime = Get-Date
    $DailyLogFile = Join-Path $LogFolder "OCSIntuneAudit_$(Get-Date -Format 'yyyy-MM-dd').log"
    
    Write-CustomLog -Message "================================================" -EventSource $EventSource -LogFileName $DailyLogFile
    Write-CustomLog -Message "Zaciatok auditu OCS ↔ Entra ↔ Intune" -EventSource $EventSource -LogFileName $DailyLogFile
    Write-CustomLog -Message "Verzia skriptu: $ScriptVersion" -EventSource $EventSource -LogFileName $DailyLogFile
    Write-CustomLog -Message "Start cas: $StartTime" -EventSource $EventSource -LogFileName $DailyLogFile
    Write-CustomLog -Message "================================================" -EventSource $EventSource -LogFileName $DailyLogFile

    Write-Host "Zaciatok auditu: $StartTime"
    Write-Host "Verzia skriptu: $ScriptVersion"
    Write-Host "Log file: $DailyLogFile"

    # -----------------------------------------------------------------
    # MySQL pripojenie a nacitanie dat
    # -----------------------------------------------------------------
    Write-CustomLog -Message "Nacitavam data z OCS Inventory (MySQL)..." -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Nacitavam data z OCS Inventory (MySQL)..."

    $MySQLDllPath = "C:\Program Files (x86)\MySQL\MySQL Connector NET 9.4\Assemblies\net8.0\MySql.Data.dll"
    if (Test-Path $MySQLDllPath) {
        try {
            Add-Type -Path $MySQLDllPath -ErrorAction Stop
            Write-CustomLog -Message "MySQL konektor nacitany z: $MySQLDllPath" -EventSource $EventSource -LogFileName $DailyLogFile
            Write-Host "MySQL konektor nacitany z: $MySQLDllPath"
        }
        catch {
            Write-CustomLog -Message "Chyba pri nacitani MySQL konektora z $MySQLDllPath : $($_.Exception.Message)" -Type "Warning" -EventSource $EventSource -LogFileName $DailyLogFile
            Write-Host "Konektor MySQL nenajdeny, skusam nacitat z GAC..."
            Add-Type -AssemblyName "MySql.Data" -ErrorAction Stop
            Write-CustomLog -Message "MySQL konektor nacitany z GAC" -EventSource $EventSource -LogFileName $DailyLogFile
        }
    }
    else {
        Write-CustomLog -Message "MySQL konektor nenajdeny na standardnej ceste, skusam GAC..." -Type "Warning" -EventSource $EventSource -LogFileName $DailyLogFile
        Add-Type -AssemblyName "MySql.Data" -ErrorAction Stop
        Write-CustomLog -Message "MySQL konektor nacitany z GAC" -EventSource $EventSource -LogFileName $DailyLogFile
    }

    $ConnString = "server=$SqlServer;user id=$SqlUser;password=$SqlPass;database=$Database;SslMode=none"
    $SqlConn = New-Object MySql.Data.MySqlClient.MySqlConnection($ConnString)

    Write-CustomLog -Message "Pripajam sa k MySQL serveru $SqlServer..." -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Pripajam sa k MySQL serveru $SqlServer..."
    
    $SqlConn.Open()
    Write-CustomLog -Message "Spojenie s MySQL uspesne nadviazane" -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Spojenie uspesne."

    $SqlCmd = $SqlConn.CreateCommand()
    $SqlCmd.CommandText = @"
SELECT 
    h.NAME AS 'Computer',
    h.OSNAME AS 'OperatingSystem',
    h.LASTDATE AS 'LastInventory',
    a.TAG AS 'AccountTag'
FROM hardware h
LEFT JOIN accountinfo a ON h.ID = a.HARDWARE_ID
WHERE h.ID IN (
    SELECT DISTINCT h2.ID
    FROM hardware h2
    LEFT JOIN accountinfo a2 ON h2.ID = a2.HARDWARE_ID
    LEFT JOIN archive ar ON h2.ID = ar.HARDWARE_ID
    WHERE 
        h2.USERAGENT = 'OCS-NG_WINDOWS_AGENT_v2.1.0.3' AND
        h2.OSNAME NOT LIKE '%Server%' AND
        ar.HARDWARE_ID IS NULL AND
        (a2.TAG IS NULL OR a2.TAG != 'NoIntune')
)
ORDER BY h.NAME;
"@

    Write-CustomLog -Message "Spustam SQL dopyt..." -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Spustam SQL dopyt..."
    
    $Reader = $SqlCmd.ExecuteReader()
    $Table = New-Object System.Data.DataTable
    $Table.Load($Reader)
    $OCSComputers = $Table
    $SqlConn.Close()

    if (-not $OCSComputers -or $OCSComputers.Rows.Count -eq 0) {
        $errorMsg = "OCS dotaz nevratil ziadne data. Skontroluj SQL pripojenie alebo filter."
        Write-CustomLog -Message $errorMsg -Type "Error" -EventSource $EventSource -LogFileName $DailyLogFile
        throw $errorMsg
    }

    $computersCount = $OCSComputers.Rows.Count
    Write-CustomLog -Message "Nacitanych z OCS: $computersCount zariadeni" -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Nacitanych z OCS: $computersCount zariadeni."
    
    if ($computersCount -gt 0) {
        $firstComputer = $OCSComputers.Rows[0]["Computer"]
        Write-CustomLog -Message "Prva polozka: $firstComputer" -EventSource $EventSource -LogFileName $DailyLogFile
        Write-Host "Prva polozka: $firstComputer"
    }
    # -----------------------------------------------------------------

    # -----------------------------------------------------------------
    # Microsoft Graph - prihlasenie
    # -----------------------------------------------------------------
    Write-CustomLog -Message "Pripajam sa na Microsoft Graph (client credentials)..." -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Pripajam sa na Microsoft Graph (client credentials)..."
    
    $Body = @{
        Grant_Type    = "client_credentials"
        Scope         = "https://graph.microsoft.com/.default"
        Client_Id     = $ClientId
        Client_Secret = $ClientSecret
    }
    
    try {
        $TokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $Body -ErrorAction Stop
        $Headers = @{ Authorization = "Bearer $($TokenResponse.access_token)" }
        Write-CustomLog -Message "Token ziskany uspesne" -EventSource $EventSource -LogFileName $DailyLogFile
        Write-Host "Token ziskany uspesne."
    }
    catch {
        $errorMsg = "Chyba pri ziskavani tokenu: $($_.Exception.Message)"
        Write-CustomLog -Message $errorMsg -Type "Error" -EventSource $EventSource -LogFileName $DailyLogFile
        throw $errorMsg
    }
    # -----------------------------------------------------------------

    # -----------------------------------------------------------------
    # Entra ID zariadenia
    # -----------------------------------------------------------------
    Write-CustomLog -Message "Nacitavam zariadenia z Entra ID..." -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Nacitavam zariadenia z Entra ID..."
    
    $EntraDevices = @()
    $NextUrl = "https://graph.microsoft.com/v1.0/devices"
    $pageCount = 0
    
    try {
        while ($NextUrl) {
            $pageCount++
            Write-CustomLog -Message "Nacitavam stranku $pageCount z Entra ID..." -EventSource $EventSource -LogFileName $DailyLogFile
            Write-Host "Volanie: $NextUrl"
            
            $Response = Invoke-RestMethod -Uri $NextUrl -Headers $Headers -Method GET -ErrorAction Stop
            $EntraDevices += $Response.value
            $NextUrl = $Response.'@odata.nextLink'
        }
        
        $entraCount = $EntraDevices.Count
        Write-CustomLog -Message "Nacitanych zariadeni z Entra ID: $entraCount (pocet stranok: $pageCount)" -EventSource $EventSource -LogFileName $DailyLogFile
        Write-Host "Nacitanych zariadeni z Entra ID: $entraCount"
    }
    catch {
        $errorMsg = "Chyba pri nacitavani zariadeni z Entra ID: $($_.Exception.Message)"
        Write-CustomLog -Message $errorMsg -Type "Error" -EventSource $EventSource -LogFileName $DailyLogFile
        throw $errorMsg
    }
    # -----------------------------------------------------------------

    # -----------------------------------------------------------------
    # Intune zariadenia
    # -----------------------------------------------------------------
    Write-CustomLog -Message "Nacitavam zariadenia z Intune..." -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Nacitavam zariadenia z Intune..."
    
    $IntuneDevices = @()
    $NextUrl = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
    $pageCount = 0
    
    try {
        while ($NextUrl) {
            $pageCount++
            Write-CustomLog -Message "Nacitavam stranku $pageCount z Intune..." -EventSource $EventSource -LogFileName $DailyLogFile
            Write-Host "Volanie: $NextUrl"
            
            $Response = Invoke-RestMethod -Uri $NextUrl -Headers $Headers -Method GET -ErrorAction Stop
            $IntuneDevices += $Response.value
            $NextUrl = $Response.'@odata.nextLink'
        }
        
        $intuneCount = $IntuneDevices.Count
        Write-CustomLog -Message "Nacitanych zariadeni z Intune: $intuneCount (pocet stranok: $pageCount)" -EventSource $EventSource -LogFileName $DailyLogFile
        Write-Host "Nacitanych zariadeni z Intune: $intuneCount"
    }
    catch {
        $errorMsg = "Chyba pri nacitavani zariadeni z Intune: $($_.Exception.Message)"
        Write-CustomLog -Message $errorMsg -Type "Error" -EventSource $EventSource -LogFileName $DailyLogFile
        throw $errorMsg
    }
    # -----------------------------------------------------------------

    # -----------------------------------------------------------------
    # Porovnanie dat
    # -----------------------------------------------------------------
    Write-CustomLog -Message "Porovnavam data OCS vs Entra vs Intune..." -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Porovnavam data OCS vs Entra vs Intune..."
    
    $Report = @()
    $processedCount = 0
    
    foreach ($row in $OCSComputers.Rows) {
        $processedCount++
        $comp = $row["Computer"]
        $entra = $EntraDevices | Where-Object { $_.displayName -eq $comp }
        $intune = $IntuneDevices | Where-Object { $_.deviceName -eq $comp }

        $Report += [PSCustomObject]@{
            Computer        = $comp
            OperatingSystem = $row["OperatingSystem"]
            LastInventory   = $row["LastInventory"]
            AccountTag      = $row["AccountTag"]
            InEntra         = if ($entra) { "YES" } else { "NO" }
            InIntune        = if ($intune) { "YES" } else { "NO" }
        }

        # Progress logging every 100 records
        if ($processedCount % 100 -eq 0) {
            Write-CustomLog -Message "Spracovanych $processedCount z $computersCount zariadeni" -EventSource $EventSource -LogFileName $DailyLogFile
            Write-Host "Spracovanych $processedCount z $computersCount zariadeni"
        }
    }

    Write-CustomLog -Message "Porovnanie ukoncene. Spracovanych celkom: $processedCount zariadeni" -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Porovnanie ukoncene. Generujem vystupne subory..."
    # -----------------------------------------------------------------

    # -----------------------------------------------------------------
    # Vystup a logovanie
    # -----------------------------------------------------------------
    $CsvPath = Join-Path $ReportFolder ("OCS_Audit_{0}.csv" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    
    try {
        $Report | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-CustomLog -Message "CSV report ulozeny do: $CsvPath" -EventSource $EventSource -LogFileName $DailyLogFile
        Write-Host "CSV report ulozeny do: $CsvPath"
    }
    catch {
        $errorMsg = "Chyba pri ukladani CSV reportu: $($_.Exception.Message)"
        Write-CustomLog -Message $errorMsg -Type "Error" -EventSource $EventSource -LogFileName $DailyLogFile
        throw $errorMsg
    }

    # Statistika
    $inEntraCount = ($Report | Where-Object { $_.InEntra -eq "YES" }).Count
    $inIntuneCount = ($Report | Where-Object { $_.InIntune -eq "YES" }).Count
    $compliantCount = ($Report | Where-Object { $_.InEntra -eq "YES" -and $_.InIntune -eq "YES" }).Count
    
    $Duration = (Get-Date) - $StartTime
    $Summary = @"
Audit ukonceny uspesne.
- Celkovy pocet zariadeni z OCS: $computersCount
- Zariadenia v Entra: $inEntraCount
- Zariadenia v Intune: $inIntuneCount  
- Kompliantne zariadenia (v oboch): $compliantCount
- Trvanie: $([math]::Round($Duration.TotalSeconds, 2)) sekund
- Report: $CsvPath
"@

    Write-CustomLog -Message $Summary -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host $Summary
    
    Write-EventLog -LogName $EventLogName -Source $EventSource -EventId 1002 -EntryType Information -Message $Summary
    # -----------------------------------------------------------------

}
catch {
    $err = "Chyba pocas auditu: $($_.Exception.Message)"
    Write-CustomLog -Message $err -Type "Error" -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host $err -ForegroundColor Red
    
    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EventId 9001 -EntryType Error -Message $err
    }
    catch {
        Write-Host "Nepodarilo sa zapisat do Event Logu: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
finally {
    Write-CustomLog -Message "Skript ukonceny" -EventSource $EventSource -LogFileName $DailyLogFile
    Write-Host "Skript ukonceny"
    
    # Cleanup - odinstalovanie modulu
    try {
        Remove-Module LogHelper -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore errors during module removal
    }
}