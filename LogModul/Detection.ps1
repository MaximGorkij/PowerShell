<#
.SYNOPSIS
    Detekcia modulu LogHelper
.DESCRIPTION
    Overi, ci je modul LogHelper uz nacitany. Ak nie, importuje ho z pevnej cesty.
.AUTHOR
    Marek Findrik
.CREATED
    2025-09-04
.VERSION
    1.3
.NOTES
    Modul sa importuje len ak este nie je nacitany.
    Pridane robustnejsie kontroly a detailne ladice logy pre version.txt.
#>

# Premenne
$ModuleName = "LogHelper"
$ModulePath = "C:\Program Files\WindowsPowerShell\Modules\LogHelper"
$VersionFile = "$ModulePath\version.txt"
$ManifestFile = "$ModulePath\$ModuleName.psd1"
$ModuleFile = "$ModulePath\$ModuleName.psm1"
$ExpectedVersion = "1.6.0"

Write-Output "=== Zaciatok detekcie modulu $ModuleName ==="

try {
    # 1. Kontrola existencie hlavneho priecinku modulu
    if (-not (Test-Path $ModulePath -PathType Container)) {
        Write-Output "CHYBA: Modulovy priecinok '$ModulePath' neexistuje."
        exit 1
    }
    Write-Output "OK: Modulovy priecinok existuje."

    # 2. Kontrola klucovych suborov modulu
    $MissingFiles = @()
    
    if (-not (Test-Path $VersionFile -PathType Leaf)) {
        $MissingFiles += "version.txt"
    }
    
    # Kontrola ci existuje aspon jeden z hlavnych suborov modulu
    $ModuleFileExists = (Test-Path $ModuleFile -PathType Leaf) -or (Test-Path $ManifestFile -PathType Leaf)
    if (-not $ModuleFileExists) {
        $MissingFiles += "hlavny subor modulu (.psm1 alebo .psd1)"
    }
    
    if ($MissingFiles.Count -gt 0) {
        Write-Output "CHYBA: Chybaju klucove subory: $($MissingFiles -join ', ')"
        exit 1
    }
    Write-Output "OK: Klucove subory modulu existuju."

    # 3. Overenie a validacia verzie
    try {
        Write-Output "DEBUG: Kontrola suboru version.txt na ceste: $VersionFile"

        $fileInfo = Get-Item $VersionFile -ErrorAction Stop
        Write-Output "DEBUG: Velkost suboru version.txt = $($fileInfo.Length) bajtov"
        Write-Output "DEBUG: Pristupove prava (ACL):"
        (Get-Acl $VersionFile).Access | ForEach-Object {
            Write-Output "   $($_.IdentityReference) : $($_.FileSystemRights)"
        }

        $VersionContent = Get-Content $VersionFile -ErrorAction Stop
        if (-not $VersionContent -or $VersionContent.Count -eq 0) {
            Write-Output "CHYBA: Subor version.txt je prazdny."
            exit 1
        }
        
        $InstalledVersion = $VersionContent[0].Trim()
        
        # Validacia formatu verzie (zakladny check)
        if ([string]::IsNullOrWhiteSpace($InstalledVersion)) {
            Write-Output "CHYBA: Verzia v subore version.txt je prazdna alebo whitespace."
            exit 1
        }
        
        Write-Output "INFO: Zistena verzia: '$InstalledVersion'"
        Write-Output "INFO: Ocakavana verzia: '$ExpectedVersion'"
        
    }
    catch {
        Write-Output "CHYBA: Nepodarilo sa nacitat verziu zo suboru '$VersionFile': $($_.Exception.Message)"
        exit 1
    }

    # 4. Porovnanie verzii
    if ($InstalledVersion -eq $ExpectedVersion) {
        Write-Output "USPECH: Modul je v spravnej verzii $ExpectedVersion."
        exit 0
    }
    else {
        Write-Output "CHYBA: Nespravna verzia modulu."
        Write-Output "       Nainstalovana: '$InstalledVersion'"
        Write-Output "       Pozadovana:   '$ExpectedVersion'"
        exit 1
    }

}
catch {
    Write-Output "KRITICKA CHYBA pri detekcii modulu: $($_.Exception.Message)"
    Write-Output "Stack Trace: $($_.ScriptStackTrace)"
    exit 1
}

Write-Output "=== Koniec detekcie modulu $ModuleName ==="
