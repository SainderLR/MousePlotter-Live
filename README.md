# MousePlotter Live

A bootable Linux USB image for recording mouse data with the
[MousePlotter](https://github.com/XBAB-Tech/MousePlotter) Linux CLI in a quiet,
controlled environment, so a PC can be used as a probe of a mouse's own
behavior. The system runs from RAM with CPU frequency scaling and idle states
tuned for low timing jitter between a USB report arriving and its evdev
timestamp, and nothing else running in the background. Reports open in
Chromium right on the machine, which also runs the WebHID-based web pages
that many mice are configured with.

Based on Debian 13 (trixie), built with Debian's standard `live-build`.

## Using it

1. Download `mouseplotter-live-amd64.hybrid.iso` from the
   [latest release](https://github.com/XBAB-Tech/MousePlotter-Live/releases/latest),
   which is rebuilt whenever Debian updates Chromium (about weekly), and write
   it to a USB drive with [Rufus](https://rufus.ie),
   [balenaEtcher](https://etcher.balena.io), or
   `dd if=mouseplotter-live-amd64.hybrid.iso of=/dev/sdX bs=4M conv=fsync status=progress`.
   This erases the drive.
2. Boot from it. Secure Boot can stay on (see below).
3. The menu appears on its own:

   | Key | |
   |---|---|
   | R | Record. Pick the mouse by clicking with it (or press its number), then press Space (or click and hold) to record. H saves the recording as an HTML report and opens it in Chromium; close Chromium to return. C saves a CSV. Esc goes back to the mouse list, and Esc there back to the menu. |
   | H | Chromium with the saved results, also for the web (mouse configuration pages, uploading results) |
   | N / O | Network on (with Wi-Fi setup) / off |
   | T | Next CPU idle-state level: POLL and C1 only (the default), the kernel's defaults, POLL only |
   | K | Keyboard layout |
   | S | Shell (`sudo` needs no password) |

Results are saved to `~/results` in RAM and are **lost at power off**. To
keep them, turn the network on and upload them from Chromium, or copy them to
another drive from the shell.

The system is copied into RAM at boot, so the USB drive can be removed once
the menu appears (the menu says so), leaving one less device on the USB bus.

The boot menu has a single entry and starts it after 2 seconds. To change
the kernel parameters for one boot, press `e` there: for example remove
`toram=filesystem.squashfs` on a PC with less than 2 GB of RAM (the drive
then has to stay plugged in).

### Secure Boot

The image boots with Secure Boot enabled through Debian's shim, which is
signed with both the Microsoft UEFI CA 2011 and 2023 certificates, and
Debian's signed GRUB and kernel. No key enrollment is needed. Some PCs ship
with the "Microsoft 3rd-party UEFI CA" disabled, in which case it has to be
allowed in the firmware settings, as for any Linux USB drive.

### Display

No GPU driver is loaded (`nomodeset`), so there are no GPU interrupts or
driver work during a recording. The console and the report viewer draw on
the framebuffer set up by the PC's firmware, which works on any UEFI PC
regardless of GPU, with software rendering. With `video=efifb:auto` the
kernel switches it to the firmware's highest resolution mode before booting,
which is normally the display's native one. If that picks a mode the display
doesn't show well, replace it in the boot entry (`e`) with a specific one,
such as `video=efifb:1920x1080`; `video=efifb:list` shows the available
modes.

## Latency tuning

At boot (`mouseplotter-tune`):

- `performance` cpufreq governor on every CPU, always
- CPU idle states limited to POLL and C1. T in the menu cycles through the
  kernel's defaults, POLL only (as `cpupower idle-set -D 0` does) and back.
  The CLI's own zero-latency request, which would allow only POLL, is turned
  off so the chosen level applies during recordings too.
- the console cursor doesn't blink (a periodic redraw timer)
- the USB host controllers' interrupts go to the fastest cores (P-cores on
  hybrid CPUs) other than core 0, which handles all other interrupts

On the kernel command line:

- `nowatchdog`: no lockup-detector timers and NMIs
- `rcu_nocbs=all`: kernel cleanup work (RCU callbacks) runs in its own
  threads, not in the interrupt handling that also processes mouse reports
- `irqaffinity=0`: device interrupts go to core 0 by default
- `usbcore.autosuspend=-1` and, through a udev rule, USB 2 link power
  management (LPM) off
- `pcie_aspm.policy=performance`: no PCIe link power states
- `toram=filesystem.squashfs`: after boot, no USB storage traffic shares the
  host controller with the mouse

Also: the network is off until turned on and periodic maintenance timers are
masked. The MousePlotter CLI locks its memory while running.

## Building

Needs [podman](https://podman.io) (works rootless) and about 4 GB of disk.

```sh
git clone --recurse-submodules https://github.com/XBAB-Tech/MousePlotter-Live
cd MousePlotter-Live
./build.sh
```

The ISO lands in `out/`. The build runs `live-build` in a Debian trixie
container ([Containerfile](Containerfile),
[scripts/build-in-container.sh](scripts/build-in-container.sh)), which also
compiles the MousePlotter CLI from the submodule. live-build's work tree and
package cache stay in the podman volume `mouseplotter-live-work` between
builds; `podman volume rm mouseplotter-live-work` removes them.

GitHub Actions ([.github/workflows/build.yml](.github/workflows/build.yml))
checks daily whether Debian has a newer Chromium than the latest release, and
if so builds the ISO and publishes it as a release tagged with the date,
along with its package list. "Run workflow" in the Actions tab publishes one
regardless. Releases older than 30 days are deleted.

To boot the result in QEMU (as a USB drive, Secure Boot on):

```sh
scripts/qemu.sh                   # --no-secure-boot, --bios, --headless
```

### Image size

The ISO is about 435 MB. Beyond installing without recommended packages,
docs, manuals and translations, the build:

- leaves out Mesa's OpenGL drivers and the LLVM libraries they need
  (`dpkg.cfg.d/02-mouseplotter-no-mesa`): nothing uses them without a GPU
  driver, and they are about 190 MB uncompressed
- removes kernel modules for hardware the system never uses (GPU, camera,
  sound card, InfiniBand, RAID, rare filesystems), since Debian's modules are
  already compressed and cost their full size
- uses 1 MiB squashfs blocks with xz's x86 filter, and keeps the kernel and
  initrd (already on the ISO) out of the squashfs

Wi-Fi firmware for Intel, MediaTek, Realtek, Qualcomm (Atheros) and Broadcom
chips is the largest remaining part after Chromium.

## Layout

- [live/auto/config](live/auto/config): live-build options
- [live/config/package-lists](live/config/package-lists): installed packages
- [live/config/bootloaders/grub-pc](live/config/bootloaders/grub-pc): boot
  menu and kernel parameters (used for both UEFI and BIOS)
- [live/config/includes.chroot](live/config/includes.chroot): files added to
  the system: the menu, tuning script and service, report viewer, X and udev
  configuration
- [live/config/hooks/live](live/config/hooks/live): build-time setup
- [MousePlotter](MousePlotter): the MousePlotter repository (submodule)
