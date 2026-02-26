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
  const diskPanelEl = document.getElementById("disk-panel");
  const injectServerSrcEl = document.getElementById("inject-server-src");
  const injectDiskPathEl = document.getElementById("inject-disk-path");
  const injectDiskFileBtn = document.getElementById("inject-disk-file-btn");
  const clearBootImportsBtn = document.getElementById("clear-boot-imports-btn");
  const rootWatchToggleBtn = document.getElementById("root-watch-toggle");
  const rootWatchSecondsEl = document.getElementById("root-watch-seconds");
  const rootWatchStatusEl = document.getElementById("root-watch-status");
  const rootWatchListEl = document.getElementById("root-watch-list");
  const diskStatusEl = document.getElementById("disk-status");

  const defaultBootDiskImage = config.diskImage || "assets/buildroot-linux.img";

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
  let diskStateReady = Promise.resolve();
  let bootImports = [];
  let bootImportInFlight = false;
  let bootImportRetryTimer = null;
  let bootImportRetryStopTimer = null;
  let rootWatchEnabled = false;
  let rootWatchTimer = null;
  let rootWatchPending = false;
  let rootWatchBuffer = "";
  let rootWatchPendingTimer = null;
  let rootWatchKnownNames = new Set();
  let rootDownloadInFlight = false;
  let rootDownloadTargetName = "";
  let rootDownloadTimeout = null;
  let preferSerialCharStream = false;
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
  const MAX_RUNTIME_IMPORT_BYTES = 2 * 1024 * 1024;
  const ROOT_WATCH_BEGIN = "__NB_ROOTWATCH_BEGIN__";
  const ROOT_WATCH_END = "__NB_ROOTWATCH_END__";
  const ROOT_GET_BEGIN = "__NB_ROOTGET_BEGIN__";
  const ROOT_GET_END = "__NB_ROOTGET_END__";
  const ROOT_WATCH_BEGIN_PRINTF = markerToPrintfEscapes(ROOT_WATCH_BEGIN);
  const ROOT_WATCH_END_PRINTF = markerToPrintfEscapes(ROOT_WATCH_END);
  const ROOT_GET_BEGIN_PRINTF = markerToPrintfEscapes(ROOT_GET_BEGIN);
  const ROOT_GET_END_PRINTF = markerToPrintfEscapes(ROOT_GET_END);

  function setStatus(text) {
    statusEl.textContent = `status: ${text}`;
  }

  function setIps(text) {
    ipsEl.textContent = `instructions/sec: ${text}`;
  }

  function setDiskStatus(text) {
    if (!diskStatusEl) {
      return;
    }
    diskStatusEl.textContent = `disk: ${text}`;
  }

  function setRootWatchStatus(text) {
    if (!rootWatchStatusEl) {
      return;
    }
    rootWatchStatusEl.textContent = `monitor: ${text}`;
  }

  function updateRootWatchToggleButton() {
    if (!rootWatchToggleBtn) {
      return;
    }
    rootWatchToggleBtn.textContent = rootWatchEnabled ? "Stop /root Monitor" : "Start /root Monitor";
  }

  function rootWatchIntervalMs() {
    const raw = Number.parseInt(rootWatchSecondsEl?.value || "3", 10);
    const seconds = Number.isFinite(raw) ? Math.max(1, raw) : 3;
    if (rootWatchSecondsEl) {
      rootWatchSecondsEl.value = String(seconds);
    }
    return seconds * 1000;
  }

  function parentDiskPath(path) {
    if (typeof path !== "string" || path.length === 0 || path === "/") {
      return "/";
    }
    const trimmed = path.endsWith("/") ? path.slice(0, -1) : path;
    const idx = trimmed.lastIndexOf("/");
    if (idx <= 0) {
      return "/";
    }
    return trimmed.slice(0, idx);
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

  function shellQuote(value) {
    const raw = String(value);
    return `'${raw.replace(/'/g, `'\"'\"'`)}'`;
  }

  function normalizeGuestPath(inputPath, fallbackName) {
    const raw = String(inputPath || "").trim();
    const base = raw.length > 0 ? raw : `/root/${fallbackName}`;
    if (/[\x00\n\r]/.test(base)) {
      throw new Error("invalid destination path");
    }
    const absolute = base.startsWith("/") ? base : `/${base}`;
    const pieces = [];
    for (const segment of absolute.split("/")) {
      if (!segment || segment === ".") {
        continue;
      }
      if (segment === "..") {
        if (pieces.length > 0) {
          pieces.pop();
        }
        continue;
      }
      pieces.push(segment);
    }
    return `/${pieces.join("/")}`;
  }

  function normalizeServerSourcePath(src) {
    const value = String(src || "").trim();
    if (!value) {
      throw new Error("missing server source path");
    }
    if (/^https?:\/\//i.test(value)) {
      throw new Error("server source must be a local path");
    }
    if (/[\x00\n\r]/.test(value)) {
      throw new Error("invalid server source path");
    }
    return value.startsWith("/") ? value : `/${value}`;
  }

  function bytesToBase64(bytes) {
    let binary = "";
    const chunkSize = 0x8000;
    for (let i = 0; i < bytes.length; i += chunkSize) {
      const chunk = bytes.subarray(i, i + chunkSize);
      binary += String.fromCharCode(...chunk);
    }
    return btoa(binary);
  }

  function markerToPrintfEscapes(marker) {
    const chars = Array.from(String(marker || ""));
    return chars
      .map((ch) => `\\${ch.charCodeAt(0).toString(8).padStart(3, "0")}`)
      .join("");
  }

  function upsertBootImport(srcPath, targetPath) {
    const existingIndex = bootImports.findIndex((entry) => entry.targetPath === targetPath);
    const item = { srcPath, targetPath };
    if (existingIndex >= 0) {
      bootImports[existingIndex] = item;
    } else {
      bootImports.push(item);
    }
  }

  function clearBootImports() {
    bootImports = [];
    stopBootImportRetryLoop();
    setDiskStatus("cleared staged one-shot boot imports");
  }

  function buildRuntimeImportScript(targetPath, base64Data) {
    const parentPath = parentDiskPath(targetPath);
    const tempPath = `/tmp/.nixbrowser-import-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}.b64`;
    const encodedLines = base64Data.match(/.{1,76}/g) || [];
    return [
      `mkdir -p ${shellQuote(parentPath)} || exit 1`,
      `cat > ${shellQuote(tempPath)} <<'__NIXBROWSER_IMPORT_B64__'`,
      ...encodedLines,
      "__NIXBROWSER_IMPORT_B64__",
      `(base64 -d ${shellQuote(tempPath)} > ${shellQuote(targetPath)} || busybox base64 -d ${shellQuote(tempPath)} > ${shellQuote(targetPath)})`,
      "rc=$?",
      `rm -f ${shellQuote(tempPath)}`,
      "if [ \"$rc\" -eq 0 ]; then echo '[import] ok'; else echo '[import] failed'; fi"
    ].join("\n");
  }

  async function stageImportIntoRunningVm(srcPath, targetPath) {
    const sourceResp = await fetch(srcPath, { cache: "no-store" });
    if (!sourceResp.ok) {
      throw new Error(await readResponseError(sourceResp));
    }
    const sourceBytes = new Uint8Array(await sourceResp.arrayBuffer());
    if (sourceBytes.byteLength <= 0) {
      throw new Error("source file is empty");
    }
    if (sourceBytes.byteLength > MAX_RUNTIME_IMPORT_BYTES) {
      throw new Error(`source file exceeds runtime limit (${formatBytes(MAX_RUNTIME_IMPORT_BYTES)})`);
    }
    const payload = bytesToBase64(sourceBytes);
    const script = `${buildRuntimeImportScript(targetPath, payload)}\n`;
    if (!sendSerialText(script)) {
      throw new Error("serial console not available");
    }
    return sourceBytes.byteLength;
  }

  async function applyBootImportsToRunningVm(source = "manual") {
    if (!hasRunningVm() || bootImports.length === 0 || bootImportInFlight) {
      return;
    }
    bootImportInFlight = true;
    try {
      for (const entry of bootImports) {
        await stageImportIntoRunningVm(entry.srcPath, entry.targetPath);
      }
      if (source === "boot") {
        const applied = bootImports.length;
        bootImports = [];
        stopBootImportRetryLoop();
        setDiskStatus(`applied ${applied} one-shot boot import(s)`);
      } else {
        setDiskStatus(`import staged; ${bootImports.length} boot import(s) active`);
      }
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setDiskStatus(`runtime import failed (${msg})`);
      console.error(err);
    } finally {
      bootImportInFlight = false;
    }
  }

  function stopBootImportRetryLoop() {
    if (bootImportRetryTimer) {
      window.clearInterval(bootImportRetryTimer);
      bootImportRetryTimer = null;
    }
    if (bootImportRetryStopTimer) {
      window.clearTimeout(bootImportRetryStopTimer);
      bootImportRetryStopTimer = null;
    }
  }

  function startBootImportRetryLoop() {
    stopBootImportRetryLoop();
    if (bootImports.length === 0) {
      return;
    }
    const tick = () => {
      void applyBootImportsToRunningVm("boot");
    };
    tick();
    bootImportRetryTimer = window.setInterval(tick, 3000);
    bootImportRetryStopTimer = window.setTimeout(() => {
      stopBootImportRetryLoop();
    }, 30000);
  }

  function basename(path) {
    if (typeof path !== "string" || path.length === 0) {
      return "asset";
    }
    const parts = path.split("/").filter(Boolean);
    return parts.length > 0 ? parts[parts.length - 1] : path;
  }

  async function readResponseError(response) {
    if (!response) {
      return "request failed";
    }
    let body = "";
    try {
      body = await response.text();
    } catch (err) {
      body = "";
    }
    if (body) {
      try {
        const parsed = JSON.parse(body);
        if (parsed && typeof parsed.error === "string" && parsed.error.length > 0) {
          return parsed.error;
        }
      } catch (err) {
        // non-JSON response body; keep raw text
      }
      return body;
    }
    return `http ${response.status}`;
  }

  async function importServerFileIntoVmRoot() {
    const srcRaw = (injectServerSrcEl?.value || "").trim();
    if (!srcRaw) {
      setDiskStatus("enter a server file path (e.g. assets/tool.bin)");
      return;
    }
    let srcPath;
    let targetPath;
    try {
      srcPath = normalizeServerSourcePath(srcRaw);
      const sourceName = basename(srcPath) || "server-file.bin";
      targetPath = normalizeGuestPath(injectDiskPathEl?.value || "", sourceName);
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setDiskStatus(`invalid import request (${msg})`);
      return;
    }

    if (injectDiskFileBtn) {
      injectDiskFileBtn.disabled = true;
    }
    setDiskStatus(`staging ${srcPath} -> ${targetPath} (one-shot, non-persistent)...`);
    try {
      if (hasRunningVm()) {
        const size = await stageImportIntoRunningVm(srcPath, targetPath);
        setDiskStatus(`imported to running VM (${formatBytes(size)}); current boot only`);
        setStatus("running (one-shot import applied)");
        if (rootWatchEnabled) {
          window.setTimeout(() => {
            requestRootWatchScan();
          }, 500);
        }
      } else {
        upsertBootImport(srcPath, targetPath);
        setDiskStatus(`queued for next boot only (${bootImports.length} staged import(s))`);
        setStatus("idle (one-shot boot import queued)");
      }
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setDiskStatus(`import failed (${msg})`);
      console.error(err);
    } finally {
      if (injectDiskFileBtn) {
        injectDiskFileBtn.disabled = false;
      }
    }
  }

  async function refreshDiskStateFromServer() {
    if (!diskPanelEl) {
      return;
    }
    rootWatchKnownNames = new Set();
    if (rootWatchListEl) {
      rootWatchListEl.textContent = "";
    }
    updateRootWatchToggleButton();
    if (rootWatchEnabled) {
      setRootWatchStatus("waiting for VM start...");
    } else {
      setRootWatchStatus("idle");
    }
    if (bootImports.length > 0) {
      setDiskStatus(`one-shot boot imports queued: ${bootImports.length}`);
    } else {
      setDiskStatus("non-persistent one-shot mode: stage import, then start VM");
    }
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

  function sendSerialText(text) {
    const encoder = new TextEncoder();
    return sendSerialBytes(encoder.encode(text));
  }

  function renderRootWatchList(names, newNamesSet = new Set()) {
    if (!rootWatchListEl) {
      return;
    }
    rootWatchListEl.textContent = "";
    for (const name of names) {
      const item = document.createElement("li");
      const label = document.createElement("span");
      label.className = "disk-file-name";
      label.textContent = newNamesSet.has(name) ? `[new] ${name}` : name;
      item.appendChild(label);

      const actions = document.createElement("span");
      actions.className = "disk-file-actions";
      const downloadBtn = document.createElement("button");
      downloadBtn.type = "button";
      downloadBtn.textContent = "Download";
      downloadBtn.disabled = rootDownloadInFlight;
      downloadBtn.addEventListener("click", () => {
        void requestRootFileDownload(name);
      });
      actions.appendChild(downloadBtn);
      item.appendChild(actions);
      rootWatchListEl.appendChild(item);
    }
  }

  function stopRootWatchPolling() {
    if (rootWatchTimer) {
      window.clearInterval(rootWatchTimer);
      rootWatchTimer = null;
    }
    if (rootWatchPendingTimer) {
      window.clearTimeout(rootWatchPendingTimer);
      rootWatchPendingTimer = null;
    }
    rootWatchPending = false;
  }

  function refreshRootWatchPolling() {
    stopRootWatchPolling();
    if (!rootWatchEnabled || !hasRunningVm()) {
      return;
    }
    rootWatchTimer = window.setInterval(() => {
      requestRootWatchScan();
    }, rootWatchIntervalMs());
  }

  function requestRootWatchScan() {
    if (!rootWatchEnabled || !hasRunningVm() || rootWatchPending || rootDownloadInFlight) {
      return;
    }
    rootWatchPending = true;
    if (rootWatchPendingTimer) {
      window.clearTimeout(rootWatchPendingTimer);
    }
    rootWatchPendingTimer = window.setTimeout(() => {
      rootWatchPending = false;
      rootWatchPendingTimer = null;
      if (rootWatchEnabled) {
        setRootWatchStatus("scan timeout; retrying...");
      }
    }, 4000);

    const cmd = [
      "",
      `printf '${ROOT_WATCH_BEGIN_PRINTF}\\n'`,
      "for __nb_entry in /root/.??* /root/*; do",
      "  [ -e \"$__nb_entry\" ] || continue",
      "  __nb_name=\"${__nb_entry##*/}\"",
      "  printf '%s\\n' \"$__nb_name\"",
      "done",
      `printf '${ROOT_WATCH_END_PRINTF}\\n'`,
      ""
    ].join("\n");
    if (!sendSerialText(cmd)) {
      rootWatchPending = false;
      if (rootWatchPendingTimer) {
        window.clearTimeout(rootWatchPendingTimer);
        rootWatchPendingTimer = null;
      }
      setRootWatchStatus("monitor unavailable (serial not ready)");
    }
  }

  function decodeBase64Payload(payload) {
    const lines = String(payload || "")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line.length > 0);
    const normalized = lines
      .filter((line) => /^[A-Za-z0-9+/=]+$/.test(line))
      .join("");
    if (!normalized) {
      throw new Error("empty payload");
    }
    const binary = atob(normalized);
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      out[i] = binary.charCodeAt(i) & 0xff;
    }
    return out;
  }

  function triggerBrowserDownload(bytes, filename) {
    const blob = new Blob([bytes], { type: "application/octet-stream" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename || "root-file.bin";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => {
      URL.revokeObjectURL(url);
    }, 1000);
  }

  async function requestRootFileDownload(name) {
    if (!hasRunningVm()) {
      setRootWatchStatus("start VM first to download files");
      return;
    }
    if (rootDownloadInFlight) {
      setRootWatchStatus("download already in progress");
      return;
    }
    rootDownloadInFlight = true;
    rootDownloadTargetName = name;
    setRootWatchStatus(`downloading /root/${name}...`);
    if (rootDownloadTimeout) {
      window.clearTimeout(rootDownloadTimeout);
    }
    rootDownloadTimeout = window.setTimeout(() => {
      if (!rootDownloadInFlight) {
        return;
      }
      rootDownloadInFlight = false;
      rootDownloadTargetName = "";
      setRootWatchStatus("download timeout");
    }, 15000);

    const path = `/root/${name}`;
    const cmd = [
      "",
      `printf '${ROOT_GET_BEGIN_PRINTF}\\n'`,
      `(base64 < ${shellQuote(path)} 2>/dev/null || busybox base64 < ${shellQuote(path)} 2>/dev/null)`,
      `printf '\\n${ROOT_GET_END_PRINTF}\\n'`,
      ""
    ].join("\n");
    if (!sendSerialText(cmd)) {
      if (rootDownloadTimeout) {
        window.clearTimeout(rootDownloadTimeout);
        rootDownloadTimeout = null;
      }
      rootDownloadInFlight = false;
      rootDownloadTargetName = "";
      setRootWatchStatus("download failed (serial not ready)");
    }
  }

  function handleRootWatchPayload(payload) {
    const names = payload
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line.length > 0)
      .filter((line) => line !== "." && line !== "..");
    names.sort((a, b) => a.localeCompare(b));

    const nextSet = new Set(names);
    const newNames = names.filter((name) => !rootWatchKnownNames.has(name));
    rootWatchKnownNames = nextSet;
    renderRootWatchList(names, new Set(newNames));

    if (rootWatchPendingTimer) {
      window.clearTimeout(rootWatchPendingTimer);
      rootWatchPendingTimer = null;
    }
    rootWatchPending = false;
    const now = new Date().toLocaleTimeString();
    if (newNames.length > 0) {
      setRootWatchStatus(`${names.length} entries (${newNames.length} new) @ ${now}`);
    } else {
      setRootWatchStatus(`${names.length} entries @ ${now}`);
    }
  }

  function handleRootDownloadPayload(payload) {
    if (!rootDownloadInFlight) {
      return;
    }
    try {
      const bytes = decodeBase64Payload(payload);
      const filename = rootDownloadTargetName || "root-file.bin";
      triggerBrowserDownload(bytes, filename);
      setRootWatchStatus(`downloaded ${filename} (${formatBytes(bytes.byteLength)})`);
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setRootWatchStatus(`download failed (${msg})`);
    } finally {
      if (rootDownloadTimeout) {
        window.clearTimeout(rootDownloadTimeout);
        rootDownloadTimeout = null;
      }
      rootDownloadInFlight = false;
      rootDownloadTargetName = "";
      if (rootWatchEnabled) {
        requestRootWatchScan();
      }
    }
  }

  function consumeSerialMarkerBuffer() {
    while (true) {
      const watchIdx = rootWatchBuffer.indexOf(ROOT_WATCH_BEGIN);
      const getIdx = rootWatchBuffer.indexOf(ROOT_GET_BEGIN);
      let mode = "";
      let startIdx = -1;
      if (watchIdx >= 0 && (getIdx < 0 || watchIdx < getIdx)) {
        mode = "watch";
        startIdx = watchIdx;
      } else if (getIdx >= 0) {
        mode = "get";
        startIdx = getIdx;
      } else {
        if (rootWatchBuffer.length > 4096) {
          rootWatchBuffer = rootWatchBuffer.slice(-1024);
        }
        return;
      }

      if (startIdx > 0) {
        rootWatchBuffer = rootWatchBuffer.slice(startIdx);
      }

      const begin = mode === "watch" ? ROOT_WATCH_BEGIN : ROOT_GET_BEGIN;
      const end = mode === "watch" ? ROOT_WATCH_END : ROOT_GET_END;
      const endIdx = rootWatchBuffer.indexOf(end, begin.length);
      if (endIdx < 0) {
        if (rootWatchBuffer.length > 65536) {
          rootWatchBuffer = rootWatchBuffer.slice(0, begin.length);
        }
        return;
      }

      const payload = rootWatchBuffer.slice(begin.length, endIdx);
      rootWatchBuffer = rootWatchBuffer.slice(endIdx + end.length);

      if (mode === "watch") {
        handleRootWatchPayload(payload);
      } else {
        handleRootDownloadPayload(payload);
      }
    }
  }

  function appendSerialCaptureText(text) {
    if (!text) {
      return;
    }
    rootWatchBuffer += text;
    consumeSerialMarkerBuffer();
  }

  function handleSerialOutputByte(value) {
    if (preferSerialCharStream) {
      return;
    }
    if (typeof value !== "number" || !Number.isFinite(value)) {
      return;
    }
    appendSerialCaptureText(String.fromCharCode(value & 0xff));
  }

  function handleSerialOutputChar(value) {
    preferSerialCharStream = true;
    if (typeof value === "string") {
      appendSerialCaptureText(value);
      return;
    }
    if (typeof value === "number" && Number.isFinite(value)) {
      appendSerialCaptureText(String.fromCharCode(value & 0xff));
    }
  }

  function startRootMonitor() {
    rootWatchEnabled = true;
    updateRootWatchToggleButton();
    if (!hasRunningVm()) {
      setRootWatchStatus("waiting for VM start...");
      return;
    }
    setRootWatchStatus(`monitoring /root every ${rootWatchIntervalMs() / 1000}s`);
    refreshRootWatchPolling();
    requestRootWatchScan();
  }

  function stopRootMonitor() {
    rootWatchEnabled = false;
    updateRootWatchToggleButton();
    stopRootWatchPolling();
    setRootWatchStatus("idle");
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
    const rootDevice = typeof config.rootDevice === "string" && config.rootDevice.trim().length > 0
      ? config.rootDevice.trim()
      : "/dev/sda";
    const cdromBlacklist = cdromEnabled ? "" : " modprobe.blacklist=sr_mod,cdrom";
    const defaultCmdlineBase = `root=${rootDevice} rootfstype=${rootFsType} rw rootwait ip=off net.ifnames=0 mitigations=off${cdromBlacklist}`;
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
    const defaultAsync = config.asyncDisk === true;
    const bootDiskAsync = typeof config.asyncBootDisk === "boolean" ? config.asyncBootDisk : defaultAsync;

    const vmOptions = {
      wasm_path: config.wasmPath || "assets/v86/v86.wasm",
      memory_size: (config.memoryMb || 512) * 1024 * 1024,
      bios: { url: config.bios || "assets/v86/seabios.bin" },
      bzimage: { url: config.bzImage || "assets/vmlinuz" },
      initrd: { url: config.initrd || "assets/initrd.img" },
      hda: { url: defaultBootDiskImage, async: bootDiskAsync },
      cmdline,
      acpi: false,
      net_device: { type: netDeviceType },
      disable_keyboard: !vgaEnabled,
      disable_mouse: !mouseEnabled,
      disable_cdrom: !cdromEnabled,
      disable_speaker: true,
      uart1: false,
      uart2: false,
      uart3: false,
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
      vmOptions.serial_console = {
        type: "xtermjs",
        container: serialXtermEl,
        xterm_lib: xtermCtor
      };
    }

    emulator = new window.V86(vmOptions);

    emulator.add_listener("download-progress", (info) => {
      handleDownloadProgress(info);
    });

    emulator.add_listener("download-error", (info) => {
      handleDownloadError(info);
    });
    emulator.add_listener("serial0-output-byte", (value) => {
      handleSerialOutputByte(value);
    });
    emulator.add_listener("serial0-output-char", (value) => {
      handleSerialOutputChar(value);
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
      startBootImportRetryLoop();
      rootWatchBuffer = "";
      rootWatchKnownNames = new Set();
      preferSerialCharStream = false;
      if (rootWatchListEl) {
        rootWatchListEl.textContent = "";
      }
      if (rootWatchEnabled) {
        setRootWatchStatus(`monitoring /root every ${rootWatchIntervalMs() / 1000}s`);
        refreshRootWatchPolling();
        window.setTimeout(() => {
          requestRootWatchScan();
        }, 1500);
      }
    });

    emulator.add_listener("emulator-stopped", () => {
      setStatus("stopped");
      stopSampling();
      stopBootImportRetryLoop();
      stopRootWatchPolling();
      rootWatchBuffer = "";
      rootWatchKnownNames = new Set();
      preferSerialCharStream = false;
      if (rootWatchListEl) {
        rootWatchListEl.textContent = "";
      }
      if (rootDownloadTimeout) {
        window.clearTimeout(rootDownloadTimeout);
        rootDownloadTimeout = null;
      }
      rootDownloadInFlight = false;
      rootDownloadTargetName = "";
      if (rootWatchEnabled) {
        setRootWatchStatus("waiting for VM start...");
      }
    });

    return emulator;
  }

  startBtn.addEventListener("click", async () => {
    try {
      await diskStateReady;
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

  if (injectDiskFileBtn) {
    injectDiskFileBtn.addEventListener("click", () => {
      void importServerFileIntoVmRoot();
    });
  }
  if (injectServerSrcEl) {
    injectServerSrcEl.addEventListener("change", () => {
      if (!injectDiskPathEl) {
        return;
      }
      const src = injectServerSrcEl.value.trim();
      if (!src) {
        return;
      }
      const current = injectDiskPathEl.value.trim();
      if (current.length === 0) {
        const sourceName = src.split("/").filter(Boolean).pop() || "server-file.bin";
        injectDiskPathEl.value = `/root/${sourceName}`;
      }
    });
  }
  if (clearBootImportsBtn) {
    clearBootImportsBtn.addEventListener("click", () => {
      clearBootImports();
    });
  }
  if (rootWatchToggleBtn) {
    rootWatchToggleBtn.addEventListener("click", () => {
      if (rootWatchEnabled) {
        stopRootMonitor();
      } else {
        startRootMonitor();
      }
    });
  }
  if (rootWatchSecondsEl) {
    rootWatchSecondsEl.addEventListener("change", () => {
      if (rootWatchEnabled) {
        refreshRootWatchPolling();
        setRootWatchStatus(`monitoring /root every ${rootWatchIntervalMs() / 1000}s`);
      }
    });
  }
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

  if (diskPanelEl) {
    diskStateReady = refreshDiskStateFromServer();
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
