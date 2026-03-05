window.V86_VM_CONFIG = {
  memoryMb: 1024,
  bios: "assets/v86/seabios.bin",
  wasmPath: "assets/v86/v86.wasm",
  bzImage: "assets/vmlinuz",
  initrd: "assets/initrd.img",
  // Primary boot/root disk (Buildroot image).
  diskImage: "assets/buildroot-linux.img",
  // Kernel root= value. With the root filesystem image mounted as hda in v86,
  // /dev/sda is the direct root block device (no partition table).
  rootDevice: "/dev/sda",
  // Optional override; if omitted, app.js chooses based on enableSerial/build flag.
  cmdline: "",
  enableSerial: true,
  // Keep VM serial-only by default (no VGA/video device).
  enableVga: false,
  // Keep mouse disabled by default.
  enableMouse: false,
  // Keep CD-ROM disabled by default.
  enableCdrom: false,
  // Keep loopback-only networking by default (no emulated ethernet controller).
  enableEthernet: false,
  // Optional: explicit net device type, e.g. "ne2k" or "none" (default).
  // netDeviceType: "none",
  // Optional: only used when net device is enabled.
  // networkRelayUrl: "wss://relay.widgetry.org/",
  // Enable host<->guest non-persistent /root exchange over virtio-9p.
  enableRootExchange: true,
  // Exposed size of the host 9p share mounted at /root (default 1 GiB).
  rootExchangeSizeMb: 1024,
  // Optional VGA knobs when enableVga=true.
  // vgaMemoryMb: 8,
  // vgaBios: "assets/v86/vgabios.bin",
  // Global async default (overridden per-disk below when set).
  asyncDisk: true,
  // Keep boot disk async for faster startup.
  asyncBootDisk: true
};
