<#
.SYNOPSIS
  Intune Detection Script - kontrola extensionAttribute1 podla IP adresy
.DESCRIPTION
  Zisti IP adresu clienta, porovna so zoznamom IP adries a lokalit
  a zisti ci je extensionAttribute1 nastaveny spravne.
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
$LogFile = "IPcheck_Detection.log"
$LogModulePath = "C:\TaurisIT\Tools\LogHelper.psm1"
$ConfigFile = "IPLocationMap.json"
$RegistryPath = "HKLM:\SOFTWARE\TaurisIT\IPcheck"

# Intune exit codes
$SUCCESS = 0
$REMEDIATION_REQUIRED = 1
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
            Write-EventLog -LogName Application -Source "IntuneScripts" -EventId 1000 -EntryType Information -Message $Message -ErrorAction SilentlyContinue
        }
    }
}

function Get-PrimaryIPAddress {
    try {
        Write-IPLog -Message "Zistujem primarnu IP adresu" -Level INFO
        
        # Metoda 1: Get-NetIPAddress (moderna)
        $ipAddresses = @()
        
        try {
            $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.IPAddress -notmatch '^(169\.254\.|127\.|0\.)' -and
                $_.AddressState -eq 'Preferred' -and
                $_.PrefixOrigin -in @('Dhcp', 'Manual', 'WellKnown')
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
                            $ipAddresses += [PSCustomObject]@{
                                IPAddress       = $ip
                                PrefixLength    = 24
                                InterfaceMetric = 0
                            }
                        }
                    }
                }
            }
        }
        
        if (-not $ipAddresses -or $ipAddresses.Count -eq 0) {
            Write-IPLog -Message "DEBUG: Zoznam vsetkych sieťovych adaptérov:" -Level INFO
            Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
                Write-IPLog -Message "  Adapter: $($_.Name), Status: $($_.Status)" -Level INFO
            }
            throw "Nebola najdena ziadna platna IPv4 adresa"
        }
        
        Write-IPLog -Message "Najdenych $($ipAddresses.Count) IP adries" -Level INFO
        
        # Vyber primarnu IP (uprednostni privatne siete)
        $privateIPs = $ipAddresses | Where-Object { 
            $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' 
        }
        
        if ($privateIPs) {
            # Vyber IP s najvyssou metric hodnotou (najviac preferovana)
            $primaryIP = $privateIPs | 
            Sort-Object -Property @{Expression = { $_.IPAddress -match '^10\.' }; Descending = $true },
            InterfaceMetric |
            Select-Object -First 1 -ExpandProperty IPAddress
            
            Write-IPLog -Message "Vybrata privatna IP: $primaryIP" -Level INFO
        }
        else {
            # Vyber prvu dostupnu IP
            $primaryIP = $ipAddresses | 
            Sort-Object -Property InterfaceMetric |
            Select-Object -First 1 -ExpandProperty IPAddress
            
            Write-IPLog -Message "Vybrata verejna IP: $primaryIP" -Level INFO
        }
        
        return $primaryIP
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

function Get-CurrentLocationFromRegistry {
    try {
        if (Test-Path $RegistryPath) {
            $location = (Get-ItemProperty -Path $RegistryPath -Name "CurrentLocation" -ErrorAction SilentlyContinue).CurrentLocation
            if ($location) {
                $detectedIP = (Get-ItemProperty -Path $RegistryPath -Name "DetectedIP" -ErrorAction SilentlyContinue).DetectedIP
                $lastUpdated = (Get-ItemProperty -Path $RegistryPath -Name "LastUpdated" -ErrorAction SilentlyContinue).LastUpdated
                
                Write-IPLog -Message "Lokalita z registry: $location (IP: $detectedIP, Aktualizovane: $lastUpdated)" -Level INFO
                return $location
            }
        }
        return $null
    }
    catch {
        Write-IPLog -Message "Chyba pri citani z registry: $_" -Level WARN
        return $null
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
#endregion

#region Main Execution
try {
    # Inicializacia logovania
    $loggingInitialized = Initialize-Logging
    
    Write-IPLog -Message "=== Intune Detection Script zaciatok ===" -Level INFO
    Write-IPLog -Message "Script verzia: 2.1 (LogHelper integracia)" -Level INFO
    Write-IPLog -Message "Computer: $env:COMPUTERNAME" -Level INFO
    Write-IPLog -Message "User: $env:USERNAME" -Level INFO
    Write-IPLog -Message "OS: $([System.Environment]::OSVersion.VersionString)" -Level INFO
    Write-IPLog -Message "Logging module: $(if ($loggingInitialized) {'OK'} else {'Failed'})" -Level INFO

    # 1. Load IP location map
    $map = Load-IPLocationMap

    # 2. Get current location from registry
    $currentLocation = Get-CurrentLocationFromRegistry
    $forceRecheck = $false
    
    # Kontrola ci je lokalita starsia ako 24 hodin
    if ($currentLocation) {
        $lastUpdated = (Get-ItemProperty -Path $RegistryPath -Name "LastUpdated" -ErrorAction SilentlyContinue).LastUpdated
        if ($lastUpdated) {
            try {
                $lastUpdateDate = [datetime]::ParseExact($lastUpdated, "yyyy-MM-dd HH:mm:ss", $null)
                $hoursSinceUpdate = ((Get-Date) - $lastUpdateDate).TotalHours
                
                if ($hoursSinceUpdate -gt 24) {
                    Write-IPLog -Message "Lokalita je starsia ako 24 hodin ($hoursSinceUpdate hodin), kontrolujem znova" -Level INFO
                    $forceRecheck = $true
                }
            }
            catch {
                Write-IPLog -Message "Chyba pri parsovani datumu, kontrolujem znova" -Level WARN
                $forceRecheck = $true
            }
        }
    }

    # 3. Get IP address (ak treba recheck alebo nemame lokalitu)
    if ($forceRecheck -or -not $currentLocation) {
        $ip = Get-PrimaryIPAddress
        
        if (-not $ip) {
            # Ak mame staru lokalitu, pouzijeme ju
            if ($currentLocation) {
                Write-IPLog -Message "SUCCESS: IP adresa sa nenasla, pouzivam existujucu lokalitu: $currentLocation" -Level INFO
                Write-IPLog -Message "=== Script koniec: COMPLIANT (stara lokalita) ===" -Level INFO
                exit $SUCCESS
            }
            else {
                Write-IPLog -Message "FAIL: IP adresa sa nenasla a nemame ulozenu lokalitu" -Level ERROR
                exit $REMEDIATION_REQUIRED
            }
        }

        # 4. Determine expected location from IP
        $expectedLocation = Get-LocationFromIP -IPAddress $ip -Map $map
        
        if (-not $expectedLocation) {
            # Ak mame staru lokalitu, pouzijeme ju
            if ($currentLocation) {
                Write-IPLog -Message "WARN: IP $ip nepatri do znamej siete, pouzivam existujucu lokalitu: $currentLocation" -Level WARN
                Write-IPLog -Message "=== Script koniec: COMPLIANT (VPN/unknown network) ===" -Level INFO
                exit $SUCCESS
            }
            else {
                Write-IPLog -Message "FAIL: Prefix pre IP $ip nebol najdeny v mape lokacii" -Level ERROR
                exit $REMEDIATION_REQUIRED
            }
        }
        
        # 5. Compare with current location
        if (-not $currentLocation) {
            Write-IPLog -Message "FAIL: Lokalita nie je nastavena v registry" -Level ERROR
            exit $REMEDIATION_REQUIRED
        }
        
        if ($currentLocation -eq $expectedLocation) {
            Write-IPLog -Message "SUCCESS: Lokalita je spravna ($currentLocation)" -Level SUCCESS
            Write-IPLog -Message "=== Script koniec: COMPLIANT ===" -Level INFO
            exit $SUCCESS
        }
        else {
            Write-IPLog -Message "FAIL: NESUHLASI - Aktualna: '$currentLocation', Ocakavana: '$expectedLocation'" -Level ERROR
            exit $REMEDIATION_REQUIRED
        }
    }
    else {
        # Mame aktualnu lokalitu v registry
        Write-IPLog -Message "SUCCESS: Lokalita je aktualna v registry: $currentLocation" -Level SUCCESS
        Write-IPLog -Message "=== Script koniec: COMPLIANT ===" -Level INFO
        exit $SUCCESS
    }
}
catch {
    $errorMsg = $_.Exception.Message
    Write-IPLog -Message "KRITICKA CHYBA: $errorMsg" -Level ERROR
    
    if ($_.ScriptStackTrace) {
        Write-IPLog -Message "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    }
    
    # V pripade chyby povazujeme za non-compliant
    exit $REMEDIATION_REQUIRED
}
#endregion