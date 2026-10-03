#!/usr/bin/env bash
# Boots out/mouseplotter-live-amd64.hybrid.iso in QEMU as a USB stick on an
# xHCI controller, with a USB keyboard and mouse. Secure Boot is on by default,
# using Debian's OVMF with the Microsoft keys enrolled.
#
#   scripts/qemu.sh [--no-secure-boot | --bios] [--headless] [qemu args...]
#
# A QMP socket at out/qemu-qmp.sock allows screenshots and key presses; the
# stick can be unplugged with the QMP command device_del id=usbstick.
set -euo pipefail
cd "$(dirname "$0")/.."

iso=out/mouseplotter-live-amd64.hybrid.iso
fw=out/ovmf
mode=secure-boot
display=(-display gtk)
while [ $# -gt 0 ]; do
	case $1 in
	--no-secure-boot) mode=uefi ;;
	--bios) mode=bios ;;
	--headless) display=(-display none) ;;
	*) break ;;
	esac
	shift
done

if [ ! -f "$fw/OVMF_VARS_4M.ms.fd" ]; then
	mkdir -p "$fw"
	podman run --rm -v "$PWD/$fw:/fw" mouseplotter-live-builder \
		cp /usr/share/OVMF/OVMF_CODE_4M.secboot.fd /usr/share/OVMF/OVMF_VARS_4M.ms.fd \
		/usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_VARS_4M.fd /fw/
fi

vars=$(mktemp)
trap 'rm -f "$vars"' EXIT
case $mode in
secure-boot)
	cp "$fw/OVMF_VARS_4M.ms.fd" "$vars"
	firmware=(-machine q35,smm=on -global driver=cfi.pflash01,property=secure,value=on
		-drive "if=pflash,format=raw,unit=0,readonly=on,file=$fw/OVMF_CODE_4M.secboot.fd"
		-drive "if=pflash,format=raw,unit=1,file=$vars")
	;;
uefi)
	cp "$fw/OVMF_VARS_4M.fd" "$vars"
	firmware=(-machine q35
		-drive "if=pflash,format=raw,unit=0,readonly=on,file=$fw/OVMF_CODE_4M.fd"
		-drive "if=pflash,format=raw,unit=1,file=$vars")
	;;
bios)
	firmware=(-machine q35)
	;;
esac

qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4G "${firmware[@]}" \
	-vga std \
	-device qemu-xhci,id=xhci \
	-drive "if=none,id=stick,format=raw,readonly=on,file=$iso" \
	-device usb-storage,bus=xhci.0,drive=stick,removable=on,id=usbstick \
	-device usb-kbd,bus=xhci.0 \
	-device usb-mouse,bus=xhci.0 \
	-netdev user,id=net0 -device e1000e,netdev=net0 \
	-qmp unix:out/qemu-qmp.sock,server=on,wait=off \
	"${display[@]}" "$@"
