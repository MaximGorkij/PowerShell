<# 
.SYNOPSIS
    Export clenov Azure AD / Intune skupiny "MOP Predajne MuB" do Excelu.
.DESCRIPTION
    Skontroluje clenov skupiny raz za dva mesiace, vygeneruje Excel a odosle
    report cez Microsoft Graph API. Obsahuje automaticke cistenie historie.
.NOTES
    Verzia: 3.4
    Autor: Marek + Automaticky report
    Pozadovane moduly: ImportExcel
    Datum vytvorenia: $(Get-Date -Format 'dd.MM.yyyy')
    Logovanie: C:\taurisit\log\export_log.txt
#>

# ---------------------------------------------------------------------
# KONFIGURACIA A .ENV
# ---------------------------------------------------------------------

$envPath = "C:\taurisit\skripty\.env"
$ExportDir = "C:\taurisit\Reports"
$LogDir = "C:\taurisit\log"
$LogFile = Join-Path $LogDir "export_log.txt"
$GroupName = "MOP Predajne MuB"

# Vytvorenie adresarov ak neexistuju
if (!(Test-Path $ExportDir)) { New-Item -ItemType Directory -Path $ExportDir | Out-Null }
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# Nacitanie .env (KEY=VALUE)
if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            $key = $matches[1].Trim()
            $val = $matches[2].Trim()
            [System.Environment]::SetEnvironmentVariable($key, $val)
        }
    }
}

# Priradenie premennych
$TenantId = [System.Environment]::GetEnvironmentVariable("TENANT_ID")
$ClientId = [System.Environment]::GetEnvironmentVariable("CLIENT_ID")
$ClientSecret = [System.Environment]::GetEnvironmentVariable("CLIENT_SECRET")
$LogLevelEnv = [System.Environment]::GetEnvironmentVariable("LOG_LEVEL")
if (-not $LogLevelEnv) { $LogLevelEnv = "INFO" }

# Email konfiguracia
$Mail_To = @("zajac@tauris.sk", "mensik@tauris.sk")
$Mail_Cc = @("findrik@tauris.sk")
$Mail_FromUpn = "servisit@tauris.sk"

# ---------------------------------------------------------------------
# LOGOVANIE
# ---------------------------------------------------------------------

function Write-Log {
    param([string]$msg, [string]$level = "INFO")
    $priority = @{ "ERROR" = 1; "WARN" = 2; "INFO" = 3; "DEBUG" = 4 }
    $currentLimit = if ($priority.ContainsKey($LogLevelEnv)) { $priority[$LogLevelEnv] } else { 3 }
    
    if ($priority[$level] -le $currentLimit) {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $line = "$timestamp SERVER-INTUNE-EXPORT [$level] $msg"
        $line | Out-File -FilePath $LogFile -Encoding UTF8 -Append
    }
}

# ---------------------------------------------------------------------
# FUNKCIE GRAPH API
# ---------------------------------------------------------------------

function Get-GraphToken {
    Write-Log "Ziskavam Graph token" "DEBUG"
    $body = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    try {
        $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body -ErrorAction Stop
        return $tokenResponse.access_token
    }
    catch {
        Write-Log "Chyba pri ziskavani tokenu: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Get-GroupIdByName {
    param([string]$AccessToken, [string]$GroupName)
    $url = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$GroupName'"
    try {
        $response = Invoke-RestMethod -Headers @{Authorization = "Bearer $AccessToken" } -Uri $url -Method Get -ErrorAction Stop
        if (-not $response.value -or $response.value.Count -eq 0) { throw "Skupina '$GroupName' nebola v Azure najdena." }
        return $response.value[0].id
    }
    catch {
        Write-Log "Chyba pri hladani skupiny '$GroupName': $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Get-GroupMembers {
    param([string]$AccessToken, [string]$GroupId)
    $members = @()
    $url = "https://graph.microsoft.com/v1.0/groups/$GroupId/transitiveMembers"
    while ($url) {
        try {
            $response = Invoke-RestMethod -Headers @{Authorization = "Bearer $AccessToken" } -Uri $url -Method Get -ErrorAction Stop
            if ($response.value) { $members += $response.value }
            $url = $response.'@odata.nextLink'
        }
        catch {
            Write-Log "Chyba pri stahovani clenov: $($_.Exception.Message)" "ERROR"
            throw
        }
    }
    return $members
}

# ---------------------------------------------------------------------
# EXPORT A EMAIL
# ---------------------------------------------------------------------

function Export-MembersToExcel {
    param([array]$Members, [string]$ExportDir)
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $excelPath = Join-Path $ExportDir "MOP_Predajne_MuB_$timestamp.xlsx"
    
    try {
        if ($Members.Count -gt 0) {
            Write-Log "Filtrujem vybrane stlpce pre $($Members.Count) clenov." "DEBUG"
            
            $exportData = $Members | ForEach-Object {
                [PSCustomObject]@{
                    "Meno zariadenia / Uzivatela" = $_.displayName
                    "Operacny system"             = $_.operatingSystemVersion
                    "Posledne prihlasenie"        = if ($_.approximateLastSignInDateTime) { 
                        [DateTime]$_.approximateLastSignInDateTime 
                    }
                    else { $null }
                    "Konto aktivne"               = $_.accountEnabled
                }
            }

            $exportData | Export-Excel -Path $excelPath -AutoSize -WorksheetName "Members" -TableStyle Medium2
        }
        else {
            "Ziadni clenovia nenajdeni v skupine." | Out-File $excelPath
        }
        return $excelPath
    }
    catch {
        Write-Log "Chyba pri exporte do Excelu: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Send-ReportMail {
    param([string]$AccessToken, [string]$FromUpn, [string[]]$To, [string[]]$Cc, [string]$AttachmentPath)
    
    $attachmentName = Split-Path $AttachmentPath -Leaf
    $attachmentBytes = [System.IO.File]::ReadAllBytes($AttachmentPath)
    $attachmentBase64 = [System.Convert]::ToBase64String($attachmentBytes)

    # Vytvorenie polí pre príjemcov (vždy ako pole, aj pri 1 osobe)
    $toParticipants = New-Object System.Collections.Generic.List[Object]
    foreach ($addr in $To) {
        if ($addr -and $addr -match '@') {
            $toParticipants.Add(@{ emailAddress = @{ address = $addr.Trim() } })
        }
    }

    $ccParticipants = New-Object System.Collections.Generic.List[Object]
    foreach ($addr in $Cc) {
        if ($addr -and $addr -match '@') {
            $ccParticipants.Add(@{ emailAddress = @{ address = $addr.Trim() } })
        }
    }

    # Kompletný objekt správy
    $mailJson = @{
        message         = @{
            subject      = "Intune export - MOP Predajne MuB ($(Get-Date -Format 'dd.MM.yyyy'))"
            body         = @{
                contentType = "HTML"
                content     = "<html><body><p>V prilohe zasielame aktualny export clenov skupiny <b>MOP Predajne MuB</b>.</p><p>Generovane: $(Get-Date)</p></body></html>"
            }
            toRecipients = $toParticipants
            ccRecipients = $ccParticipants
            attachments  = @(
                @{
                    "@odata.type" = "#microsoft.graph.fileAttachment"
                    name          = $attachmentName
                    contentBytes  = $attachmentBase64
                }
            )
        }
        saveToSentItems = "false"
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        # Použijeme priamo UTF8 bajty, aby sme predišli problémom s kódovaním
        $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($mailJson)
        
        $params = @{
            Headers     = @{
                "Authorization" = "Bearer $AccessToken"
                "Content-Type"  = "application/json; charset=utf-8"
            }
            Uri         = "https://graph.microsoft.com/v1.0/users/$FromUpn/sendMail"
            Method      = "Post"
            Body        = $utf8Body
            ErrorAction = "Stop"
        }
        
        Write-Log "Odosielam poziadavku na Graph API..." "DEBUG"
        Invoke-RestMethod @params
    }
    catch {
        $errorBody = "Neznamy detail"
        if ($_.Exception.Response) {
            $responseStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($responseStream)
            $errorBody = $reader.ReadToEnd()
        }
        Write-Log "Graph API Error Detail: $errorBody" "ERROR"
        throw "MailSendFailed"
    }
}

# ---------------------------------------------------------------------
# HLAVNA CAST SKRIPTU
# ---------------------------------------------------------------------

try {
    Write-Log "--- Start dvojmesacneho exportu ---" "INFO"
    
    if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
        throw "Chybaju prihlasovacie udaje v .env subore!"
    }

    $token = Get-GraphToken
    $groupId = Get-GroupIdByName -AccessToken $token -GroupName $GroupName
    $members = Get-GroupMembers -AccessToken $token -GroupId $groupId

    $excelPath = Export-MembersToExcel -Members $members -ExportDir $ExportDir
    
    Write-Log "Odosielam email na: $($Mail_To -join ', ')" "INFO"
    Send-ReportMail -AccessToken $token -FromUpn $Mail_FromUpn -To $Mail_To -Cc $Mail_Cc -AttachmentPath $excelPath

    # Cleanup starších súborov (viac ako 180 dní)
    Get-ChildItem -Path $ExportDir -Filter "*.xlsx" | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-180) } | ForEach-Object {
        Write-Log "Cistenie: Mazem stary export $($_.Name)" "INFO"
        Remove-Item $_.FullName -Force
    }

    Write-Log "Export uspesne dokonceny a odoslany." "INFO"
}
catch {
    Write-Log "FATALNA CHYBA: $($_.Exception.Message)" "ERROR"
    exit 1
}