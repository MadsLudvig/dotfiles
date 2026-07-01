# DUMMY hardware config — just enough for the flake to `nix eval`/build on a
# non-target machine. It is OVERWRITTEN at install:
#
#   nixos-generate-config --root /mnt
#   cp /mnt/etc/nixos/hardware-configuration.nix ~/nixos/
#
# The real file has your actual disk UUIDs and the Asahi EFI/boot mounts.
{ ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
