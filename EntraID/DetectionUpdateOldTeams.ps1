$targetFile = Get-ChildItem -Path "C:\" -Recurse -Force -ErrorAction SilentlyContinue | 
              Where-Object { $_.Name -eq "Update.exe" }
if ($targetFile) { exit 1 }  # Non-zero = problem found
else { exit 0 }              # 0 = compliant