# Disko declarative disk partitioning for Hetzner Cloud CX22
# Disk: /dev/sda, 38.1 GB
# Layout: GPT with BIOS boot + EFI + root (supports both legacy BIOS and UEFI)
{
  disko.devices.disk.sda = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # BIOS boot partition — required for GRUB on GPT with legacy BIOS
        bios = {
          size = "1M";
          type = "EF02";
          priority = 1;
        };

        # EFI system partition — for GRUB on UEFI (Hetzner Cloud supports UEFI)
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };

        # Root filesystem — remainder of disk
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
