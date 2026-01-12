function Import-Env {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnvPath,

        [string]$ExportDir
    )

    if (-not (Test-Path $EnvPath)) {
        throw "Env file not found: $EnvPath"
    }

    Get-Content $EnvPath | ForEach-Object {
        if ($_ -match '^\s*#' -or [string]::IsNullOrWhiteSpace($_)) {
            return
        }

        if ($_ -match '^\s*([^=\s]+)\s*=\s*(.*)\s*$') {
            $name = $matches[1]
            $value = $matches[2]

            if (-not [string]::IsNullOrWhiteSpace($value)) {
                [Environment]::SetEnvironmentVariable($name, $value, 'Process')
            }
        }
    }

    if ($ExportDir -and -not $env:EXPORT_DIR) {
        [Environment]::SetEnvironmentVariable('EXPORT_DIR', $ExportDir, 'Process')
    }

    if ($env:EXPORT_DIR -and -not (Test-Path $env:EXPORT_DIR)) {
        New-Item -ItemType Directory -Path $env:EXPORT_DIR -Force | Out-Null
    }
}

function Initialize-Env {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnvPath,

        [string]$ExportDir
    )

    Import-Env -EnvPath $EnvPath -ExportDir $ExportDir
}

Export-ModuleMember -Function Import-Env, Initialize-Env
