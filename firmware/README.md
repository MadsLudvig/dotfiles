# Asahi peripheral firmware (vendored)

`hardware.asahi.peripheralFirmwareDirectory` points here. A **pure** flake
cannot read `/boot/asahi`, so the Wi-Fi/Bluetooth firmware must live inside the
repo tree and be git-tracked.

## During install, on the Mac:

```sh
cp /boot/asahi/all_firmware.tar.gz  ~/.dotfiles/firmware/
cp /boot/asahi/kernelcache*         ~/.dotfiles/firmware/
git -C ~/.dotfiles add -f firmware/all_firmware.tar.gz firmware/kernelcache*
```

(They're `.gitignore`-exempt via `-f` if needed — but the flake only sees
**tracked** files, so they must be added.)

## ⚠ Keep this repository PRIVATE

This firmware is **non-free and non-redistributable**. Do not push it to a
public remote.

Until you copy these files in, `nixos-rebuild`/`nixos-install` will fail at the
firmware-extraction step — that's expected, same as the placeholder
`hardware-configuration.nix`.
