<#
.SYNOPSIS
    Installs Windows PE to the GRUB multiboot media drive.
.DESCRIPTION
    This command copyes and prepares Windows PE from the Windows ADK to the GRUB multiboot media drive.
.EXAMPLE
    PS C:\> .\Install-WindowsPE.ps1 -OutputDirectory D:\
    Installs Windows PE to the "D:\" drive.
.EXAMPLE
    PS C:\> .\Install-WindowsPE.ps1 -OutputDirectory WinPE -Architectures amd64
    Installs Windows PE for the amd64 processor achitecture only to the "WinPE" directory.
    After that you can copy files from this directory to the GRUB multiboot media drive manually.
.LINK
    https://github.com/rikdev/grub-multiboot
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$OutputDirectory,
    [string[]]$Architectures = @('amd64', 'x86')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


class BCDEditor {
    BCDEditor([string]$BCDPath) {
        $this.BCDStore = (
            Invoke-CimMethod -Namespace Root\WMI -ClassName BCDStore -MethodName 'OpenStore' -Arguments @{
                File = $BCDPath
            }).Store
    }

    [Microsoft.Management.Infrastructure.CimInstance] GetDeviceOptions() {
        return (Invoke-CimMethod -InputObject $this.BCDStore -MethodName 'EnumerateObjects' -Arguments @{
                Type = 0x30000000
            }).Objects[0]
    }

    [Microsoft.Management.Infrastructure.CimInstance] GetWindowsBootManager() {
        return (Invoke-CimMethod -InputObject $this.BCDStore -MethodName 'EnumerateObjects' -Arguments @{
                Type = 0x10100002
            }).Objects[0]
    }

    [Microsoft.Management.Infrastructure.CimInstance] CreateItem(
        [uint32]$BCDType, [uint32]$BCDOrderElementType, [string]$Description) {
        $BaseItem = $this.GetBaseItem($BCDType)

        $NewItem = (Invoke-CimMethod -InputObject $this.BCDStore -MethodName 'CreateObject' -Arguments @{
                Id   = "{$(New-Guid)}"
                Type = $BCDType
            }).Object

        $null = Invoke-CimMethod -InputObject $NewItem -MethodName 'SetObjectListElement' -Arguments @{
                Type = 0x14000006 # Inherit
                Ids  = @($BaseItem.Id)
            }

        $null = Invoke-CimMethod -InputObject $NewItem -MethodName 'SetStringElement' -Arguments @{
                Type   = 0x12000004 # Description
                String = $Description
            }

        $this.AddItemToBootManager($NewItem, $BCDOrderElementType)

        return $NewItem
    }

    [Microsoft.Management.Infrastructure.CimInstance] hidden GetBaseItem([uint32]$BCDType) {
        $Items = (Invoke-CimMethod -InputObject $this.BCDStore -MethodName 'EnumerateObjects' -Arguments @{
                Type = $BCDType
            }).Objects

        foreach ($Item in $Items) {
            $InheritIds = (Invoke-CimMethod -InputObject $Item -MethodName 'GetElement' -Arguments @{
                    Type = 0x14000006 # Inherit
                }).Element.Ids

            foreach ($InheritId in $InheritIds) {
                $InheritObject = (
                    Invoke-CimMethod -InputObject $this.BCDStore -MethodName 'OpenObject' -Arguments @{
                        Id = $InheritId
                    }).Object
                
                if ($InheritObject.Type -ne $BCDType) {
                    return $Item
                }
            }
        }

        return $null
    }

    hidden AddItemToBootManager(
        [Microsoft.Management.Infrastructure.CimInstance]$BCDItem, [uint32]$BCDOrderElementType) {
        $WindowsBootManager = $this.GetWindowsBootManager()

        $ItemsOrder = (Invoke-CimMethod -InputObject $WindowsBootManager -MethodName 'GetElement' -Arguments @{
                Type = $BCDOrderElementType
            }).Element.Ids
        $ItemsOrder += @($BCDItem.Id)

        $null = Invoke-CimMethod -InputObject $WindowsBootManager -MethodName 'SetObjectListElement' -Arguments @{
                Type = $BCDOrderElementType
                Ids  = $ItemsOrder
            }
    }

    [ValidateNotNull()] hidden $BCDStore
}

function Get-WindowsKitsPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$KitsRegName
    )

    $KitsPath = Get-ItemProperty `
        -ErrorAction SilentlyContinue `
        -Path 'HKLM:\Software\Wow6432Node\Microsoft\Windows Kits\Installed Roots' `
        -Name $KitsRegName

    if ($null -eq $KitsPath) {
        $KitsPath = Get-ItemProperty `
            -ErrorAction SilentlyContinue `
            -Path 'HKLM:\Software\Microsoft\Windows Kits\Installed Roots' `
            -Name $KitsRegName
    }

    return $KitsPath.$KitsRegName
}

function Install-File {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$DestinationDirectory,
        [string]$DestinationName
    )

    $null = New-Item -ErrorAction SilentlyContinue -ItemType 'directory' -Path $DestinationDirectory
    Copy-Item -Path $Path -Destination "$DestinationDirectory\$DestinationName"
}

function Initialize-BCD {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $BCDEditor = [BCDEditor]::new($Path)

    # Device options

    $DeviceOptions = $BCDEditor.GetDeviceOptions()

    $null = Invoke-CimMethod -InputObject $DeviceOptions -MethodName 'SetStringElement' -Arguments @{
            Type   = 0x32000004 # RamDiskSdiPath
            String = '\boot\windows\boot\boot.sdi'
        }

    # Windows Boot Manager

    $WindowsBootManager = $BCDEditor.GetWindowsBootManager()

    $null = Invoke-CimMethod -InputObject $WindowsBootManager -MethodName 'DeleteElement' -Arguments @{
            Type = 0x25000004 # Timeout
        }

    $null = Invoke-CimMethod -InputObject $WindowsBootManager -MethodName 'SetObjectListElement' -Arguments @{
            Type = 0x24000001 # DisplayOrder
            Ids  = @('{00000000-0000-0000-0000-000000000000}')
        }

    $null = Invoke-CimMethod -InputObject $WindowsBootManager -MethodName 'SetObjectListElement' -Arguments @{
            Type = 0x24000010 # ToolsDisplayOrder
            Ids  = @('{00000000-0000-0000-0000-000000000000}')
        }

    $null = Invoke-CimMethod -InputObject $WindowsBootManager -MethodName 'SetBooleanElement' -Arguments @{
            Type    = 0x26000020 # DisplayBootMenu
            Boolean = $true
        }
}

function Install-CommonResources {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$OutputDirectory
    )

    Install-File -Path "$SourcePath\Media\bootmgr" -DestinationDirectory "$OutputDirectory\boot\windows"
    Install-File -Path "$SourcePath\Media\en-us\*" -DestinationDirectory "$OutputDirectory\boot\windows\en-us"

    Install-File `
        -Path "$SourcePath\Media\EFI\Boot\*.efi" `
        -DestinationDirectory "$OutputDirectory\boot\windows\EFI\Boot"
    Install-File `
        -Path "$SourcePath\Media\EFI\Boot\en-us\*" `
        -DestinationDirectory "$OutputDirectory\boot\windows\EFI\Boot\en-us"

    Install-File -Path "$SourcePath\Media\Boot\boot.sdi" -DestinationDirectory "$OutputDirectory\boot\windows\Boot"

    Install-File -Path "$SourcePath\Media\Boot\BCD" -DestinationDirectory "$OutputDirectory\boot"
    Initialize-BCD -Path "$OutputDirectory\boot\BCD"

    Install-File `
        -Path "$SourcePath\Media\EFI\Microsoft\Boot\BCD" `
        -DestinationDirectory "$OutputDirectory\EFI\Microsoft\Boot"
    Initialize-BCD -Path "$OutputDirectory\EFI\Microsoft\Boot\BCD"
}

function Initialize-WindowsPEImage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$ImagePath
    )

    $PackagesPath = "$SourcePath\WinPE_OCs"

    $MountPath = "$(Split-Path -Path $ImagePath)\mount"
    $null = New-Item -ErrorAction SilentlyContinue -ItemType 'directory' -Path $MountPath

    # https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-adding-powershell-support-to-windows-pe
    $null = Mount-WindowsImage -Path $MountPath -ImagePath $ImagePath -Index 1

    $PackageNames = @(
        'WinPE-WMI',
        'WinPE-NetFX',
        'WinPE-Scripting',
        'WinPE-PowerShell',
        'WinPE-StorageWMI',
        'WinPE-DismCmdlets'
    )
    foreach ($PackageName in $PackageNames) {
        $null = Add-WindowsPackage -Path $MountPath -PackagePath:"$PackagesPath\$PackageName.cab"
        $null = Add-WindowsPackage -Path $MountPath -PackagePath:"$PackagesPath\en-us\${PackageName}_en-us.cab"
    }

    $null = Dismount-WindowsImage -Path $MountPath -Save

    Remove-Item -LiteralPath $MountPath
}

function Add-BCDWindowsImage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$BCDPath,
        [Parameter(Mandatory)]
        [string]$ImagePath
    )

    $BCDEditor = [BCDEditor]::new($BCDPath)

    # Windows Boot Loader

    $WindowsBootLoader = $BCDEditor.CreateItem(0x10200003, 0x24000001, $(Split-Path -Path $ImagePath -Leaf))
    
    # Device
    # OSDevice
    $DeviceOptions = $BCDEditor.GetDeviceOptions()
    foreach ($ElementType in 0x11000001, 0x21000001) {
        $null = Invoke-CimMethod -InputObject $WindowsBootLoader -MethodName 'SetFileDeviceElement' -Arguments @{
                Type                    = $ElementType
                DeviceType              = 4
                AdditionalOptions       = $DeviceOptions.Id
                Path                    = ${ImagePath}
                ParentDeviceType        = 1
                ParentAdditionalOptions = ''
                ParentPath              = ''
            }
    }
}
function Add-BCDMemtest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$BCDPath,
        [Parameter(Mandatory)]
        [string]$MemtestPath
    )

    $BCDEditor = [BCDEditor]::new($BCDPath)

    $WindowsMemoryTester = $BCDEditor.CreateItem(0x10200005, 0x24000010, $(Split-Path -Path $MemtestPath -Leaf))
    $null = Invoke-CimMethod -InputObject $WindowsMemoryTester -MethodName 'SetStringElement' -Arguments @{
            Type   = 0x12000002 # Path
            String = $MemtestPath
        }
}

function Install-WIM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$OutputDirectory
    )

    $Architecture = $(Split-Path -Path $SourcePath -Leaf)
    $ImageName = "WinPE_$Architecture.wim"
    $ImageDirectory = '\boot\windows\sources'

    Install-File `
        -Path "$SourcePath\en-us\winpe.wim" `
        -DestinationDirectory "$OutputDirectory\$ImageDirectory" `
        -DestinationName "$ImageName"
    Initialize-WindowsPEImage -SourcePath $SourcePath "$OutputDirectory\$ImageDirectory\$ImageName"
    Add-BCDWindowsImage -BCDPath "$OutputDirectory\boot\BCD" -ImagePath "$ImageDirectory\$ImageName"
    Add-BCDWindowsImage -BCDPath "$OutputDirectory\EFI\Microsoft\Boot\BCD" -ImagePath "$ImageDirectory\$ImageName"
}

function Install-Memtest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$OutputDirectory
    )

    $Architecture = $(Split-Path -Path $SourcePath -Leaf)
    $MemtestBaseName = "memtest_$Architecture"

    $ExeMemtestName = "$MemtestBaseName.exe"
    $ExeMemtestDirectory = '\boot\windows\Boot'
    Install-File `
        -Path "$SourcePath\Media\Boot\memtest.exe" `
        -DestinationDirectory "$OutputDirectory\$ExeMemtestDirectory" `
        -DestinationName "$ExeMemtestName"
    Add-BCDMemtest -BCDPath "$OutputDirectory\boot\BCD" -MemtestPath "$ExeMemtestDirectory\$ExeMemtestName"

    $EfiMemtestName = "$MemtestBaseName.efi"
    $EfiMemtestDirectory = '\boot\windows\EFI\Microsoft\Boot'
    Install-File `
        -Path "$SourcePath\Media\EFI\Microsoft\Boot\memtest.efi" `
        -DestinationDirectory "$OutputDirectory\$EfiMemtestDirectory" `
        -DestinationName "$EfiMemtestName"
    Add-BCDMemtest `
        -BCDPath "$OutputDirectory\EFI\Microsoft\Boot\BCD" -MemtestPath "$EfiMemtestDirectory\$EfiMemtestName"
}


$KitsPath = Get-WindowsKitsPath 'KitsRoot10'
if ($null -eq $KitsPath) {
    $Message = @'
Couldn't find the Windows Kits.
1. Download the Windows ADK
   (https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install)
2. Install the "OptionId.DeplymentTools" feature:
   PS .\adksetup.exe /features OptionId.DeploymentTools
3. Download and install the WinPE add-on for the Windows ADK
   (https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install)
'@
    Write-Error $Message
    exit 1
}

[Security.Principal.WindowsPrincipal] $CurrentPrincipial = [Security.Principal.WindowsIdentity]::GetCurrent()
if (! $CurrentPrincipial.IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-Error 'This script requires Administrator rights. It need to prepare Windows PE images.'
    exit 1
}

$WindowsPEPath = "$KitsPath\Assessment and Deployment Kit\Windows Preinstallation Environment"

Write-Progress 'Installing common resources...'
Install-CommonResources -SourcePath "$WindowsPEPath\$($Architectures[0])" -OutputDirectory "$OutputDirectory"

foreach ($Architecture in $Architectures) {
    $SourcePath = "$WindowsPEPath\$Architecture"

    Write-Progress "Installing windows image for the `"$Architecture`" architecture..."
    Install-WIM -SourcePath $SourcePath -OutputDirectory $OutputDirectory

    Write-Progress "Installing memory test utility for the `"$Architecture`" architecture..."
    Install-Memtest -SourcePath $SourcePath -OutputDirectory $OutputDirectory
}

Remove-Item -Path "$OutputDirectory\boot\BCD.LOG*" -Force
Remove-Item -Path "$OutputDirectory\EFI\Microsoft\Boot\BCD.LOG*" -Force
