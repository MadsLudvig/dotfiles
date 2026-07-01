# mads — NixOS config (one flake, two machines)

Declarative NixOS for:

| host | `nixosConfigurations.<name>` | arch | notes |
|------|------------------------------|------|-------|
| MacBook (M1 Pro, Asahi) | `mbp` | `aarch64-linux` | Apple Silicon support module + vendored firmware |
| Arbitrary x86 PC        | `pc`  | `x86_64-linux`  | plain NixOS |

Everything shared (Hyprland, greetd autologin, Zen+Tridactyl, neovim, zsh+starship,
packages, user) lives in the `common` / `home` modules in `flake.nix`. Host-specific
bits (Asahi firmware/cache vs. x86 boot) are the small inline modules per host.

```
flake.nix                     inputs + common/home modules + both hosts
hosts/mbp/hardware-configuration.nix   ← DUMMY, regenerate on the Mac
hosts/pc/hardware-configuration.nix    ← DUMMY, regenerate on the PC
config/   hypr eww fuzzel nvim         raw configs (sourced by home-manager)
firmware/                              Wi-Fi/BT blobs (Mac only, git-add at install)
```

> **Keep this repo private** — the Mac firmware under `firmware/` is non-redistributable.

The `hardware-configuration.nix` files are placeholders so the flake evaluates
off-target; each is overwritten by `nixos-generate-config` during that machine's install.

---

## Rename a host / set your timezone

- Host name: change the `nixosConfigurations.<name>` key **and** its
  `networking.hostName` in `flake.nix` (e.g. `pc` → `desktop`).
- `time.timeZone` is in the `common` module.

---

## Install on the MacBook (Asahi + NixOS)

Follows the official guide — **always check the latest**, as steps change:
<https://github.com/nix-community/nixos-apple-silicon/blob/main/docs/uefi-standalone.md>
(this config tracks Asahi `main`; currently kernel `linux-asahi 7.0.13`).

> ⚠ **Back up first.** Damaging the GPT / first / last partition can brick the Mac
> and lose all data.

### 1. macOS → install the UEFI environment
In macOS Terminal (admin account):
```sh
curl https://alx.sh | sh
```
- `r` — resize macOS, leave ≥ 20 GB free for NixOS
- `f` — install into free space → **UEFI environment only**, name it `NixOS`
- Reboot into recovery when told; set **permissive security** for the new OS.
- It reboots into U-Boot (Asahi + U-Boot logos). Power off.

### 2. Build + write the installer USB
On any Linux box with Nix (or download a release ISO from the repo's Releases):
```sh
nix build github:nix-community/nixos-apple-silicon#installer-bootstrap -o installer
sudo dd if=installer/iso/nixos-*.iso of=/dev/sdX bs=4M conv=fsync status=progress
```
(`dd` only — not unetbootin.)

### 3. Boot the installer, partition, mount
Boot the USB (U-Boot → GRUB → installer), then:
```sh
sudo su
sgdisk /dev/nvme0n1 -n 0:0 -s          # root fills free space
sgdisk /dev/nvme0n1 -p                  # find the new 8300 partition number (e.g. p5)
mkfs.ext4 -L nixos /dev/nvme0n1p5

mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-partuuid/$(cat /proc/device-tree/chosen/asahi,efi-system-partition) /mnt/boot
```

### 4. Hardware config + vendored firmware + this flake
```sh
nixos-generate-config --root /mnt

# get this repo onto the target (private remote or USB), e.g.:
git clone <your-private-remote> /mnt/etc/nixos/config && cd /mnt/etc/nixos/config

cp /mnt/etc/nixos/hardware-configuration.nix hosts/mbp/hardware-configuration.nix

# vendor the Wi-Fi/BT firmware (pure flakes can't read /boot/asahi)
mkdir -p firmware
cp /mnt/boot/asahi/all_firmware.tar.gz firmware/
cp /mnt/boot/asahi/kernelcache*        firmware/
git add -f hosts/mbp/hardware-configuration.nix firmware/*
```

### 5. Install
```sh
nixos-install --flake .#mbp     # sets root password at the end
reboot
```
Boot picker: hold the power button. greetd autologins `mads` into Hyprland.
**First thing after login: `passwd`** (the config ships `initialPassword = "changeme"`).

---

## Install on an x86 PC

Standard NixOS install (<https://nixos.org/manual/nixos/stable/#sec-installation>),
just point `nixos-install` at `.#pc`.

### 1. Boot the NixOS ISO, get network, partition (UEFI/GPT)
```sh
sudo -i
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 512MiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart primary 512MiB 100%

mkfs.fat -F32 -n BOOT /dev/nvme0n1p1
mkfs.ext4 -L nixos    /dev/nvme0n1p2

mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot
```
(The `BOOT` / `nixos` labels match the dummy `hosts/pc/hardware-configuration.nix`,
but the generated one below replaces it with real UUIDs anyway.)

### 2. Hardware config + this flake + install
```sh
nixos-generate-config --root /mnt
git clone <your-private-remote> /mnt/etc/nixos/config && cd /mnt/etc/nixos/config
cp /mnt/etc/nixos/hardware-configuration.nix hosts/pc/hardware-configuration.nix

nixos-install --flake .#pc
reboot
```
Then `passwd`.

---

## Day-to-day

```sh
# apply config changes
sudo nixos-rebuild switch --flake ~/nixos#mbp     # or #pc

# update everything (nixpkgs + asahi + zen + addons), then rebuild
nix flake update
sudo nixos-rebuild switch --flake ~/nixos#mbp

# roll back: pick a previous generation in the boot menu
```

Both `apple-silicon` and `nixpkgs` are cached (asahi via its Cachix), so updates
download rather than compile.

---

## Verify-on-first-boot (can't be checked off-machine)

- **greetd session** — the command is `uwsm start hyprland`. If you land on a blank
  tty instead of Hyprland, change it to `command = "Hyprland"` in `common`.
- **Asahi `hardware.asahi.*`** — firmware path / sound options, per the guide above.
