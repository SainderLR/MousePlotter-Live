#!/usr/bin/env bash
# Builds out/mouseplotter-live-amd64.hybrid.iso in a podman container (works
# rootless). live-build's work tree and package cache live in the podman
# volume "mouseplotter-live-work"; remove it with
#   podman volume rm mouseplotter-live-work
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f MousePlotter/linux_cli/log.c ]; then
	echo "MousePlotter submodule missing; run: git submodule update --init" >&2
	exit 1
fi

mkdir -p out
podman build -t mouseplotter-live-builder -f Containerfile .
podman run --rm --privileged \
	-v "$PWD:/src:ro" \
	-v "$PWD/out:/out" \
	-v mouseplotter-live-work:/work \
	mouseplotter-live-builder /src/scripts/build-in-container.sh
