const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");

test("embed layout styles are present", () => {
  const css = fs.readFileSync(path.join(root, "public/style.css"), "utf8");
  assert.match(css, /body\.embed-mode/);
  assert.match(css, /body\.embed-mode\.embed-layout-serial/);
  assert.match(css, /body\.embed-mode\.embed-layout-vga/);
  assert.match(css, /body\.embed-mode\.embed-layout-both/);
  assert.match(css, /body\.embed-mode #status-panel/);
});

test("embed status bar mount exists in index", () => {
  const html = fs.readFileSync(path.join(root, "public/index.html"), "utf8");
  assert.match(html, /id="embed-status-bar"/);
  assert.match(html, /id="status-panel"/);
});
