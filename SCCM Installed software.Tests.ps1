﻿#Requires -Modules Pester
#Requires -Version 5.1

BeforeAll {
    $testImportFile = @{
        MailTo = 'bob@contoso.com'
        AD     = @{
            IncludeServers = $true
            OU             = @('OU=EU,DC=contoso,DC=net')
        }
    }

    $testADComputers = @(
        [PSCustomObject]@{
            Name    = 'PC1'
            Enabled = $true
        }
        [PSCustomObject]@{
            Name    = 'PC2'
            Enabled = $true
        }
    )

    $testInstalledSoftware = @(
        [PSCustomObject]@{
            ComputerName   = 'PC1'
            ProductName    = 'Office'
            ProductVersion = 1
        }
        [PSCustomObject]@{
            ComputerName   = 'PC1'
            ProductName    = 'McAffee'
            ProductVersion = 2
        }
        [PSCustomObject]@{
            ComputerName   = 'PC2'
            ProductName    = 'Office'
            ProductVersion = 1
        }
        [PSCustomObject]@{
            ComputerName   = 'PC2'
            ProductName    = 'McAffee'
            ProductVersion = 2
        }
    )

    $SCCMPrimaryDeviceUsersHC = @(
        [PSCustomObject]@{
            ComputerName   = 'PC1'
            SamAccountName = 'Bob'
            DisplayName    = 'Bob Lee swagger'
        }
        [PSCustomObject]@{
            ComputerName   = 'PC1'
            SamAccountName = 'Mike'
            DisplayName    = 'Mike and the mechanics'
        }
        [PSCustomObject]@{
            ComputerName   = 'PC2'
            SamAccountName = 'Jake'
            DisplayName    = 'Jake Sully'
        }
    )

    $testOutParams = @{
        FilePath = (New-Item 'TestDrive:/Test.json' -ItemType File).FullName
        Encoding = 'utf8'
    }

    $testScript = $PSCommandPath.Replace('.Tests.ps1', '.ps1')

    $testParams = @{
        ScriptName  = 'Test (Brecht)'
        ImportFile  = $testOutParams.FilePath
        ScriptAdmin = 'admin@contoso.com'
        LogFolder   = 'TestDrive:/log'
    }

    $MailAdminParams = {
        ($To -eq $testParams.ScriptAdmin) -and ($Priority -eq 'High') -and
        ($Subject -eq 'FAILURE')
    }

    Mock Get-ADComputerHC
    Mock Get-SCCMHardwareHC
    Mock Get-SCCMPrimaryDeviceUsersHC
    Mock Get-SCCMandDNSdetailsHC
    Mock Send-MailHC
    Mock Write-EventLog
}

Describe 'Prerequisites' {
    Context 'ImportFile' {
        It 'file not found' {
            $testNewParams = $testParams.Clone()
            $testNewParams.ImportFile = 'NotExisting.txt'

            .$testScript @testNewParams

            Should -Invoke Send-MailHC -Exactly 1 -ParameterFilter {
                (&$MailAdminParams) -and ($Message -like "*Cannot find path*")
            }
        }
        It 'MailTo not found' {
            $testNewImportFile = Copy-ObjectHC $testImportFile
            $testNewImportFile.MailTo = @()

            $testNewImportFile | ConvertTo-Json | Out-File @testOutParams

            .$testScript @testParams

            Should -Invoke Send-MailHC -Exactly 1 -ParameterFilter {
                (&$MailAdminParams) -and ($Message -like "*'MailTo' not found*")
            }
        }
        It 'AD.OU not found' {
            $testNewImportFile = Copy-ObjectHC $testImportFile
            $testNewImportFile.AD.OU = @()

            $testNewImportFile | ConvertTo-Json | Out-File @testOutParams

            .$testScript @testParams

            Should -Invoke Send-MailHC -Exactly 1 -ParameterFilter {
                (&$MailAdminParams) -and ($Message -like "*'AD.OU' not found*")
            }
        }
        It 'AD.IncludeServers not a boolean' {
            $testNewImportFile = Copy-ObjectHC $testImportFile
            $testNewImportFile.AD.IncludeServers = $null

            $testNewImportFile | ConvertTo-Json | Out-File @testOutParams

            .$testScript @testParams

            Should -Invoke Send-MailHC -Exactly 1 -ParameterFilter {
                (&$MailAdminParams) -and ($Message -like "*'AD.IncludeServers' is not a boolean value*")
            }
        }
    }
    Context 'LogFolder' {
        It 'folder not found' {
            $testImportFile | ConvertTo-Json | Out-File @testOutParams

            $testNewParams = $testParams.Clone()
            $testNewParams.LogFolder = 'x:\NonExisting'

            .$testScript @testNewParams

            Should -Invoke Send-MailHC -Exactly 1 -ParameterFilter {
                (&$MailAdminParams) -and ($Message -like "*Failed creating the log folder 'x:\NonExisting'*")
            }
        }
    }
}
Describe 'export Excel files' {
    BeforeAll {
        $testImportFile | ConvertTo-Json | Out-File @testOutParams
    }
    BeforeEach {
        Remove-Item "$($testParams.LogFolder)\*" -Recurse -Force -EA Ignore
    }
    It 'one file for each computer with its software in the machines folder' {
        Mock Get-ADComputerHC {
            $testADComputers
        }
        Mock Get-SCCMInstalledSoftwareHC {
            $testInstalledSoftware
        }

        .$testScript @testParams

        $testMachines = @($testInstalledSoftware.ComputerName |
            Sort-Object -Unique).Count

        $testMachines | Should -Not -BeExactly 0

        Get-ChildItem $testParams.LogFolder -Recurse -Directory |
        Where-Object { $_.Name -like '*Machines' } | Get-ChildItem -File |
        Where-Object {
            $testInstalledSoftware.ComputerName -contains $_.BaseName
        } |
        Should -HaveCount $testMachines
    }
    It 'one overview file for all SCCM software installed' {
        Mock Get-ADComputerHC {
            $testADComputers
        }
        Mock Get-SCCMInstalledSoftwareHC {
            $testInstalledSoftware
        }

        .$testScript @testParams

        @($testInstalledSoftware.ProductName).Count | Should -Not -BeExactly 0

        Get-ChildItem $testParams.LogFolder -Recurse |
        Where-Object { $_.Name -like "*SCCM installed software.xlsx" } | Should -HaveCount 1
    }
    It 'one file for all AD computers' {
        Mock Get-ADComputerHC {
            $testADComputers
        }
        Mock Get-SCCMInstalledSoftwareHC {
            $testInstalledSoftware
        }

        .$testScript @testParams

        @($testInstalledSoftware.ProductName).Count | Should -Not -BeExactly 0

        Get-ChildItem $testParams.LogFolder -Recurse |
        Where-Object { $_.Name -like "*SCCM AD computers overview.xlsx" } | Should -HaveCount 1
    }
}
Describe 'send mail' {
    BeforeAll {
        $testImportFile | ConvertTo-Json | Out-File @testOutParams
    }
    BeforeEach {
        Remove-Item "$($testParams.LogFolder)\*" -Recurse -Force -EA Ignore
    }
    It "with the 'AD Computers' and 'All installed software' in attachment" {
        Mock Get-ADComputerHC {
            $testADComputers
        }
        Mock Get-SCCMInstalledSoftwareHC {
            $testInstalledSoftware
        }

        Mock Get-SCCMPrimaryDeviceUsersHC {
            $SCCMPrimaryDeviceUsersHC
        }

        .$testScript @testParams

        @($testInstalledSoftware.ProductName).Count | Should -Not -BeExactly 0

        Should -Invoke Send-MailHC -Times 1 -Exactly -ParameterFilter {
            (@($Attachments).Count -eq 2)
        }
    }
}
