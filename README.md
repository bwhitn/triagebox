# Alpine Linux v86 Environment

This repository provides a minimal v86 setup with:

- Alpine Linux guest root filesystem built from `alpine:3.20` (`linux/386`)
- No audio, no CD-ROM image, no floppy image, no networking relay, and mouse disabled
- Serial-first CLI workflow with VGA BIOS enabled
- 512MB RAM default
- Built-in lightweight profiling (`instructions/sec` and instruction stats dump)

## What is included

- `rootfs/Dockerfile`: defines the boot disk content (Alpine based)
- `rootfs/overlay/`: files copied into the guest filesystem
- `scripts/build-boot-assets.sh`: builds guest artifacts (`alpine-linux.img`, `vmlinuz`, `initrd.img`)
- `scripts/fetch-v86-assets.sh`: fetches `libv86.js`, `v86.wasm`, SeaBIOS, and VGA BIOS
- `public/`: static UI to run the VM and profile it
- `Dockerfile` + `compose.yaml`: serve UI from a Debian Trixie slim container

## Prerequisites

- Docker
- `mke2fs` (from `e2fsprogs`)
- `python3` (only for local non-docker serving)

## Build VM assets

```bash
make build
```

If needed, override architecture with:

```bash
PLATFORM=linux/386 make build
```

This does:

1. Download v86 runtime assets to `public/assets/v86/`
2. Build Alpine rootfs image from `rootfs/Dockerfile`
3. Export rootfs and create `public/assets/alpine-linux.img`
4. Copy kernel/initramfs to `public/assets/vmlinuz` and `public/assets/initrd.img`

If Docker socket permissions fail, run with sudo mode:

```bash
DOCKER_USE_SUDO=1 make build
```

Then optionally fix permanently (so sudo mode is not needed):

```bash
sudo usermod -aG docker $USER
newgrp docker
```

## Serve for testing

### Local host server

```bash
make serve
```

Open `http://localhost:8080`.

### Docker server (Debian trixie-slim)

```bash
make docker-serve
```

If needed:

```bash
DOCKER_USE_SUDO=1 make docker-serve
```

Open `http://localhost:8080`.

## Configure boot disk changes

Edit either:

- `rootfs/Dockerfile` (packages and kernel/initramfs behavior)
- `rootfs/overlay/` (files/scripts/config copied into guest filesystem)

Then rebuild just the guest artifacts:

```bash
make build-disk
```

## Runtime tuning

Edit `public/vm-config.js`:

- `memoryMb` defaults to `512`
- `cmdline` controls guest init behavior
- file paths for BIOS/kernel/initrd/disk image

## Profiling

In the web UI:

- `instructions/sec` is sampled continuously while VM runs
- `Dump Instruction Profile` shows v86 instruction statistics from `get_instruction_stats()`

## Notes

- v86 currently exposes a single emulated CPU in standard builds; a true dual-core guest is not currently configurable here.
- No networking is configured (`network_relay_url` omitted), and no floppy/CD images are attached.
- The Alpine rootfs build prefers `linux-lts` and falls back to `linux-virt` if needed for the selected architecture.
