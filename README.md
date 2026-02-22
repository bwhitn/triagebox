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
- `scripts/fetch-v86-assets.sh`: fetches `libv86.js`, `v86.wasm`, SeaBIOS, VGA BIOS, and xterm.js assets
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
   and terminal assets to `public/assets/xterm/`
2. Build Alpine rootfs image from `rootfs/Dockerfile`
3. Export rootfs and create `public/assets/alpine-linux.img`
4. Copy kernel/initramfs to `public/assets/vmlinuz` and `public/assets/initrd.img`
5. Write `public/build-config.js` with build-time flags

Default disk sizing targets a compact image:

- `MIN_DISK_MB=512`
- `EXTRA_MB=96` (added to exported rootfs size before applying minimum)
- `PRUNE_ROOTFS=1` (removes kernel modules/firmware/docs from runtime rootfs after extracting boot artifacts)
- `AUTO_SHRINK=1` (enabled by default after filesystem creation)
- `SHRINK_PAD_MB=2` (extra free slack retained)
- `SHRINK_MIN_MB=0` by default (no forced minimum after shrink)
- `MKINITFS_FEATURES="base ata scsi ext4"` by default (safe root-mount feature set)
- transient files are cleaned before packing (for example `/tmp`, `/var/tmp`, `/var/cache`, `/var/log`)
- pip/apk temporary artifacts are cleaned during build (`py3-pip` removed, pip cache/wheels purged, root cache dirs cleared)

Rootfs package policy is allowlist-based:

- only minimal boot requirements are always installed (`mkinitfs` + kernel package during build)
- additional runtime tools are installed only if you list them in `rootfs/user-packages.txt`
- one-off package additions can be passed with `USER_APK_PACKAGES`
- Python pip packages can be installed at build time via `PYTHON_PIP_PACKAGES` (defaults to `binary-refinery`), then `py3-pip` is removed from the final image
- `STRIP_TO_BUSYBOX=1` by default removes package-manager tooling (`apk`) from the final runtime image

You can override explicitly for tighter control:

```bash
DISK_MB=512 make build-disk
```

Disable auto-shrink if you want to keep the initial size:

```bash
AUTO_SHRINK=0 make build-disk
```

Keep full rootfs content (no pruning):

```bash
PRUNE_ROOTFS=0 make build-disk
```

Keep a final minimum only when you want one:

```bash
SHRINK_MIN_MB=512 make build-disk
```

Install one-off extra packages for a build:

```bash
USER_APK_PACKAGES="curl strace" make build-disk
```

Override pip-installed Python tools for a build:

```bash
PYTHON_PIP_PACKAGES="binary-refinery" make build-disk
```

Disable pip-installed Python tools:

```bash
PYTHON_PIP_PACKAGES="" make build-disk
```

Keep `apk` tooling in the runtime image (disable busybox-only strip):

```bash
STRIP_TO_BUSYBOX=0 make build-disk
```

If root-device probing ever fails on your host/browser combo, add SCSI support back:

```bash
MKINITFS_FEATURES="base ata scsi ext4" make build-disk
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

This uses a gzip-capable static server that can apply `Content-Encoding: gzip`
to selected file extensions (including `.img`, `.bin`, `.wasm`) when the browser
advertises gzip support.

### Docker server (Debian trixie-slim)

```bash
make docker-serve
```

If needed:

```bash
DOCKER_USE_SUDO=1 make docker-serve
```

Open `http://localhost:8080`.

Compression server environment knobs (for both local and docker):

- `COMPRESS_EXT` (comma-separated extensions, default includes `.img,.bin,.wasm,.js,.css`)
- `COMPRESS_MIN_BYTES` (default `1024`)
- `COMPRESS_LEVEL` (default `6`)

Example:

```bash
COMPRESS_MIN_BYTES=1 COMPRESS_LEVEL=9 make serve
```

## Configure boot disk changes

Edit either:

- `rootfs/Dockerfile` (boot package policy and kernel/initramfs behavior)
- `rootfs/user-packages.txt` (allowlisted runtime tools, one package per line)
- `rootfs/overlay/` (files/scripts/config copied into guest filesystem)

Then rebuild just the guest artifacts:

```bash
make build-disk
```

Enable serial console for a build:

```bash
ENABLE_SERIAL=1 make build-disk
```

When serial is enabled, the UI uses xterm.js (if assets are present) for proper
terminal behavior with full-screen programs like `top`. If xterm assets are
missing, it falls back to a textarea.

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
- `enableSerial` defaults to `true` (build flag can override via `public/build-config.js`)
- `asyncDisk` is opt-in and defaults to `false` for compatibility with simple static servers (such as `python3 -m http.server`). Set it to `true` only with a server that supports HTTP byte-range requests.

## Notes

- v86 currently exposes a single emulated CPU in standard builds; a true dual-core guest is not currently configurable here.
- No networking is configured (`network_relay_url` omitted), and no floppy/CD images are attached.
- The Alpine rootfs build prefers `linux-virt` (smaller footprint) and falls back to `linux-lts` if needed for the selected architecture.
- The rootfs build removes Alpine `busybox-suid` (`/bin/bbsuid`) to avoid ext4 image population failures in unprivileged `mke2fs -d` runs.
