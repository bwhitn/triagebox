window.V86_VM_CONFIG = {
  memoryMb: 512,
  vgaMemoryMb: 8,
  bios: "assets/v86/seabios.bin",
  vgaBios: "assets/v86/vgabios.bin",
  wasmPath: "assets/v86/v86.wasm",
  bzImage: "assets/vmlinuz",
  initrd: "assets/initrd.img",
  diskImage: "assets/alpine-linux.img",
  cmdline: "root=/dev/sda rw rootwait init=/usr/local/sbin/v86-init console=ttyS0 console=tty0",
  asyncDisk: true
};
