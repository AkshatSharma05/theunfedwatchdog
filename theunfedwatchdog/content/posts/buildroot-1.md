+++
date = '2026-05-21T00:51:05+05:30'
title = 'Setting Up a Minimal Linux Image on the Raspberry Pi Zero 2W using Buildroot'
author = 'Akshat'

[cover]
    image = "/images/buildroot/thumb.png"
    alt = "Bare-metal RISC-V setup"
    relative = true
    hidden = false
    hiddenInSingle = true
    
+++

NOTE: This is not a tutorial. Just stuff I understood from watching videos and reading forums/articles.

## What is Buildroot?

I'd been curious for a while about why certain Linux-based gadgets feel so snappy — fast boot times, no bloat, just doing exactly what they're supposed to do. 

I started reading about it and kept running into the name Buildroot.

Buildroot is a build system that compiles a complete Linux image from scratch, tailored exactly to your target hardware, with nothing on it that you didn't explicitly ask for. That minimal footprint is precisely why these devices boot so fast.

Around the same time, I realized my 3D printer was running Linux. On a whim, I tried SSHing into it — and it worked. Poked around a bit and sure enough, it was running Buildroot. Seeing it in the wild like that made everything click.

I'd already been thinking about building a Linux-based music player, and after all this, Buildroot felt like the obvious choice for it.

## Installing Buildroot

Clone the Buildroot source:

```sh
git clone https://gitlab.com/buildroot.org/buildroot.git
cd buildroot
```

Buildroot does not need to be installed — you work directly from the source tree. To start configuring for the Pi Zero 2W:

```sh
make raspberrypizero2w_64_defconfig
make menuconfig
```

The `defconfig` loads a known-good baseline for the hardware. From there, `menuconfig` lets you customize packages, system settings, and kernel options before building.

Once configured, kick off the build with:

```sh
make
```

The first build takes a while — typically 30–90 minutes depending on your machine, since it compiles the entire toolchain and system from source. Subsequent builds are much faster. The final image lands at `output/images/sdcard.img` and can be flashed to an SD card with:

```sh
dd if=output/images/sdcard.img of=/dev/sdX bs=4M status=progress
```

Replace `/dev/sdX` with your actual SD card device.

---

## 1. Package Selection

When configuring your Buildroot build, include the following packages under **Target packages**. These cover peripheral communication, module management, and serial file transfer for development.

| Package | Purpose |
|---|---|
| `i2c-tools` | Userspace utilities for I2C bus inspection and communication |
| `spi-tools` | Userspace utilities for SPI bus communication |
| `pigpio` | GPIO control library and daemon for the Pi |
| `lrzsz` | XMODEM/YMODEM/ZMODEM file transfer over serial (essential for development) |
| `kmod` | Kernel module management (`lsmod`, `modprobe`, etc.) |

---

## 2. Serial Console Configuration

I am using a USB-to-TTL converter to get serial access to the terminal through the UART available on the rpi. I'll eventually end up setting up SSH on this but this will come in handy either way for initial debugging and is essential for a minimal setup like this.

In `menuconfig`, navigate to **System Configuration → getty login prompt** and set:

- **TTY port:** `ttyAMA0`
- **Baud rate:** `115200`
- **TERM:** `vt100`

This configures the login prompt over the Pi's hardware UART, which will be exposed through the USB-to-TTL converter.

---

## 3. Enabling I2C and SPI

### Kernel Module Auto-loading

`The following step is only required if the I2C and SPI drivers were configured as kernel modules ( M ) in menuconfig.
If they were built directly into the kernel ( Y ), they will be available automatically at boot and no module auto-loading configuration is needed.
`

`
Using modules ( M ) is useful when hardware support should remain optional, or during development/testing where drivers may need frequent rebuilds or unloading without rebuilding the entire kernel.
`

Create the following two files in your Buildroot overlay or post-build script:

**`/etc/modules-load.d/i2c.conf`**
```
i2c-bcm2835
i2c-dev
```

**`/etc/modules-load.d/spi.conf`**
```
spi_bcm2835
spidev
```

### Boot Configuration

In the `config.txt` file on the boot partition, add:

```
dtparam=i2c_arm=on
dtparam=spi=on
```

After booting, verify the modules loaded correctly:

```sh
lsmod
ls /dev/i2c-*
ls /dev/spidev*
```

---

## 4. File Transfer Over Serial with lrzsz

During development, `lrzsz` provides a convenient way to transfer files between your host machine and the Pi over the serial connection — no network required.

### Connecting via Minicom

On your host machine:

```sh
minicom -b 115200 -D /dev/ttyUSB0
```

### Transferring Files from Host → Pi

1. On the Pi, type `rz` to start receiving. The terminal will wait silently for an incoming transfer.
2. In minicom on the host, press **Ctrl+A**, then **S**, and select **zmodem**.
3. Navigate the file selector, mark the files you want to send, and confirm. Transfer begins automatically.

To send files **from the Pi to the host**, use `sz <filename>` on the Pi side instead.

---

## 5. Configuring the Shell Prompt

By default, the shell accessed through minicom won't show your current working directory in the prompt, which can get disorienting during development. The fix is to set a custom `PS1` (Prompt String 1) in `/etc/profile`.

**PS1** controls what your shell prompt looks like. The escape sequences used here are:

| Escape | Meaning |
|---|---|
| `\u` | Current username |
| `\h` | Hostname |
| `\w` | Current working directory |

There are two ways to bake this into your image properly.

### Option A: Board Overlay

A board overlay lets you place files directly into the root filesystem at build time. Any file in the overlay replaces the corresponding file from Buildroot's default skeleton.

Create the overlay directory structure inside your Buildroot tree:

```sh
mkdir -p board/rpi0w2/overlay/etc
```

Since the overlay **replaces** Buildroot's default `/etc/profile` entirely rather than merging with it, copy the original first so you don't lose any existing behavior:

```sh
cp system/skeleton/etc/profile board/rpi0w2/overlay/etc/profile
```

Then open the file and append your PS1 line at the bottom:

```sh
export PS1="[\u@\h \w]$ "
```

Now tell Buildroot to use the overlay. Run `make menuconfig` and navigate to:

```
System configuration --->
    Root filesystem overlay directories
```

Set the value to:

```
board/rpi0w2/overlay
```

Rebuild with `make` and flash as usual. The prompt will be baked into the image.

### Option B: Post-Build Script

If you only want to append the PS1 line and don't want to maintain a copy of the entire profile file, use a post-build script instead. Post-build scripts run after the filesystem is assembled but before the image is finalized, and have access to `$TARGET_DIR` — the root of the target filesystem.

Create the script:

```sh
mkdir -p board/rpi0w2
nano board/rpi0w2/post-build.sh
```

Contents:

```sh
#!/bin/sh
echo 'export PS1="[\u@\h \w]$ "' >> $TARGET_DIR/etc/profile
```

Make it executable:

```sh
chmod +x board/rpi0w2/post-build.sh
```

Then enable it in `menuconfig`:

```
System configuration --->
    Custom scripts to run after creating filesystem images
```

Set it to:

```
board/rpi0w2/post-build.sh
```

Rebuild with `make`. The PS1 line will be appended to the existing profile on every build.

---

## 6. Emergency Shell Access (Login Recovery)

If login fails — for example, due to a misconfigured credential setup — you can bypass the normal init sequence entirely by editing `cmdline.txt` on the boot partition and appending:

```
rw init=/bin/sh -c "exec /bin/sh </dev/ttyAMA0 >/dev/ttyAMA0 2>&1"
```

This drops you directly into a read-write shell over the serial port, bypassing any login prompt. If `ttyAMA0` doesn't work, try `ttyS0`.

Once in the recovery shell, you can inspect and fix user accounts:

```sh
# List existing users with home directories
cat /etc/passwd | grep /home

# Reset a user's password
passwd <username>
```

---

