Import-Module GroupPolicy
Import-Module -SkipEditionCheck

# Cieľový priečinok na uloženie reportov
$targetFolder = "D:\adminfindrik\PowerShell\GPOResults"
New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null

# Hľadaný path rule (napr. powershell.exe)
$searchTerm = "powershell.exe"

# Získaj všetky GPO
$gpos = Get-GPO -All

foreach ($gpo in $gpos) {
    # Vygeneruj XML report do pamäte
    $report = Get-GPOReport -Guid $gpo.Id -ReportType Xml

    # Skontroluj, či obsahuje Software Restriction Policies
    if ($report -match "SoftwareRestrictionPolicies") {
        # Skontroluj, či obsahuje konkrétny path rule
        if ($report -match $searchTerm) {
            # Vytvor bezpečný názov súboru
            $safeName = $gpo.DisplayName -replace '[\\/:*?"<>|]', '_'
            $filePath = Join-Path $targetFolder "$safeName.xml"

            # Ulož report do súboru
            $report | Out-File -FilePath $filePath -Encoding UTF8

            Write-Host "✅ GPO '$($gpo.DisplayName)' obsahuje Software Restriction Policies a path rule '$searchTerm'."
        }
    }
}