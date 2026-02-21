# Debian Trixie v86 Environment

This repository provides a minimal v86 setup with:

- Debian Trixie guest root filesystem built from `i386/debian:trixie-slim`
- No audio, no CD-ROM image, no floppy image, no networking relay, and mouse disabled
- Serial-first CLI workflow with VGA BIOS enabled
- 512MB RAM default
- Built-in lightweight profiling (`instructions/sec` and instruction stats dump)

## What is included

- `rootfs/Dockerfile`: defines the boot disk content (Debian Trixie slim based)
- `rootfs/overlay/`: files copied into the guest filesystem
- `scripts/build-boot-assets.sh`: builds guest artifacts (`debian-trixie.img`, `vmlinuz`, `initrd.img`)
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
2. Build Debian rootfs image from `rootfs/Dockerfile`
3. Export rootfs and create `public/assets/debian-trixie.img`
4. Copy kernel/initrd to `public/assets/vmlinuz` and `public/assets/initrd.img`

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

Open `http://localhost:8080`.

## Configure boot disk changes

Edit either:

- `rootfs/Dockerfile` (packages, apt install steps, base behavior)
- `rootfs/overlay/` (drop files/scripts/config into guest filesystem)

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
