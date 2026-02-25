# Použijeme absolútnu cestu k skriptu
$ScriptFile = "TurnORealTime.ps1"
$ScriptPath = Join-Path $PSScriptRoot $ScriptFile

Describe "Defender RTP Remediation Script" {
    
    BeforeAll {
        # Overíme, či súbor vôbec existuje, aby sme nehadali
        if (-not (Test-Path $ScriptPath)) {
            Write-Error "TEST ERROR: Subor $ScriptPath nebol najdeny!"
        }

        # Mockujeme vsetko, co by mohlo skript zastavit
        Mock Write-CustomLog { return $true }
        Mock Test-Path { return $true }
        Mock Import-Module { return $true }
        # Mockujeme admin kontrolu (v skripte je to if s IsInRole, toto zachyti vsetky volania)
        Mock Get-Current { return [PSCustomObject]@{ IsInRole = { return $true } } }
        
        # Zakladny stav Defendera
        Mock Get-MpComputerStatus {
            return [PSCustomObject]@{
                AMServiceEnabled          = $true
                RealTimeProtectionEnabled = $true
            }
        }
        Mock Set-MpPreference { return $true }
    }

    Context "RTP Status Checks" {
        
        It "Should run the script without throwing errors" {
            # Namiesto { . $ScriptPath } pouzijeme scriptblock s explicitnou cestou
            $TestData = {
                param($Path)
                . $Path
            }
            
            Invoke-Command -ScriptBlock $TestData -ArgumentList $ScriptPath | Should -Not -Throw
        }

        It "Should call Set-MpPreference if RTP is disabled" {
            # Predefinujeme Mock len pre tento test
            Mock Get-MpComputerStatus {
                return [PSCustomObject]@{
                    AMServiceEnabled          = $true
                    RealTimeProtectionEnabled = $false
                }
            }
            
            # Jednoduchy Mock bez specifikacie modulu (Pester si ho najde sam v globale)
            Mock Set-MpPreference { }
            
            # Spustime skript
            $TestData = { param($Path) . $Path }
            Invoke-Command -ScriptBlock $TestData -ArgumentList $ScriptPath
            
            # Overime volanie
            Assert-MockCalled Set-MpPreference -Times 1 -Exactly
        }
    }
}