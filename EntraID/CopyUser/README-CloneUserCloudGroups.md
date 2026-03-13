# Clone-ADUser.ps1

Skript na klonovanie Active Directory používateľského účtu vrátane členstva v AD skupinách a cloud skupinách (Entra ID / Intune).

**Verzia:** 4.0  
**Prostredie:** Windows Server, PowerShell 5.1+

---

## Požiadavky

| Modul | Zdroj |
|---|---|
| `ActiveDirectory` | RSAT / Windows Server |
| `LogHelper` | Interný modul (`C:\Program Files\WindowsPowerShell\Modules\LogHelper\LogHelper.psm1`) |
| `Microsoft.Graph.Groups` | PSGallery |
| `Microsoft.Graph.Users` | PSGallery |
| `ScheduledTasks` | Vstavaný (Windows) |

Inštalácia Graph modulov:
```powershell
Install-Module Microsoft.Graph.Groups, Microsoft.Graph.Users -Scope AllUsers
```

---

## Konfigurácia

Na začiatku skriptu sa nachádzajú tieto nastaviteľné premenné:

| Premenná | Predvolená hodnota | Popis |
|---|---|---|
| `$TestMode` | `$false` | `$true` = WhatIf simulácia, nič sa nevytvorí |
| `$ModulePath` | `C:\Program Files\...\LogHelper.psm1` | Cesta k LogHelper modulu |
| `$LogDir` | `C:\TaurisIT\Log\UserClone` | Adresár pre log súbory |
| `$EventSource` | `ADUserCloneApp` | Zdroj pre Windows Event Log |

---

## Spustenie

```powershell
.\Clone-ADUser.ps1
```

Skript je interaktívny – všetky vstupy sa zadávajú počas behu cez `Read-Host`.

---

## Postup skriptu

### 1. Vyhľadanie predlohy
Zadáte priezvisko vzorového používateľa. Skript vráti zoznam zhôd, z ktorého vyberiete číslo.

### 2. Zadanie údajov nového účtu

| Pole | Validácia |
|---|---|
| Meno / Priezvisko | Kontrola duplicity v AD (Meno + Priezvisko) |
| Email | Automaticky detekuje doménu `@tauris.sk` alebo `@masiarstvoubyka.sk` podľa predlohy |
| Employee ID | 5 alebo 7 číslic, musí začínať `0` (napr. `01234` alebo `0123456`) |
| SAM login | Generuje návrh z priezviska (bez diakritiky), overuje unikátnosť v AD |
| Telefón | Formát `09XXXXXXXX` → automaticky prepíše na `+421XXXXXXXXX` |

### 3. Technická kontrola
Pred vytvorením overí, či `SamAccountName` aj `EmailAddress` ešte nie sú obsadené v AD.

### 4. Súhrn (Summary)
Zobrazí všetky zadané aj prenesené údaje. Vyžaduje potvrdenie `A` pred pokračovaním.

### 5. Vytvorenie účtu
Účet sa vytvorí s `Enabled = $false` a `ChangePasswordAtLogon = $false`. Heslo je vo formáte `TaurisROK` (napr. `Tauris2025`).

Zo vzorového účtu sa prenesú: `Title`, `Department`, `Company`, `Manager`, `Office`, `StreetAddress`, `City`, `PostalCode`, `State`, `Country`, `Description`.

### 6. AD skupiny
Nový účet sa pridá do všetkých AD skupín, ktorých je predloha členom. Výsledok (`OK` / `Chyba`) sa vypíše a zaloguje.

### 7. Cloud skupiny – Scheduled Task
Voliteľný doplnok. Skript sa pripojí na Microsoft Graph, načíta cloud skupiny predlohy (filtruje skupiny kde `OnPremisesSyncEnabled -ne $true`) a zaregistruje **Scheduled Task** na `+1 hodinu` od spustenia skriptu.

Dôvod oneskorenia: AAD Connect synchronizácia trvá typicky 20–30 minút. Task počká, kým je nový účet dostupný v Entra ID.

Po spustení task zapíše výsledok do **Windows Event Log**:
- `Application` → Source: `ADUserCloneApp`
- EventId `100` = úspech
- EventId `101` = chyba pri konkrétnej skupine

### 8. Auto-Enable – Scheduled Task
Voliteľný doplnok. Naplánuje automatické zapnutie účtu (`Enabled = $true`) na zvolený dátum vo formáte `dd.MM.yyyy`. Čas spustenia je `06:00`. Do popisu účtu (`Description`) sa zapíše značka `[AUTO-ENABLE: dd.MM.yyyy]`.

---

## Logika domény

| Email predlohy | Doména nového účtu |
|---|---|
| `*@tauris.sk` | `@tauris.sk` |
| `*@masiarstvoubyka.sk` | `@masiarstvoubyka.sk` |

---

## Logovanie

Každý beh vytvorí log súbor v `$LogDir` s názvom `yyyyMMddHHmm-UserClone.log`.

Ak modul `LogHelper` nie je dostupný, skript pokračuje s fallback funkciou ktorá vypíše správy len do konzoly.

---

## Test / WhatIf režim

```powershell
$TestMode = $true
```

V tomto režime sa:
- nevytvorí žiadny AD účet
- nepridá žiadna skupina
- nezaregistruje žiadny Scheduled Task
- všetky akcie sa vypíšu s prefixom `WHATIF:`

---

## Scheduled Tasky

| Názov tasku | Čas spustenia | Popis |
|---|---|---|
| `CloudGroups-<sam>` | +1h od spustenia skriptu | Pridanie do Entra ID cloud skupín |
| `Enable-ADUser-<sam>` | Zvolený dátum o 06:00 | Automatické zapnutie účtu |

Tasky bežia pod `RunLevel Highest` (elevated).

---

## Oprávnenia

| Akcia | Požadované oprávnenie |
|---|---|
| Čítanie / zápis AD | `Domain Admins` alebo delegované Account Operators |
| Registrácia Scheduled Taskov | Lokálny administrátor na serveri kde skript beží |
| Graph API | `GroupMember.ReadWrite.All`, `User.Read.All` |

---

## Príklad behu

```
Zadaj priezvisko vzoroveho pouzivatela: Novak

Najdene:
[0] Jan Novak (jan.novak@tauris.sk)
[1] Peter Novak (peter.novak@tauris.sk)

Vyberte cislo (0 - 1): 0

Zadaj udaje noveho uctu:
Meno: Martin
Priezvisko: Kovac
Email (pred @tauris.sk): martin.kovac
Employee ID (5 alebo 7 miest, musi zacinat 0): 0123456
SAM login [kovac]: kovac
Telefon (zadajte 09XXXXXXXX): 0901234567

==========================================
          SUHRN NOVEHO UZIVATELA
==========================================
Meno a Priezvisko : Martin Kovac
Email             : martin.kovac@tauris.sk
...
Suhlasite s vytvorenim uctu? (A/N): A
```