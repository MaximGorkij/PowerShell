function Import-Secrets {
    param (
        [Parameter(Mandatory = $false)]
        [string]$SecretsPath = "$PSScriptRoot\secrets.json"
    )

    if (-not (Test-Path $SecretsPath)) {
        throw "Secrets file not found: $SecretsPath"
    }

    try {
        $secrets = Get-Content $SecretsPath -Raw | ConvertFrom-Json

        # Validácia formátov
        function Test-Guid($value) {
            return [guid]::TryParse($value, [ref]([guid]::Empty))
        }

        function Test-Base64($value) {
            try {
                [Convert]::FromBase64String($value) | Out-Null
                return $true
            }
            catch {
                return $false
            }
        }

        if ($secrets.ClientId) {
            if (-not (Test-Guid $secrets.ClientId)) {
                Write-Warning "ClientId nemá formát GUID: $($secrets.ClientId)"
            }
            Set-Variable -Name ClientId -Value $secrets.ClientId -Scope Global
        }

        if ($secrets.ClientSecret) {
            if (-not (Test-Base64 $secrets.ClientSecret)) {
                Write-Warning "ClientSecret nemá formát Base64: $($secrets.ClientSecret)"
            }
            Set-Variable -Name ClientSecret -Value $secrets.ClientSecret -Scope Global
        }

        if ($secrets.TenantId) {
            if (-not (Test-Guid $secrets.TenantId)) {
                Write-Warning "TenantId nemá formát GUID: $($secrets.TenantId)"
            }
            Set-Variable -Name TenantId -Value $secrets.TenantId -Scope Global
        }

        Write-Host "Secrets injektované do session." -ForegroundColor Green
    }
    catch {
        Write-Host "Chyba pri načítaní secrets: $_" -ForegroundColor Red
    }
}

Export-ModuleMember -Function Import-Secrets