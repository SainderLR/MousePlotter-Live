#!/bin/bash
# Runs inside the builder container (see build.sh): builds the MousePlotter
# CLI against the glibc the image ships, then the live image with live-build.
#   /src   this repository, read-only
#   /work  live-build working directory, kept between builds for its caches
#   /out   receives the ISO and its package list
set -euo pipefail

# Build the CLI from a copy so the read-only source tree stays untouched.
rm -rf /tmp/mouseplotter
cp -a /src/MousePlotter /tmp/mouseplotter
make -C /tmp/mouseplotter/linux_cli

cd /work
if [ -d config ]; then
	lb clean
fi
rm -rf auto config
cp -a /src/live/auto /src/live/config .
install -D -m 0755 /tmp/mouseplotter/linux_cli/mouseplotter \
	config/includes.chroot/usr/local/bin/mouseplotter

lb config
lb build 2>&1 | tee build.log

iso=mouseplotter-live-amd64.hybrid.iso
cp "$iso" mouseplotter-live-amd64.packages /out/
(cd /out && sha256sum "$iso" > "$iso.sha256")
ls -l "/out/$iso"
