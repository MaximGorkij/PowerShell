$datum = get-date -format "yyyy-MM-dd_HH.mm"
Add-Content -Path "c:\Users\adminfindrik\lock.log" -Value $datum
Get-SmbOpenFile -CimSession "FSKE21" | Where-Object { $_.ClientUserName -notlike "TAURIS\*" } | Select-object FileID, ClientUserName, Path | Add-Content "c:\Users\adminfindrik\lock.log"
Add-Content -Path "c:\Users\adminfindrik\lock.log" -Value "..."
