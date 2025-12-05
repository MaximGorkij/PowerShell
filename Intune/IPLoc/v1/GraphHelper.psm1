<#
.SYNOPSIS
  Graph Helper Module pre Intune Remediation
.DESCRIPTION
  Pomocne funkcie pre pracu s Microsoft Graph API
  Pouziva deviceId namiesto serialNumber pre vyhladavanie zariadeni
.VERSION
  2.0
#>

function Get-GraphToken {
    <#
    .SYNOPSIS
    Ziska OAuth2 token pre Microsoft Graph API
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        
        [Parameter(Mandatory = $true)]
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
    <#
    .SYNOPSIS
    Najde zariadenie v Graph API podla deviceId alebo computer name
    #>
    param(
        [string]$AccessToken,
        [string]$DeviceId,
        [string]$ComputerName
    )
    
    $headers = @{
        Authorization  = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }
    
    try {
        # Metoda 1: Hladat podla deviceId (Azure AD Device ID)
        if ($DeviceId) {
            $deviceUri = "https://graph.microsoft.com/v1.0/devices?`$filter=deviceId eq '$DeviceId'&`$select=id,displayName,deviceId,extensionAttributes"
            Write-Output "Hladam zariadenie podla deviceId: $DeviceId"
            
            $response = Invoke-RestMethod -Uri $deviceUri -Headers $headers -Method Get -ErrorAction Stop
            
            if ($response.value -and $response.value.Count -gt 0) {
                Write-Output "Nasiel som zariadenie podla deviceId"
                return $response.value[0]
            }
        }
        
        # Metoda 2: Hladat podla displayName (computer name)
        if ($ComputerName) {
            $deviceUri = "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$ComputerName'&`$select=id,displayName,deviceId,extensionAttributes"
            Write-Output "Hladam zariadenie podla computer name: $ComputerName"
            
            $response = Invoke-RestMethod -Uri $deviceUri -Headers $headers -Method Get -ErrorAction Stop
            
            if ($response.value -and $response.value.Count -gt 0) {
                Write-Output "Nasiel som zariadenie podla computer name"
                
                # Ak je viac zariadeni, vrat prve
                if ($response.value.Count -eq 1) {
                    return $response.value[0]
                }
                else {
                    Write-Output "Varovanie: Viacero zariadeni s rovnakym menom, pouzivam prve"
                    
                    # Ak mame deviceId, skusime najst spravne zariadenie
                    if ($DeviceId) {
                        foreach ($device in $response.value) {
                            if ($device.deviceId -eq $DeviceId) {
                                Write-Output "Nasiel som spravne zariadenie podla deviceId"
                                return $device
                            }
                        }
                    }
                    
                    return $response.value[0]
                }
            }
        }
        
        # Metoda 3: Ziskat vsetky zariadenia (obmedzene)
        Write-Output "Hladam medzi vsetkymi zariadeniami..."
        $deviceUri = "https://graph.microsoft.com/v1.0/devices?`$top=100&`$select=id,displayName,deviceId,extensionAttributes"
        
        $response = Invoke-RestMethod -Uri $deviceUri -Headers $headers -Method Get -ErrorAction Stop
        
        if ($response.value) {
            # Hladat podla deviceId
            if ($DeviceId) {
                foreach ($device in $response.value) {
                    if ($device.deviceId -eq $DeviceId) {
                        Write-Output "Nasiel som zariadenie v zozname vsetkych zariadeni"
                        return $device
                    }
                }
            }
            
            # Hladat podla computer name
            if ($ComputerName) {
                foreach ($device in $response.value) {
                    if ($device.displayName -eq $ComputerName) {
                        Write-Output "Nasiel som zariadenie v zozname podla mena"
                        return $device
                    }
                }
            }
        }
        
        throw "Zariadenie nebolo najdene v Graph API (DeviceId: $DeviceId, Computer: $ComputerName)"
    }
    catch {
        Write-Error "Chyba pri hladani zariadenia: $_"
        throw
    }
}

function Update-DeviceInGraph {
    <#
    .SYNOPSIS
    Aktualizuje extensionAttributes zariadenia v Graph API
    #>
    param(
        [string]$AccessToken,
        [string]$DeviceObjectId,
        [string]$Location,
        [string]$SerialNumber
    )
    
    $headers = @{
        Authorization  = "Bearer $AccessToken"
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
        Write-Output "Body: $updateBody"
        
        Invoke-RestMethod -Uri $updateUri -Headers $headers -Method Patch -Body $updateBody -ErrorAction Stop
        
        Write-Output "Zariadenie uspesne aktualizovane"
        return $true
    }
    catch {
        Write-Error "Chyba pri aktualizacii zariadenia: $_"
        
        # Log error details
        if ($_.ErrorDetails) {
            Write-Error "Error details: $($_.ErrorDetails.Message)"
        }
        
        throw
    }
}

function Test-GraphConnection {
    <#
    .SYNOPSIS
    Testuje spojenie s Graph API
    #>
    param(
        [string]$AccessToken
    )
    
    $headers = @{
        Authorization  = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }
    
    try {
        $testUri = "https://graph.microsoft.com/v1.0/organization"
        $response = Invoke-RestMethod -Uri $testUri -Headers $headers -Method Get -ErrorAction Stop
        
        Write-Output "Graph API connection successful"
        Write-Output "Tenant: $($response.value[0].displayName)"
        return $true
    }
    catch {
        Write-Error "Graph API connection failed: $_"
        return $false
    }
}

Export-ModuleMember -Function Get-GraphToken, Find-DeviceInGraph, Update-DeviceInGraph, Test-GraphConnection