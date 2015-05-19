[CmdletBinding()]
param()

if (!$PSScriptRoot) # $PSScriptRoot is not defined in 2.0
{
    $PSScriptRoot = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
}

$ErrorActionPreference = 'stop'
Set-StrictMode -Version latest

$RepoRoot = (Resolve-Path $PSScriptRoot\..\..).Path

$ModuleName = 'MSFT_xVMHyperV'
Import-Module (Join-Path $RepoRoot "DSCResources\$ModuleName\$ModuleName.psm1") -Force;

Describe 'xVMHyper-V' {
    InModuleScope $ModuleName {
        $stubVMDisk = New-Item -Path 'TestDrive:\TestVM.vhdx' -ItemType File;
        $StubVMConfig = New-Item -Path 'TestDrive:\TestVM.xml' -ItemType File;
        $stubVM = @{
            HardDrives = @(
                @{ Path = $stubVMDisk.FullName; }
            );
            State = 'Running';
            Path = $StubVMConfig.FullPath;
            Generation = 2;
            MemoryStartup = 512MB;
            MinimumMemory = 128MB;
            MaximumMemory = 4096MB;
            ProcessorCount = 1;
            ID = [System.Guid]::NewGuid().ToString();
            #Status = 'Running';
            CPUUsage = 10;
            MemoryAssigned = 512MB;
            Uptime = New-TimeSpan -Hours 12;
            CreationTime = (Get-Date).AddHours(-12);
            DynamicMemoryEnabled = $true;
            NetworkAdapters  = @(
                @{ SwitchName = 'TestSwitch'; MacAddress = 'AA-BB-CC-DD-EE-FF'; IpAddresses = @('192.168.0.1','10.0.0.1'); };
            );
            Notes = '';
        }

        Mock -CommandName Get-VM -ParameterFilter { $Name -eq 'RunningVM' } -MockWith { $runningVM = $stubVM.Clone(); $runningVM['State'] = 'Running'; return [PSCustomObject] $runningVM; }
        Mock -CommandName Get-VM -ParameterFilter { $Name -eq 'StoppedVM' } -MockWith { $stoppedVM = $stubVM.Clone(); $stoppedVM['State'] = 'Off'; return [PSCustomObject] $stoppedVM; }
        Mock -CommandName Get-VM -ParameterFilter { $Name -eq 'PausedVM' } -MockWith { $pausedVM = $stubVM.Clone(); $pausedVM['State'] = 'Paused'; return [PSCustomObject] $pausedVM; }
        Mock -CommandName Get-VM -ParameterFilter { $Name -eq 'NonexistentVM' } -MockWith { Write-Error 'VM not found'; }
        Mock -CommandName Get-VM -ParameterFilter { $Name -eq 'DuplicateVM' } -MockWith { return @([PSCustomObject] $stubVM, [PSCustomObject] $stubVM); }
        Mock -CommandName Get-Module -ParameterFilter { ($Name -eq 'Hyper-V') -and ($ListAvailable -eq $true) } -MockWith { return $true; }
        
        Context 'Validates Get-TargetResource Method' {

            It 'Returns a hashtable' {
                $targetResource = Get-TargetResource -Name 'RunningVM' -VhdPath $stubVMDisk.FullName;
                $targetResource -is [System.Collections.Hashtable] | Should Be $true;
            }
            It 'Throws when multiple VMs are present' {
                { Get-TargetResource -Name 'DuplicateVM' -VhdPath $stubVMDisk.FullName } | Should Throw;
            }
        } #end context Validates Get-TargetResource Method

        Context 'Validates Test-TargetResource Method' {
            $testParams = @{
                VhdPath = $stubVMDisk.FullName;
                Generation = 'Vhdx';
            }

            It 'Returns a boolean' {
                $targetResource =  Test-TargetResource -Name 'RunningVM' @testParams;
                $targetResource -is [System.Boolean] | Should Be $true;
            }

            It 'Returns $true when VM is present and "Ensure" = "Present"' {
                Test-TargetResource -Name 'RunningVM' @testParams | Should Be $true;
            }

            It 'Returns $false when VM is not present and "Ensure" = "Present"' {
                Test-TargetResource -Name 'NonexistentVM' @testParams | Should Be $false;
            }
            
            It 'Returns $true when VM is not present and "Ensure" = "Absent"' {
                Test-TargetResource -Name 'NonexistentVM' -Ensure Absent @testParams | Should Be $true;
            }

            It 'Returns $false when VM is present and "Ensure" = "Absent"' {
                Test-TargetResource -Name 'RunningVM' -Ensure Absent @testParams | Should Be $false;
            }

            It 'Returns $true when VM is in the "Running" state and no state is explicitly specified' {
                Test-TargetResource -Name 'RunningVM' @testParams | Should Be $true;
            }

            It 'Returns $true when VM is in the "Stopped" state and no state is explicitly specified' {
                Test-TargetResource -Name 'StoppedVM' @testParams | Should Be $true;
            }

            It 'Returns $true when VM is in the "Paused" state and no state is explicitly specified' {
                Test-TargetResource -Name 'PausedVM' @testParams | Should Be $true;
            }

            It 'Returns $true when VM is in the "Running" state and requested "State" = "Running"' {
                Test-TargetResource -Name 'RunningVM' @testParams | Should Be $true;
            }

            It 'Returns $true when VM is in the "Off" state and requested "State" = "Off"' {
                Test-TargetResource -Name 'StoppedVM' -State Off @testParams | Should Be $true;
            }

            It 'Returns $true when VM is in the "Paused" state and requested "State" = Paused"' {
                Test-TargetResource -Name 'PausedVM' -State Paused @testParams | Should Be $true;
            }

            It 'Returns $false when VM is in the "Running" state and requested "State" = "Off"' {
                Test-TargetResource -Name 'RunningVM' -State Off @testParams | Should Be $false;
            }

            It 'Returns $false when VM is in the "Off" state and requested "State" = "Runnning"' {
                Test-TargetResource -Name 'StoppedVM' -State Running @testParams | Should Be $false;
            }

            It 'Throws when Hyper-V Tools are not installed' {
                Mock -CommandName Get-Module -ParameterFilter { ($Name -eq 'Hyper-V') -and ($ListAvailable -eq $true) } -MockWith { }
                { Test-TargetResource -Name 'RunningVM' @testParams } | Should Throw;
            }
        } #end context Validates Test-TargetResource Method
        
        Context 'Validates Set-TargetResource Method' {
            $testParams = @{
                VhdPath = $stubVMDisk.FullName;
                Generation = 'Vhdx';
            }

            Mock -CommandName Get-VM -ParameterFilter { $Name -eq 'NewVM' } -MockWith { }
            Mock -CommandName New-VM -MockWith { $newVM = $stubVM.Clone(); $newVM['State'] = 'Off'; return $newVM; }
            Mock -CommandName Set-VM -MockWith { return $true; }
            Mock -CommandName Stop-VM -MockWith { return $true; } # requires output to be piped to Remove-VM
            Mock -CommandName Remove-VM -MockWith { return $true; }
            Mock -CommandName Set-VMNetworkAdapter -MockWith { return $true; }
            Mock -CommandName Get-VMNetworkAdapter -MockWith { return $stubVM.NetworkAdapters.IpAddresses; }
            Mock -CommandName Set-VMState -MockWith { return $true; }

            It 'Removes an existing VM when "Ensure" = "Absent"' {
                Set-TargetResource -Name 'RunningVM' -Ensure Absent @testParams;
                Assert-MockCalled -CommandName Remove-VM -Scope It;
            }

            It 'Creates and does not start a VM that does not exist when "Ensure" = "Present"' {
                Set-TargetResource -Name 'NewVM' @testParams;
                Assert-MockCalled -CommandName New-VM -Exactly -Times 1 -Scope It;
                Assert-MockCalled -CommandName Set-VM -Exactly -Times 1 -Scope It;
                Assert-MockCalled -CommandName Set-VMState -Exactly -Times 0 -Scope It;
            }

            It 'Creates and starts a VM that does not exist when "Ensure" = "Present" and "State" = "Running"' {
                #Mock -CommandName Change-VMProperty -MockWith { }
                Set-TargetResource -Name 'NewVM' -State Running @testParams;
                Assert-MockCalled -CommandName New-VM -Exactly -Times 1 -Scope It;
                Assert-MockCalled -CommandName Set-VM -Exactly -Times 1 -Scope It;
                Assert-MockCalled -CommandName Set-VMState -Exactly -Times 1 -Scope It;
            }

            It 'Does not change VM state when VM "State" = "Running" and requested "State" = "Running"' {
                Set-TargetResource -Name 'RunningVM' -State Running @testParams;
                 Assert-MockCalled -CommandName Set-VMState -Exactly -Times 0 -Scope It;
            }

            It 'Does not change VM state when VM "State" = "Off" and requested "State" = "Off"' {
                Set-TargetResource -Name 'StoppedVM' -State Off @testParams;
                 Assert-MockCalled -CommandName Set-VMState -Exactly -Times 0 -Scope It;
            }

            It 'Changes VM state when existing VM "State" = "Off" and requested "State" = "Running"' {
                 Set-TargetResource -Name 'StoppedVM' -State Running @testParams;
                 Assert-MockCalled -CommandName Set-VMState -Exactly -Times 1 -Scope It;
            }

            It 'Changes VM state when existing VM "State" = "Running" and requested "State" = "Off"' {
                 Set-TargetResource -Name 'RunningVM' -State Off @testParams;
                 Assert-MockCalled -CommandName Set-VMState -Exactly -Times 1 -Scope It;
            }

            It 'Throws when Hyper-V Tools are not installed' {
                Mock -CommandName Get-Module -ParameterFilter { ($Name -eq 'Hyper-V') -and ($ListAvailable -eq $true) } -MockWith { }
                { Set-TargetResource -Name 'RunningVM' @testParams } | Should Throw;
            }
        } #end context Validates Set-TargetResource Method
    } #end inmodulescope
} #end describe xVMHyper-V
