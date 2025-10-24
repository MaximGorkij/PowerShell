function Process-ScriptsAndInjectSecrets {
    param (
        [Parameter(Mandatory)]
        [string]$ScriptRoot,

        [Parameter(Mandatory)]
        [string]$InjectModuleSourcePath
    )

    $outputPath = Join-Path $ScriptRoot "CollectedSecrets.json"
    $secretsPath = Join-Path $ScriptRoot "secrets.json"
    $injectModuleTargetPath = Join-Path $ScriptRoot "InjectSecrets.psm1"

    # Skopíruj modul do root adresára, ak tam ešte nie je
    if (-not (Test-Path $injectModuleTargetPath)) {
        Copy-Item -Path $InjectModuleSourcePath -Destination $injectModuleTargetPath -Force
        Write-Host "Modul InjectSecrets.psm1 skopírovaný do: $injectModuleTargetPath" -ForegroundColor Cyan
    }

    $patterns = @{
        "ClientId"     = '(?i)(ClientId|AppId)\s*=\s*["'']([^"'']+)["'']'
        "ClientSecret" = '(?i)(ClientSecret|AppSecret)\s*=\s*["'']([^"'']+)["'']'
        "TenantId"     = '(?i)(TenantId)\s*=\s*["'']([^"'']+)["'']'
    }

    $results = @{}

    Get-ChildItem -Path $ScriptRoot -Recurse -Include *.ps1, *.psm1 | ForEach-Object {
        $file = $_.FullName
        $content = Get-Content $file -Raw
        $originalContent = $content
        $modified = $false

        foreach ($key in $patterns.Keys) {
            $regex = $patterns[$key]
            if ($content -match $regex) {
                $value = $matches[2]
                $content = [regex]::Replace($content, $regex, "$key = `$$key")
                $modified = $true

                if (-not $results.ContainsKey($key)) {
                    $results[$key] = @()
                }
                $results[$key] += @{
                    "value"  = $value
                    "source" = $file
                }
            }
        }

        if ($modified -and $content -ne $originalContent) {
            # Doplníme import modulu a secrets, ak tam ešte nie sú
            if ($content -notmatch 'Import-Module\s+.+InjectSecrets') {
                $importLine = "Import-Module '.\InjectSecrets.psm1'"
                $content = "$importLine`n$content"
            }
            if ($content -notmatch 'Import-Secrets') {
                $importSecretsLine = "Import-Secrets -SecretsPath '.\secrets.json'"
                $content = "$importSecretsLine`n$content"
            }

            Set-Content -Path $file -Value $content -Encoding UTF8
            Write-Host "Upravený: $file" -ForegroundColor Yellow
        }
    }

    # Export secrets do JSON
    $results | ConvertTo-Json -Depth 5 | Out-File $outputPath -Encoding UTF8
    Write-Host "Secrets exportované do: $outputPath" -ForegroundColor Green

    # Vytvor secrets.json ak ešte neexistuje
    if (-not (Test-Path $secretsPath)) {
        $flatSecrets = @{}
        foreach ($key in $results.Keys) {
            $flatSecrets[$key] = $results[$key][0].value
        }
        $flatSecrets | ConvertTo-Json | Out-File $secretsPath -Encoding UTF8
        Write-Host "Vytvorený súbor: $secretsPath" -ForegroundColor Green
    }
}
Export-ModuleMember -Function Process-ScriptsAndInjectSecrets