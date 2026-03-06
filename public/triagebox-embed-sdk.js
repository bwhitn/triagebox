(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.TriageBoxEmbed = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  function isObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
  }

  function create(iframeEl, options = {}) {
    if (!iframeEl || typeof iframeEl !== "object" || iframeEl.nodeType !== 1 || iframeEl.tagName !== "IFRAME") {
      throw new Error("iframeEl must be an <iframe> element");
    }
    let inferredTargetOrigin = "";
    if (typeof options.targetOrigin === "string" && options.targetOrigin.length > 0) {
      inferredTargetOrigin = options.targetOrigin;
    } else if (iframeEl && typeof iframeEl.src === "string" && iframeEl.src.length > 0) {
      try {
        inferredTargetOrigin = new URL(iframeEl.src, window.location.href).origin;
      } catch (err) {
        inferredTargetOrigin = "";
      }
    } else if (window && window.location && typeof window.location.origin === "string") {
      inferredTargetOrigin = window.location.origin;
    }
    const targetOrigin = inferredTargetOrigin || "*";
    const timeoutMs = Number.isFinite(options.timeoutMs) ? Math.max(1000, options.timeoutMs) : 30000;

    let counter = 0;
    const pending = new Map();
    const listeners = new Map();
    let readyPayload = null;

    function emit(eventName, payload) {
      const handlers = listeners.get(eventName);
      if (!handlers || handlers.size === 0) {
        return;
      }
      for (const handler of handlers) {
        try {
          handler(payload);
        } catch (err) {
          console.error("TriageBoxEmbed listener error", err);
        }
      }
    }

    function on(eventName, callback) {
      if (typeof eventName !== "string" || !eventName) {
        throw new Error("event name must be a non-empty string");
      }
      if (typeof callback !== "function") {
        throw new Error("callback must be a function");
      }
      const handlers = listeners.get(eventName) || new Set();
      handlers.add(callback);
      listeners.set(eventName, handlers);
      return () => {
        handlers.delete(callback);
      };
    }

    function postCommand(command, payload) {
      const frameWindow = iframeEl.contentWindow;
      if (!frameWindow) {
        return Promise.reject(new Error("iframe contentWindow is not available"));
      }
      counter += 1;
      const id = String(counter);
      const envelope = {
        type: "tb.command",
        id,
        command,
        payload: isObject(payload) ? payload : {},
      };
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`timeout waiting for response to '${command}'`));
        }, timeoutMs);
        pending.set(id, {
          resolve,
          reject,
          timeout,
        });
        frameWindow.postMessage(envelope, targetOrigin);
      });
    }

    function handleMessage(event) {
      if (event.source !== iframeEl.contentWindow) {
        return;
      }
      if (targetOrigin !== "*" && event.origin !== targetOrigin) {
        return;
      }
      const data = event.data;
      if (!isObject(data) || typeof data.type !== "string") {
        return;
      }
      if (data.type === "tb.response") {
        const id = data.id === undefined || data.id === null ? "" : String(data.id);
        if (!id || !pending.has(id)) {
          return;
        }
        const entry = pending.get(id);
        pending.delete(id);
        clearTimeout(entry.timeout);
        if (data.ok === true) {
          entry.resolve(data.payload || {});
        } else {
          const message = typeof data.error === "string" && data.error ? data.error : "command failed";
          const error = new Error(message);
          if (isObject(data.payload) && typeof data.payload.code === "string") {
            error.code = data.payload.code;
          }
          if (isObject(data.payload)) {
            error.payload = data.payload;
          }
          entry.reject(error);
        }
        return;
      }
      if (data.type === "tb.event") {
        const eventName = typeof data.event === "string" ? data.event : "unknown";
        const payload = isObject(data.payload) ? data.payload : {};
        if (eventName === "ready") {
          readyPayload = payload;
        }
        emit(eventName, payload);
      }
    }

    window.addEventListener("message", handleMessage);

    function destroy() {
      window.removeEventListener("message", handleMessage);
      for (const [, entry] of pending) {
        clearTimeout(entry.timeout);
        entry.reject(new Error("sdk destroyed"));
      }
      pending.clear();
      listeners.clear();
    }

    return {
      start() {
        return postCommand("start", {});
      },
      stop() {
        return postCommand("stop", {});
      },
      inject(payload) {
        return postCommand("inject", payload || {});
      },
      listRoot() {
        return postCommand("list_root", {});
      },
      download(payload) {
        return postCommand("download", payload || {});
      },
      on,
      destroy,
      getReady() {
        return readyPayload;
      },
    };
  }

  return { create };
});
