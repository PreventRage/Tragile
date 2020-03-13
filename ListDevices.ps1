using module .\Utilities.psm1
using module .\SetupApi.psm1

<#
.SYNOPSIS
Lists devices attached to your system. Notices ghost devices. Removes them.

.DESCRIPTION
This script will remove ghost devices from your system. These are devices that registered but not
actually plugged in or present. They're usually invisible in Device Manager but show up (in faded
colors) when you select "Show hidden devices" from the View menu. They seem to be left behind if
you plug a device into a different USB port, for example.
This script has NO WARRANTY OF ANY KIND. Please use cautiously as removing devices is a destructive
process without an undo. Presume I'm an idiot and that it'll do someone awful.

.PARAMETER OnlyGhosts
By default this command lists all devices. If you set -OnlyGhosts it'll shorten the list.

.PARAMETER RemoveGhosts
Actually remove ghost devices.

.PARAMETER KeepName 
An optional array of names for us to keep (even if ghost).

.PARAMETER KeepClass 
An optional array of classes for us to keep (even if ghost).

.NOTES
There are no notes.
#>

Param(
  [switch]$OnlyGhosts,
  [switch]$RemoveGhosts,
  $KeepClass,
  $KeepName
)


Utilities\Print -SetColor Green

if ($OnlyGhosts) {
    Utilities\Print "List only ghosts." -Space 1
} else {
    Utilities\Print "List all devices." -Space 1
}

if ($KeepClass -or $KeepName) {
    Utilities\Print "Keep devices where "
    if ($KeepClass) {
        Utilities\Print "class matches $KeepClass"
    }
    if ($KeepName) {
        if ($KeepClass) {
            Utilities\Print " or "
        }
        Utilities\Print "name matches $KeepName"
    }
    Utilities\Print "." -Space 1
}

Utilities\Print -ResetColor

if ($RemoveGhosts) {
    Utilities\Print "Remove all " -Color Red
    if ($KeepClass -or $KeepName) {
        Utilities\Print "other " -Color Red
    }
    Utilities\Print "ghosts." -Color Red -Space 1
}

Utilities\Print -FinishLine

$FriendlyClassNames = @{
    AudioEndpoint = "Audio inputs and ouputs"
    Biometric = "Biometric devices"
    Bluetooth = "Bluetooth"
    Computer = "Computer"
    DiskDrive = "Disk drives"
    Display = "Display adapters"
    CDROM = "DVD/CD-ROM drives"
    Firmware = "Firmware"
    HIDClass = "Human Interface Devices"
    HDC = "IDE ATA/ATAPI controllers"
    Image = "Imaging Devices"
    Keyboard = "Keyboards"
    Mouse = "Mice and other pointing devices"
    Monitor = "Monitors"
    Net = "Network adapters"
    Ports = "Ports (COM & LPT)"
    PrintQueue = "Print queues"
    Printer = "Printers"
    Processor = "Processors"
    "Razer Device" = "Razer Device"
    SecurityDevices = "Security Devices"
    SmartCardFilter = "Smart card filters"
    SmartCardReader = "Smart card readers"
    SoftwareComponent = "Software components"
    SoftwareDevice = "Software devices"
    Media = "Sound, video and game controllers"
    SCSIAdapter = "Storage controllers"
    VolumeSnapshot = "Storage volume shadow copies"
    Volume = "Storage volumes"
    System = "System devices"
    USB = "Universal Serial Bus controllers"
}

Write-Host "Loading Devices ...";

[System.Collections.ArrayList]$collectDevices = @();

$deviceClass = [Guid]::Empty; # We want all devices.
$deviceInfoSet = [SetupApi]::SetupDiGetClassDevs([ref]$deviceClass, [IntPtr]::Zero, [IntPtr]::Zero, [ControlFlags]::DIGCF_ALLCLASSES);
    # This is actually a handle. HDEVINFO in Win32 speak
$deviceInfo = new-object SP_DEVINFO_DATA
$deviceInfo.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($deviceInfo)
    # We fill $deviceInfo with each device in a loop

 function GetDeviceProperty {
    Param(
        [Parameter(Mandatory=$true)]
        [PropertyId]$id,

        [Parameter(Mandatory=$true)]
        [Microsoft.Win32.RegistryValueKind]$kind
    )
    $type = 0;
    $cb = 0;
    $success = [SetupApi]::SetupDiGetDeviceRegistryProperty($deviceInfoSet, [ref]$deviceInfo, $id, [ref]$type, $null,   0,   [ref]$cb);
    if ($success) {
        throw "get property with no buffer (to get the cb) should not succeed";
    }
    $buffer = New-Object byte[] $cb;
    $cbWritten = 0;
    $success = [SetupApi]::SetupDiGetDeviceRegistryProperty($deviceInfoSet, [ref]$deviceInfo, $id, [ref]$type, $buffer, $cb, [ref]$cbWritten);
    if ($cbWritten -ne $cb) {
        throw "cb changes from one call to the next";
    }
    if ($success) {
        switch ($kind) {
            ([Microsoft.Win32.RegistryValueKind]::String) {
                $value = [System.Text.Encoding]::Unicode.GetString($buffer);
                # The string is likely invalid in that it includes its null terminator and possibly more characters beyond that.
                $i = $value.IndexOf(0);
                if ($i -ge 0) {
                    $value = $value.Remove($i);
                }
                return $value;
            }
            ([Microsoft.Win32.RegistryValueKind]::DWord) {
                $value = [System.BitConverter]::ToUInt32($buffer, 0);
                return $value;
            }
            ([Microsoft.Win32.RegistryValueKind]::MultiString) {
                $value = [System.Text.Encoding]::Unicode.GetString($buffer);
                $value = $value.split(0);
                for ($i = $value.length - 1; $i -ge 0; $i--) {
                    if ($value[$i] -ne "") {
                        return ,$value[0..$i]; # the , makes sure an array of 1 stays an array
                    }
                }
                return ,@(); # returning empty arrays from a powershell function is tricky
            }
        }
    }
}

for (
    $iDevice = 0;
    $result = [SetupApi]::SetupDiEnumDeviceInfo($deviceInfoSet, $iDevice, [ref]$deviceInfo);
    $iDevice++
) {
    $device = @{}

    $device.Class_Raw = $cr = GetDeviceProperty `
        -id ([PropertyId]::SPDRP_CLASS) `
        -kind ([Microsoft.Win32.RegistryValueKind]::String)
    if ($device.Class_Raw -eq $null) {
        # I ran into such a device. One. It seems really weird. I wonder if it's some all-null
        # sentinal or something. Anyway, it seems safest to ignore it. It doesn't show up in
        # device manager, in any event.
        continue;
    }
    $device.Class = if ($fc = $FriendlyClassNames[$cr]) {$fc} else {$cr}

    $device.FriendlyName = $fn = GetDeviceProperty `
        -id ([PropertyId]::SPDRP_FRIENDLYNAME) `
        -kind ([Microsoft.Win32.RegistryValueKind]::String)

    $device.DeviceDescription = $dd = GetDeviceProperty `
        -id ([PropertyId]::SPDRP_DEVICEDESC) `
        -kind ([Microsoft.Win32.RegistryValueKind]::String)

    $device.Name = if ($fn) {$fn} else {$dd}
    
    $device.HardwareIDs = $hids = GetDeviceProperty `
        -id ([PropertyId]::SPDRP_HARDWAREID) `
        -kind ([Microsoft.Win32.RegistryValueKind]::MultiString)
    $device.HardwareID = if ($hids) {$hids[0]} else {$null}

    $device.Location = GetDeviceProperty `
        -id ([PropertyId]::SPDRP_LOCATION_INFORMATION) `
        -kind ([Microsoft.Win32.RegistryValueKind]::String)

    # $device.Address = GetDeviceProperty `
    #     -id ([PropertyId]::SPDRP_ADDRESS) `
    #     -kind ([Microsoft.Win32.RegistryValueKind]::DWord)

    # $device.Manufacturer = GetDeviceProperty `
    #     -id ([PropertyId]::SPDRP_MFG) `
    #     -kind ([Microsoft.Win32.RegistryValueKind]::String)

    $device.InstallState = [Nullable[InstallState]](GetDeviceProperty `
        -id ([PropertyId]::SPDRP_INSTALL_STATE) `
        -kind ([Microsoft.Win32.RegistryValueKind]::DWord))

    $device.IsGhost = ($device.InstallState -eq $null)
    
    $device.Remove = $device.IsGhost

    if ($device.Remove) {
        foreach ($kc in $KeepClass) {
            if ($device.Class_Raw -like $kc) {
                $device.Kept = "Kept because Class_Raw matches $kc"
                $device.Remove = $false
                break
            }

            if ($device.Class -like $kc) {
                $device.Kept = "Kept because Class matches $kc"
                $device.Remove = $false
                break
            }
        }
    }

    if ($device.Remove) {
        foreach ($kn in $KeepName) {
            if ($device.FriendlyName -like $kn) {
                $device.Kept = "Kept because FriendlyName matches $kn"
                $device.Remove = $false
                break
            }
            if ($device.DeviceDescription -like $kn) {
                $device.Kept = "Kept because DeviceDescription matches $kn"
                $device.Remove = $false
                break
            }
        }
    }

    # if $Remove is set, actually remove the device
    if ($device.Remove -and $RemoveGhosts) {
        if([SetupApi]::SetupDiRemoveDevice($deviceInfoSet, [ref]$deviceInfo)){
            $device.Result = "Removed"
        } else {
            $device.Result = "FailedToRemove"
        }
    }

    $collectDevices.Add([PSCustomObject]$device) | Out-Null; # suppress the returned new count of the ArrayList
}

$destroyed = [SetupApi]::SetupDiDestroyDeviceInfoList($deviceInfoSet)
if (-not $destroyed) {
    throw "Something went wrong destroying our deviceInfoSet"
}

$listAll = ($collectDevices | Sort-Object -Property Class, Name, HardwareID);
$listGhosts = $listAll | Where-Object {$_.IsGhost};
$listRemoved = $listAll | Where-Object {$_.Result -eq "Removed"};

function PrintDevice {
    Param(
        $device
    );

    if ($device.Class) {
        Utilities\Print $device.Class -Color Cyan -Space 1
    }
    if ($device.Name) {
        Utilities\Print $device.Name -Color Green -AtMost 80 -Space 1
    }

    if ($device.IsGhost) {
        Utilities\Print "Ghost" -Color Magenta -Space 1
    }

    if ($device.Remove) {
        Utilities\Print "Remove" -Color Red -Space 1
    }

    if ($device.Result) {
        Utilities\Print $device.Result -Color Yellow -Space 1
    }

}

function PrintList {
    Param(
        $list
    );

    foreach ($device in $list) {
        PrintDevice $device
        Utilities\Print -FinishLine
    }
}

PrintList $(if ($OnlyGhosts) {$listGhosts} else {$listAll})

Write-Host "Total=$($listAll.count) Ghosts=$($listGhosts.count) Removed=$($listRemoved.count)"
