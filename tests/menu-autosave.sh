#!/bin/bash
# Exercise the menu's save/shutdown sequencing without Linux block devices.
set -eu
tests_path=$(cd "$(dirname "$0")" && pwd)
menu=${1:-"$tests_path/../live/config/includes.chroot/usr/local/bin/mouseplotter-menu"}
test_root=$(mktemp -d "$tests_path/run-XXXXXX")
export HOME="$test_root/home"
mkdir -p "$HOME"
# Load the real functions without entering the interactive menu loop.
set +e
source <(sed '/^while true; do$/,$d' "$menu")
set -e

fail() { echo "FAIL: $*" >&2; exit 1; }
check() { "$@" || fail "$*"; }
expect_failure() { if "$@"; then fail "unexpected success: $*"; fi; }
log() { printf '%s\n' "$*" >> "$event_log"; }
clear() { :; }
pause() { log pause; }
network_up() { return 1; }
lsblk() { log lsblk; printf '%s\n' "$mock_devices"; return "$lsblk_failure"; }
findmnt() { [ "$externally_mounted" = 1 ]; }
mount() { log mount; return "$mount_failure"; }
umount() { log umount; return "$unmount_failure"; }
sync() { log sync; return "$sync_failure"; }
rsync() {
	log rsync
	[ "$copy_failure" = 0 ] || return 1
	local source_path="${@: -2:1}" target_path="${@: -1}"
	cp -R "$source_path/." "$target_path/"
}
sudo() {
	if [ "$1" = MOUSEPLOTTER_NO_PM_QOS=1 ]; then
		log record-start
		[ "$save_mounted" = 0 ] || fail "save mount was active during recording"
		printf 'recorded\n' > "$results/record.csv"
		log record-end
		return 0
	fi
	"$@"
}
systemctl() { log "systemctl $*"; }

fixture() {
	local name=$1
	results="$test_root/$name/results"
	save_mount="$test_root/$name/MPDATA"
	event_log="$test_root/$name/events"
	mkdir -p "$results" "$save_mount"
	: > "$event_log"
	session_id=current-boot
	save_path="MousePlotter/$session_id/results"
	save_status="not saved yet; exit the recorder to save"
	save_mounted=0
	mock_devices='/dev/sdb1 MPDATA exfat'
	lsblk_failure=0 mount_failure=0 copy_failure=0 sync_failure=0 unmount_failure=0
	externally_mounted=0
	printf 'capture\n' > "$results/sample.csv"
}

fixture successful
mkdir -p "$save_mount/MousePlotter/prior-boot/results"
printf 'prior data\n' > "$save_mount/MousePlotter/prior-boot/results/sample.csv"
save_results
check cmp "$results/sample.csv" "$save_mount/$save_path/sample.csv"
check grep -qx 'prior data' "$save_mount/MousePlotter/prior-boot/results/sample.csv"
check test "$save_mounted" = 0
check test "$(cat "$event_log")" = $'lsblk\nmount\nrsync\nsync\numount'
# Changed files within this boot are recopied instead of cp -n skipping them.
printf 'updated capture\n' > "$results/sample.csv"
save_results
check cmp "$results/sample.csv" "$save_mount/$save_path/sample.csv"

fixture empty
results="$test_root/empty/no-results"
mkdir -p "$results"
save_results
check test ! -s "$event_log"

fixture missing
mock_devices='/dev/sdb1 OTHER exfat'
expect_failure save_results
check test "$(cat "$event_log")" = lsblk
check test "$save_status" = 'SAVE FAILED: MPDATA not found; results remain in RAM'

fixture duplicate
mock_devices=$'/dev/sdb1 MPDATA exfat\n/dev/sdc1 MPDATA exfat'
expect_failure save_results
check test "$(cat "$event_log")" = lsblk
check test "$data_error" = 'multiple MPDATA partitions found; keep only one connected'

fixture detection_failure
lsblk_failure=1
expect_failure save_results
check test "$data_error" = 'cannot check MPDATA partitions'

fixture unsupported
mock_devices='/dev/sdb1 MPDATA ext4'
expect_failure save_results
check test "$(cat "$event_log")" = lsblk

fixture already_mounted
externally_mounted=1
expect_failure save_results
check test "$(cat "$event_log")" = lsblk
record
check test "$(tail -n 1 "$event_log")" = pause
check test "$(grep -c record-start "$event_log" || true)" = 0

fixture mount_failure
mount_failure=1
expect_failure save_results
check test "$(cat "$event_log")" = $'lsblk\nmount'
check test "$save_mounted" = 0

fixture copy_failure
copy_failure=1
expect_failure save_results
check test "$(cat "$event_log")" = $'lsblk\nmount\nrsync\nsync\numount'
check test "$save_mounted" = 0

fixture flush_failure
sync_failure=1
expect_failure save_results
check test "$(cat "$event_log")" = $'lsblk\nmount\nrsync\nsync\numount'
check test "$save_mounted" = 0

fixture unmount_failure
unmount_failure=1
expect_failure save_results
check test "$save_mounted" = 1
record
check test "$(tail -n 2 "$event_log")" = $'umount\npause'
check test "$(grep -c record-start "$event_log" || true)" = 0
unmount_failure=0
record
check test "$save_mounted" = 0
check test "$(tail -n 4 "$event_log")" = $'umount\nlsblk\nrecord-start\nrecord-end'

fixture sequencing
# The menu's actual recording arm executes record; save_results || pause.
record
save_results
check test "$(cat "$event_log")" = $'lsblk\nrecord-start\nrecord-end\nlsblk\nmount\nrsync\nsync\numount'
check cmp "$results/record.csv" "$save_mount/$save_path/record.csv"

fixture shutdown_success
shutdown poweroff
check test "$(tail -n 2 "$event_log")" = $'umount\nsystemctl poweroff'

fixture shutdown_cancel
copy_failure=1
shutdown reboot <<< ''
check test "$(grep -c systemctl "$event_log" || true)" = 0

fixture shutdown_override
copy_failure=1
shutdown reboot <<< YES
check test "$(tail -n 1 "$event_log")" = 'systemctl reboot'

fixture status
check test "$(usb_save_status)" = 'MPDATA found, keep plugged in; not saved yet; exit the recorder to save'
mock_devices=''
check test "$(usb_save_status)" = 'MPDATA not found; not saved yet; exit the recorder to save'

printf '\nPASS: 16 mocked save, sequencing, failure, shutdown, and status scenarios.\n'
printf 'Fixtures and event logs: %s\n' "$test_root"
