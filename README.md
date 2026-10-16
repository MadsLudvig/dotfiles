# dotfiles

NixOS for `pc` (x86_64 desktop) and `mbp` (MacBook M1 Pro, Asahi). Everything is in `flake.nix`.

```sh
sudo nixos-rebuild switch --flake ~/dotfiles#pc   # or #mbp
```

Install: boot an installer, partition, mount at `/mnt`, clone this repo, `nixos-install --flake .#<host>`.
The pc mounts by label (`NIXBOOT` fat32, `NIXROOT` ext4). The mbp follows the
[Asahi guide](https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md):
put its partition UUIDs into the `mbp` block, and copy `/mnt/boot/vendorfw/firmware.cpio`
to `mbp-firmware.cpio` (`git add -f`). That file is Apple's firmware, so keep the repo private.

Initial password: `changeme`.
