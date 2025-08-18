@echo off
setlocal

:: Nazov skriptu
set SCRIPT=RemoveSCCM.ps1

:: Overenie, či sa spúšťa ako admin
whoami /groups | find "S-1-5-32-544" >nul
if %errorlevel% neq 0 (
    echo Spustenie ako administrator je vyžadované. Znova spustím ako admin...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: Voliteľné: povoliť DryRun režim (nastav DRYRUN=1 pre simuláciu)
set DRYRUN=1

:: Spustenie skriptu
if %DRYRUN%==1 (
    powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0%SCRIPT%" -DryRun
) else (
    powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0%SCRIPT%"
)

endlocal
pause
