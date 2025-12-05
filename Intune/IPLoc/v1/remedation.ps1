<#
.SYNOPSIS
  Intune Remediation Script - nastavenie lokality a extensionAttribute1
.DESCRIPTION
  Zisti IP adresu clienta, urci lokalitu podla zoznamu IP adries,
  ulozi do registry a aktualizuje extensionAttribute1 v Entra ID cez Graph API.
  Credentials su v subore .env.
.VERSION
  2.1 - Pouziva LogHelper modul
.AUTHOR
  TaurisIT
#>

[CmdletBinding()]
param()

#region Config
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$LogDir = "C:\TaurisIT\Log\IPcheck"
$LogFile = "IPcheck_Remediation.log"
$LogModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1"
$ConfigFile = "$PSScriptRoot\IPLocationMap.json"
$RegistryPath = "HKLM:\SOFTWARE\TaurisIT\IPcheck"
$EnvFile = "$PSScriptRoot\.env"
$GraphHelperModule = "$PSScriptRoot\GraphHelper.psm1"
$MaxRetries = 3
$RetryDelaySeconds = 2

# Intune exit codes
$SUCCESS = 0
$FAILURE = 1
#endregion

#region Functions
function Initialize-Logging {
    <#
    .SYNOPSIS
        Inicializuje logovanie cez LogHelper modul
    #>
    try {
        if (Test-Path $LogModulePath) {
            Import-Module $LogModulePath -Force -ErrorAction Stop
            Write-Verbose "LogHelper modul uspesne naimportovany" -Verbose
            return $true
        }
        else {
            # Fallback logging
            Write-Host "WARNING: LogHelper modul nebol najdeny na $LogModulePath" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "ERROR: Nepodarilo sa importovat LogHelper: $_" -ForegroundColor Red
        return $false
    }
}

function Write-IPLog {
    <#
    .SYNOPSIS
        Wrapper pre logovanie IP check skriptov
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"
    
    # Zapísať do konzoly (pre Intune)
    Write-Host $logMessage
    
    # Pokúsiť sa zapísať cez LogHelper
    try {
        Write-IntuneLog -Message $Message -Level $Level -LogFile $LogFile -EventSource $ScriptName
    }
    catch {
        # Fallback na lokálny súbor
        try {
            if (-not (Test-Path $LogDir)) {
                New-Item -ItemType Directory -Path $LogDir -Force -ErrorAction Stop | Out-Null
            }
            Add-Content -Path (Join-Path $LogDir $LogFile) -Value $logMessage -ErrorAction Stop
        }
        catch {
            Write-EventLog -LogName Application -Source "IntuneScripts" -EventId 1001 -EntryType Information -Message $Message -ErrorAction SilentlyContinue
        }
    }
}

function Get-PrimaryIPAddress {
    try {
        Write-IPLog -Message "Zistujem primarnu IP adresu" -Level INFO
        
        # Metoda 1: Get-NetIPAddress
        $ipAddresses = @()
        
        try {
            $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.IPAddress -notmatch '^(169\.254\.|127\.|0\.)' -and
                $_.AddressState -eq 'Preferred'
            }
        }
        catch {
            Write-IPLog -Message "Get-NetIPAddress zlyhalo: $_" -Level WARN
        }
        
        # Metoda 2: WMI fallback
        if (-not $ipAddresses) {
            Write-IPLog -Message "Pouzivam WMI fallback pre IP adresu" -Level INFO
            
            $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction SilentlyContinue
            
            foreach ($adapter in $adapters) {
                if ($adapter.IPAddress) {
                    foreach ($ip in $adapter.IPAddress) {
                        if ($ip -match '^\d+\.\d+\.\d+\.\d+$' -and $ip -notmatch '^(169\.254\.|127\.)') {
                            Write-IPLog -Message "Najdena IP cez WMI: $ip" -Level INFO
                            return $ip
                        }
                    }
                }
            }
        }
        else {
            # Vybrat najlepsiu IP
            # Uprednostni privatne siete (10.x.x.x, 192.168.x.x)
            $privateIPs = $ipAddresses | Where-Object { 
                $_.IPAddress -match '^(10\.|192\.168\.)' 
            }
            
            if ($privateIPs) {
                $primaryIP = $privateIPs | 
                Sort-Object -Property InterfaceMetric |
                Select-Object -First 1 -ExpandProperty IPAddress
                
                Write-IPLog -Message "Vybrata privatna IP: $primaryIP" -Level INFO
                return $primaryIP
            }
            else {
                $primaryIP = $ipAddresses | 
                Sort-Object -Property InterfaceMetric |
                Select-Object -First 1 -ExpandProperty IPAddress
                
                Write-IPLog -Message "Vybrata IP: $primaryIP" -Level INFO
                return $primaryIP
            }
        }
        
        throw "Nebola najdena ziadna platna IPv4 adresa"
    }
    catch {
        Write-IPLog -Message "Chyba pri zistovani IP: $_" -Level ERROR
        return $null
    }
}

function Get-LocationFromIP {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IPAddress,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Map
    )
    
    # Zorad prefixy od najdlhsieho (najspecifikcnejsieho)
    foreach ($prefix in ($Map.Keys | Sort-Object -Descending { $_.Length })) {
        if ($IPAddress.StartsWith($prefix)) { 
            Write-IPLog -Message "IP prefix '$prefix' zodpoveda lokalite '$($Map[$prefix])'" -Level INFO
            return $Map[$prefix]
        }
    }
    
    Write-IPLog -Message "Pre IP '$IPAddress' nebol najdeny ziadny zodpovedajuci prefix" -Level WARN
    return $null
}

function Load-IPLocationMap {
    try {
        if (Test-Path $ConfigFile) {
            Write-IPLog -Message "Nacitavam mapu lokacii z $ConfigFile" -Level INFO
            
            $mapJson = Get-Content $ConfigFile -Raw -ErrorAction Stop | ConvertFrom-Json
            $map = @{}
            $mapJson.PSObject.Properties | ForEach-Object { 
                $map[$_.Name] = $_.Value 
            }
            
            Write-IPLog -Message "Nacitanych $(($map.Keys).Count) IP prefixov" -Level INFO
            return $map
        }
        else {
            Write-IPLog -Message "Konfiguracny subor nenajdeny, pouzivam zakladnu mapu" -Level WARN
            
            return @{
                "10.10.0."   = "RS"
                "10.20.0."   = "RS"
                "10.20.11."  = "RS"
                "10.20.20."  = "Server"
                "10.20.30."  = "RS"
                "10.20.40."  = "RS"
                "10.20.50."  = "RS"
                "10.20.51."  = "RS"
                "10.20.70."  = "RS"
                "10.30.0."   = "SNV"
                "10.30.40."  = "SNV"
                "10.30.50."  = "SNV"
                "10.30.51."  = "SNV"
                "10.40.0."   = "NR"
                "10.40.40."  = "NR"
                "10.40.50."  = "NR"
                "10.40.51."  = "NR"
                "10.50.0."   = "LDCKE"
                "10.50.40."  = "LDCKE"
                "10.50.50."  = "LDCKE"
                "10.50.51."  = "LDCKE"
                "10.50.52."  = "LDCKE"
                "10.60.7."   = "RybaKE"
                "10.60.11."  = "RybaKE"
                "10.60.17."  = "RybaKE"
                "10.60.40."  = "RybaKE"
                "10.60.50."  = "RybaKE"
                "10.60.51."  = "RybaKE"
                "10.60.77."  = "RybaKE"
                "10.70.123." = "LDCKE"
                "10.80.0."   = "BB"
                "10.80.40."  = "BB"
                "10.80.50."  = "BB"
                "10.80.51."  = "BB"
                "10.82.0."   = "BA"
                "10.82.40."  = "BA"
                "10.82.50."  = "BA"
                "10.82.51."  = "BA"
                "10.82.70."  = "BA"
                "10.83.0."   = "ZA"
                "10.83.40."  = "ZA"
                "10.83.50."  = "ZA"
                "10.83.51."  = "ZA"
                "192.168.7." = "RybaKE"
            }
        }
    }
    catch {
        Write-IPLog -Message "Chyba pri nacitani mapy lokacii: $_" -Level ERROR
        throw
    }
}

function Load-EnvCredentials {
    try {
        if (-not (Test-Path $EnvFile)) {
            Write-IPLog -Message "ERROR: Subor .env nebol najdeny v $EnvFile" -Level ERROR
            return $null, $null, $null
        }
        
        Write-IPLog -Message "Nacitavam credentials z .env suboru" -Level INFO
        
        $envContent = Get-Content $EnvFile -ErrorAction Stop
        $envVars = @{}
        
        foreach ($line in $envContent) {
            # Skip comments and empty lines
            if ($line -match '^\s*#') { continue }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            
            # Parse KEY=VALUE
            if ($line -match '^\s*([^=]+)\s*=\s*(.*?)\s*$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                # Remove quotes if present
                $value = $value -replace '^["'']|["'']$', ''
                
                $envVars[$key] = $value
                Write-IPLog -Message "  Nacitana premenna: $key" -Level INFO
            }
        }
        
        $tenantId = $envVars["GRAPH_TENANT_ID"]
        $clientId = $envVars["GRAPH_CLIENT_ID"]
        $clientSecret = $envVars["GRAPH_CLIENT_SECRET"]
        
        if ([string]::IsNullOrWhiteSpace($tenantId)) {
            Write-IPLog -Message "ERROR: Chyba GRAPH_TENANT_ID v .env subore" -Level ERROR
        }
        if ([string]::IsNullOrWhiteSpace($clientId)) {
            Write-IPLog -Message "ERROR: Chyba GRAPH_CLIENT_ID v .env subore" -Level ERROR
        }
        if ([string]::IsNullOrWhiteSpace($clientSecret)) {
            Write-IPLog -Message "ERROR: Chyba GRAPH_CLIENT_SECRET v .env subore" -Level ERROR
        }
        
        if ([string]::IsNullOrWhiteSpace($tenantId) -or 
            [string]::IsNullOrWhiteSpace($clientId) -or 
            [string]::IsNullOrWhiteSpace($clientSecret)) {
            Write-IPLog -Message "ERROR: Nie su kompletne credentials v .env subore" -Level ERROR
            return $null, $null, $null
        }
        
        Write-IPLog -Message "Credentials uspesne nacitane" -Level INFO
        return $tenantId, $clientId, $clientSecret
    }
    catch {
        Write-IPLog -Message "Chyba pri nacitani .env suboru: $_" -Level ERROR
        return $null, $null, $null
    }
}

function Save-LocationToRegistry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [string]$IPAddress
    )
    
    try {
        # Vytvorit registry path ak neexistuje
        if (-not (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
            Write-IPLog -Message "Vytvoreny registry path: $RegistryPath" -Level INFO
        }
        
        # Ulozit lokalitu a metadata
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        Set-ItemProperty -Path $RegistryPath -Name "CurrentLocation" -Value $Location -Type String -Force -ErrorAction Stop
        Set-ItemProperty -Path $RegistryPath -Name "DetectedIP" -Value $IPAddress -Type String -Force -ErrorAction Stop
        Set-ItemProperty -Path $RegistryPath -Name "LastUpdated" -Value $timestamp -Type String -Force -ErrorAction Stop
        Set-ItemProperty -Path $RegistryPath -Name "ComputerName" -Value $env:COMPUTERNAME -Type String -Force -ErrorAction Stop
        
        Write-IPLog -Message "Lokalita '$Location' ulozena do registry (IP: $IPAddress)" -Level SUCCESS
        return $true
    }
    catch {
        Write-IPLog -Message "Chyba pri ukladani do registry: $_" -Level ERROR
        return $false
    }
}

function Get-DeviceSerialNumber {
    try {
        # Viacero metod pre získanie serial number
        $serial = $null
        
        # 1. BIOS (najspolahlivejsie)
        $bios = Get-WmiObject -Class Win32_BIOS -ErrorAction SilentlyContinue
        if ($bios -and $bios.SerialNumber) {
            $serial = $bios.SerialNumber.Trim()
            Write-IPLog -Message "Serial number z BIOS: $serial" -Level INFO
        }
        
        # 2. Computer System Product
        if ([string]::IsNullOrWhiteSpace($serial)) {
            $csProduct = Get-WmiObject -Class Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
            if ($csProduct -and $csProduct.IdentifyingNumber) {
                $serial = $csProduct.IdentifyingNumber.Trim()
                Write-IPLog -Message "Serial number z ComputerSystemProduct: $serial" -Level INFO
            }
        }
        
        # 3. Registry (pre VMs)
        if ([string]::IsNullOrWhiteSpace($serial)) {
            $regSerial = (Get-ItemProperty -Path "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -Name "SystemSerialNumber" -ErrorAction SilentlyContinue).SystemSerialNumber
            if ($regSerial) {
                $serial = $regSerial.Trim()
                Write-IPLog -Message "Serial number z registry: $serial" -Level INFO
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($serial)) {
            Write-IPLog -Message "WARN: Nepodarilo sa ziskat serial number" -Level WARN
            return $null
        }
        
        return $serial
    }
    catch {
        Write-IPLog -Message "Chyba pri ziskavani serial number: $_" -Level WARN
        return $null
    }
}

function Get-AzureADDeviceId {
    try {
        Write-IPLog -Message "Zistujem Azure AD Device ID..." -Level INFO
        
        $deviceId = $null
        
        # 1. dsregcmd (pre Azure AD Joined)
        try {
            $dsregcmdStatus = dsregcmd /status 2>$null
            if ($dsregcmdStatus) {
                $deviceIdLine = $dsregcmdStatus | Where-Object { $_ -match "DeviceId" }
                if ($deviceIdLine) {
                    $deviceId = $deviceIdLine.Split(":")[1].Trim()
                    Write-IPLog -Message "Azure AD Device ID z dsregcmd: $deviceId" -Level INFO
                }
            }
        }
        catch {
            Write-IPLog -Message "dsregcmd nie je dostupny" -Level WARN
        }
        
        # 2. Registry - CloudDomainJoin
        if (-not $deviceId) {
            $cloudJoinPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo"
            if (Test-Path $cloudJoinPath) {
                $childKeys = Get-ChildItem -Path $cloudJoinPath
                foreach ($key in $childKeys) {
                    $id = (Get-ItemProperty -Path $key.PSPath -Name "DeviceId" -ErrorAction SilentlyContinue).DeviceId
                    if ($id) {
                        $deviceId = $id
                        Write-IPLog -Message "Azure AD Device ID z registry: $deviceId" -Level INFO
                        break
                    }
                }
            }
        }
        
        # 3. Intune Management Extension
        if (-not $deviceId) {
            $intunePath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Settings"
            if (Test-Path $intunePath) {
                $id = (Get-ItemProperty -Path $intunePath -Name "EntDMID" -ErrorAction SilentlyContinue).EntDMID
                if ($id) {
                    $deviceId = $id
                    Write-IPLog -Message "Intune Device ID: $deviceId" -Level INFO
                }
            }
        }
        
        if (-not $deviceId) {
            Write-IPLog -Message "Nepodarilo sa ziskat Azure AD Device ID" -Level WARN
        }
        
        return $deviceId
    }
    catch {
        Write-IPLog -Message "Chyba pri ziskavani Azure AD Device ID: $_" -Level WARN
        return $null
    }
}

function Import-GraphHelperModule {
    try {
        if (Test-Path $GraphHelperModule) {
            Import-Module $GraphHelperModule -Force -ErrorAction Stop
            Write-IPLog -Message "GraphHelper modul uspesne nacitany" -Level INFO
            return $true
        }
        else {
            Write-IPLog -Message "WARN: GraphHelper modul nebol najdeny, vytvaram zakladny modul" -Level WARN
            
            # Vytvorit zakladny GraphHelper modul
            $moduleContent = @'
function Get-GraphToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    $uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        return $response.access_token
    }
    catch {
        Write-Error "Chyba pri ziskavani Graph tokenu: $_"
        throw
    }
}

function Find-DeviceInGraph {
    param(
        [string]$AccessToken,
        [string]$DeviceId,
        [string]$ComputerName
    )
    
    $headers = @{
        Authorization = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }
    
    try {
        # Pokus 1: Hladat podla deviceId (Azure AD Device ID)
        if ($DeviceId) {
            $deviceUri = "https://graph.microsoft.com/v1.0/devices?`$filter=deviceId eq '$DeviceId'"
            $response = Invoke-RestMethod -Uri $deviceUri -Headers $headers -Method Get
            
            if ($response.value -and $response.value.Count -gt 0) {
                Write-Output "Nasiel som zariadenie podla deviceId: $DeviceId"
                return $response.value[0]
            }
        }
        
        # Pokus 2: Hladat podla displayName (computer name)
        if ($ComputerName) {
            $deviceUri = "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$ComputerName'"
            $response = Invoke-RestMethod -Uri $deviceUri -Headers $headers -Method Get
            
            if ($response.value -and $response.value.Count -gt 0) {
                Write-Output "Nasiel som zariadenie podla computer name: $ComputerName"
                
                # Ak je viac zariadeni, vrat prve
                if ($response.value.Count -eq 1) {
                    return $response.value[0]
                }
                else {
                    Write-Output "Varovanie: Viacero zariadeni s rovnakym menom, pouzivam prve"
                    return $response.value[0]
                }
            }
        }
        
        # Pokus 3: Ziskat vsetky zariadenia a hladat podla deviceId
        if ($DeviceId) {
            $deviceUri = "https://graph.microsoft.com/v1.0/devices"
            $allDevices = @()
            $nextLink = $deviceUri
            
            # Obmedzime na 3 strany pre performance
            $pageCount = 0
            do {
                $pageCount++
                if ($pageCount -gt 3) { break }
                
                $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get
                $allDevices += $response.value
                
                # Hladat deviceId medzi zariadeniami
                foreach ($device in $response.value) {
                    if ($device.deviceId -eq $DeviceId) {
                        Write-Output "Nasiel som zariadenie v zozname vsetkych zariadeni"
                        return $device
                    }
                }
                
                $nextLink = $response.'@odata.nextLink'
            } while ($nextLink)
        }
        
        throw "Zariadenie nebolo najdene v Graph API"
    }
    catch {
        Write-Error "Chyba pri hladani zariadenia: $_"
        throw
    }
}

function Update-DeviceInGraph {
    param(
        [string]$AccessToken,
        [string]$DeviceObjectId,
        [string]$Location,
        [string]$SerialNumber
    )
    
    $headers = @{
        Authorization = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }
    
    try {
        $updateUri = "https://graph.microsoft.com/v1.0/devices/$DeviceObjectId"
        
        # Vytvorit update body
        $updateBody = @{
            extensionAttributes = @{
                extensionAttribute1 = $Location
                extensionAttribute2 = $SerialNumber
            }
        } | ConvertTo-Json -Compress
        
        Write-Output "Aktualizujem zariadenie $DeviceObjectId..."
        Invoke-RestMethod -Uri $updateUri -Headers $headers -Method Patch -Body $updateBody
        
        Write-Output "Zariadenie uspesne aktualizovane"
        return $true
    }
    catch {
        Write-Error "Chyba pri aktualizacii zariadenia: $_"
        throw
    }
}

Export-ModuleMember -Function Get-GraphToken, Find-DeviceInGraph, Update-DeviceInGraph
'@
            
            Set-Content -Path $GraphHelperModule -Value $moduleContent -Force -ErrorAction Stop
            Import-Module $GraphHelperModule -Force -ErrorAction Stop
            Write-IPLog -Message "GraphHelper modul vytvoreny a nacitany" -Level INFO
            return $true
        }
    }
    catch {
        Write-IPLog -Message "Chyba pri nacitani GraphHelper modulu: $_" -Level ERROR
        return $false
    }
}

function Invoke-GraphApiWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        try {
            Write-IPLog -Message "Pokus $attempt/$MaxRetries o Graph API volanie" -Level INFO
            return & $ScriptBlock
        }
        catch {
            $lastError = $_
            $errorMsg = $_.Exception.Message
            
            # Kontrola ci ma zmysel retry
            if ($errorMsg -like "*401*" -or $errorMsg -like "*403*") {
                Write-IPLog -Message "Autentifikacna chyba - retry nebude mat efekt" -Level ERROR
                throw
            }
            
            if ($attempt -lt $MaxRetries) {
                Write-IPLog -Message "Pokus $attempt zlyhal: $errorMsg. Cakam ${DelaySeconds}s..." -Level WARN
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    
    # Vsetky pokusy zlyhali
    Write-IPLog -Message "Vsetky pokusy ($MaxRetries) zlyhali" -Level ERROR
    throw $lastError
}

function Update-EntraIDLocation {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$Location,
        [string]$SerialNumber
    )
    
    try {
        Write-IPLog -Message "Pripravujem aktualizaciu Entra ID..." -Level INFO
        
        # Nacitat GraphHelper modul
        if (-not (Import-GraphHelperModule)) {
            Write-IPLog -Message "Nepodarilo sa nacitat GraphHelper modul, preskakujem Graph API" -Level WARN
            return $false
        }
        
        # Ziskat Azure AD Device ID
        $azureADDeviceId = Get-AzureADDeviceId
        
        if (-not $azureADDeviceId) {
            Write-IPLog -Message "INFO: Nemozem aktualizovat Entra ID - chyba Azure AD Device ID" -Level INFO
            Write-IPLog -Message "INFO: Zariadenie moze byt offline alebo nie je Azure AD joined" -Level INFO
            return $false
        }
        
        # Spustit Graph API volanie s retry
        Invoke-GraphApiWithRetry -MaxRetries $MaxRetries -DelaySeconds $RetryDelaySeconds -ScriptBlock {
            Write-IPLog -Message "Ziskavam Graph API token..." -Level INFO
            $token = Get-GraphToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
            
            if ([string]::IsNullOrWhiteSpace($token)) {
                throw "Nepodarilo sa ziskat Graph API token"
            }
            
            Write-IPLog -Message "Hladam zariadenie v Entra ID..." -Level INFO
            
            # Najst zariadenie
            $device = Find-DeviceInGraph -AccessToken $token -DeviceId $azureADDeviceId -ComputerName $env:COMPUTERNAME
            
            if (-not $device) {
                throw "Zariadenie nebolo najdene v Entra ID"
            }
            
            Write-IPLog -Message "Zariadenie najdene: $($device.displayName) (ObjectId: $($device.id))" -Level INFO
            
            # Skontrolovat aktualnu lokalitu
            $currentLocation = $device.extensionAttributes.extensionAttribute1
            if ($currentLocation -eq $Location) {
                Write-IPLog -Message "Lokalita je uz nastavena spravne: $currentLocation" -Level INFO
                return
            }
            
            Write-IPLog -Message "Aktualizujem extensionAttribute1 na hodnotu: '$Location'..." -Level INFO
            
            # Aktualizovat zariadenie
            Update-DeviceInGraph -AccessToken $token -DeviceObjectId $device.id -Location $Location -SerialNumber $SerialNumber
            
            Write-IPLog -Message "Entra ID uspesne aktualizovane" -Level SUCCESS
            
            # Ulozit informaciu o uspesnej aktualizacii
            $graphUpdateFile = Join-Path $LogDir "GraphUpdate_Success.log"
            $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $($device.displayName), Lokalita: $Location, DeviceId: $azureADDeviceId"
            Add-Content -Path $graphUpdateFile -Value $logEntry -ErrorAction SilentlyContinue
        }
        
        return $true
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-IPLog -Message "Chyba pri aktualizacii Entra ID: $errorMsg" -Level ERROR
        
        # Log specificke chyby
        $graphErrorFile = Join-Path $LogDir "GraphUpdate_Errors.log"
        $errorEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Computer: $env:COMPUTERNAME, Error: $errorMsg"
        Add-Content -Path $graphErrorFile -Value $errorEntry -ErrorAction SilentlyContinue
        
        if ($errorMsg -like "*404*" -or $errorMsg -like "*Not Found*") {
            Write-IPLog -Message "ERROR: Zariadenie neexistuje v Entra ID" -Level ERROR
            Write-IPLog -Message "INFO: Mozno zariadenie este nie je synchronizovane s Azure AD" -Level INFO
        }
        elseif ($errorMsg -like "*401*" -or $errorMsg -like "*403*") {
            Write-IPLog -Message "ERROR: Autentifikacna chyba - skontrolujte permissions" -Level ERROR
            Write-IPLog -Message "INFO: App Registration potrebuje Device.ReadWrite.All permission" -Level INFO
        }
        elseif ($errorMsg -like "*timeout*") {
            Write-IPLog -Message "ERROR: Timeout pri volani Graph API" -Level ERROR
        }
        
        return $false
    }
}
#endregion

#region Main Execution
try {
    # Inicializacia logovania
    $loggingInitialized = Initialize-Logging
    
    Write-IPLog -Message "=== Intune Remediation Script zaciatok ===" -Level INFO
    Write-IPLog -Message "Script verzia: 2.1 (LogHelper integracia)" -Level INFO
    Write-IPLog -Message "Computer: $env:COMPUTERNAME" -Level INFO
    Write-IPLog -Message "User: $env:USERNAME" -Level INFO
    Write-IPLog -Message "Logging module: $(if ($loggingInitialized) {'OK'} else {'Failed'})" -Level INFO

    # 1. Nacitat mapu lokacii
    Write-IPLog -Message "Krok 1/4: Nacitavam mapu lokacii" -Level INFO
    $map = Load-IPLocationMap

    # 2. Ziskat IP adresu
    Write-IPLog -Message "Krok 2/4: Zistujem IP adresu" -Level INFO
    $ip = Get-PrimaryIPAddress
    
    if (-not $ip) {
        Write-IPLog -Message "FAIL: IP adresa sa nenasla" -Level ERROR
        exit $FAILURE
    }

    # 3. Urcit lokalitu z IP
    Write-IPLog -Message "Krok 3/4: Urcujem lokalitu z IP" -Level INFO
    $location = Get-LocationFromIP -IPAddress $ip -Map $map
    
    if (-not $location) {
        Write-IPLog -Message "FAIL: Prefix pre IP $ip nebol najdeny v mape lokacii" -Level ERROR
        exit $FAILURE
    }
    
    Write-IPLog -Message "Detekovana lokalita: $location" -Level INFO

    # 4. Ulozit do registry
    Write-IPLog -Message "Krok 4/4: Ukladam lokalitu do registry" -Level INFO
    if (-not (Save-LocationToRegistry -Location $location -IPAddress $ip)) {
        Write-IPLog -Message "FAIL: Nepodarilo sa ulozit lokalitu do registry" -Level ERROR
        exit $FAILURE
    }

    # 5. Volitelne: Aktualizovat Entra ID cez Graph API
    Write-IPLog -Message "Volitelny krok: Aktualizacia Entra ID cez Graph API" -Level INFO
    
    # Nacitat credentials z .env
    $tenantId, $clientId, $clientSecret = Load-EnvCredentials
    
    if ($tenantId -and $clientId -and $clientSecret) {
        # Ziskat serial number zariadenia
        $serial = Get-DeviceSerialNumber
        
        if ($serial) {
            Write-IPLog -Message "Serial number zariadenia: $serial" -Level INFO
            
            # Aktualizovat Entra ID
            $graphSuccess = Update-EntraIDLocation -TenantId $tenantId -ClientId $clientId `
                -ClientSecret $clientSecret -Location $location -SerialNumber $serial
            
            if ($graphSuccess) {
                Write-IPLog -Message "SUCCESS: Entra ID aktualizovane s lokalitou: $location" -Level SUCCESS
            }
            else {
                Write-IPLog -Message "WARN: Lokalita ulozena lokalne, ale Entra ID nebolo aktualizovane" -Level WARN
            }
        }
        else {
            Write-IPLog -Message "WARN: Nemozem aktualizovat Entra ID - chyba serial number" -Level WARN
        }
    }
    else {
        Write-IPLog -Message "INFO: Graph API credentials nie su dostupne, lokalita ulozena iba lokalne" -Level INFO
    }

    Write-IPLog -Message "=== Remediation Script koniec: SUCCESS ===" -Level SUCCESS
    exit $SUCCESS
}
catch {
    $errorMsg = $_.Exception.Message
    Write-IPLog -Message "KRITICKA CHYBA: $errorMsg" -Level ERROR
    
    if ($_.ScriptStackTrace) {
        Write-IPLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    }
    
    exit $FAILURE
}
#endregion