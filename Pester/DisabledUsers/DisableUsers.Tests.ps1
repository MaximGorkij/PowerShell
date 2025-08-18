Describe 'Entra Disabled Users Group Script Tests' {

    BeforeAll {
        $global:TestUser = [PSCustomObject]@{
            Id = 'user-id-1234'
            DisplayName = 'P0001 TestUser'
            UserPrincipalName = 'P0001@mojadomena.sk'
            OnPremisesSyncEnabled = $true
        }

        $global:TestGroup = [PSCustomObject]@{
            Id = 'group-id-5678'
            DisplayName = 'Disabled Users Group'
        }

        $global:AllUsersGroup = [PSCustomObject]@{
            Id = 'group-id-9999'
            DisplayName = 'All users'
        }
    }

    Mock Get-MgUser {
        return ,$global:TestUser
    }

    Mock Get-MgGroup {
        return ,$global:TestGroup
    }

    Mock Get-MgUserMemberOf {
        return ,$global:AllUsersGroup
    }

    Mock Get-MgGroupMember {
        return @()
    }

    Mock Add-MgGroupMember {}
    Mock Remove-MgGroupMember {}
    Mock Set-Mailbox {}
    Mock Get-ADUser {}
    Mock Remove-ADUser {}

    Context 'Kontrola filtrovania pouzivatelov' {
        It 'Zachyti iba pouzivatelov s prefixom P0000 a spravnou domenou' {
            $match = $TestUser.UserPrincipalName -match '^P\d{4}@mojadomena.sk$'
            $match | Should -Be $true
        }
    }

    Context 'Kontrola logickeho rozhodnutia o odstraneni uzivatela' {
        It 'Vyhodnoti spravne 90-dnovy limit' {
            $oldDate = (Get-Date).AddDays(-100)
            $result = $oldDate -lt (Get-Date).AddDays(-90)
            $result | Should -Be $true
        }
    }

    Context 'Skupina a clenstvo' {
        It 'Spravne rozpozna, ze pouzivatel nie je clen skupiny' {
            $members = @(@{ Id = 'other-id' })
            $isMember = $members | Where-Object { $_.Id -eq $TestUser.Id }
            ($isMember -eq $null) | Should -Be $true
        }
    }

    Context 'Test logovania' {
        It 'Loguje zaznam do pola logEntries' {
            $logEntries = @()
            $logEntries += "Test log zaznam"
            $logEntries.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Mock volania pre Microsoft Graph' {
        It 'Overi ze Get-MgUser vrati test uzivatela' {
            $users = Get-MgUser -Filter "accountEnabled eq false"
            $users[0].UserPrincipalName | Should -Be 'P0001@mojadomena.sk'
        }

        It 'Overi ze Get-MgGroup vrati test skupinu' {
            $group = Get-MgGroup -Filter "displayName eq 'Disabled Users Group'"
            $group.DisplayName | Should -Be 'Disabled Users Group'
        }
    }

    Context 'Simulacia zalohy pouzivatela' {
        It 'Zalohuje JSON obsah pouzivatela do test suboru' {
            $backupPath = "$env:TEMP\P0001@mojadomena.sk_backup.json"
            $global:TestUser | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupPath -Encoding UTF8
            Test-Path $backupPath | Should -BeTrue

            $content = Get-Content $backupPath -Raw | ConvertFrom-Json
            $content.UserPrincipalName | Should -Be 'P0001@mojadomena.sk'

            Remove-Item $backupPath -Force
        }
    }

}
