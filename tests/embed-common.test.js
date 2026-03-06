const test = require("node:test");
const assert = require("node:assert/strict");

const common = require("../public/embed-common.js");

test("embed=1 is parsed as embed mode", () => {
  const cfg = common.parseEmbedConfig("?embed=1", {
    referrer: "",
    locationOrigin: "https://tb.local",
  });
  assert.equal(cfg.embedMode, true);
});

test("autoload query success path parses expected values", () => {
  const cfg = common.parseEmbedConfig(
    "?embed=1&autostart=1&autoload_src=/samples/in.bin&autoload_dst=/root/subdir/out.bin",
    {
      referrer: "https://parent.local/page",
      locationOrigin: "https://tb.local",
    }
  );
  assert.equal(cfg.autostart, true);
  assert.equal(cfg.autoloadSrc, "/samples/in.bin");
  assert.equal(cfg.autoloadDst, "/root/subdir/out.bin");

  const src = common.resolveAutoloadSource(cfg.autoloadSrc, {
    baseUrl: "https://tb.local/index.html",
    baseOrigin: "https://tb.local",
    allowCrossOrigin: false,
  });
  const dst = common.sanitizeAutoloadDst(cfg.autoloadDst);
  assert.equal(src, "https://tb.local/samples/in.bin");
  assert.equal(dst, "/root/out.bin");
});

test("autoload src accepts same-origin http(s) and rejects cross-origin by default", () => {
  const ok = common.resolveAutoloadSource("/assets/sample.bin", {
    baseUrl: "https://tb.local/index.html",
    baseOrigin: "https://tb.local",
    allowCrossOrigin: false,
  });
  assert.equal(ok, "https://tb.local/assets/sample.bin");

  assert.throws(() => {
    common.resolveAutoloadSource("https://evil.example/sample.bin", {
      baseUrl: "https://tb.local/index.html",
      baseOrigin: "https://tb.local",
      allowCrossOrigin: false,
    });
  }, /cross-origin autoload source is not allowed/);
});

test("sanitizeAutoloadDst forces basename under /root", () => {
  const out = common.sanitizeAutoloadDst("/root/a/b/c.bin");
  assert.equal(out, "/root/c.bin");
});

test("sanitizeAutoloadDst rejects dangerous paths", () => {
  assert.throws(() => common.sanitizeAutoloadDst("/etc/passwd"), /must be under \/root/);
  assert.throws(() => common.sanitizeAutoloadDst("/root/../../evil"), /cannot contain '\.\.'/);
});

test("sanitizeRootPath only allows /root/*", () => {
  assert.equal(common.sanitizeRootPath("/root/file.bin"), "/root/file.bin");
  assert.throws(() => common.sanitizeRootPath("/tmp/file.bin"), /under \/root/);
});

test("validateCommandEnvelope accepts valid and rejects malformed envelopes", () => {
  const envelope = common.validateCommandEnvelope({
    type: "tb.command",
    id: "1",
    command: "start",
    payload: {},
  });
  assert.equal(envelope.id, "1");
  assert.equal(envelope.command, "start");

  assert.throws(() => {
    common.validateCommandEnvelope({ type: "wrong", id: "1", command: "start" });
  }, /tb.command/);
});

test("origin checks allow expected origin and reject others", () => {
  const allowed = ["https://parent.local"];
  assert.equal(common.isAllowedOrigin("https://parent.local", allowed), true);
  assert.equal(common.isAllowedOrigin("https://other.local", allowed), false);
});

test("root record signature changes when file list changes", () => {
  const a = common.rootRecordListSignature([
    { name: "a.bin", path: "/root/a.bin", size: 1, mtime_epoch: 1, sha256: null, kind: "file" },
  ]);
  const b = common.rootRecordListSignature([
    { name: "a.bin", path: "/root/a.bin", size: 2, mtime_epoch: 1, sha256: null, kind: "file" },
  ]);
  assert.notEqual(a, b);
});
