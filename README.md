# Alpine Linux v86 Environment

This repository provides a minimal v86 setup with:

- Alpine Linux guest root filesystem built from `alpine:3.20` (`linux/386`)
- No audio, no CD-ROM image, no floppy image, no networking relay, and mouse disabled
- Serial console disabled by default (can be enabled at build time)
- 512MB RAM default
- Lightweight runtime throughput display (`instructions/sec`)

## What is included

- `rootfs/Dockerfile`: defines the boot disk content (Alpine based)
- `rootfs/overlay/`: files copied into the guest filesystem
- `scripts/build-boot-assets.sh`: builds guest artifacts (`alpine-linux.img`, `vmlinuz`, `initrd.img`)
- `scripts/write-build-config.sh`: writes build-time UI flags (for example serial enablement)
- `scripts/fetch-v86-assets.sh`: fetches `libv86.js`, `v86.wasm`, SeaBIOS, and VGA BIOS
- `public/`: static UI to run the VM
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
5. Write `public/build-config.js` with build-time flags

Default disk sizing targets a compact image:

- `MIN_DISK_MB=512`
- `EXTRA_MB=96` (added to exported rootfs size before applying minimum)
- `AUTO_SHRINK=1` (enabled by default after filesystem creation)
- `SHRINK_PAD_MB=32` (extra free slack retained)
- `SHRINK_MIN_MB=0` by default (no forced minimum after shrink)

You can override explicitly for tighter control:

```bash
DISK_MB=512 make build-disk
```

Disable auto-shrink if you want to keep the initial size:

```bash
AUTO_SHRINK=0 make build-disk
```

Keep a final minimum only when you want one:

```bash
SHRINK_MIN_MB=512 make build-disk
```

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

Enable serial console for a build:

```bash
ENABLE_SERIAL=1 make build-disk
```

## Check disk usage

```bash
make disk-usage
```

Or on any image path:

```bash
./scripts/disk-usage.sh public/assets/alpine-linux.img
```

## Shrink an existing image after build

The build process already auto-shrinks by default, but you can also run shrink manually.

Default shrink leaves 32MB free slack:

```bash
make shrink-disk
```

Tune slack space (example: 16MB):

```bash
PAD_MB=16 ./scripts/shrink-image.sh public/assets/alpine-linux.img
```

Enforce a minimum output size (example: 512MB):

```bash
MIN_MB=512 ./scripts/shrink-image.sh public/assets/alpine-linux.img
```

Create a backup before shrinking:

```bash
BACKUP_PATH=public/assets/alpine-linux.pre-shrink.img make shrink-disk
```

## Runtime tuning

Edit `public/vm-config.js`:

- `memoryMb` defaults to `512`
- `cmdline` can override guest init behavior (left empty by default so app.js picks serial/non-serial defaults)
- file paths for BIOS/kernel/initrd/disk image
- `enableSerial` defaults to `false` (build flag can override via `public/build-config.js`)
- `asyncDisk` is opt-in and defaults to `false` for compatibility with simple static servers (such as `python3 -m http.server`). Set it to `true` only with a server that supports HTTP byte-range requests.

## Notes

- v86 currently exposes a single emulated CPU in standard builds; a true dual-core guest is not currently configurable here.
- No networking is configured (`network_relay_url` omitted), and no floppy/CD images are attached.
- The Alpine rootfs build prefers `linux-virt` (smaller footprint) and falls back to `linux-lts` if needed for the selected architecture.
- The rootfs build removes Alpine `busybox-suid` (`/bin/bbsuid`) to avoid ext4 image population failures in unprivileged `mke2fs -d` runs.
