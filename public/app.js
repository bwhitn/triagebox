(() => {
  const config = Object.assign({}, window.V86_VM_CONFIG || {}, window.V86_BUILD_CONFIG || {});
  const serialEnabled = config.enableSerial === true;

  const statusEl = document.getElementById("status");
  const ipsEl = document.getElementById("ips");
  const serialPanelEl = document.getElementById("serial-panel");
  const serialEl = document.getElementById("serial");

  const startBtn = document.getElementById("start");
  const stopBtn = document.getElementById("stop");
  const restartBtn = document.getElementById("restart");
  const clearSerialBtn = document.getElementById("clear-serial");

  let emulator = null;
  let emulatorReadyPromise = null;
  let emulatorReadyResolve = null;
  let sampleTimer = null;
  let lastSampleTime = 0;
  let lastInstructionCount = 0;

  function setStatus(text) {
    statusEl.textContent = `status: ${text}`;
  }

  function setIps(text) {
    ipsEl.textContent = `instructions/sec: ${text}`;
  }

  function startSampling() {
    if (sampleTimer) {
      return;
    }

    lastSampleTime = performance.now();
    lastInstructionCount = emulator ? (emulator.get_instruction_counter() >>> 0) : 0;

    sampleTimer = window.setInterval(() => {
      if (!emulator) {
        return;
      }

      const now = performance.now();
      const count = emulator.get_instruction_counter() >>> 0;
      const elapsedSeconds = (now - lastSampleTime) / 1000;

      if (elapsedSeconds > 0) {
        const delta = (count - lastInstructionCount) >>> 0;
        const ips = Math.round(delta / elapsedSeconds);
        setIps(ips.toLocaleString());
      }

      lastSampleTime = now;
      lastInstructionCount = count;
    }, 1000);
  }

  function stopSampling() {
    if (!sampleTimer) {
      return;
    }

    clearInterval(sampleTimer);
    sampleTimer = null;
  }

  function ensureEmulator() {
    if (emulator) {
      return emulator;
    }

    if (typeof window.V86 !== "function") {
      setStatus("error (libv86.js missing)");
      throw new Error("V86 constructor not found. Did you run make fetch-v86?");
    }

    setStatus("loading");
    emulatorReadyPromise = new Promise((resolve) => {
      emulatorReadyResolve = resolve;
    });

    const defaultCmdlineNoSerial = "root=LABEL=rootfs rootfstype=ext4 rw rootwait init=/usr/local/sbin/v86-init console=tty0";
    const defaultCmdlineSerial = "root=LABEL=rootfs rootfstype=ext4 rw rootwait init=/usr/local/sbin/v86-init console=ttyS0 console=tty0";
    const cmdline = typeof config.cmdline === "string" && config.cmdline.trim().length > 0
      ? config.cmdline
      : (serialEnabled ? defaultCmdlineSerial : defaultCmdlineNoSerial);

    const vmOptions = {
      wasm_path: config.wasmPath || "assets/v86/v86.wasm",
      memory_size: (config.memoryMb || 512) * 1024 * 1024,
      vga_memory_size: (config.vgaMemoryMb || 8) * 1024 * 1024,
      screen_container: document.getElementById("screen_container"),
      bios: { url: config.bios || "assets/v86/seabios.bin" },
      vga_bios: { url: config.vgaBios || "assets/v86/vgabios.bin" },
      bzimage: { url: config.bzImage || "assets/vmlinuz" },
      initrd: { url: config.initrd || "assets/initrd.img" },
      hda: { url: config.diskImage || "assets/alpine-linux.img", async: config.asyncDisk === true },
      cmdline,
      disable_mouse: true,
      disable_speaker: true,
      boot_order: 0x132,
      autostart: false
    };
    if (serialEnabled) {
      vmOptions.serial_container = serialEl;
      vmOptions.uart1 = true;
    } else {
      vmOptions.uart1 = false;
    }

    emulator = new window.V86(vmOptions);

    emulator.add_listener("emulator-ready", () => {
      setStatus("ready");
      if (emulatorReadyResolve) {
        emulatorReadyResolve();
        emulatorReadyResolve = null;
      }
    });

    emulator.add_listener("emulator-started", () => {
      setStatus("running");
      startSampling();
    });

    emulator.add_listener("emulator-stopped", () => {
      setStatus("stopped");
      stopSampling();
    });

    return emulator;
  }

  startBtn.addEventListener("click", async () => {
    try {
      const vm = ensureEmulator();
      if (emulatorReadyPromise) {
        await emulatorReadyPromise;
      }
      await vm.run();
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setStatus(`error (${msg})`);
      if (msg.includes("Range: bytes=")) {
        setStatus("error (async disk requires HTTP range support; set asyncDisk=false)");
      }
      // Surface to console for debugging.
      console.error(err);
    }
  });

  stopBtn.addEventListener("click", async () => {
    if (!emulator) {
      return;
    }
    await emulator.stop();
  });

  restartBtn.addEventListener("click", () => {
    if (!emulator) {
      return;
    }
    emulator.restart();
  });

  clearSerialBtn.addEventListener("click", () => {
    serialEl.value = "";
  });

  if (!serialEnabled && serialPanelEl) {
    serialPanelEl.style.display = "none";
  }

  setStatus("idle");
})();
