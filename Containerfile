# Build environment for the live image: Debian trixie with live-build, plus
# gcc/python3 to build the MousePlotter CLI against the same glibc the image
# ships, and OVMF (with Microsoft keys enrolled) for Secure Boot tests in QEMU.
FROM docker.io/library/debian:trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        live-build make gcc libc6-dev python3 ovmf \
 && rm -rf /var/lib/apt/lists/*
