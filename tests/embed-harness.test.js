const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");

test("embed harness html and js exist with expected wiring", () => {
  const html = fs.readFileSync(path.join(root, "public/embed-harness.html"), "utf8");
  const js = fs.readFileSync(path.join(root, "public/embed-harness.js"), "utf8");

  assert.match(html, /id="tb-frame"/);
  assert.match(html, /triagebox-embed-sdk\.js/);
  assert.match(html, /embed-harness\.js/);

  assert.match(js, /TriageBoxEmbed\.create/);
  assert.match(js, /listRootFiles/);
  assert.match(js, /readRootFile/);
  assert.match(js, /downloadRootFile/);
  assert.match(js, /run_flow/i);
});
