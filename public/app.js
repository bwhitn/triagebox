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
  const xtermFitAddonCtor = (() => {
    if (window.FitAddon && typeof window.FitAddon.FitAddon === "function") {
      return window.FitAddon.FitAddon;
    }
    if (window.XtermAddonFit && typeof window.XtermAddonFit.FitAddon === "function") {
      return window.XtermAddonFit.FitAddon;
    }
    if (typeof window.FitAddon === "function") {
      return window.FitAddon;
    }
    return null;
  })();
  const vgaEnabled = config.enableVga === true || (config.enableVga !== false && !serialEnabled);
  const mouseEnabled = config.enableMouse === true;
  const cdromEnabled = config.enableCdrom === true;

  const statusEl = document.getElementById("status");
  const ipsEl = document.getElementById("ips");
  const serialPanelEl = document.getElementById("serial-panel");
  const serialHintEl = document.getElementById("serial-hint");
  const serialXtermWrapEl = document.getElementById("serial-xterm-wrap");
  const serialXtermEl = document.getElementById("serial-xterm");
  const vgaPanelEl = document.getElementById("vga-panel");
  const specialKeyButtons = document.querySelectorAll("[data-special-key]");
  const serialUseXterm = serialEnabled && !!xtermCtor;

  const startBtn = document.getElementById("start");
  const stopBtn = document.getElementById("stop");
  const restartBtn = document.getElementById("restart");
  const clearSerialBtn = document.getElementById("clear-serial");
  const serialFullscreenBtn = document.getElementById("serial-fullscreen");
  const downloadPanelEl = document.getElementById("download-panel");
  const downloadStatusEl = document.getElementById("download-status");
  const downloadProgressEl = document.getElementById("download-progress");
  const downloadDetailEl = document.getElementById("download-detail");

  let emulator = null;
  let emulatorReadyPromise = null;
  let emulatorReadyResolve = null;
  let sampleTimer = null;
  let lastSampleTime = 0;
  let lastInstructionCount = 0;
  let serialResizeObserver = null;
  let serialResizeListenerBound = false;
  let serialFitRaf = 0;
  let serialFitAddon = null;
  let downloadHideTimer = null;
  let downloadFileProgress = new Map();
  let downloadFileCount = 0;
  let sawDownloadProgress = false;
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

  function isSerialFullscreen() {
    return !!serialXtermWrapEl && document.fullscreenElement === serialXtermWrapEl;
  }

  function updateSerialFullscreenButton() {
    if (!serialFullscreenBtn) {
      return;
    }
    serialFullscreenBtn.textContent = isSerialFullscreen() ? "Exit Fullscreen" : "Fullscreen";
  }

  async function enterSerialFullscreen() {
    if (!serialXtermWrapEl) {
      return;
    }
    const request = serialXtermWrapEl.requestFullscreen || serialXtermWrapEl.webkitRequestFullscreen;
    if (typeof request !== "function") {
      throw new Error("fullscreen api not supported in this browser");
    }
    await request.call(serialXtermWrapEl);
  }

  async function exitAnyFullscreen() {
    const exit = document.exitFullscreen || document.webkitExitFullscreen;
    if (typeof exit !== "function") {
      throw new Error("fullscreen api not supported in this browser");
    }
    await exit.call(document);
  }

  async function toggleSerialFullscreen() {
    try {
      if (isSerialFullscreen()) {
        await exitAnyFullscreen();
      } else {
        await enterSerialFullscreen();
      }
      updateSerialFullscreenButton();
      scheduleSerialFit();
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setStatus(`error (${msg})`);
      console.error(err);
    }
  }

  function setDownloadVisible(visible) {
    if (!downloadPanelEl) {
      return;
    }
    downloadPanelEl.classList.toggle("active", visible);
  }

  function setDownloadStatus(text) {
    if (!downloadStatusEl) {
      return;
    }
    downloadStatusEl.textContent = `download: ${text}`;
  }

  function setDownloadDetail(text) {
    if (!downloadDetailEl) {
      return;
    }
    downloadDetailEl.textContent = text;
  }

  function setDownloadProgress(percent) {
    if (!downloadProgressEl) {
      return;
    }
    const bounded = Math.max(0, Math.min(100, Math.round(percent)));
    downloadProgressEl.value = bounded;
  }

  function clearDownloadHideTimer() {
    if (downloadHideTimer) {
      clearTimeout(downloadHideTimer);
      downloadHideTimer = null;
    }
  }

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes < 0) {
      return "n/a";
    }
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KiB`;
    }
    if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MiB`;
    }
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GiB`;
  }

  function basename(path) {
    if (typeof path !== "string" || path.length === 0) {
      return "asset";
    }
    const parts = path.split("/").filter(Boolean);
    return parts.length > 0 ? parts[parts.length - 1] : path;
  }

  function beginDownloadMeter() {
    clearDownloadHideTimer();
    downloadFileProgress = new Map();
    downloadFileCount = 0;
    sawDownloadProgress = false;
    setDownloadVisible(true);
    setDownloadProgress(0);
    setDownloadStatus("starting");
    setDownloadDetail("waiting for asset downloads...");
  }

  function handleDownloadProgress(info) {
    const evt = info && typeof info === "object" ? info : {};
    sawDownloadProgress = true;
    clearDownloadHideTimer();
    setDownloadVisible(true);

    if (Number.isFinite(evt.file_count) && evt.file_count > 0) {
      downloadFileCount = evt.file_count;
    }

    const index = Number.isFinite(evt.file_index) ? evt.file_index : downloadFileProgress.size;
    const loaded = Number.isFinite(evt.loaded) ? Math.max(0, evt.loaded) : 0;
    const total = Number.isFinite(evt.total) ? Math.max(0, evt.total) : 0;
    const computable = evt.lengthComputable === true && total > 0;
    const fileName = typeof evt.file_name === "string" ? evt.file_name : "";

    downloadFileProgress.set(index, { loaded, total, computable, fileName });

    let knownLoaded = 0;
    let knownTotal = 0;
    downloadFileProgress.forEach((entry) => {
      if (entry.computable) {
        knownLoaded += Math.min(entry.loaded, entry.total);
        knownTotal += entry.total;
      }
    });

    if (knownTotal > 0) {
      setDownloadProgress((knownLoaded / knownTotal) * 100);
    }

    const fileNumber = Number.isFinite(evt.file_index) ? (evt.file_index + 1) : downloadFileProgress.size;
    const fileCount = downloadFileCount > 0 ? downloadFileCount : downloadFileProgress.size;
    const displayFile = fileCount > 0 ? Math.min(fileNumber, fileCount) : fileNumber;
    setDownloadStatus(`loading ${displayFile}/${Math.max(fileCount, 1)}`);

    const name = basename(fileName);
    if (computable) {
      const filePercent = Math.round((loaded / total) * 100);
      setDownloadDetail(`${name}: ${filePercent}% (${formatBytes(loaded)} / ${formatBytes(total)})`);
    } else {
      setDownloadDetail(`${name}: ${formatBytes(loaded)} downloaded`);
    }
  }

  function handleDownloadError(info) {
    const evt = info && typeof info === "object" ? info : {};
    clearDownloadHideTimer();
    setDownloadVisible(true);
    setDownloadStatus("error");
    setDownloadDetail(`failed to fetch ${basename(evt.file_name)}`);
  }

  function completeDownloadMeter() {
    clearDownloadHideTimer();
    setDownloadVisible(true);
    setDownloadProgress(100);
    if (sawDownloadProgress) {
      setDownloadStatus("complete");
      setDownloadDetail("all vm assets loaded");
    } else {
      setDownloadStatus("complete (cached)");
      setDownloadDetail("assets already available");
    }
    downloadHideTimer = window.setTimeout(() => {
      downloadHideTimer = null;
      setDownloadVisible(false);
    }, 1200);
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

  function fitSerialTerminal() {
    if (!serialEnabled || !serialUseXterm || !serialXtermEl || !emulator?.serial_adapter?.term) {
      return;
    }

    const term = emulator.serial_adapter.term;
    if (serialFitAddon && typeof serialFitAddon.fit === "function") {
      serialFitAddon.fit();
      return;
    }

    // Fallback path when xterm-addon-fit is unavailable.
    const dims = term?._core?._renderService?.dimensions?.css;
    const cellWidth = dims?.cell?.width || 0;
    const cellHeight = dims?.cell?.height || 0;
    const viewportWidth = serialXtermEl.clientWidth;
    const viewportHeight = serialXtermEl.clientHeight;

    if (cellWidth <= 0 || cellHeight <= 0 || viewportWidth <= 0 || viewportHeight <= 0) {
      return;
    }

    const cols = Math.max(20, Math.floor(viewportWidth / cellWidth));
    const rows = Math.max(5, Math.floor(viewportHeight / cellHeight));

    if (term.cols !== cols || term.rows !== rows) {
      term.resize(cols, rows);
    }
  }

  function scheduleSerialFit() {
    if (serialFitRaf) {
      cancelAnimationFrame(serialFitRaf);
    }
    serialFitRaf = requestAnimationFrame(() => {
      serialFitRaf = 0;
      fitSerialTerminal();
    });
  }

  function setupSerialResizeHandling() {
    if (!serialEnabled || !serialUseXterm || !serialXtermEl) {
      return;
    }

    const observeTarget = serialXtermWrapEl || serialXtermEl;
    if (!serialResizeObserver && typeof ResizeObserver === "function") {
      serialResizeObserver = new ResizeObserver(() => {
        scheduleSerialFit();
      });
      serialResizeObserver.observe(observeTarget);
    }

    if (!serialResizeListenerBound) {
      window.addEventListener("resize", scheduleSerialFit);
      serialResizeListenerBound = true;
    }

    scheduleSerialFit();
    setTimeout(scheduleSerialFit, 80);
    setTimeout(scheduleSerialFit, 250);
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

    const rootFsType = typeof config.rootFsType === "string" && config.rootFsType.trim().length > 0
      ? config.rootFsType.trim()
      : "ext4";
    const cdromBlacklist = cdromEnabled ? "" : " modprobe.blacklist=sr_mod,cdrom";
    const defaultCmdlineBase = `root=LABEL=rootfs rootfstype=${rootFsType} rw rootwait init=/usr/local/sbin/v86-init ip=off net.ifnames=0${cdromBlacklist}`;
    const defaultCmdlineNoSerial = `${defaultCmdlineBase} console=tty0`;
    const defaultCmdlineSerial = vgaEnabled
      ? `${defaultCmdlineBase} console=ttyS0 console=tty0`
      : `${defaultCmdlineBase} console=ttyS0`;
    const cmdline = typeof config.cmdline === "string" && config.cmdline.trim().length > 0
      ? config.cmdline
      : (serialEnabled ? defaultCmdlineSerial : defaultCmdlineNoSerial);
    const networkRelayUrl = typeof config.networkRelayUrl === "string" && config.networkRelayUrl.trim().length > 0
      ? config.networkRelayUrl.trim()
      : "";
    const netDeviceType = typeof config.netDeviceType === "string" && config.netDeviceType.trim().length > 0
      ? config.netDeviceType.trim().toLowerCase()
      : ((config.enableEthernet === true || networkRelayUrl.length > 0) ? "ne2k" : "none");

    const vmOptions = {
      wasm_path: config.wasmPath || "assets/v86/v86.wasm",
      memory_size: (config.memoryMb || 512) * 1024 * 1024,
      bios: { url: config.bios || "assets/v86/seabios.bin" },
      bzimage: { url: config.bzImage || "assets/vmlinuz" },
      initrd: { url: config.initrd || "assets/initrd.img" },
      hda: { url: config.diskImage || "assets/buildroot-linux.img", async: config.asyncDisk === true },
      cmdline,
      net_device: { type: netDeviceType },
      disable_keyboard: !vgaEnabled,
      disable_mouse: !mouseEnabled,
      disable_cdrom: !cdromEnabled,
      disable_speaker: true,
      boot_order: 0x132,
      autostart: false
    };
    if (netDeviceType === "none") {
      vmOptions.disable_ne2k = true;
    }
    if (vgaEnabled) {
      vmOptions.vga_bios = { url: config.vgaBios || "assets/v86/vgabios.bin" };
      vmOptions.vga_memory_size = (config.vgaMemoryMb || 8) * 1024 * 1024;
      vmOptions.screen_container = document.getElementById("screen_container");
    }
    if (networkRelayUrl.length > 0 && netDeviceType !== "none") {
      vmOptions.network_relay_url = networkRelayUrl;
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

    emulator.add_listener("download-progress", (info) => {
      handleDownloadProgress(info);
    });

    emulator.add_listener("download-error", (info) => {
      handleDownloadError(info);
    });

    emulator.add_listener("emulator-ready", () => {
      setStatus("ready");
      completeDownloadMeter();
      setupSerialResizeHandling();
      if (serialEnabled && serialUseXterm) {
        const term = emulator?.serial_adapter?.term;
        if (!serialFitAddon && xtermFitAddonCtor && term && typeof term.loadAddon === "function") {
          try {
            serialFitAddon = new xtermFitAddonCtor();
            term.loadAddon(serialFitAddon);
          } catch (err) {
            serialFitAddon = null;
            console.warn("failed to load xterm fit addon", err);
          }
        }
        scheduleSerialFit();
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
      if (!emulator) {
        beginDownloadMeter();
      }
      const vm = ensureEmulator();
      if (emulatorReadyPromise) {
        await emulatorReadyPromise;
      }
      await vm.run();
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setStatus(`error (${msg})`);
      setDownloadVisible(true);
      setDownloadStatus("error");
      setDownloadDetail(msg);
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

  if (serialFullscreenBtn) {
    serialFullscreenBtn.addEventListener("click", () => {
      void toggleSerialFullscreen();
    });
  }

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

  document.addEventListener("fullscreenchange", () => {
    updateSerialFullscreenButton();
    scheduleSerialFit();
  });
  document.addEventListener("webkitfullscreenchange", () => {
    updateSerialFullscreenButton();
    scheduleSerialFit();
  });
  updateSerialFullscreenButton();

  setStatus("idle");
})();
