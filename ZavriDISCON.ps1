[int]$Rpov=$pocet = 0                    #  všetky parametre  : Get-ADUser p6102 -properties *    297 adminsaliga   0x7FFFFFFFFFFFFFFF al. 9223372036854775807 indicates that the account never expires.
$datum = get-date -format "yyyy-MM-dd_HH.mm.ss"              #   $subor[$Rpov].PocetDni.GetType().name          $pocet.GetType().name    Default
$suborceksV = "C:\Tasky\openDISCONNECTED_$datum.csv.txt"
$suborceksVsmb = "C:\Tasky\openDISCONNECTED_$datum.SMB.txt"
$suborceksVsmb
$ComputerName = "FSRS21"
$openfiles = openfiles.exe /query /s $computerName /fo csv /V
$FileName = "C:\Tasky\openfiles.txt"
$suborVsmb = Get-SMBOpenFile -CIMSession $sessn 
Export-Csv -InputObject $suborVsmb -LiteralPath $suborceksVsmb -NoTypeInformation -Delimiter ";" -Encoding DEFAULT 
$suborceks = "C:\Tasky\openDISCONNECTED.txt"
        if (Test-Path $FileName) {  Remove-Item $FileName }        
        $openfiles | ForEach-Object         {
            $line =( ($_).replace('","',";").replace('"',""))
            if ($line -match ';')    # povodne   '","'
            {
                $line >> $FileName   # sú tam aj diconnected     OPENFILES /Disconnect /ID 1140851578       $($suborceks)    UTF8
            }
        } | ConvertFrom-Csv   #  | Where-Object {$_."Accessed By" -match "albertus"} | format-table -auto            #  [Disconnected]    #  asi tabulator  -Delimiter "`t"    | Select -First 4
#        $suborr = import-csv $openfiles -Delimiter "," -Encoding Default   # | sort dok

import-csv -path $FileName -Delimiter ";" -Encoding UTF8 | Select -skip 2 | Where-Object {($_."Accessed By" -eq "[Disconnected]") } | Export-Csv $suborceks -NoTypeInformation -Delimiter ";" -Encoding UTF8 | sort "Open File (Path\executable)"  
$subor = import-csv $suborceks -Delimiter ";" -Encoding UTF8 | Export-Csv $suborceksV -NoTypeInformation -Delimiter ";" -Encoding UTF8    #| sort "Accessed By" | 
$subor = import-csv $suborceks -Delimiter ";" -Encoding UTF8   # | sort dok
$subor | format-table -auto #| Select -First 15      
$pocet = (Get-Content $($suborceks) | Measure-Object).Count     #   $celkom = $subor.count     $pocetN = $pocet
while ( $pocet-1 -gt $Rpov )
   { $idcko = $subor[$Rpov].ID           #      [int]$Rpov=$pocet = 1      
     $pristup = $subor[$Rpov].'Open Mode'
     if (( $pristup -eq "Read" ) -or ( $pristup -eq "No Access." ) ) {echo $subor[$Rpov].ID  
                                 OPENFILES /Disconnect /ID $subor[$Rpov].ID  }
        elseif (( $pristup -eq "Write + Read" ) -or ( $pristup -eq "No Access." ))  { echo $Rpov  $subor[$Rpov].'Open Mode'==> $subor[$Rpov].ID           # elseif ( $pristup -eq "Write + Read" )  { echo $Rpov  $subor[$Rpov].'Open Mode'==> $subor[$Rpov].ID
                                                  # 
                                                  OPENFILES /Disconnect /ID $subor[$Rpov].ID   #  OPENFILES /Disconnect /ID 3825205265
                                                }
     
     $rpov += 1
   }
"" >> $FileName



