# GRUB multiboot

It is a simple script for the [GRUB2](https://www.gnu.org/software/grub/grub-documentation.html) that downloads images from USB flash drive. This USB flash drive allows booting multiple bootable image files without unpacking them.

## Installation

1. Create active MBR partition on the USB flash drive.
2. Format the partition located on the USB drive to FAT32:

    `# mkfs.vfat -F32 /dev/sdXN`

3. Mount the filesystem located on the USB drive:

    `# mount /dev/sdXN /mnt`

4. Create the `/boot/` directory on the mounted filesystem:

    `# mkdir /mnt/boot`

5. Install the GRUB2 on the USB flash drive:

    ```
    # grub-install --target=i386-pc --recheck --boot-directory=/mnt/boot /dev/sdX
    # grub-install --target=x86_64-efi --removable --boot-directory=/mnt/boot --efi-directory=/mnt
    ```

    Note: Most UEFIs can boots efi-files from MBR partitions.

6. Copy the `grub.cfg` file from this repository to the `/mnt/boot/grub` directory.

### Installation ISO images

In order to install [ISO images](https://en.wikipedia.org/wiki/ISO_image) just copy them to the `/boot/images` directory on the USB flash drive. You can make nested directories in the `/boot/images` directory.

### Installation Windows images

The GRUB2 can boot the Windows Boot Manager. Windows Boot Manager can boot the Windows from [WIM](https://en.wikipedia.org/wiki/Windows_Imaging_Format) or [VHD](https://en.wikipedia.org/wiki/VHD_(file_format)) images. You can find the Windows Boot Manager in the Windows installation CD or download one from the Microsoft website as part of [Windows PE](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-intro). Consider the installation and configuration the Windows Boot Manager to the USB flash drive on the example of Windows PE.

First build a Windows PE image according to this instruction "[Create bootable WinPE media](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-create-usb-bootable-drive)". After that you can just copy the Windows Boot Manager files from the Windows PE directory to the the USB flash drive:

```
C:\>mkdir <usb_drive_mount_point>\boot\windows\EFI\Boot\
C:\>copy <windows_pe_directory>\bootmgr <usb_drive_mount_point>\boot\windows\
C:\>copy <windows_pe_directory>\EFI\Boot\bootx64.efi <usb_drive_mount_point>\boot\windows\EFI\Boot\
```

Optionally you can copy language files.

Also you can copy the ramdisk file `boot.sdi` to the common directory (for example `boot/windows/Boot`) on the USB flash drive because multiple Windows images can use one shared ramdisk file:

```
C:\>mkdir <usb_drive_mount_point>\boot\windows\Boot\
C:\>copy <windows_pe_directory>\Boot\boot.sdi <usb_drive_mount_point>\boot\windows\Boot\
```

The Windows Boot Manager reads settings from BCD files that searches for by fixed paths: `/Boot/BCD` in BIOS mode and `/EFI/Microsoft/Boot/BCD` in UEFI mode. Copy these files from the Windows PE directory:

```
C:\>copy <windows_pe_directory>\Boot\BCD <usb_drive_mount_point>\boot\
C:\>mkdir <usb_drive_mount_point>\EFI\Microsoft\Boot\
C:\>copy <windows_pe_directory>\EFI\Microsoft\Boot\BCD <usb_drive_mount_point>\EFI\Microsoft\Boot\
```

Create on the USB flash drive a directory where Windows images will be stored and copy the `sources/boot.wim` image file from the Windows PE directory into it:

```
C:\>mkdir <usb_drive_mount_point>\boot\windows\sources\
C:\>copy <windows_pe_directory>\sources\boot.wim <usb_drive_mount_point>\boot\windows\sources\winpe.wim
```

---

If you copy `boot.wim` and `install.wim` images from Windows installation disk you should patch the `boot.wim` file so that the [Windows Setup](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-installation-process) program from this image can find the file `install.wim` located in the new path.

---

Finally you should edit the BCD files so that the Windows Boot Manager can find the image files:

```
C:\>bcdedit /store <usb_drive_mount_point>\boot\BCD /enum {default}

Windows Boot Loader
-------------------
identifier              {default}
device                  ramdisk=[boot]\sources\boot.wim,{7619dcc8-fafe-11d9-b411-000476eba25f}
path                    \windows\system32\boot\winload.exe
description             Windows Setup
locale                  en-US
inherit                 {bootloadersettings}
osdevice                ramdisk=[boot]\sources\boot.wim,{7619dcc8-fafe-11d9-b411-000476eba25f}
systemroot              \windows
bootmenupolicy          Standard
detecthal               Yes
winpe                   Yes
ems                     No

C:\>bcdedit /store <usb_drive_mount_point>\boot\BCD /set {default} device ramdisk=[boot]\boot\windows\sources\winpe.wim,{7619dcc8-fafe-11d9-b411-000476eba25f}
C:\>bcdedit /store <usb_drive_mount_point>\boot\BCD /set {default} osdevice ramdisk=[boot]\boot\windows\sources\winpe.wim,{7619dcc8-fafe-11d9-b411-000476eba25f}
C:\>bcdedit /store <usb_drive_mount_point>\boot\BCD /set {7619dcc8-fafe-11d9-b411-000476eba25f} ramdisksdipath \boot\windows\boot\boot.sdi
```

Similar for UEFI:

```
C:\>bcdedit /store <usb_drive_mount_point>\EFI\Microsoft\Boot\BCD /enum {default}

Windows Boot Loader
-------------------
identifier              {default}
device                  ramdisk=[boot]\sources\boot.wim,{7619dcc8-fafe-11d9-b411-000476eba25f}
path                    \windows\system32\boot\winload.efi
description             Windows Setup
locale                  en-US
inherit                 {bootloadersettings}
isolatedcontext         Yes
osdevice                ramdisk=[boot]\sources\boot.wim,{7619dcc8-fafe-11d9-b411-000476eba25f}
systemroot              \windows
bootmenupolicy          Standard
detecthal               Yes
winpe                   Yes
ems                     No

C:\>bcdedit /store <usb_drive_mount_point>\EFI\Microsoft\Boot\BCD /set {default} device ramdisk=[boot]\boot\windows\sources\winpe.wim,{7619dcc8-fafe-11d9-b411-000476eba25f}
C:\>bcdedit /store <usb_drive_mount_point>\EFI\Microsoft\Boot\BCD /set {default} osdevice ramdisk=[boot]\boot\windows\sources\winpe.wim,{7619dcc8-fafe-11d9-b411-000476eba25f}
C:\>bcdedit /store <usb_drive_mount_point>\EFI\Microsoft\Boot\BCD /set {7619dcc8-fafe-11d9-b411-000476eba25f} ramdisksdipath \boot\windows\boot\boot.sdi
```

Optionally you can show the Windows Boot Manager boot menu and rename default boot entry:

```
C:\>bcdedit /store <usb_drive_mount_point>\boot\BCD /set {bootmgr} displaybootmenu True
C:\>bcdedit /store <usb_drive_mount_point>\boot\BCD /deletevalue {bootmgr} timeout
C:\>bcdedit /store <usb_drive_mount_point>\boot\BCD /set {default} description "Windows PE"

C:\>bcdedit /store <usb_drive_mount_point>\EFI\Microsoft\Boot\BCD /set {bootmgr} displaybootmenu True
C:\>bcdedit /store <usb_drive_mount_point>\EFI\Microsoft\Boot\BCD /deletevalue {bootmgr} timeout
C:\>bcdedit /store <usb_drive_mount_point>\EFI\Microsoft\Boot\BCD /set {default} description "Windows PE"
```

Optionally you can add memory diagnostic tools from the Windows PE directory:

```
C:\>copy <windows_pe_directory>\Boot\memtest.exe <usb_drive_mount_point>\boot\windows\Boot\
C:\>mkdir <usb_drive_mount_point>\boot\windows\EFI\Microsoft\Boot\
C:\>copy <windows_pe_directory>\EFI\Microsoft\Boot\memtest.efi <usb_drive_mount_point>\boot\windows\EFI\Microsoft\Boot\

C:\>bcdedit /store <usb_drive_mount_point>\Boot\BCD /set {memdiag} path \boot\windows\Boot\memtest.exe
C:\>bcdedit /store <usb_drive_mount_point>\EFI\Microsoft\Boot\BCD /set {memdiag} path \boot\windows\EFI\Microsoft\Boot\memtest.efi
```

In order to add a new Windows image file to the USB flash drive copy one into `boot/windows/sources` directory on the USB flash drive and add new boot entry in BCD files.

---

BCD file is a Windows registry hive. So you can edit one on the Linux using the `hivex` program or any other Windows registry editor. [BcdLibraryElementTypes enumeration](https://docs.microsoft.com/en-us/previous-versions/windows/desktop/bcd/bcdlibraryelementtypes) article describes element names of BCD objects.

---
