# Buildroot v86 Environment

This repository provides a minimal Buildroot-based v86 setup with:

- Buildroot guest root filesystem (`qemu_x86_defconfig`)
- No audio, no CD-ROM image, no floppy image, serial console first, and mouse disabled
- Serial console enabled by default (can be disabled at build time)
- 1GB RAM default
- Lightweight runtime throughput display (`instructions/sec`)

## What is included

- `buildroot/overlay/`: files copied into the guest filesystem
- `buildroot/linux-v86-trim.fragment`: Linux kernel fragment that strips unused drivers (video/audio/cdrom/mouse/network-device stack)
- `buildroot-external/`: custom Buildroot package metadata (includes `python-binary-refinery`)
- `scripts/build-boot-assets-buildroot.sh`: builds guest artifacts (`buildroot-linux.img`, `vmlinuz`, `initrd.img`)
- `scripts/write-build-config.sh`: writes build-time UI flags
- `scripts/fetch-v86-assets.sh`: fetches `libv86.js`, `v86.wasm`, SeaBIOS, and xterm assets (VGA BIOS optional)
- `public/`: static UI to run the VM
- `Dockerfile` + `compose.yaml`: serve UI from a Debian Trixie slim container

## Prerequisites

- `curl`, `tar`, `make`, `gcc`, `patch`, `bison`, `flex`, `perl`, `rsync`, `bc`, `unzip`
- `mke2fs`, `e2fsck`, `resize2fs` (from `e2fsprogs`)
- `python3` (required)
- `python3-pip` (only required when `REFINERY_REQUIRE_BUILDROOT_TARGET=0` and `PREFETCH_REFINERY_WHEELS=1`)

## Build VM assets

```bash
make build
```

`make build` now runs a host dependency preflight first and fails fast if anything is missing.
You can run only the check with:

```bash
make preflight
```

This does:

1. Download v86 runtime assets to `public/assets/v86/` and terminal assets to `public/assets/xterm/`
2. Build Buildroot kernel/rootfs output
3. Optionally generate Buildroot legal-info and archive it as `public/assets/buildroot-legal-info.tar.gz` (disabled by default)
4. Create `public/assets/buildroot-linux.img` (ext2)
5. Copy kernel/initramfs to `public/assets/vmlinuz` and `public/assets/initrd.img`
6. Write `public/build-config.js`

Build just the disk/kernel/initrd artifacts:

```bash
make build-disk
```

Resume a failed Buildroot disk build without deleting `.work/buildroot/output`:

```bash
make build-disk-resume
```

Build only the kernel artifact (`public/assets/vmlinuz`) without rebuilding disk/initrd:

```bash
make build-kernel
```

Resume kernel-only build:

```bash
make build-kernel-resume
```

## Build knobs

- `BUILDROOT_VERSION` (default `2026.02-rc1`)
- `BUILDROOT_ARCHIVE_URL` (default points to buildroot.org tarball for that version)
- `BUILDROOT_DEFCONFIG` (default `qemu_x86_defconfig`)
- `BUILDROOT_RESUME` (default `0`; set `1` to reuse existing Buildroot output dir and continue failed builds)
- `BUILDROOT_JOBS` (default `nproc`)
- `BUILDROOT_TOPLEVEL_PARALLEL` (default `0`; set `1` to enable Buildroot top-level parallel build via `BR2_PER_PACKAGE_DIRECTORIES`, experimental but often faster)
- `BUILDROOT_CCACHE` (default `1`; set `0` to disable compiler cache)
- `BUILDROOT_CCACHE_DIR` (default `.work/buildroot/ccache`)
- `BUILDROOT_PRIMARY_SITE` (default `https://sources.buildroot.net`)
- `BUILDROOT_PRIMARY_SITE_ONLY` (default `0`; set to `1` for mirror-only fetches)
- `BUILDROOT_GLOBAL_PATCH_DIR` (default `buildroot/patches`; applies local package patches during Buildroot builds)
- `INITRD_MODE` (default `minimal`; `minimal` boots rootfs from disk image via tiny initrd, `full` uses Buildroot `rootfs.cpio.gz` as initrd)
- `BUILDROOT_ONLY` (default `all`; set `kernel` to build/export kernel only and skip disk/initrd generation)
- Linux kernel always applies `buildroot/linux-v86-trim.fragment` to remove unused driver classes for this serial-first VM profile.
- If `BR2_DOWNLOAD_FORCE_CHECK_HASHES=y` from the base defconfig and the pinned kernel patchlevel is no longer present in Buildroot's `linux.hash`, the build script auto-adjusts to the newest hashed patchlevel in the same major/minor series.
- x86 target CPU is forced to `pentium-m` (SSE2-capable, avoids pentium4-specific behavior)
- Buildroot toolchain C++ support is forced on so `python-pymupdf` can be built from source on target arch
- `BUILD_PROFILE` (default `optimized`; options: `optimized`, `fast`)
  `optimized`: userspace/toolchain `-O3` + LTO for best runtime speed
  `fast`: userspace/toolchain `-O0`, LTO off for shorter build times
- `KERNEL_CFLAGS` (default `-O3`; passed as `LINUX_CFLAGS` so kernel builds stay high optimization by default)
- `PYTHON_MODULE_FORMAT` (default `pyc`; options: `pyc`, `py`, `both`)
  `pyc`: precompiled `.pyc` only (no `.py` sources in target)
  `py`: source `.py` only
  `both`: install `.py` and `.pyc`
- `PREFETCH_DOWNLOADS` (default `1`; runs `make source` before compile)
- `PREFETCH_REFINERY_WHEELS` (default `1`; pre-downloads binary-refinery wheel deps early, requires local `python3 -m pip` only when `REFINERY_REQUIRE_BUILDROOT_TARGET=0`)
- `REFINERY_WHEELHOUSE_DIR` (default `.work/buildroot/dl/python-binary-refinery-wheelhouse`)
- `REFINERY_WHEEL_PLATFORM_PRIMARY` (default `manylinux_2_28_i686`)
- `REFINERY_WHEEL_PLATFORM_FALLBACK` (default `manylinux2014_i686`)
- `REFINERY_REQUIRE_BUILDROOT_TARGET` (default `1`; when `1`, binary-refinery optional requirements must be provided as Buildroot target packages, no pip fallback)
- `REFINERY_WHEEL_STRICT` (default `1`; build fails if any optional dependency cannot be resolved for i686)
- `REFINERY_SDIST_FALLBACK` (default `1`; if wheel is missing, try sdist and keep it only when a universal `*-none-any.whl` can be built)
- `REFINERY_SDIST_BUILD_JOBS` (default `BUILDROOT_JOBS`; parallelism for sdist fallback wheel builds)
- `REFINERY_SDIST_SKIP_PACKAGES` (default `pikepdf icicle-emu speakeasy-emulator-refined lief pyppmd`; skips costly host sdist builds for known native packages on i686 wheel path)
- `REFINERY_MISSING_WHEELS_REPORT` (default `public/assets/binary-refinery-missing-wheels.txt`)
- `REFINERY_BUILDROOT_PROVIDED_REPORT` (default `public/assets/binary-refinery-buildroot-provided.txt`)
- `REFINERY_MISSING_BUILDROOT_REPORT` (default `public/assets/binary-refinery-missing-buildroot-packages.txt`)
- `BUILD_LEGAL_INFO` (default `0`; set to `1` to run `make legal-info` and publish archive)
- `LEGAL_INFO_ARCHIVE` (default `public/assets/buildroot-legal-info.tar.gz`)
- Python 3 is always included
- binary-refinery is always included
- `BINARY_REFINERY_VERSION` (default `0.9.26`)
- `PYTHON_LIEF_VERSION` (default `0.17.3`)
- `DISK_MB` (fixed final pre-shrink size; optional)
- `EXTRA_MB` (default `32`)
- `MIN_DISK_MB` (default `64`)
- `AUTO_SHRINK` (default `1`)
- `SHRINK_PAD_MB` (default `0`)
- `SHRINK_MIN_MB` (default `0`)
- `ENABLE_SERIAL` (default `1`, accepted: `0` or `1`)
- `FETCH_VGA_BIOS` (default `0`; set `1` only when you enable VGA output)

Binary-refinery note:

- The Buildroot package installs `binary-refinery` plus the full upstream Python optional set (`[all]`), including `python-lief`.
- Optional deps are resolved in two phases for i686:
  1) If a matching Buildroot `python-*` package exists, it is enabled and built for target.
  2) Remaining deps are resolved via pip wheel prefetch (`manylinux_2_28_i686` plus fallback `manylinux2014_i686`), with optional sdist fallback to universal wheels only.
- With `REFINERY_REQUIRE_BUILDROOT_TARGET=1`, step (2) is disabled and build fails early for any optional dependency not backed by a Buildroot target package (report written to `REFINERY_MISSING_BUILDROOT_REPORT`).
- If an auto-mapped Buildroot package is unavailable for the active config/arch after `olddefconfig`, that requirement is automatically pushed back to pip resolution.
- Some optional deps do not publish i686 Linux wheels for newer Python ABIs. With `REFINERY_SDIST_FALLBACK=1`, build tries sdist next and only accepts universal wheels (`*-none-any.whl`) to avoid host-arch contamination.
- With `REFINERY_WHEEL_STRICT=1` (default), unresolved items fail the build. Set `REFINERY_WHEEL_STRICT=0` only if you explicitly want best-effort mode.
- Binary-refinery does not have one fixed built-in list of required external non-Python executables.
- If you use the `run` unit to call host tools, install those command-line tools in the image.

Examples:

```bash
BUILDROOT_VERSION=2026.02-rc1 make build-disk
BUILDROOT_TOPLEVEL_PARALLEL=1 BUILDROOT_JOBS=8 make build-disk-resume
BUILDROOT_ONLY=kernel make build-disk
INITRD_MODE=minimal make build-disk
INITRD_MODE=full make build-disk
DISK_MB=512 make build-disk
AUTO_SHRINK=0 make build-disk
SHRINK_PAD_MB=0 SHRINK_MIN_MB=0 make build-disk
BUILDROOT_PRIMARY_SITE=https://sources.buildroot.net BUILDROOT_PRIMARY_SITE_ONLY=1 make build-disk
BUILD_PROFILE=optimized make build-disk
BUILD_PROFILE=fast make build-disk
KERNEL_CFLAGS=-O3 make build-kernel
PYTHON_MODULE_FORMAT=pyc make build-disk
PREFETCH_DOWNLOADS=0 make build-disk
PREFETCH_REFINERY_WHEELS=0 make build-disk
FETCH_VGA_BIOS=1 make fetch-v86
REFINERY_REQUIRE_BUILDROOT_TARGET=1 make build-disk
REFINERY_REQUIRE_BUILDROOT_TARGET=0 make build-disk
REFINERY_SDIST_FALLBACK=0 make build-disk
REFINERY_SDIST_BUILD_JOBS=8 make build-disk
REFINERY_SDIST_SKIP_PACKAGES="pikepdf icicle-emu speakeasy-emulator-refined lief pyppmd" make build-disk
REFINERY_WHEEL_PLATFORM_PRIMARY=manylinux_2_28_i686 REFINERY_WHEEL_PLATFORM_FALLBACK=manylinux2014_i686 make build-disk
REFINERY_WHEEL_STRICT=1 make build-disk
REFINERY_WHEEL_STRICT=0 make build-disk
BUILD_LEGAL_INFO=1 make build-disk
BINARY_REFINERY_VERSION=0.9.26 make build-disk
PYTHON_LIEF_VERSION=0.17.3 make build-disk
ENABLE_SERIAL=0 make write-build-config
```

## Serve for testing

### Local host server

```bash
make serve
```

Open `http://localhost:8080`.
If enabled at build time, download legal info archive at `http://localhost:8080/assets/buildroot-legal-info.tar.gz`.
If present, missing optional binary-refinery wheel report is at `http://localhost:8080/assets/binary-refinery-missing-wheels.txt`.
Buildroot-provided optional dependency report is at `http://localhost:8080/assets/binary-refinery-buildroot-provided.txt`.
Missing Buildroot target coverage report is at `http://localhost:8080/assets/binary-refinery-missing-buildroot-packages.txt`.

### Docker server (Debian trixie-slim)

```bash
make docker-serve
```

If Docker socket permissions fail:

```bash
DOCKER_USE_SUDO=1 make docker-serve
```

## Configure boot disk changes

Edit:

- `buildroot/overlay/` (files/scripts/config copied into guest rootfs)
- `scripts/build-boot-assets-buildroot.sh` (build behavior)

Then rebuild:

```bash
make build-disk
```

## Check disk usage

```bash
make disk-usage
```

Or for any image path:

```bash
./scripts/disk-usage.sh public/assets/buildroot-linux.img
```

## Shrink an existing image manually

The build already auto-shrinks by default. Manual run:

```bash
make shrink-disk
```

Tune shrink slack:

```bash
PAD_MB=8 ./scripts/shrink-image.sh public/assets/buildroot-linux.img
```

## Runtime tuning

Edit `public/vm-config.js`:

- `memoryMb` defaults to `1024`
- `cmdline` override is optional (if empty, app.js uses defaults)
- `rootFsType` is injected at build time as `ext2`
- `enableSerial` defaults to `true` (build flag can override via `public/build-config.js`)
- `enableVga` defaults to `false` (serial-only UI; no VGA BIOS/device attached)
- `enableEthernet` defaults to `false` (guest loopback only; no emulated ethernet controller)
- `asyncDisk` defaults to `false` unless your server supports HTTP byte ranges

## Notes

- v86 exposes a single emulated CPU in this setup.
- No networking relay is configured and no emulated ethernet NIC is attached by default.
- No floppy/CD images are attached.
