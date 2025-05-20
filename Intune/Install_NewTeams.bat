@echo off
REM Odinštaluj starý Teams (ak je per-user)
for /D %%x in ("C:\Users\*\AppData\Local\Microsoft\Teams") do (
    "%%x\Update.exe" --uninstall -s
)

REM Odinštaluj machine-wide Teams inštalátor (ak existuje)
msiexec /x {731F6BAA-A986-45A4-8936-7C3AAAAA760B} /qn

REM Inštaluj nový Teams (enterprise mode, all users)
TeamsBootstrapper.exe -p

exit /b 0
