# Generic x86_64 UEFI hardware profile — boots on most machines WITHOUT
# per-machine `nixos-generate-config`, as long as you format the disks with the
# labels `nixos` (root) and `BOOT` (ESP).
#
# `availableKernelModules` covers NVMe + SATA/AHCI + USB boot. An exotic storage
# controller could need one more entry — check with:
#   nixos-generate-config --show-hardware-config
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" "sr_mod" "vmd"
  ];

  hardware.enableRedistributableFirmware = true; # wifi/gpu firmware for arbitrary hw

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXROOT";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXBOOT";
    fsType = "vfat";
  };

  swapDevices = [ ];
}
