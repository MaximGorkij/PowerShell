# SoftwareDetection Module

Modul pre PowerShell, ktorý slúži na detekciu softvéru, porovnanie verzie a podporu režimov Intune (Detection / Requirement).

## Inštalácia
```powershell
Import-Module .\SoftwareDetection.psm1

### Výstupy
- Exit 0: Softvér nainštalovaný / verzia vyhovuje
- Exit 1: Softvér nenainštalovaný / verzia nevyhovuje
