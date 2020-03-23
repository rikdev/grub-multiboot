# GRUB multiboot

It is a simple script for the [GRUB2](https://www.gnu.org/software/grub/grub-documentation.html) that downloads images from USB flash drive. This USB flash drive allows booting multiple ISO files without unpacking them.

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
7. Copy ISO files to the `/mnt/boot/iso` directory.
