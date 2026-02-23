window.V86_VM_CONFIG = {
  memoryMb: 512,
  bios: "assets/v86/seabios.bin",
  wasmPath: "assets/v86/v86.wasm",
  bzImage: "assets/vmlinuz",
  initrd: "assets/initrd.img",
  diskImage: "assets/buildroot-linux.img",
  // Optional override; if omitted, app.js chooses based on enableSerial/build flag.
  cmdline: "",
  enableSerial: true,
  // Keep VM serial-only by default (no VGA/video device).
  enableVga: false,
  // Keep loopback-only networking by default (no emulated ethernet controller).
  enableEthernet: false,
  // Optional: explicit net device type, e.g. "ne2k" or "none" (default).
  // netDeviceType: "none",
  // Optional: only used when net device is enabled.
  // networkRelayUrl: "wss://relay.widgetry.org/",
  // Optional VGA knobs when enableVga=true.
  // vgaMemoryMb: 8,
  // vgaBios: "assets/v86/vgabios.bin",
  asyncDisk: true
};
