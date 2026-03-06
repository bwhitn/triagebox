(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.TriageBoxEmbedCommon = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  const API_VERSION = "1.0";
  const CAPABILITIES = ["start", "stop", "inject", "list_root", "read_root", "download_root", "download"];

  function makeError(code, message, details) {
    const error = new Error(message);
    error.code = code;
    if (details !== undefined) {
      error.details = details;
    }
    return error;
  }

  function parseBooleanFlag(value, defaultValue) {
    if (value === undefined || value === null || String(value).trim() === "") {
      return defaultValue;
    }
    const raw = String(value).trim().toLowerCase();
    if (raw === "1" || raw === "true" || raw === "yes" || raw === "on") {
      return true;
    }
    if (raw === "0" || raw === "false" || raw === "no" || raw === "off") {
      return false;
    }
    return defaultValue;
  }

  function parseOriginList(value) {
    if (!value) {
      return [];
    }
    if (Array.isArray(value)) {
      const out = [];
      for (const item of value) {
        out.push(...parseOriginList(item));
      }
      return out;
    }
    return String(value)
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  function parseReferrerOrigin(referrerUrl) {
    if (!referrerUrl) {
      return null;
    }
    try {
      return new URL(referrerUrl).origin;
    } catch (err) {
      return null;
    }
  }

  function uniqueOrigins(items) {
    const result = [];
    const seen = new Set();
    for (const item of items) {
      if (!item || typeof item !== "string") {
        continue;
      }
      try {
        const origin = new URL(item).origin;
        if (!seen.has(origin)) {
          seen.add(origin);
          result.push(origin);
        }
      } catch (err) {
        continue;
      }
    }
    return result;
  }

  function parseEmbedConfig(search, options) {
    const params = new URLSearchParams(search || "");
    const queryParentOrigins = parseOriginList(params.get("parent_origin") || params.get("parent_origins") || "");
    const configParentOrigins = parseOriginList(options && options.configParentOrigins);
    const embedMode = parseBooleanFlag(params.get("embed"), false);
    const embedLayoutRaw = (params.get("embed_layout") || "").trim().toLowerCase();
    const embedLayout = embedLayoutRaw === "vga" || embedLayoutRaw === "both" ? embedLayoutRaw : "serial";
    const autostart = parseBooleanFlag(params.get("autostart"), false);
    const autoloadSrc = (params.get("autoload_src") || "").trim();
    const autoloadDst = (params.get("autoload_dst") || "").trim();
    const autoloadModeRaw = (params.get("autoload_mode") || "").trim().toLowerCase();
    const autoloadMode = autoloadModeRaw === "runtime" ? "runtime" : "stage";
    const referrerOrigin = parseReferrerOrigin(options && options.referrer);
    const locationOrigin = options && options.locationOrigin ? String(options.locationOrigin) : "";

    let allowedOrigins = uniqueOrigins([...configParentOrigins, ...queryParentOrigins]);

    if (allowedOrigins.length === 0 && referrerOrigin) {
      allowedOrigins = uniqueOrigins([referrerOrigin]);
    }

    if (!embedMode && locationOrigin) {
      allowedOrigins = uniqueOrigins([locationOrigin, ...allowedOrigins]);
    }

    return {
      embedMode,
      embedLayout,
      autostart,
      autoloadSrc,
      autoloadDst,
      autoloadMode,
      allowedParentOrigins: allowedOrigins,
    };
  }

  function ensureNoControlChars(value, code, fieldName) {
    if (/[\x00-\x1f\x7f]/.test(value)) {
      throw makeError(code, `${fieldName} contains control characters`);
    }
  }

  function sanitizeAutoloadDst(rawPath) {
    const original = String(rawPath || "").trim();
    if (!original) {
      throw makeError("AUTOLOAD_DST_MISSING", "autoload destination is required");
    }
    ensureNoControlChars(original, "AUTOLOAD_DST_INVALID", "autoload destination");

    if (original.startsWith("/") && !original.startsWith("/root/") && original !== "/root") {
      throw makeError("AUTOLOAD_DST_INVALID", "autoload destination must be under /root");
    }

    const segments = original.split("/").filter(Boolean);
    if (segments.some((segment) => segment === "..")) {
      throw makeError("AUTOLOAD_DST_INVALID", "autoload destination cannot contain '..'");
    }

    const baseName = segments.length > 0 ? segments[segments.length - 1] : "";
    if (!baseName || baseName === "." || baseName === "..") {
      throw makeError("AUTOLOAD_DST_INVALID", "autoload destination filename is invalid");
    }
    return `/root/${baseName}`;
  }

  function sanitizeRootPath(rawPath) {
    const original = String(rawPath || "").trim();
    if (!original) {
      throw makeError("PATH_REJECTED", "path is required");
    }
    ensureNoControlChars(original, "PATH_REJECTED", "path");

    const absolute = original.startsWith("/") ? original : `/${original}`;
    const segments = absolute.split("/").filter(Boolean);
    if (segments.some((segment) => segment === "..")) {
      throw makeError("PATH_REJECTED", "path cannot contain '..'");
    }
    const normalized = `/${segments.join("/")}`;
    if (normalized === "/root") {
      throw makeError("PATH_REJECTED", "path must target a file under /root");
    }
    if (!normalized.startsWith("/root/")) {
      throw makeError("PATH_REJECTED", "path must be under /root");
    }
    return normalized;
  }

  function resolveAutoloadSource(rawSrc, options) {
    const source = String(rawSrc || "").trim();
    if (!source) {
      throw makeError("AUTOLOAD_SRC_MISSING", "autoload source is required");
    }
    ensureNoControlChars(source, "AUTOLOAD_SRC_INVALID", "autoload source");

    let url;
    try {
      url = new URL(source, options && options.baseUrl ? options.baseUrl : undefined);
    } catch (err) {
      throw makeError("AUTOLOAD_SRC_INVALID", "autoload source must be a valid URL");
    }

    if (url.protocol !== "http:" && url.protocol !== "https:") {
      throw makeError("AUTOLOAD_SRC_INVALID", "autoload source scheme must be http or https");
    }

    const sameOriginOnly = !(options && options.allowCrossOrigin === true);
    const baseOrigin = options && options.baseOrigin ? String(options.baseOrigin) : "";
    if (sameOriginOnly && baseOrigin && url.origin !== baseOrigin) {
      throw makeError("AUTOLOAD_SRC_DENIED", "cross-origin autoload source is not allowed");
    }

    return url.toString();
  }

  function isAllowedOrigin(origin, allowedOrigins) {
    if (typeof origin !== "string" || !origin) {
      return false;
    }
    return Array.isArray(allowedOrigins) && allowedOrigins.includes(origin);
  }

  function validateCommandEnvelope(message) {
    if (!message || typeof message !== "object" || Array.isArray(message)) {
      throw makeError("ENVELOPE_INVALID", "message envelope must be an object");
    }
    if (message.source === "host" && message.type === "command") {
      if (message.id === undefined || message.id === null || String(message.id).trim() === "") {
        throw makeError("ENVELOPE_INVALID", "message id is required");
      }
      if (typeof message.cmd !== "string" || message.cmd.trim() === "") {
        throw makeError("ENVELOPE_INVALID", "message cmd is required");
      }
      const payload = message.payload && typeof message.payload === "object" && !Array.isArray(message.payload)
        ? message.payload
        : {};
      return {
        id: String(message.id),
        command: message.cmd.trim(),
        payload,
        protocol: "host-v1",
      };
    }

    if (message.type !== "tb.command") {
      throw makeError("ENVELOPE_INVALID", "message type must be 'command' or 'tb.command'");
    }
    if (message.id === undefined || message.id === null || String(message.id).trim() === "") {
      throw makeError("ENVELOPE_INVALID", "message id is required");
    }
    if (typeof message.command !== "string" || message.command.trim() === "") {
      throw makeError("ENVELOPE_INVALID", "message command is required");
    }
    const payload = message.payload && typeof message.payload === "object" && !Array.isArray(message.payload)
      ? message.payload
      : {};
    return {
      id: String(message.id),
      command: message.command.trim(),
      payload,
      protocol: "tb-v1",
    };
  }

  function pickEpochSeconds(value) {
    if (!Number.isFinite(value)) {
      return 0;
    }
    if (value > 1e12) {
      return Math.floor(value / 1000);
    }
    if (value < 0) {
      return 0;
    }
    return Math.floor(value);
  }

  function normalizeRootRecord(record) {
    const name = String(record && record.name ? record.name : "").trim();
    const path = String(record && record.path ? record.path : "").trim();
    const size = Number.isFinite(record && record.size) ? Math.max(0, Math.floor(record.size)) : 0;
    const mtime = pickEpochSeconds(record && record.mtime_epoch);
    const sha256 = typeof (record && record.sha256) === "string" && record.sha256.trim().length > 0
      ? record.sha256.trim()
      : null;
    const kind = record && record.kind === "dir" ? "dir" : "file";
    return { name, path, size, mtime_epoch: mtime, sha256, kind };
  }

  function normalizeRootRecordList(records) {
    if (!Array.isArray(records)) {
      return [];
    }
    const out = records.map(normalizeRootRecord).filter((item) => item.path.startsWith("/root/"));
    out.sort((a, b) => a.path.localeCompare(b.path));
    return out;
  }

  function rootRecordListSignature(records) {
    return normalizeRootRecordList(records)
      .map((item) => `${item.path}|${item.kind}|${item.size}|${item.mtime_epoch}|${item.sha256 || ""}`)
      .join("\n");
  }

  function toApiErrorPayload(error, fallbackCode) {
    if (!error) {
      return {
        code: fallbackCode || "UNKNOWN_ERROR",
        message: "unknown error",
      };
    }
    const code = typeof error.code === "string" && error.code ? error.code : (fallbackCode || "UNKNOWN_ERROR");
    const message = typeof error.message === "string" && error.message ? error.message : String(error);
    const payload = { code, message };
    if (error.details !== undefined) {
      payload.details = error.details;
    }
    return payload;
  }

  return {
    API_VERSION,
    CAPABILITIES,
    makeError,
    parseBooleanFlag,
    parseOriginList,
    parseReferrerOrigin,
    parseEmbedConfig,
    sanitizeAutoloadDst,
    sanitizeRootPath,
    resolveAutoloadSource,
    isAllowedOrigin,
    validateCommandEnvelope,
    normalizeRootRecord,
    normalizeRootRecordList,
    rootRecordListSignature,
    toApiErrorPayload,
  };
});
