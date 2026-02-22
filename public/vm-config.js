window.V86_VM_CONFIG = {
  memoryMb: 512,
  vgaMemoryMb: 8,
  bios: "assets/v86/seabios.bin",
  vgaBios: "assets/v86/vgabios.bin",
  wasmPath: "assets/v86/v86.wasm",
  bzImage: "assets/vmlinuz",
  initrd: "assets/initrd.img",
  diskImage: "assets/buildroot-linux.img",
  // Optional override; if omitted, app.js chooses based on enableSerial/build flag.
  cmdline: "",
  enableSerial: true,
  // Optional: force VGA on/off. Default behavior is VGA off in serial mode, on otherwise.
  // enableVga: true,
  asyncDisk: false
};
