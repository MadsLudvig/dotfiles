#!/usr/bin/env python3
"""
Case lighting on the PC, by talking to the devices directly: no OpenRGB, no
liquidctl. The byte layouts are lifted from those projects' sources
(OpenRGB 1.0, liquidctl 1.16); the vendors document none of this.

flake.nix runs it as the `rgb` service with `mask --keepalive`. Colours and
the dead-LED list are the constants below. Needs root (the hidraw and i2c
nodes) and the i2c-dev kernel module (flake.nix loads it) for the GPU.

  rgb.py                  hardware modes everywhere, kept in the controllers'
                          flash, so it shows from POST. Lights the dead
                          Corsair LEDs too (purple).
  rgb.py mask             same, but the Corsair hub goes to per-LED software
                          mode with the dead LEDs dark. The hub blanks that
                          channel unless it gets a commit every few seconds:
  rgb.py mask --keepalive ...which this does, in the foreground, forever.
  rgb.py off              everything black, LCD off.
  rgb.py test             everything black, LCD on with the coolant screen.

Try it by hand with `sudo systemctl stop rgb` first, e.g.
  sudo $(nix build --print-out-paths nixpkgs#python3)/bin/python3 hosts/pc/rgb.py test
"""
import fcntl
import glob
import os
import select
import sys
import time

FAN = (0x80, 0x60, 0x38)      # warm white at half
BOARD = (0x80, 0x70, 0x60)    # cooler white at half, for board and GPU
BLACK = (0, 0, 0)
CORSAIR_LEDS = 150            # 3 LL + 3 QL fans
DEAD = {58, 69, 80, 97, 99, 110, 121, 124, 142}   # 1-based, hub order
LCD_BRIGHTNESS = 0            # 0..100, 0 = off

I2C_SLAVE = 0x0703


def hidraw(name):
    """/dev/hidrawN whose HID name contains `name`."""
    for uevent in glob.glob("/sys/class/hidraw/hidraw*/device/uevent"):
        with open(uevent) as f:
            if any(line.startswith("HID_NAME=") and name in line for line in f):
                return "/dev/" + uevent.split("/")[4]
    sys.exit(f"no hidraw device named like {name!r}")


def hid_write(fd, data, size):
    # hidraw: first byte is the report number; 0 means "none", and the kernel
    # strips it. Anything else goes on the wire as the first byte.
    os.write(fd, bytes(data).ljust(size, b"\0"))


def hid_read(fd, size, timeout):
    ready, _, _ = select.select([fd], [], [], timeout)
    return os.read(fd, size) if ready else b""


# ── Corsair Lighting Node CORE (USB HID, 64-byte reports, no report id) ──

def corsair(color, per_led):
    fd = os.open(hidraw("Lighting Node CORE"), os.O_RDWR)

    def cmd(*b):
        hid_write(fd, [0x00, *b], 65)
        hid_read(fd, 17, 0.5)          # every command is answered; ignore it

    ch = 0                             # channel 0 = the six fan ports
    if not per_led:
        r, g, b = color
        cmd(0x37, ch)                  # reset channel
        cmd(0x34, ch)                  # begin
        cmd(0x38, ch, 0x01)            # port state: hardware effect
        #   effect config: [start=0, leds, mode=static(4), speed=medium(1),
        #   direction, random, pad, colour 0 rgb]
        cmd(0x35, ch, 0x00, CORSAIR_LEDS, 0x04, 0x01, 0x00, 0x00, 0x00, r, g, b)
        cmd(0x39, ch, 100)             # brightness
        cmd(0x33, 0xFF)                # commit
    else:
        colors = [BLACK if i + 1 in DEAD else color for i in range(CORSAIR_LEDS)]
        cmd(0x38, ch, 0x02)            # port state: software (per-LED)
        for off in range(0, CORSAIR_LEDS, 50):
            chunk = colors[off:off + 50]
            for plane in range(3):     # one packet per colour plane: R, G, B
                cmd(0x32, ch, off, len(chunk), plane, *[c[plane] for c in chunk])
        cmd(0x33, 0xFF)
    return fd


def corsair_keepalive(fd):
    while True:
        time.sleep(4)
        hid_write(fd, [0x00, 0x33, 0xFF], 65)
        hid_read(fd, 17, 0.5)


# ── ASUS Aura USB (motherboard), report id 0xEC ──

def aura(color):
    fd = os.open(hidraw("AURA LED Controller"), os.O_RDWR)

    def w(*b):
        hid_write(fd, [0xEC, *b], 65)

    w(0xB0)                                      # read the config table
    table = hid_read(fd, 65, 1.0)
    n = table[4 + 0x1B] if len(table) >= 0x20 and table[1] == 0x30 else 3
    w(0x52, 0x53, 0x00, 0x01)                    # init, as OpenRGB does
    w(0x35, 0x00, 0x00, 0x00, 0x01)              # effect: channel 0 (board LEDs), static
    mask = (1 << n) - 1
    w(0x36, mask >> 8, mask & 0xFF, 0x00, *(color * n))   # colour per board LED
    w(0x3F, 0x55)                                # commit: saved in flash
    os.close(fd)
    print(f"board: {n} LEDs")


# ── Gigabyte RGB Fusion GPU (i2c on the card's own bus, address 0x63) ──

def gpu(color):
    for path in glob.glob("/sys/class/i2c-dev/i2c-*"):
        with open(path + "/name") as f:
            if "NVIDIA" not in f.read():
                continue
        dev = "/dev/" + os.path.basename(path)
        fd = os.open(dev, os.O_RDWR)
        try:
            fcntl.ioctl(fd, I2C_SLAVE, 0x63)

            def wb(*bs):               # SMBus "write byte", one transaction each
                for b in bs:
                    os.write(fd, bytes([b]))

            def rb():
                return os.read(fd, 1)[0]

            try:                       # probe, exactly like OpenRGB's detector
                wb(0xAB, 0, 0, 0)
                if rb() != 0xAB or rb() not in (0x10, 0x11, 0x12, 0x14):
                    continue
            except OSError:
                continue
            r, g, b = color
            wb(0x40, r, g, b)          # colour
            wb(0x88, 0x01, 0x00, 0x63) # mode static, speed 0, brightness max
            wb(0xAA, 0, 0, 0)          # save
            print(f"gpu: {dev}")
            return
        finally:
            os.close(fd)
    print("gpu: not found on any NVIDIA i2c bus", file=sys.stderr)


# ── NZXT Kraken Z LCD (USB HID, 64-byte reports) ──

def kraken(brightness, liquid=False):
    fd = os.open(hidraw("KrakenZ"), os.O_RDWR)
    hid_write(fd, [0x30, 0x01], 64)              # ask for LCD info
    orientation = 0
    for _ in range(12):                          # the kernel driver's status
        reply = hid_read(fd, 64, 1.0)            # reports come in too
        if reply[:2] == b"\x31\x01":
            orientation = reply[0x1A]
            break
    if liquid:
        hid_write(fd, [0x38, 0x01, 0x02, 0x00], 64)   # built-in coolant temperature screen
        hid_read(fd, 64, 1.0)
    hid_write(fd, [0x30, 0x02, 0x01, brightness, 0, 0, 1, orientation], 64)
    os.close(fd)
    print(f"lcd: brightness {brightness}" + (", coolant screen" if liquid else ""))


if __name__ == "__main__":
    args = sys.argv[1:]
    test = "test" in args              # all LEDs off, LCD on with the coolant screen
    off = "off" in args or test
    per_led = "mask" in args and not off
    fan = BLACK if off else FAN
    board = BLACK if off else BOARD

    hub = corsair(fan, per_led)
    print(f"fans: {'per-LED, dead ones dark' if per_led else 'static'}")
    aura(board)
    gpu(board)
    if test:
        kraken(60, liquid=True)
    else:
        kraken(0 if off else LCD_BRIGHTNESS)

    if "--keepalive" in args and per_led:
        print("keepalive: committing every 4 s, Ctrl-C to stop")
        corsair_keepalive(hub)
