# nixos

One flake, two machines. Hyprland + greetd autologin, Zen+Tridactyl, neovim, zsh+starship.

| host | arch | build |
|------|------|-------|
| `mbp` | aarch64 | MacBook M1 Pro (Asahi) |
| `pc`  | x86_64  | any UEFI x86 |

```
flake.nix          everything: system + home config for both hosts, Hyprland, nixvim, all app configs inline
mbp-firmware.cpio  Mac Wi-Fi/BT blobs, copied from /boot/vendorfw at install. Non-redistributable: KEEP REPO PRIVATE.
```

Set `time.timeZone` in `common`. Rename a host = change the `nixosConfigurations.<name>` key + its `networking.hostName`.

## Apply

```sh
sudo nixos-rebuild switch --flake ~/nixos#mbp   # or #pc
nix flake update && sudo nixos-rebuild switch --flake ~/nixos#mbp   # update
```
Roll back = pick an older generation at boot.

## Install: MacBook (Asahi)

Full/latest guide: <https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md>. **Back up — a bad partition can brick the Mac.**

1. macOS Terminal: `curl https://alx.sh | sh` → `r` resize (≥20 GB free) → `f` install **UEFI environment only**, name `NixOS` → recovery: permissive security. Reboots to U-Boot; power off.
2. Installer USB (on a Linux+Nix box): `nix build github:nix-community/nixos-apple-silicon#installer-bootstrap -o installer` then `dd` the ISO to USB.
3. Boot USB → `sudo su`:
```sh
sgdisk /dev/nvme0n1 -n 0:0 -s && sgdisk /dev/nvme0n1 -p   # note new 8300 part, e.g. p5
mkfs.ext4 -L nixos /dev/nvme0n1p5
mount /dev/disk/by-label/nixos /mnt && mkdir -p /mnt/boot
mount /dev/disk/by-partuuid/$(cat /proc/device-tree/chosen/asahi,efi-system-partition) /mnt/boot
nixos-generate-config --root /mnt
git clone <private-remote> /mnt/root/nixos && cd /mnt/root/nixos
# hardware: copy the UUIDs from /mnt/etc/nixos/hardware-configuration.nix into the mbp block of flake.nix
cp /mnt/boot/vendorfw/firmware.cpio mbp-firmware.cpio
git add -f mbp-firmware.cpio
nixos-install --flake .#mbp && reboot
```

## Install: x86

No hardware generation — the pc block in `flake.nix` is generic (mounts by label). Boot the NixOS ISO, `sudo -i`:
```sh
parted /dev/nvme0n1 -- mklabel gpt \
  mkpart ESP fat32 1MiB 512MiB set 1 esp on \
  mkpart primary 512MiB 100%
mkfs.fat -F32 -n BOOT /dev/nvme0n1p1
mkfs.ext4 -L nixos    /dev/nvme0n1p2
mount /dev/disk/by-label/nixos /mnt && mkdir -p /mnt/boot && mount /dev/disk/by-label/BOOT /mnt/boot
git clone <private-remote> /mnt/root/nixos && cd /mnt/root/nixos
nixos-install --flake .#pc && reboot
```
Exotic storage controller won't boot? Add its module to `availableKernelModules` in the pc block of `flake.nix` (`nixos-generate-config --show-hardware-config` lists it).

## After first boot

`passwd` (ships `initialPassword = "changeme"`). If you land on a tty instead of Hyprland, change greetd's `uwsm start -eD Hyprland hyprland.desktop` → `start-hyprland` in `common`.
