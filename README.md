# dotfiles

NixOS for two machines, everything in `flake.nix`: Hyprland, nixvim, zsh.

| host  | machine                          |
|-------|----------------------------------|
| `pc`  | x86_64 desktop                   |
| `mbp` | MacBook M1 Pro (Asahi, aarch64)  |

```sh
sudo nixos-rebuild switch --flake ~/dotfiles#pc    # or #mbp
nix flake update                                   # then rebuild
```

## Install

**pc**: boot the NixOS ISO, make a GPT disk with a FAT32 ESP labelled `NIXBOOT`
and an ext4 root labelled `NIXROOT`, mount them at `/mnt` and `/mnt/boot`,
clone this repo and run `nixos-install --flake .#pc`.

**mbp**: follow the [nixos-apple-silicon guide][asahi]. Root is btrfs
(subvolume `@`); put the new partition UUIDs into the `mbp` block of
`flake.nix`, then copy the firmware the Asahi installer left on the ESP:

```sh
cp /mnt/boot/vendorfw/firmware.cpio mbp-firmware.cpio && git add -f mbp-firmware.cpio
```

`mbp-firmware.cpio` is Apple's non-redistributable firmware: keep this repo private.

First boot: `passwd` (initial password `changeme`).

[asahi]: https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md
