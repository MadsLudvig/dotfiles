# Asahi peripheral firmware (vendored)

`hardware.asahi.peripheralFirmwareDirectory` points here. A **pure** flake
cannot read `/boot/vendorfw`, so the Wi-Fi/Bluetooth firmware must live inside
the repo tree and be git-tracked.

Since nixos-apple-silicon 66d8dd2 the module expects the pre-extracted
`firmware.cpio` (placed on the ESP by the Asahi installer) instead of
`all_firmware.tar.gz` + `kernelcache.*`.

## During install, on the Mac:

```sh
cp /boot/vendorfw/firmware.cpio ~/.dotfiles/firmware/
git -C ~/.dotfiles add -f firmware/firmware.cpio
```

(They're `.gitignore`-exempt via `-f` if needed — but the flake only sees
**tracked** files, so they must be added.)

## ⚠ Keep this repository PRIVATE

This firmware is **non-free and non-redistributable**. Do not push it to a
public remote.

Until you copy these files in, `nixos-rebuild`/`nixos-install` will fail at the
firmware-extraction step — that's expected, same as the placeholder
`hardware-configuration.nix`.
