# ACME.psm1
# Modul pre pracu s win-acme
# Logovanie v Windows-1250, centralna konfiguracia, audit-ready

function Load-Env {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "ENV file not found: $Path"
    }

    Get-Content $Path | ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            Set-Item -Path "env:$($matches[1])" -Value $matches[2]
        }
    }
}

function Write-Log {
    param(
        [string]$Message,
        [string]$LogFile = "C:\Skripty\ExportIntuneLogs\acme.log"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "$timestamp`t$Message"

    $bytes = [System.Text.Encoding]::GetEncoding(1250).GetBytes($line + "`r`n")
    [System.IO.File]::Open($LogFile, "Append", "Write", "ReadWrite").Write($bytes, 0, $bytes.Length)
}

function Validate-Path {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        Write-Log "Created missing directory: $Path"
    }
}

function Get-CertExpiration {
    param([string]$Domain)

    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$Domain*" }
    return $cert.NotAfter
}

function Run-WinAcme {
    param(
        [string]$Args
    )

    $exe = "C:\Tools\win-acme\wacs.exe"

    if (-not (Test-Path $exe)) {
        Write-Log "win-acme not found at $exe"
        throw "win-acme not found"
    }

    Write-Log "Running win-acme with args: $Args"
    & $exe $Args
}

function Export-CertPfx {
    param(
        [string]$Domain,
        [string]$OutPath,
        [string]$Password
    )

    Validate-Path (Split-Path $OutPath)

    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$Domain*" }

    Export-PfxCertificate -Cert $cert -FilePath $OutPath -Password (ConvertTo-SecureString $Password -AsPlainText -Force)

    Write-Log "Exported PFX for $Domain to $OutPath"
}

function Renew-Cert {
    param(
        [string]$Domain,
        [string]$PfxPath,
        [string]$Password
    )

    Write-Log "Starting renewal for $Domain"

    Run-WinAcme "--renew"

    Export-CertPfx -Domain $Domain -OutPath $PfxPath -Password $Password

    $exp = Get-CertExpiration -Domain $Domain
    Write-Log "Renewal complete. New expiration: $exp"
}