(() => {
  const config = Object.assign({}, window.V86_VM_CONFIG || {}, window.V86_BUILD_CONFIG || {});
  const serialEnabled = config.enableSerial === true;
  const xtermCtor = (() => {
    if (typeof window.Terminal === "function") {
      return window.Terminal;
    }
    if (window.Xterm && typeof window.Xterm.Terminal === "function") {
      return window.Xterm.Terminal;
    }
    return null;
  })();
  const vgaEnabled = config.enableVga === true || (config.enableVga !== false && !serialEnabled);

  const statusEl = document.getElementById("status");
  const ipsEl = document.getElementById("ips");
  const serialPanelEl = document.getElementById("serial-panel");
  const serialHintEl = document.getElementById("serial-hint");
  const serialXtermEl = document.getElementById("serial-xterm");
  const vgaPanelEl = document.getElementById("vga-panel");
  const specialKeyButtons = document.querySelectorAll("[data-special-key]");
  const serialUseXterm = serialEnabled && !!xtermCtor;

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
  const specialKeySerialBytes = {
    ctrl_c: [0x03],
    ctrl_d: [0x04],
    ctrl_z: [0x1a],
    ctrl_l: [0x0c],
    esc: [0x1b],
    tab: [0x09],
    up: [0x1b, 0x5b, 0x41],
    down: [0x1b, 0x5b, 0x42],
    left: [0x1b, 0x5b, 0x44],
    right: [0x1b, 0x5b, 0x43],
    pgup: [0x1b, 0x5b, 0x35, 0x7e],
    pgdn: [0x1b, 0x5b, 0x36, 0x7e]
  };
  const specialKeyKeyboardScancodes = {
    ctrl_alt_del: [0x1d, 0x38, 0xe0, 0x53, 0xe0, 0xd3, 0xb8, 0x9d],
    ctrl_c: [0x1d, 0x2e, 0xae, 0x9d],
    ctrl_d: [0x1d, 0x20, 0xa0, 0x9d],
    ctrl_z: [0x1d, 0x2c, 0xac, 0x9d],
    ctrl_l: [0x1d, 0x26, 0xa6, 0x9d],
    esc: [0x01, 0x81],
    tab: [0x0f, 0x8f],
    up: [0xe0, 0x48, 0xe0, 0xc8],
    down: [0xe0, 0x50, 0xe0, 0xd0],
    left: [0xe0, 0x4b, 0xe0, 0xcb],
    right: [0xe0, 0x4d, 0xe0, 0xcd],
    pgup: [0xe0, 0x49, 0xe0, 0xc9],
    pgdn: [0xe0, 0x51, 0xe0, 0xd1],
    alt_f1: [0x38, 0x3b, 0xbb, 0xb8],
    alt_f2: [0x38, 0x3c, 0xbc, 0xb8]
  };

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

  function hasRunningVm() {
    return !!(emulator && emulator.is_running && emulator.is_running());
  }

  function sendSerialBytes(bytes) {
    if (!serialEnabled || !bytes || bytes.length === 0) {
      return false;
    }
    if (!emulator || typeof emulator.serial_send_bytes !== "function") {
      return false;
    }
    emulator.serial_send_bytes(0, bytes);
    if (emulator?.serial_adapter?.term?.focus) {
      emulator.serial_adapter.term.focus();
    }
    return true;
  }

  async function sendSpecialKeys(name) {
    if (!hasRunningVm()) {
      setStatus("stopped (start VM first)");
      return;
    }

    try {
      // In serial mode, send terminal control bytes first (e.g. Ctrl+C => 0x03).
      const serialBytes = specialKeySerialBytes[name];
      if (sendSerialBytes(serialBytes)) {
        return;
      }

      // Fallback to keyboard scancodes for non-serial actions (e.g. Ctrl+Alt+Del).
      const sequence = specialKeyKeyboardScancodes[name];
      if (sequence) {
        await emulator.keyboard_send_scancodes(sequence, 0);
        if (emulator?.serial_adapter?.term?.focus) {
          emulator.serial_adapter.term.focus();
        }
        return;
      }

      setStatus(`unsupported key action: ${name}`);
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setStatus(`error (${msg})`);
      console.error(err);
    }
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
    const defaultCmdlineSerial = vgaEnabled
      ? "root=LABEL=rootfs rootfstype=ext4 rw rootwait init=/usr/local/sbin/v86-init console=ttyS0 console=tty0"
      : "root=LABEL=rootfs rootfstype=ext4 rw rootwait init=/usr/local/sbin/v86-init console=ttyS0";
    const cmdline = typeof config.cmdline === "string" && config.cmdline.trim().length > 0
      ? config.cmdline
      : (serialEnabled ? defaultCmdlineSerial : defaultCmdlineNoSerial);

    const vmOptions = {
      wasm_path: config.wasmPath || "assets/v86/v86.wasm",
      memory_size: (config.memoryMb || 512) * 1024 * 1024,
      bios: { url: config.bios || "assets/v86/seabios.bin" },
      vga_bios: { url: config.vgaBios || "assets/v86/vgabios.bin" },
      bzimage: { url: config.bzImage || "assets/vmlinuz" },
      initrd: { url: config.initrd || "assets/initrd.img" },
      hda: { url: config.diskImage || "assets/alpine-linux.img", async: config.asyncDisk === true },
      cmdline,
      disable_keyboard: !vgaEnabled,
      disable_mouse: !vgaEnabled,
      disable_speaker: true,
      boot_order: 0x132,
      autostart: false
    };
    if (vgaEnabled) {
      vmOptions.vga_memory_size = (config.vgaMemoryMb || 8) * 1024 * 1024;
      vmOptions.screen_container = document.getElementById("screen_container");
    }
    if (serialEnabled) {
      if (!serialUseXterm || !serialXtermEl) {
        throw new Error("serial mode requires xterm.js assets (run make fetch-v86)");
      }
      vmOptions.uart1 = true;
      vmOptions.serial_console = {
        type: "xtermjs",
        container: serialXtermEl,
        xterm_lib: xtermCtor
      };
    } else {
      vmOptions.uart1 = false;
    }

    emulator = new window.V86(vmOptions);

    emulator.add_listener("emulator-ready", () => {
      setStatus("ready");
      if (serialEnabled && serialUseXterm) {
        const term = emulator?.serial_adapter?.term;
        if (term && typeof term.attachCustomKeyEventHandler === "function") {
          term.attachCustomKeyEventHandler((event) => {
            if (event.type !== "keydown") {
              return true;
            }
            if (!event.ctrlKey || event.altKey || event.metaKey) {
              return true;
            }
            const key = (event.key || "").toLowerCase();
            if (key === "c") {
              event.preventDefault();
              sendSerialBytes([0x03]);
              return false;
            }
            if (key === "d") {
              event.preventDefault();
              sendSerialBytes([0x04]);
              return false;
            }
            if (key === "l") {
              event.preventDefault();
              sendSerialBytes([0x0c]);
              return false;
            }
            if (key === "z") {
              event.preventDefault();
              sendSerialBytes([0x1a]);
              return false;
            }
            return true;
          });
        }
      }
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
    if (emulator?.serial_adapter?.term?.clear) {
      emulator.serial_adapter.term.clear();
    }
  });

  specialKeyButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const action = btn.getAttribute("data-special-key");
      if (!action) {
        return;
      }
      void sendSpecialKeys(action);
    });
  });

  if (!serialEnabled && serialPanelEl) {
    serialPanelEl.style.display = "none";
  } else if (serialEnabled) {
    if (serialHintEl) {
      serialHintEl.textContent = serialUseXterm
        ? "Serial backend: xterm.js (interactive)."
        : "xterm.js missing; run make fetch-v86.";
    }
  }
  if (vgaPanelEl && !vgaEnabled) {
    vgaPanelEl.style.display = "none";
  }

  setStatus("idle");
})();
