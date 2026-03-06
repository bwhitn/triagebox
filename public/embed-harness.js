(() => {
  const frameEl = document.getElementById("tb-frame");
  const logEl = document.getElementById("log");
  const statusEl = document.getElementById("status");
  const layoutEl = document.getElementById("layout");
  const srcEl = document.getElementById("src");
  const dstEl = document.getElementById("dst");
  const modeEl = document.getElementById("mode");

  const reloadBtn = document.getElementById("reload");
  const runFlowBtn = document.getElementById("run-flow");
  const startBtn = document.getElementById("start");
  const stopBtn = document.getElementById("stop");
  const injectBtn = document.getElementById("inject");
  const listRootBtn = document.getElementById("list-root");
  const readRootBtn = document.getElementById("read-root");
  const downloadRootBtn = document.getElementById("download-root");
  const clearLogBtn = document.getElementById("clear-log");

  if (!frameEl || !logEl || !statusEl) {
    return;
  }
  if (!window.TriageBoxEmbed || typeof window.TriageBoxEmbed.create !== "function") {
    statusEl.textContent = "status: error (triagebox-embed-sdk.js missing)";
    return;
  }

  let sdk = null;
  let ready = false;
  let readyPromise = null;
  let readyResolve = null;
  let readyReject = null;
  let actionLock = Promise.resolve();

  function log(message, payload) {
    const stamp = new Date().toISOString();
    let line = `[${stamp}] ${message}`;
    if (payload !== undefined) {
      try {
        line += ` ${JSON.stringify(payload)}`;
      } catch (err) {
        line += ` ${String(payload)}`;
      }
    }
    logEl.textContent += `${line}\n`;
    logEl.scrollTop = logEl.scrollHeight;
  }

  function setStatus(text) {
    statusEl.textContent = `status: ${text}`;
  }

  function normalizeRootPath(input) {
    const raw = String(input || "").trim();
    const absolute = raw.startsWith("/") ? raw : `/${raw}`;
    const segments = absolute.split("/").filter(Boolean);
    if (segments.length === 0) {
      return "/root/sample.bin";
    }
    const name = segments[segments.length - 1];
    return `/root/${name}`;
  }

  function currentInjectPayload() {
    const src = String(srcEl.value || "").trim();
    const dst = normalizeRootPath(dstEl.value);
    const mode = String(modeEl.value || "runtime").trim().toLowerCase() === "stage" ? "stage" : "runtime";
    dstEl.value = dst;
    return {
      src,
      dst,
      mode,
      overwrite: true,
    };
  }

  function resetReadyPromise() {
    ready = false;
    readyPromise = new Promise((resolve, reject) => {
      readyResolve = resolve;
      readyReject = reject;
    });
  }

  async function waitUntilReady(timeoutMs = 90000) {
    if (ready) {
      return;
    }
    if (!readyPromise) {
      resetReadyPromise();
    }
    await Promise.race([
      readyPromise,
      new Promise((_, reject) => {
        setTimeout(() => reject(new Error("ready timeout")), timeoutMs);
      }),
    ]);
  }

  function buildIframeSrc() {
    const params = new URLSearchParams();
    params.set("embed", "1");
    params.set("embed_layout", String(layoutEl.value || "serial"));
    params.set("parent_origin", window.location.origin);
    return `index.html?${params.toString()}`;
  }

  function bindSdkEvents(instance) {
    const events = [
      "ready",
      "vm_ready",
      "vm_started",
      "vm_stopped",
      "inject_ok",
      "inject_error",
      "root_files_changed",
      "read_root_ok",
      "read_root_error",
      "download_done",
      "download_error",
      "error",
    ];
    for (const eventName of events) {
      instance.on(eventName, (payload) => {
        log(`event:${eventName}`, payload);
        if (eventName === "ready") {
          ready = true;
          setStatus("ready");
          if (readyResolve) {
            readyResolve(payload || {});
          }
        }
      });
    }
  }

  function createSdk() {
    if (sdk && typeof sdk.destroy === "function") {
      sdk.destroy();
    }
    resetReadyPromise();
    sdk = window.TriageBoxEmbed.create(frameEl, {
      targetOrigin: window.location.origin,
      timeoutMs: 120000,
    });
    bindSdkEvents(sdk);
  }

  function reloadIframe() {
    createSdk();
    const src = buildIframeSrc();
    frameEl.src = src;
    setStatus("loading iframe");
    log("iframe:load", { src });
  }

  async function runExclusive(label, fn) {
    const runner = actionLock.then(async () => {
      try {
        setStatus(`${label}...`);
        const result = await fn();
        setStatus(`${label}: ok`);
        return result;
      } catch (err) {
        const message = err && err.message ? err.message : String(err);
        setStatus(`${label}: failed (${message})`);
        log(`error:${label}`, { message });
        throw err;
      }
    });
    actionLock = runner.catch(() => {});
    return runner;
  }

  async function commandStart() {
    await waitUntilReady();
    const result = await sdk.start();
    log("cmd:start:ok", result);
  }

  async function commandStop() {
    await waitUntilReady();
    const result = await sdk.stop();
    log("cmd:stop:ok", result);
  }

  async function commandInject() {
    await waitUntilReady();
    const payload = currentInjectPayload();
    const result = await sdk.inject(payload);
    log("cmd:inject:ok", result);
    return payload;
  }

  async function commandListRoot() {
    await waitUntilReady();
    const files = await sdk.listRootFiles();
    log("cmd:list_root:ok", { count: files.length, files });
    return files;
  }

  async function commandReadRoot(path) {
    await waitUntilReady();
    const bytes = await sdk.readRootFile(path);
    log("cmd:read_root:ok", {
      path,
      size: bytes.length,
      preview_hex: Array.from(bytes.slice(0, 32)).map((n) => n.toString(16).padStart(2, "0")).join(""),
    });
    return bytes;
  }

  async function commandDownloadRoot(path) {
    await waitUntilReady();
    const result = await sdk.downloadRootFile(path);
    log("cmd:download_root:ok", result);
    if (result && typeof result.download_url === "string" && result.download_url) {
      const link = document.createElement("a");
      link.href = result.download_url;
      link.download = result.filename || "root-file.zip";
      document.body.appendChild(link);
      link.click();
      link.remove();
      log("download:triggered", { filename: link.download });
    }
    return result;
  }

  async function commandRunFlow() {
    await waitUntilReady();
    await sdk.start();
    log("flow:start:ok");
    const injectPayload = currentInjectPayload();
    await sdk.inject(injectPayload);
    log("flow:inject:ok", injectPayload);
    const files = await sdk.listRootFiles();
    log("flow:list_root:ok", { count: files.length });
    await sdk.readRootFile(injectPayload.dst);
    log("flow:read_root:ok", { path: injectPayload.dst });
  }

  reloadBtn?.addEventListener("click", () => {
    void runExclusive("reload", async () => {
      reloadIframe();
      await waitUntilReady();
      return {};
    }).catch(() => {});
  });

  runFlowBtn?.addEventListener("click", () => {
    void runExclusive("run_flow", commandRunFlow).catch(() => {});
  });

  startBtn?.addEventListener("click", () => {
    void runExclusive("start", commandStart).catch(() => {});
  });

  stopBtn?.addEventListener("click", () => {
    void runExclusive("stop", commandStop).catch(() => {});
  });

  injectBtn?.addEventListener("click", () => {
    void runExclusive("inject", commandInject).catch(() => {});
  });

  listRootBtn?.addEventListener("click", () => {
    void runExclusive("list_root", commandListRoot).catch(() => {});
  });

  readRootBtn?.addEventListener("click", () => {
    void runExclusive("read_root", async () => {
      const path = normalizeRootPath(dstEl.value);
      await commandReadRoot(path);
    }).catch(() => {});
  });

  downloadRootBtn?.addEventListener("click", () => {
    void runExclusive("download_root", async () => {
      const path = normalizeRootPath(dstEl.value);
      await commandDownloadRoot(path);
    }).catch(() => {});
  });

  clearLogBtn?.addEventListener("click", () => {
    logEl.textContent = "";
  });

  reloadIframe();
})();
