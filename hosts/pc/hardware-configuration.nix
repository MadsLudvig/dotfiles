# DUMMY x86 hardware config — just enough for `nix eval`/build off-target.
# OVERWRITTEN at install by:  nixos-generate-config --root /mnt
# then copy /mnt/etc/nixos/hardware-configuration.nix here.
{ ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };
}
