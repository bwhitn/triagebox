((global) => {
  function resolveMountElement(rootEl, explicit, fallbackId) {
    if (explicit && typeof explicit === "object" && explicit.nodeType === 1) {
      return explicit;
    }
    if (typeof explicit === "string" && explicit.trim().length > 0) {
      const selector = explicit.trim();
      if (rootEl && typeof rootEl.querySelector === "function") {
        const localMatch = rootEl.matches && rootEl.matches(selector) ? rootEl : rootEl.querySelector(selector);
        if (localMatch) {
          return localMatch;
        }
      }
      return document.querySelector(selector);
    }
    if (!fallbackId) {
      return null;
    }
    if (rootEl && rootEl.id === fallbackId) {
      return rootEl;
    }
    if (rootEl && typeof rootEl.querySelector === "function") {
      const localMatch = rootEl.querySelector(`#${fallbackId}`);
      if (localMatch) {
        return localMatch;
      }
    }
    return document.getElementById(fallbackId);
  }

  function createTriageBox(options = {}) {
  const rootEl = options.rootEl && typeof options.rootEl === "object" ? options.rootEl : null;
  const elements = options.elements || {};
  const config = Object.assign({}, global.V86_VM_CONFIG || {}, global.V86_BUILD_CONFIG || {}, options.config || {});
  const embedCommon = global.TriageBoxEmbedCommon || {};
  const parseEmbedConfig = typeof embedCommon.parseEmbedConfig === "function"
    ? embedCommon.parseEmbedConfig
    : (() => ({ embedMode: false, autostart: false, autoloadSrc: "", autoloadDst: "", allowedParentOrigins: [] }));
  const parseBooleanFlag = typeof embedCommon.parseBooleanFlag === "function"
    ? embedCommon.parseBooleanFlag
    : ((value, fallback) => {
      if (value === undefined || value === null || String(value).trim() === "") {
        return fallback;
      }
      return String(value).trim() === "1";
    });
  const toApiErrorPayload = typeof embedCommon.toApiErrorPayload === "function"
    ? embedCommon.toApiErrorPayload
    : ((error, code) => ({
      code: code || "UNKNOWN_ERROR",
      message: error && error.message ? error.message : String(error || "unknown error")
    }));
  const validateCommandEnvelope = typeof embedCommon.validateCommandEnvelope === "function"
    ? embedCommon.validateCommandEnvelope
    : ((message) => {
      if (!message || typeof message !== "object" || message.type !== "tb.command") {
        throw new Error("invalid command envelope");
      }
      return {
        id: String(message.id || ""),
        command: String(message.command || ""),
        payload: message.payload && typeof message.payload === "object" ? message.payload : {}
      };
    });
  const sanitizeRootPath = typeof embedCommon.sanitizeRootPath === "function"
    ? embedCommon.sanitizeRootPath
    : ((path) => {
      const value = String(path || "").trim();
      if (!value.startsWith("/root/")) {
        throw new Error("path must be under /root");
      }
      return value;
    });
  const sanitizeAutoloadDst = typeof embedCommon.sanitizeAutoloadDst === "function"
    ? embedCommon.sanitizeAutoloadDst
    : ((dst) => `/root/${String(dst || "").split("/").filter(Boolean).pop() || "autoload.bin"}`);
  const resolveAutoloadSource = typeof embedCommon.resolveAutoloadSource === "function"
    ? embedCommon.resolveAutoloadSource
    : ((src) => String(src || "").trim());
  const isAllowedOrigin = typeof embedCommon.isAllowedOrigin === "function"
    ? embedCommon.isAllowedOrigin
    : ((origin, allowed) => Array.isArray(allowed) && allowed.includes(origin));
  const normalizeRootRecordList = typeof embedCommon.normalizeRootRecordList === "function"
    ? embedCommon.normalizeRootRecordList
    : ((records) => Array.isArray(records) ? records : []);
  const rootRecordListSignature = typeof embedCommon.rootRecordListSignature === "function"
    ? embedCommon.rootRecordListSignature
    : ((records) => JSON.stringify(records || []));
  const API_VERSION = typeof embedCommon.API_VERSION === "string" ? embedCommon.API_VERSION : "1.0";
  const API_CAPABILITIES = Array.isArray(embedCommon.CAPABILITIES)
    ? embedCommon.CAPABILITIES.slice()
    : ["start", "stop", "inject", "list_root", "download"];

  const pageTitleEl = resolveMountElement(rootEl, elements.pageTitle, "page-title");
  const screenContainerEl = resolveMountElement(rootEl, elements.screenContainer, "screen_container");
  const embedStatusBarEl = resolveMountElement(rootEl, elements.embedStatusBar, "embed-status-bar");
  const PAGE_TITLE = typeof options.pageTitle === "string" && options.pageTitle.trim().length > 0
    ? options.pageTitle.trim()
    : "TriageBox Linux v86 Test Rig";
  const shouldApplyPageTitle = options.setDocumentTitle !== false;
  const embedConfig = parseEmbedConfig(global.location ? global.location.search : "", {
    configParentOrigins: config.parentOrigins || "",
    referrer: document.referrer || "",
    locationOrigin: global.location ? global.location.origin : ""
  });
  const embedMode = options.embedMode === true || embedConfig.embedMode === true;
  const serialEnabled = config.enableSerial === true;
  const sameOriginOnlyAutoload = parseBooleanFlag(config.autoloadAllowCrossOrigin, false) !== true;
  const autoloadTimeoutMs = Number.parseInt(String(config.autoloadTimeoutMs || "30000"), 10) || 30000;
  const startupTimeoutMs = Number.parseInt(String(config.startupTimeoutMs || "30000"), 10) || 30000;
  const postMessageEnabled = config.enablePostMessageApi !== false;
  const allowedParentOrigins = Array.isArray(embedConfig.allowedParentOrigins)
    ? embedConfig.allowedParentOrigins.slice()
    : [];
  const xtermCtor = (() => {
    if (typeof global.Terminal === "function") {
      return global.Terminal;
    }
    if (global.Xterm && typeof global.Xterm.Terminal === "function") {
      return global.Xterm.Terminal;
    }
    return null;
  })();
  const xtermFitAddonCtor = (() => {
    if (global.FitAddon && typeof global.FitAddon.FitAddon === "function") {
      return global.FitAddon.FitAddon;
    }
    if (global.XtermAddonFit && typeof global.XtermAddonFit.FitAddon === "function") {
      return global.XtermAddonFit.FitAddon;
    }
    if (typeof global.FitAddon === "function") {
      return global.FitAddon;
    }
    return null;
  })();
  const vgaEnabled = config.enableVga === true || (config.enableVga !== false && !serialEnabled);
  const mouseEnabled = config.enableMouse === true;
  const cdromEnabled = config.enableCdrom === true;
  const rootExchangeEnabled = config.enableRootExchange !== false;

  const statusEl = resolveMountElement(rootEl, elements.status, "status");
  const ipsEl = resolveMountElement(rootEl, elements.ips, "ips");
  const serialPanelEl = resolveMountElement(rootEl, elements.serialPanel, "serial-panel");
  const serialHintEl = resolveMountElement(rootEl, elements.serialHint, "serial-hint");
  const serialXtermWrapEl = resolveMountElement(rootEl, elements.serialXtermWrap, "serial-xterm-wrap");
  const serialXtermEl = resolveMountElement(rootEl, elements.serialXterm, "serial-xterm");
  const vgaPanelEl = resolveMountElement(rootEl, elements.vgaPanel, "vga-panel");
  const serialUseXterm = serialEnabled && !!xtermCtor;

  const startBtn = resolveMountElement(rootEl, elements.start, "start");
  const stopBtn = resolveMountElement(rootEl, elements.stop, "stop");
  const downloadPanelEl = resolveMountElement(rootEl, elements.downloadPanel, "download-panel");
  const downloadStatusEl = resolveMountElement(rootEl, elements.downloadStatus, "download-status");
  const downloadProgressEl = resolveMountElement(rootEl, elements.downloadProgress, "download-progress");
  const downloadDetailEl = resolveMountElement(rootEl, elements.downloadDetail, "download-detail");
  const diskPanelEl = resolveMountElement(rootEl, elements.diskPanel, "disk-panel");
  const injectServerSrcEl = resolveMountElement(rootEl, elements.injectServerSrc, "inject-server-src");
  const injectDiskPathEl = resolveMountElement(rootEl, elements.injectDiskPath, "inject-disk-path");
  const injectDiskFileBtn = resolveMountElement(rootEl, elements.injectDiskFileBtn, "inject-disk-file-btn");
  const clearBootImportsBtn = resolveMountElement(rootEl, elements.clearBootImportsBtn, "clear-boot-imports-btn");
  const rootWatchStatusEl = resolveMountElement(rootEl, elements.rootWatchStatus, "root-watch-status");
  const rootWatchListEl = resolveMountElement(rootEl, elements.rootWatchList, "root-watch-list");
  const diskStatusEl = resolveMountElement(rootEl, elements.diskStatus, "disk-status");

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
  let rootWatchTimer = null;
  let rootWatchPending = false;
  let rootWatchKnownNames = new Set();
  let rootWatchStatusHoldUntil = 0;
  let rootDownloadInFlight = false;
  let lastRootRecordsSignature = "";
  let lastRootRecords = [];
  let vmStartedResolvers = [];
  const parentMessageChannels = [];
  let defaultEventTargetOrigin = allowedParentOrigins.length > 0
    ? allowedParentOrigins[0]
    : (global.location ? global.location.origin : "");
  const issuedDownloadUrls = new Set();
  const ROOT_SHARE_TOTAL_BYTES = (() => {
    const raw = Number.parseInt(String(config.rootExchangeSizeMb ?? "1024"), 10);
    const mb = Number.isFinite(raw) ? Math.max(64, raw) : 1024;
    return mb * 1024 * 1024;
  })();

  let currentStatusText = "idle";
  let currentIpsText = "n/a";
  const MAX_RUNTIME_IMPORT_BYTES = 2 * 1024 * 1024;
  const ROOT_SHARE_PREFIX = "/root";
  const ROOT_WATCH_INTERVAL_MS = (() => {
    const raw = Number.parseInt(String(config.rootWatchSeconds ?? "3"), 10);
    const seconds = Number.isFinite(raw) ? Math.max(1, raw) : 3;
    return seconds * 1000;
  })();

  function applyPageTitle() {
    if (shouldApplyPageTitle) {
      document.title = PAGE_TITLE;
    }
    if (pageTitleEl) {
      pageTitleEl.textContent = PAGE_TITLE;
    }
  }

  applyPageTitle();

  function setStatus(text) {
    currentStatusText = text;
    if (statusEl) {
      statusEl.textContent = `status: ${text}`;
    }
    if (embedStatusBarEl) {
      embedStatusBarEl.textContent = `status: ${currentStatusText} | ips: ${currentIpsText}`;
    }
  }

  function setIps(text) {
    currentIpsText = text;
    if (ipsEl) {
      ipsEl.textContent = `instructions/sec: ${text}`;
    }
    if (embedStatusBarEl) {
      embedStatusBarEl.textContent = `status: ${currentStatusText} | ips: ${currentIpsText}`;
    }
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

  function rootWatchIntervalMs() {
    return ROOT_WATCH_INTERVAL_MS;
  }

  function rememberParentChannel(targetWindow, origin) {
    if (!targetWindow || typeof origin !== "string" || !origin) {
      return;
    }
    const existing = parentMessageChannels.find((entry) => entry.origin === origin && entry.target === targetWindow);
    if (existing) {
      return;
    }
    parentMessageChannels.push({ target: targetWindow, origin });
  }

  function postEnvelopeToParent(envelope, target, origin) {
    if (!target || typeof target.postMessage !== "function" || typeof origin !== "string" || !origin) {
      return;
    }
    try {
      target.postMessage(envelope, origin);
    } catch (err) {
      console.warn("postMessage send failed", err);
    }
  }

  function emitApiEvent(eventName, payload = {}) {
    if (!postMessageEnabled || !global.parent || global.parent === global) {
      return;
    }
    const envelope = {
      type: "tb.event",
      event: eventName,
      payload
    };

    let sent = false;
    for (const channel of parentMessageChannels) {
      postEnvelopeToParent(envelope, channel.target, channel.origin);
      sent = true;
    }

    if (!sent && defaultEventTargetOrigin) {
      postEnvelopeToParent(envelope, global.parent, defaultEventTargetOrigin);
    }
  }

  function sendApiResponse(targetWindow, origin, id, ok, payload, errorPayload) {
    if (!postMessageEnabled || !targetWindow || typeof targetWindow.postMessage !== "function") {
      return;
    }
    const response = {
      type: "tb.response",
      id: String(id || ""),
      ok: !!ok
    };
    if (ok) {
      response.payload = payload && typeof payload === "object" ? payload : {};
    } else {
      const errObj = errorPayload && typeof errorPayload === "object" ? errorPayload : { code: "UNKNOWN_ERROR", message: "command failed" };
      response.error = errObj.message || "command failed";
      response.payload = errObj;
    }
    postEnvelopeToParent(response, targetWindow, origin);
  }

  function emitApiError(error, context) {
    const errPayload = toApiErrorPayload(error, "UNKNOWN_ERROR");
    if (context && typeof context === "object") {
      errPayload.context = context;
    }
    emitApiEvent("error", errPayload);
    return errPayload;
  }

  if (embedMode && document.body) {
    document.body.classList.add("embed-mode");
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

  function normalizeServerSourcePath(src, options = {}) {
    return resolveAutoloadSource(src, {
      baseUrl: global.location ? global.location.href : undefined,
      baseOrigin: global.location ? global.location.origin : "",
      allowCrossOrigin: options.allowCrossOrigin === true ? true : !sameOriginOnlyAutoload
    });
  }

  function hasFilesystemBridge() {
    return !!(
      rootExchangeEnabled &&
      emulator &&
      emulator.fs9p &&
      typeof emulator.create_file === "function" &&
      typeof emulator.read_file === "function"
    );
  }

  function applyRootShareTotalSize() {
    if (!rootExchangeEnabled) {
      return;
    }
    const fs = emulator?.fs9p;
    if (!fs || typeof fs !== "object") {
      return;
    }
    if (!Number.isFinite(ROOT_SHARE_TOTAL_BYTES) || ROOT_SHARE_TOTAL_BYTES <= 0) {
      return;
    }
    fs.total_size = ROOT_SHARE_TOTAL_BYTES;
    if (Number.isFinite(fs.used_size) && fs.used_size > fs.total_size) {
      fs.total_size = fs.used_size;
    }
  }

  function toRootSharePath(targetPath) {
    const normalized = normalizeGuestPath(targetPath || "", "");
    if (normalized === ROOT_SHARE_PREFIX || !normalized.startsWith(`${ROOT_SHARE_PREFIX}/`)) {
      throw new Error("destination path must be under /root");
    }
    return normalized.slice(ROOT_SHARE_PREFIX.length);
  }

  function ensureRootShareParentDirectory(sharePath) {
    const fs = emulator?.fs9p;
    if (!fs || typeof fs.Search !== "function" || typeof fs.CreateDirectory !== "function" || typeof fs.GetInode !== "function") {
      throw new Error("filesystem bridge unavailable");
    }
    const parent = parentDiskPath(sharePath);
    const segments = parent.split("/").filter(Boolean);
    let currentId = 0;
    for (const segment of segments) {
      let nextId = fs.Search(currentId, segment);
      if (nextId === -1) {
        nextId = fs.CreateDirectory(segment, currentId);
      }
      const inode = fs.GetInode(nextId);
      if (!inode || (inode.mode & 0xF000) !== 0x4000) {
        throw new Error(`parent path is not a directory: ${segment}`);
      }
      currentId = nextId;
    }
  }

  function inodeEpochSeconds(inode) {
    const candidates = [
      inode && inode.mtime,
      inode && inode.ctime,
      inode && inode.atime,
      inode && inode.mtime_sec,
      inode && inode.ctime_sec,
      inode && inode.atime_sec
    ];
    for (const candidate of candidates) {
      if (Number.isFinite(candidate)) {
        if (candidate > 1e12) {
          return Math.floor(candidate / 1000);
        }
        if (candidate >= 0) {
          return Math.floor(candidate);
        }
      }
    }
    return 0;
  }

  function inodeKind(inode) {
    const mode = Number.isFinite(inode && inode.mode) ? inode.mode : 0;
    if ((mode & 0xF000) === 0x4000) {
      return "dir";
    }
    return "file";
  }

  function listRootShareRecords() {
    const fs = emulator?.fs9p;
    if (!fs || typeof fs.read_dir !== "function" || typeof fs.SearchPath !== "function" || typeof fs.GetInode !== "function") {
      throw new Error("filesystem bridge unavailable");
    }
    const pending = [{ sharePath: "/", relativePath: "" }];
    const records = [];
    while (pending.length > 0) {
      const node = pending.pop();
      const entries = fs.read_dir(node.sharePath) || [];
      for (const name of entries) {
        if (typeof name !== "string" || name.length === 0 || name.includes("/")) {
          continue;
        }
        const sharePath = node.sharePath === "/" ? `/${name}` : `${node.sharePath}/${name}`;
        const found = fs.SearchPath(sharePath);
        if (!found || found.id === -1) {
          continue;
        }
        const inode = fs.GetInode(found.id);
        if (!inode) {
          continue;
        }
        const rel = node.relativePath ? `${node.relativePath}/${name}` : name;
        const kind = inodeKind(inode);
        records.push({
          name,
          path: `/root/${rel}`,
          size: Number.isFinite(inode && inode.size) ? Math.max(0, Math.floor(inode.size)) : 0,
          mtime_epoch: inodeEpochSeconds(inode),
          sha256: null,
          kind
        });
        if (kind === "dir") {
          pending.push({ sharePath, relativePath: rel });
        }
      }
    }
    const normalized = normalizeRootRecordList(records);
    return normalized;
  }

  function listRootShareRegularFiles() {
    const records = listRootShareRecords();
    const files = records
      .filter((record) => record.kind === "file")
      .map((record) => record.path.replace(/^\/root\//, ""));
    files.sort((a, b) => a.localeCompare(b));
    return files;
  }

  async function fetchServerSourceBytes(srcPath, options = {}) {
    const resolvedSource = normalizeServerSourcePath(srcPath, options);
    const sourceResp = await fetch(resolvedSource, { cache: "no-store", credentials: "same-origin" });
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
    return { sourceBytes, resolvedSource };
  }

  async function writeBytesToVmRootShare(targetPath, bytes, overwrite = true) {
    if (!hasFilesystemBridge()) {
      throw new Error("filesystem bridge not ready");
    }
    const fs = emulator.fs9p;
    const sharePath = toRootSharePath(targetPath);
    ensureRootShareParentDirectory(sharePath);
    if (typeof fs.SearchPath === "function" && typeof fs.GetInode === "function" && typeof fs.DeleteNode === "function") {
      const existing = fs.SearchPath(sharePath);
      if (existing && existing.id !== -1) {
        const inode = fs.GetInode(existing.id);
        if (inode && (inode.mode & 0xF000) === 0x4000) {
          throw new Error("destination exists as directory");
        }
        if (!overwrite) {
          throw Object.assign(new Error("destination file already exists"), { code: "DEST_EXISTS" });
        }
        fs.DeleteNode(sharePath);
      }
    }
    await emulator.create_file(sharePath, bytes);
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
    setDiskStatus("cleared staged one-shot boot imports");
  }

  async function stageImportIntoRunningVm(srcPath, targetPath, options = {}) {
    const { sourceBytes, resolvedSource } = await fetchServerSourceBytes(srcPath, options);
    const overwrite = options.overwrite !== false;
    await writeBytesToVmRootShare(targetPath, sourceBytes, overwrite);
    return { size: sourceBytes.byteLength, resolvedSource };
  }

  async function applyBootImportsToVm(source = "manual") {
    if (bootImports.length === 0 || bootImportInFlight) {
      return;
    }
    if (!hasFilesystemBridge()) {
      if (source === "boot" || source === "boot-prestart") {
        throw new Error("filesystem bridge not ready");
      }
      return;
    }
    bootImportInFlight = true;
    try {
      for (const entry of bootImports) {
        await stageImportIntoRunningVm(entry.srcPath, entry.targetPath);
      }
      if (source === "boot" || source === "boot-prestart") {
        const applied = bootImports.length;
        bootImports = [];
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

  function basename(path) {
    if (typeof path !== "string" || path.length === 0) {
      return "asset";
    }
    try {
      const parsed = new URL(path, global.location ? global.location.href : undefined);
      const urlParts = parsed.pathname.split("/").filter(Boolean);
      if (urlParts.length > 0) {
        return urlParts[urlParts.length - 1];
      }
    } catch (err) {
      // treat as plain path
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
      const requestedPath = (injectDiskPathEl?.value || "").trim();
      targetPath = sanitizeRootPath(requestedPath || `/root/${sourceName}`);
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
        const result = await stageImportIntoRunningVm(srcPath, targetPath);
        setDiskStatus(`imported to running VM (${formatBytes(result.size)}); current boot only`);
        setStatus("running (one-shot import applied)");
        emitApiEvent("inject_ok", {
          src: result.resolvedSource || srcPath,
          dst: targetPath,
          bytes: result.size,
        });
        window.setTimeout(() => {
          requestRootWatchScan();
        }, 500);
      } else {
        upsertBootImport(srcPath, targetPath);
        setDiskStatus(`queued for next boot only (${bootImports.length} staged import(s))`);
        setStatus("idle (one-shot boot import queued)");
      }
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setDiskStatus(`import failed (${msg})`);
      emitApiEvent("inject_error", toApiErrorPayload(err, "INJECT_FAILED"));
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
    if (!rootExchangeEnabled) {
      if (injectDiskFileBtn) {
        injectDiskFileBtn.disabled = true;
      }
      if (clearBootImportsBtn) {
        clearBootImportsBtn.disabled = true;
      }
      setDiskStatus("root exchange disabled in vm-config");
      setRootWatchStatus("disabled");
      return;
    }
    if (injectDiskFileBtn) {
      injectDiskFileBtn.disabled = false;
    }
    if (clearBootImportsBtn) {
      clearBootImportsBtn.disabled = false;
    }
    rootWatchKnownNames = new Set();
    if (rootWatchListEl) {
      rootWatchListEl.textContent = "";
    }
    setRootWatchStatus("waiting for VM start...");
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

  function resolveVmStartedWaiters() {
    if (vmStartedResolvers.length === 0) {
      return;
    }
    const waiters = vmStartedResolvers.slice();
    vmStartedResolvers = [];
    for (const waiter of waiters) {
      try {
        waiter.resolve();
      } catch (err) {
        // ignore
      }
    }
  }

  function rejectVmStartedWaiters(error) {
    if (vmStartedResolvers.length === 0) {
      return;
    }
    const waiters = vmStartedResolvers.slice();
    vmStartedResolvers = [];
    for (const waiter of waiters) {
      try {
        waiter.reject(error);
      } catch (err) {
        // ignore
      }
    }
  }

  function waitForVmRunning(timeoutMs = startupTimeoutMs) {
    if (hasRunningVm()) {
      return Promise.resolve();
    }
    return new Promise((resolve, reject) => {
      const timeoutId = window.setTimeout(() => {
        vmStartedResolvers = vmStartedResolvers.filter((entry) => entry !== waiter);
        reject(Object.assign(new Error("VM startup timed out"), { code: "VM_START_TIMEOUT" }));
      }, Math.max(1000, timeoutMs));
      const waiter = {
        resolve: () => {
          window.clearTimeout(timeoutId);
          resolve();
        },
        reject: (err) => {
          window.clearTimeout(timeoutId);
          reject(err);
        }
      };
      vmStartedResolvers.push(waiter);
    });
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

  function emitRootFilesChanged(records, reason, force) {
    const normalized = normalizeRootRecordList(records || []);
    const signature = rootRecordListSignature(normalized);
    if (!force && signature === lastRootRecordsSignature) {
      return;
    }
    lastRootRecordsSignature = signature;
    lastRootRecords = normalized;
    emitApiEvent("root_files_changed", {
      files: normalized,
      reason: reason || "scan"
    });
  }

  function stopRootWatchPolling() {
    if (rootWatchTimer) {
      window.clearInterval(rootWatchTimer);
      rootWatchTimer = null;
    }
    rootWatchPending = false;
  }

  function refreshRootWatchPolling() {
    stopRootWatchPolling();
    if (!hasRunningVm()) {
      return;
    }
    rootWatchTimer = window.setInterval(() => {
      requestRootWatchScan();
    }, rootWatchIntervalMs());
  }

  function requestRootWatchScan(reason = "scan", forceEmit = false) {
    if (!hasRunningVm() || rootWatchPending || rootDownloadInFlight) {
      return;
    }
    if (Date.now() < rootWatchStatusHoldUntil) {
      return;
    }
    if (!hasFilesystemBridge()) {
      setRootWatchStatus("filesystem bridge not ready");
      return;
    }
    rootWatchPending = true;
    try {
      const records = listRootShareRecords();
      const names = records
        .filter((record) => record.kind === "file")
        .map((record) => record.path.replace(/^\/root\//, ""));
      const nextSet = new Set(names);
      const newNames = names.filter((name) => !rootWatchKnownNames.has(name));
      rootWatchKnownNames = nextSet;
      renderRootWatchList(names, new Set(newNames));
      emitRootFilesChanged(records, reason, forceEmit || newNames.length > 0);
      const now = new Date().toLocaleTimeString();
      if (newNames.length > 0) {
        setRootWatchStatus(`${names.length} entries (${newNames.length} new) @ ${now}`);
      } else {
        setRootWatchStatus(`${names.length} entries @ ${now}`);
      }
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setRootWatchStatus(`scan failed (${msg})`);
    } finally {
      rootWatchPending = false;
    }
  }

  function revokeIssuedDownloadUrl(url) {
    if (!url || !issuedDownloadUrls.has(url)) {
      return;
    }
    issuedDownloadUrls.delete(url);
    try {
      URL.revokeObjectURL(url);
    } catch (err) {
      // ignore
    }
  }

  function createIssuedDownloadUrl(bytes) {
    const blob = new Blob([bytes], { type: "application/zip" });
    const url = URL.createObjectURL(blob);
    issuedDownloadUrls.add(url);
    window.setTimeout(() => {
      revokeIssuedDownloadUrl(url);
    }, 5 * 60 * 1000);
    return url;
  }

  function triggerBrowserDownloadUrl(url, filename) {
    if (!url) {
      return;
    }
    const link = document.createElement("a");
    link.href = url;
    link.download = filename || "root-file.bin";
    document.body.appendChild(link);
    link.click();
    link.remove();
  }

  async function downloadEncryptedZip(name, bytes) {
    const safeName = basename(name || "root-file.bin");
    const response = await fetch(`/api/zip-protect?name=${encodeURIComponent(safeName)}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/octet-stream",
        "X-Filename": safeName
      },
      body: bytes
    });
    if (!response.ok) {
      throw new Error(await readResponseError(response));
    }
    const zipBytes = new Uint8Array(await response.arrayBuffer());
    const outName = safeName.toLowerCase().endsWith(".zip") ? safeName : `${safeName}.zip`;
    const downloadUrl = createIssuedDownloadUrl(zipBytes);
    return {
      zipSize: zipBytes.byteLength,
      outName,
      downloadUrl
    };
  }

  async function readRootShareFile(path) {
    if (!hasRunningVm()) {
      throw Object.assign(new Error("VM not running"), { code: "VM_NOT_RUNNING" });
    }
    if (!hasFilesystemBridge()) {
      throw Object.assign(new Error("filesystem bridge not ready"), { code: "FS_BRIDGE_NOT_READY" });
    }
    const normalizedPath = sanitizeRootPath(path);
    const sharePath = normalizedPath.replace(/^\/root/, "");
    const payload = await emulator.read_file(sharePath);
    const bytes = payload instanceof Uint8Array ? payload : new Uint8Array(payload);
    return {
      bytes,
      normalizedPath,
      name: basename(normalizedPath)
    };
  }

  async function downloadRootShareFile(path, options = {}) {
    const fileData = await readRootShareFile(path);
    const zipResult = await downloadEncryptedZip(fileData.name, fileData.bytes);
    const payload = {
      path: fileData.normalizedPath,
      name: fileData.name,
      size: fileData.bytes.byteLength,
      zip_size: zipResult.zipSize,
      download_url: zipResult.downloadUrl,
      filename: zipResult.outName,
      sha256: null,
      kind: "file"
    };
    emitApiEvent("download_done", payload);
    if (options.triggerBrowserDownload === true) {
      triggerBrowserDownloadUrl(zipResult.downloadUrl, zipResult.outName);
    }
    return payload;
  }

  async function requestRootFileDownload(name) {
    if (!hasRunningVm()) {
      setRootWatchStatus("start VM first to download files");
      return;
    }
    if (!hasFilesystemBridge()) {
      setRootWatchStatus("filesystem bridge not ready");
      return;
    }
    if (rootDownloadInFlight) {
      setRootWatchStatus("download already in progress");
      return;
    }
    rootDownloadInFlight = true;
    setRootWatchStatus(`downloading /root/${name} as encrypted zip...`);
    try {
      const result = await downloadRootShareFile(`/root/${name}`, { triggerBrowserDownload: true });
      setRootWatchStatus(`downloaded ${name} as zip (${formatBytes(result.zip_size)})`);
      rootWatchStatusHoldUntil = Date.now() + 5000;
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      setRootWatchStatus(`download failed (${msg})`);
      emitApiError(err, { action: "download", path: `/root/${name}` });
      rootWatchStatusHoldUntil = Date.now() + 7000;
    } finally {
      rootDownloadInFlight = false;
      window.setTimeout(() => {
        requestRootWatchScan();
      }, 250);
    }
  }

  function ensureEmulator() {
    if (emulator) {
      return emulator;
    }

    if (typeof global.V86 !== "function") {
      setStatus("error (libv86.js missing)");
      throw new Error("V86 constructor not found. Did you run make fetch-v86 or make build-v86-min?");
    }

    setStatus("loading");
    emulatorReadyPromise = new Promise((resolve) => {
      emulatorReadyResolve = resolve;
    });

    const rootFsType = typeof config.rootFsType === "string" && config.rootFsType.trim().length > 0
      ? config.rootFsType.trim()
      : "erofs";
    const rootDevice = typeof config.rootDevice === "string" && config.rootDevice.trim().length > 0
      ? config.rootDevice.trim()
      : "/dev/sda";
    const cdromBlacklist = cdromEnabled ? "" : " modprobe.blacklist=sr_mod,cdrom";
    const defaultCmdlineBase = `root=${rootDevice} rootfstype=${rootFsType} rootflags=noatime ro rootwait ip=off net.ifnames=0 mitigations=off${cdromBlacklist}`;
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
    if (rootExchangeEnabled) {
      vmOptions.filesystem = {};
    }
    if (netDeviceType === "none") {
      vmOptions.disable_ne2k = true;
    }
    if (vgaEnabled) {
      if (!screenContainerEl) {
        throw new Error("vga mode requires a screen container element");
      }
      vmOptions.vga_bios = { url: config.vgaBios || "assets/v86/vgabios.bin" };
      vmOptions.vga_memory_size = (config.vgaMemoryMb || 8) * 1024 * 1024;
      vmOptions.screen_container = screenContainerEl;
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

    emulator = new global.V86(vmOptions);
    applyRootShareTotalSize();

    emulator.add_listener("download-progress", (info) => {
      handleDownloadProgress(info);
    });

    emulator.add_listener("download-error", (info) => {
      handleDownloadError(info);
    });

    emulator.add_listener("emulator-ready", () => {
      applyRootShareTotalSize();
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
      applyRootShareTotalSize();
      setStatus("running");
      startSampling();
      resolveVmStartedWaiters();
      emitApiEvent("vm_started", {});
      rootWatchKnownNames = new Set();
      if (rootWatchListEl) {
        rootWatchListEl.textContent = "";
      }
      setRootWatchStatus(`monitoring /root every ${rootWatchIntervalMs() / 1000}s`);
      refreshRootWatchPolling();
      window.setTimeout(() => {
        requestRootWatchScan("vm_started", true);
      }, 1500);
    });

    emulator.add_listener("emulator-stopped", () => {
      setStatus("stopped");
      stopSampling();
      rejectVmStartedWaiters(Object.assign(new Error("VM stopped"), { code: "VM_STOPPED" }));
      emitApiEvent("vm_stopped", {});
      stopRootWatchPolling();
      rootWatchKnownNames = new Set();
      if (rootWatchListEl) {
        rootWatchListEl.textContent = "";
      }
      rootDownloadInFlight = false;
      emitRootFilesChanged([], "vm_stopped", true);
      setRootWatchStatus("waiting for VM start...");
    });

    return emulator;
  }

  async function startVm(options = {}) {
    try {
      await diskStateReady;
      if (!emulator) {
        beginDownloadMeter();
      }
      const vm = ensureEmulator();
      if (emulatorReadyPromise) {
        await emulatorReadyPromise;
      }
      if (bootImports.length > 0) {
        await applyBootImportsToVm("boot-prestart");
      }
      await vm.run();
      if (options.waitForRunning === true) {
        await waitForVmRunning(options.timeoutMs || startupTimeoutMs);
      }
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
      emitApiError(err, { action: "start" });
      throw err;
    }
  }

  async function stopVm() {
    if (!emulator) {
      return;
    }
    try {
      await emulator.stop();
    } catch (err) {
      emitApiError(err, { action: "stop" });
      throw err;
    }
  }

  async function injectIntoRoot(payload = {}, options = {}) {
    try {
      if (!hasRunningVm()) {
        throw Object.assign(new Error("VM not running"), { code: "VM_NOT_RUNNING" });
      }
      if (!hasFilesystemBridge()) {
        throw Object.assign(new Error("filesystem bridge not ready"), { code: "FS_BRIDGE_NOT_READY" });
      }
      const src = normalizeServerSourcePath(payload.src || "", {
        allowCrossOrigin: options.allowCrossOrigin === true ? true : false
      });
      const sourceName = basename(src) || "autoload.bin";
      const requestedDst = String(payload.dst || "").trim();
      const dst = options.autoloadMode === true
        ? sanitizeAutoloadDst(requestedDst || `/root/${sourceName}`)
        : sanitizeRootPath(requestedDst || `/root/${sourceName}`);
      const overwrite = payload.overwrite !== false;
      const result = await stageImportIntoRunningVm(src, dst, { overwrite });
      const out = {
        src: result.resolvedSource || src,
        dst,
        bytes: result.size,
        overwrite
      };
      emitApiEvent("inject_ok", out);
      window.setTimeout(() => {
        requestRootWatchScan("inject", true);
      }, 200);
      return out;
    } catch (err) {
      emitApiEvent("inject_error", toApiErrorPayload(err, "INJECT_FAILED"));
      throw err;
    }
  }

  async function runAutoloadFromQuery() {
    const hasAutoloadSrc = typeof embedConfig.autoloadSrc === "string" && embedConfig.autoloadSrc.length > 0;
    if (!hasAutoloadSrc) {
      return;
    }
    try {
      const src = normalizeServerSourcePath(embedConfig.autoloadSrc, { allowCrossOrigin: false });
      const dst = sanitizeAutoloadDst(embedConfig.autoloadDst || `/root/${basename(src)}`);
      if (embedConfig.autostart) {
        await startVm({ waitForRunning: true, timeoutMs: autoloadTimeoutMs });
      } else {
        await waitForVmRunning(autoloadTimeoutMs);
      }
      await injectIntoRoot({ src, dst, overwrite: true }, { autoloadMode: true, allowCrossOrigin: false });
    } catch (err) {
      const payload = emitApiError(err, { action: "autoload" });
      setStatus(`error (${payload.message})`);
    }
  }

  async function handleApiCommand(command, payload) {
    switch (command) {
      case "start":
        await startVm({ waitForRunning: true, timeoutMs: startupTimeoutMs });
        return {};
      case "stop":
        await stopVm();
        return {};
      case "inject":
        return await injectIntoRoot(payload || {}, { allowCrossOrigin: false });
      case "list_root": {
        const files = hasRunningVm() ? listRootShareRecords() : [];
        emitRootFilesChanged(files, "list_root", true);
        return { files };
      }
      case "download": {
        const path = payload && payload.path ? payload.path : "";
        const result = await downloadRootShareFile(path, { triggerBrowserDownload: false });
        return result;
      }
      default:
        throw Object.assign(new Error(`unsupported command: ${command}`), { code: "COMMAND_UNSUPPORTED" });
    }
  }

  function handleParentMessage(event) {
    if (!postMessageEnabled) {
      return;
    }
    let envelope;
    try {
      envelope = validateCommandEnvelope(event.data);
    } catch (err) {
      const payload = toApiErrorPayload(
        Object.assign(new Error(err && err.message ? err.message : "malformed command envelope"), {
          code: "ENVELOPE_INVALID"
        }),
        "ENVELOPE_INVALID"
      );
      emitApiEvent("error", payload);
      return;
    }
    if (!isAllowedOrigin(event.origin, allowedParentOrigins)) {
      const denied = toApiErrorPayload(
        Object.assign(new Error("origin is not allowed"), { code: "ORIGIN_DENIED", details: { origin: event.origin } }),
        "ORIGIN_DENIED"
      );
      sendApiResponse(event.source, event.origin, envelope.id, false, null, denied);
      emitApiEvent("error", denied);
      return;
    }
    defaultEventTargetOrigin = event.origin;
    rememberParentChannel(event.source, event.origin);
    void (async () => {
      try {
        const result = await handleApiCommand(envelope.command, envelope.payload);
        sendApiResponse(event.source, event.origin, envelope.id, true, result, null);
      } catch (err) {
        const errPayload = toApiErrorPayload(err, "COMMAND_FAILED");
        sendApiResponse(event.source, event.origin, envelope.id, false, null, errPayload);
        emitApiEvent("error", errPayload);
      }
    })();
  }

  if (postMessageEnabled) {
    global.addEventListener("message", handleParentMessage);
  }

  if (startBtn) {
    startBtn.addEventListener("click", () => {
      void startVm().catch(() => {});
    });
  }

  if (stopBtn) {
    stopBtn.addEventListener("click", () => {
      void stopVm().catch(() => {});
    });
  }

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
        const sourceName = basename(src) || "server-file.bin";
        injectDiskPathEl.value = `/root/${sourceName}`;
      }
    });
  }
  if (clearBootImportsBtn) {
    clearBootImportsBtn.addEventListener("click", () => {
      clearBootImports();
    });
  }
  if (serialXtermWrapEl) {
    serialXtermWrapEl.addEventListener("dblclick", () => {
      void toggleSerialFullscreen();
    });
  }

  if (!serialEnabled && serialPanelEl) {
    serialPanelEl.style.display = "none";
    if (embedMode) {
      const err = Object.assign(new Error("embed mode requires serial console"), { code: "EMBED_SERIAL_REQUIRED" });
      emitApiError(err, { action: "embed_init" });
    }
  } else if (serialEnabled) {
    if (serialHintEl) {
      if (!serialUseXterm) {
        serialHintEl.textContent = "xterm.js missing; run make fetch-v86.";
      } else {
        serialHintEl.textContent = "Serial backend: xterm.js (interactive). Double-click terminal to toggle fullscreen.";
      }
    }
  }
  if (vgaPanelEl && !vgaEnabled) {
    vgaPanelEl.style.display = "none";
  }

  if (diskPanelEl) {
    diskStateReady = refreshDiskStateFromServer();
  }

  document.addEventListener("fullscreenchange", () => {
    scheduleSerialFit();
  });
  document.addEventListener("webkitfullscreenchange", () => {
    scheduleSerialFit();
  });

  setStatus("idle");
  emitApiEvent("ready", {
    api_version: API_VERSION,
    capabilities: API_CAPABILITIES.slice()
  });

  if (embedConfig.autoloadSrc) {
    void runAutoloadFromQuery();
  } else if (embedConfig.autostart) {
    void startVm({ waitForRunning: true, timeoutMs: startupTimeoutMs }).catch((err) => {
      emitApiError(err, { action: "autostart" });
    });
  }

  return {
    config,
    embedMode,
    apiVersion: API_VERSION,
    capabilities: API_CAPABILITIES.slice(),
    elements: {
      pageTitleEl,
      statusEl,
      embedStatusBarEl,
      ipsEl,
      serialPanelEl,
      serialHintEl,
      serialXtermWrapEl,
      serialXtermEl,
      vgaPanelEl,
      screenContainerEl,
      startBtn,
      stopBtn,
      downloadPanelEl,
      downloadStatusEl,
      downloadProgressEl,
      downloadDetailEl,
      diskPanelEl,
      injectServerSrcEl,
      injectDiskPathEl,
      injectDiskFileBtn,
      clearBootImportsBtn,
      rootWatchStatusEl,
      rootWatchListEl,
      diskStatusEl
    },
    start: startVm,
    stop: stopVm,
    inject: injectIntoRoot,
    listRoot() {
      return hasRunningVm() ? listRootShareRecords() : [];
    },
    download: downloadRootShareFile,
    ensureEmulator,
    getEmulator() {
      return emulator;
    },
    requestRootWatchScan,
    refreshDiskStateFromServer
  };
  }

  global.createTriageBox = createTriageBox;
  const hasDefaultMount = !!(
    document.getElementById("start")
    || document.getElementById("serial-xterm")
    || document.getElementById("screen_container")
  );
  global.triageBoxApp = hasDefaultMount ? createTriageBox() : null;
})(window);
