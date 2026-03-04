$ScriptPath = "$PSScriptRoot\ExitUser.ps1"

Describe "ExitUser.ps1 Tests" {

    BeforeAll {
        # --- MOCKOVANIE ZÁKLADNÝCH FUNKCIÍ ---
        # Potlačenie výstupu a logovania
        # Mockneme aj New-Item pre prípad, že adresár pre zálohy neexistuje
        Mock New-Item {}
        Mock Write-Host {}
        Mock Write-CustomLog {}
        # Zabránenie načítaniu reálnych modulov
        Mock Import-Module {}
        
        # --- MOCKOVANIE PROSTREDIA (.ENV) ---
        Mock Test-Path { return $true } -ParameterFilter { $Path -like "*.env" }
        Mock Get-Content { 
            return "CLIENT_ID=test-client-id", "TENANT_ID=test-tenant-id", "CLIENT_SECRET=test-secret" 
        } -ParameterFilter { $Path -like "*.env" }

        # --- MOCKOVANIE PRIPOJENIA ---
        Mock Connect-MgGraph {}
        Mock Connect-ExchangeOnline {}
        Mock ConvertTo-SecureString { return "secure-string" }

        # --- MOCKOVANIE GRAPH A ZÁLOHOVANIA ---
        Mock Get-MgUser {}
        Mock Get-MgUserMemberOf {}
        Mock Get-MgUserJoinedTeam {}
        Mock Remove-MgGroupMemberByRef {}
        Mock Export-Clixml {}
    }

    Context "Scenár 1: Používateľ nenájdený" {
        It "Skončí a nevykoná žiadne zmeny, ak sa používateľ nenájde" {
            # Mock vstupu - hľadáme neexistujúceho
            Mock Read-Host { return "NonExistent" } -ParameterFilter { $Prompt -like "*Zadajte meno*" }
            
            # Mock AD - vráti prázdne pole
            Mock Get-ADUser { return @() }

            # Spustenie skriptu
            & $ScriptPath

            # Overenie, že sa nezavolal Disable-ADAccount
            Assert-MockCalled Disable-ADAccount -Times 0
        }
    }

    Context "Scenár 2: Offboarding s Litigation Hold (Voľba 1)" {
        It "Vykoná kompletný offboarding proces s Litigation Hold" {
            # --- MOCKOVANIE VSTUPOV (Read-Host) ---
            # 1. Meno, 2. Voľba 1, 3. LitHold Ano, 4. Potvrdenie Ano
            # 1. Meno, 2. Voľba 1, 3. LitHold Ano, 4. Odstrániť z cloud skupín Ano, 5. Potvrdenie Ano
            Mock Read-Host { return "Jan Novak" } -ParameterFilter { $Prompt -like "*Zadajte meno*" }
            Mock Read-Host { return "1" } -ParameterFilter { $Prompt -like "*Voľba (1-2)*" }
            Mock Read-Host { return "y" } -ParameterFilter { $Prompt -like "*Aktivovať Litigation Hold?*" }
            Mock Read-Host { return "y" } -ParameterFilter { $Prompt -like "*Odstrániť zo všetkých cloudových skupín*" }
            Mock Read-Host { return "y" } -ParameterFilter { $Prompt -like "*Spustiť offboarding*" }

            # --- MOCKOVANIE AD OBJEKTOV ---
            $fakeUser = [PSCustomObject]@{
                DisplayName       = "Jan Novak"
                UserPrincipalName = "jan.novak@tauris.sk"
                SamAccountName    = "jan.novak"
                DistinguishedName = "CN=Jan Novak,OU=Users,DC=tauris,DC=local"
            }

            # Mock pre Graph User
            Mock Get-MgUser { return [PSCustomObject]@{ Id = 'fake-entra-user-id' } }
            
            # Mock pre vyhľadanie usera
            Mock Get-ADUser { return $fakeUser } -ParameterFilter { $Filter -like "*Jan Novak*" }
            # Mock pre vyhľadanie usera po premenovaní (používa sa pri Move-ADObject)
            Mock Get-ADUser { return $fakeUser } -ParameterFilter { $Filter -like "*ex_jan.novak*" }

            # Mock AD Skupín (vráti Domain Users + Marketing)
            Mock Get-ADPrincipalGroupMembership { 
                return @(
                    [PSCustomObject]@{ Name = "Domain Users"; distinguishedName = "CN=Domain Users,DC=tauris,DC=local" },
                    [PSCustomObject]@{ Name = "Marketing"; distinguishedName = "CN=Marketing,OU=Groups,DC=tauris,DC=local" }
                )
            }

            # Mock Cloud Skupín (vráti 1 normálnu, 1 dynamickú a 1 Team)
            Mock Get-MgUserMemberOf {
                return @(
                    [PSCustomObject]@{ Id = 'cloud-group-1-id'; DisplayName = 'Cloud Group 1'; GroupTypes = @() },
                    [PSCustomObject]@{ Id = 'dynamic-group-id'; DisplayName = 'Dynamic Group'; GroupTypes = @('DynamicMembership') }
                )
            }
            Mock Get-MgUserJoinedTeam {
                return @(
                    [PSCustomObject]@{ DisplayName = 'Sales Team' }
                )
            }

            # --- MOCKOVANIE AKCIÍ ---
            Mock Disable-ADAccount {}
            Mock Remove-ADGroupMember {}
            Mock Set-Mailbox {}
            Mock Revoke-MgUserSignInSession {}
            Mock Rename-ADObject {}
            Mock Move-ADObject {}
            Mock Export-Clixml {}
            Mock Remove-MgGroupMemberByRef {}

            # --- SPUSTENIE ---
            & $ScriptPath

            # --- OVERENIA ---
            Assert-MockCalled Disable-ADAccount -Times 1
            # Overenie, že sa odstraňuje zo skupiny Marketing, ale NIE z Domain Users
            Assert-MockCalled Remove-ADGroupMember -Times 1 -ParameterFilter { $Identity -eq "CN=Marketing,OU=Groups,DC=tauris,DC=local" }
            # Overenie zálohy AD skupín do XML
            Assert-MockCalled Export-Clixml -Times 1
            # Overenie odstránenia z cloudovej skupiny (dynamická sa má preskočiť)
            Assert-MockCalled Remove-MgGroupMemberByRef -Times 1 -ParameterFilter { $_.GroupId -eq 'cloud-group-1-id' }
            # Overenie nastavenia Litigation Hold
            Assert-MockCalled Set-Mailbox -Times 1 -ParameterFilter { $LitigationHoldEnabled -eq $true }
            # Overenie Graph odhlásenia
            Assert-MockCalled Revoke-MgUserSignInSession -Times 1
            Assert-MockCalled Revoke-MgUserSignInSession -Times 1 -ParameterFilter { $UserId -eq 'fake-entra-user-id' }
            # Overenie premenovania a presunu
            Assert-MockCalled Rename-ADObject -Times 1 -ParameterFilter { $NewName -eq "ex_jan.novak" }
            Assert-MockCalled Move-ADObject -Times 1
        }
    }

    Context "Scenár 3: Shared Mailbox a Delegácia (Voľba 2)" {
        It "Konvertuje na Shared Mailbox a nastaví práva delegátovi" {
            # --- MOCKOVANIE VSTUPOV ---
            Mock Read-Host { return "Jan Novak" } -ParameterFilter { $Prompt -like "*Zadajte meno*" }
            Mock Read-Host { return "2" } -ParameterFilter { $Prompt -like "*Voľba (1-2)*" }
            Mock Read-Host { return "Boss" } -ParameterFilter { $Prompt -like "*Meno osoby pre prístup*" }
            Mock Read-Host { return "n" } -ParameterFilter { $Prompt -like "*Odstrániť zo všetkých cloudových skupín*" }
            Mock Read-Host { return "y" } -ParameterFilter { $Prompt -like "*Spustiť offboarding*" }

            # --- MOCKOVANIE AD ---
            $targetUser = [PSCustomObject]@{ DisplayName = "Jan Novak"; UserPrincipalName = "jan.novak@tauris.sk"; SamAccountName = "jan.novak"; DistinguishedName = "CN=Jan Novak,DC=local" }
            $delegateUser = [PSCustomObject]@{ DisplayName = "Big Boss"; UserPrincipalName = "boss@tauris.sk" }

            Mock Get-MgUser { return [PSCustomObject]@{ Id = 'fake-entra-user-id-2' } }
            Mock Get-ADUser { return $targetUser } -ParameterFilter { $Filter -like "*Jan Novak*" }
            Mock Get-ADUser { return $delegateUser } -ParameterFilter { $Filter -like "*Boss*" }
            Mock Get-ADUser { return $targetUser } -ParameterFilter { $Filter -like "*ex_jan.novak*" }
            Mock Get-ADPrincipalGroupMembership { return @() }

            # --- MOCKOVANIE AKCIÍ ---
            Mock Disable-ADAccount {}; Mock Set-Mailbox {}
            Mock Add-MailboxPermission {}; Mock Revoke-MgUserSignInSession {}
            Mock Rename-ADObject {}; Mock Move-ADObject {}
            Mock Export-Clixml {}
            Mock Remove-MgGroupMemberByRef {}

            & $ScriptPath

            Assert-MockCalled Set-Mailbox -ParameterFilter { $Type -eq "Shared" }
            Assert-MockCalled Add-MailboxPermission -ParameterFilter { $User -eq "boss@tauris.sk" -and $AccessRights -eq "FullAccess" }
            # Overenie, že sa záloha AD skupín nevolala (pretože Get-ADPrincipalGroupMembership vracia @())
            Assert-MockCalled Export-Clixml -Times 0
            # Overenie, že sa neodstraňovali cloud skupiny (pretože sme zadali 'n')
            Assert-MockCalled Remove-MgGroupMemberByRef -Times 0
        }
    }
}