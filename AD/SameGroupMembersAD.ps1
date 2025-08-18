$Searcher = [adsisearcher]'(member=*)'
    $Searcher.PageSize = 500
    $Searcher.FindAll() | ForEach-Object {
        New-Object -TypeName PSCustomObject -Property @{
            DistinguishedName = $_.Properties.distinguishedname[0]
            Member = $_.Properties.member -join ';'
        }
    } | Group-Object -Property member | Where-Object {$_.Count -gt 1} |
    Sort-Object -Property Count -Descending |
    Select-Object -ExpandProperty Group |
    Export-Csv -Path GroupWithIdenticalMembership.csv -NoTypeInformation
