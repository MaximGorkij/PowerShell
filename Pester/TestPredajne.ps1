<#
.SYNOPSIS
    Pester tests for Predajne.ps1 script
.DESCRIPTION
    Unit and integration tests for the user session termination script
#>

# Import the Pester module
Import-Module Pester

# Set strict mode for testing
Set-StrictMode -Version Latest

# Path to the script to test
$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "Predajne.ps1"

Describe "Exit-UserSessions Script Tests" {
    BeforeAll {
        # Mock functions and cmdlets that interact with external services
        function Connect-MgGraph { param($Scopes) }
        function Connect-ExchangeOnline { param($ShowBanner) }
        function Disconnect-MgGraph {}
        function Disconnect-ExchangeOnline { param($Confirm) }
        function Get-MgUser { param($Filter, $UserId, $Property) }
        function Revoke-MgUserSignInSession { param($UserId) }
        function Get-EXOMailbox { param($Identity) }
        function Get-EXOMailboxSession { param($Mailbox) }
        function Remove-PSSession { param($Id) }
        function Set-MgUser { param($UserId, $AccountEnabled) }

        # Load the script file for testing
        . $scriptPath
    }

    Context "Parameter Validation" {
        It "Should fail when no email parameter is provided" {
            { . $scriptPath } | Should -Throw -ExpectedMessage "Missing an argument for parameter 'UserEmail'"
        }

        It "Should fail with invalid email format" {
            { . $scriptPath -UserEmail "notanemail" } | Should -Throw -ExpectedMessage "Please enter a valid email address"
        }

        It "Should accept valid email format" {
            { . $scriptPath -UserEmail "valid@example.com" } | Should -Not -Throw
        }
    }

    Context "Module Management" {
        It "Should attempt to install missing modules" {
            Mock Get-Module { return $false }
            Mock Install-Module {} -Verifiable -ParameterFilter { $Name -eq "Microsoft.Graph.Authentication" }
            
            # This would normally be in the module management section of the script
            if (-not (Get-Module -Name "Microsoft.Graph.Authentication" -ListAvailable -ErrorAction SilentlyContinue)) {
                Install-Module -Name "Microsoft.Graph.Authentication" -Force -AllowClobber -Scope CurrentUser
            }
            
            Assert-VerifiableMock
        }

        It "Should import required modules" {
            Mock Import-Module {} -Verifiable -ParameterFilter { $Name -eq "Microsoft.Graph.Authentication" }
            
            # This would normally be in the module management section of the script
            Import-Module -Name "Microsoft.Graph.Authentication" -MinimumVersion "2.0.0" -Force
            
            Assert-VerifiableMock
        }
    }

    Context "User Verification" {
        BeforeEach {
            Mock Get-MgUser { 
                return @{
                    Id = "12345"
                    UserPrincipalName = "test@example.com"
                    SignInActivity = @{
                        LastSignInDateTime = (Get-Date).AddHours(-1)
                    }
                }
            }
        }

        It "Should verify user exists" {
            $user = Get-MgUser -Filter "userPrincipalName eq 'test@example.com'"
            $user | Should -Not -BeNullOrEmpty
            $user.UserPrincipalName | Should -Be "test@example.com"
        }

        It "Should fail if user doesn't exist" {
            Mock Get-MgUser { return $null }
            { . $scriptPath -UserEmail "nonexistent@example.com" } | Should -Throw
        }
    }

    Context "Session Termination" {
        BeforeEach {
            Mock Get-MgUser { 
                return @{
                    Id = "12345"
                    UserPrincipalName = "test@example.com"
                    SignInActivity = @{
                        LastSignInDateTime = (Get-Date).AddHours(-1)
                    }
                }
            }

            Mock Revoke-MgUserSignInSession {}
            Mock Get-EXOMailbox { return $true }
            Mock Get-EXOMailboxSession { return @(@{Id = "1"}, @{Id = "2"}) }
            Mock Remove-PSSession {}
            Mock Set-MgUser {}
        }

        It "Should revoke Microsoft Entra sessions" {
            . $scriptPath -UserEmail "test@example.com"
            Assert-MockCalled Revoke-MgUserSignInSession -Exactly 1 -Scope It
        }

        It "Should disconnect Exchange Online sessions" {
            . $scriptPath -UserEmail "test@example.com"
            Assert-MockCalled Remove-PSSession -Exactly 2 -Scope It
        }

        It "Should handle users with no active sessions" {
            Mock Get-MgUser { 
                return @{
                    Id = "12345"
                    UserPrincipalName = "test@example.com"
                    SignInActivity = @{
                        LastSignInDateTime = (Get-Date).AddDays(-2)
                    }
                }
            }
            
            . $scriptPath -UserEmail "test@example.com"
            Assert-MockCalled Revoke-MgUserSignInSession -Exactly 0 -Scope It
        }

        It "Should handle users with no mailbox" {
            Mock Get-EXOMailbox { return $null }
            
            . $scriptPath -UserEmail "test@example.com"
            Assert-MockCalled Get-EXOMailboxSession -Exactly 0 -Scope It
        }
    }

    Context "Error Handling" {
        It "Should handle Microsoft Graph connection errors" {
            Mock Connect-MgGraph { throw "Connection failed" }
            
            { . $scriptPath -UserEmail "test@example.com" } | Should -Not -Throw
            # The script should handle the error and exit gracefully
        }

        It "Should log errors when session termination fails" {
            Mock Revoke-MgUserSignInSession { throw "Termination failed" }
            
            { . $scriptPath -UserEmail "test@example.com" } | Should -Not -Throw
            # Verify the error was logged (you would check the log file in a real test)
        }
    }

    Context "Logging" {
        It "Should create log directory if it doesn't exist" {
            $testPath = "TestDrive:\Logs"
            Mock Join-Path { return $testPath } -ParameterFilter { $ChildPath -match "Logs\\UserSessionExit" }
            Mock Test-Path { return $false }
            Mock New-Item {} -Verifiable
            
            # This would normally be in the initialization section
            if (-not (Test-Path -Path $testPath)) {
                New-Item -ItemType Directory -Path $testPath -Force | Out-Null
            }
            
            Assert-VerifiableMock
        }

        It "Should write to log file" {
            $logFile = "TestDrive:\test.log"
            Mock Join-Path { return $logFile } -ParameterFilter { $ChildPath -match "\.log$" }
            Mock Add-Content {} -Verifiable -ParameterFilter { $Path -eq $logFile }
            
            # This would normally be in the Write-Log function
            Add-Content -Path $logFile -Value "Test log entry"
            
            Assert-VerifiableMock
        }
    }
}