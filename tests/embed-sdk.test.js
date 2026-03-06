const test = require("node:test");
const assert = require("node:assert/strict");

const sdkModule = require("../public/triagebox-embed-sdk.js");

function createWindowHarness() {
  const listeners = new Map();
  return {
    window: {
      addEventListener(type, handler) {
        const set = listeners.get(type) || new Set();
        set.add(handler);
        listeners.set(type, set);
      },
      removeEventListener(type, handler) {
        const set = listeners.get(type);
        if (!set) {
          return;
        }
        set.delete(handler);
      },
    },
    dispatch(type, event) {
      const set = listeners.get(type);
      if (!set) {
        return;
      }
      for (const handler of Array.from(set)) {
        handler(event);
      }
    },
  };
}

test("SDK correlates command responses by id", async () => {
  const harness = createWindowHarness();
  const prevWindow = global.window;
  global.window = harness.window;

  const sent = [];
  const iframeContentWindow = {
    postMessage(message, targetOrigin) {
      sent.push({ message, targetOrigin });
    },
  };

  const iframeEl = {
    nodeType: 1,
    tagName: "IFRAME",
    contentWindow: iframeContentWindow,
  };

  const sdk = sdkModule.create(iframeEl, { targetOrigin: "https://parent.local" });
  const startPromise = sdk.start();
  const stopPromise = sdk.stop();

  assert.equal(sent.length, 2);
  const startMsg = sent.find((item) => item.message.cmd === "start");
  const stopMsg = sent.find((item) => item.message.cmd === "stop");
  assert.ok(startMsg);
  assert.ok(stopMsg);
  assert.equal(startMsg.message.source, "host");
  assert.equal(startMsg.message.type, "command");

  harness.dispatch("message", {
    source: iframeContentWindow,
    origin: "https://parent.local",
    data: { source: "triagebox", type: "response", id: stopMsg.message.id, ok: true, payload: { stopped: true } },
  });
  harness.dispatch("message", {
    source: iframeContentWindow,
    origin: "https://parent.local",
    data: { source: "triagebox", type: "response", id: startMsg.message.id, ok: true, payload: { started: true } },
  });

  const [startResult, stopResult] = await Promise.all([startPromise, stopPromise]);
  assert.equal(startResult.started, true);
  assert.equal(stopResult.stopped, true);

  sdk.destroy();
  global.window = prevWindow;
});

test("SDK emits root_files_changed event payload", async () => {
  const harness = createWindowHarness();
  const prevWindow = global.window;
  global.window = harness.window;

  const iframeContentWindow = { postMessage() {} };
  const iframeEl = { nodeType: 1, tagName: "IFRAME", contentWindow: iframeContentWindow };
  const sdk = sdkModule.create(iframeEl, { targetOrigin: "https://parent.local" });

  let observed = null;
  sdk.on("root_files_changed", (payload) => {
    observed = payload;
  });

  harness.dispatch("message", {
    source: iframeContentWindow,
    origin: "https://parent.local",
    data: {
      source: "triagebox",
      type: "event",
      event: "root_files_changed",
      payload: {
        files: [
          { name: "out.bin", path: "/root/out.bin", size: 1234, mtime_epoch: 1, sha256: null, kind: "file" },
        ],
      },
    },
  });

  assert.ok(observed);
  assert.equal(observed.files[0].path, "/root/out.bin");

  sdk.destroy();
  global.window = prevWindow;
});

test("SDK download command returns payload with download_url", async () => {
  const harness = createWindowHarness();
  const prevWindow = global.window;
  global.window = harness.window;

  let sentMessage = null;
  const iframeContentWindow = {
    postMessage(message) {
      sentMessage = message;
    },
  };
  const iframeEl = { nodeType: 1, tagName: "IFRAME", contentWindow: iframeContentWindow };
  const sdk = sdkModule.create(iframeEl, { targetOrigin: "https://parent.local" });

  const pending = sdk.downloadRootFile("/root/sample.bin");
  assert.equal(sentMessage.cmd, "download_root");

  harness.dispatch("message", {
    source: iframeContentWindow,
    origin: "https://parent.local",
    data: {
      source: "triagebox",
      type: "response",
      id: sentMessage.id,
      ok: true,
      payload: {
        path: "/root/sample.bin",
        download_url: "blob:https://tb.local/1234",
      },
    },
  });

  const result = await pending;
  assert.equal(result.path, "/root/sample.bin");
  assert.equal(result.download_url, "blob:https://tb.local/1234");

  sdk.destroy();
  global.window = prevWindow;
});

test("SDK readRootFile returns Uint8Array", async () => {
  const harness = createWindowHarness();
  const prevWindow = global.window;
  global.window = harness.window;

  let sentMessage = null;
  const bytes = new Uint8Array([1, 2, 3, 4]).buffer;
  const iframeContentWindow = {
    postMessage(message) {
      sentMessage = message;
    },
  };
  const iframeEl = { nodeType: 1, tagName: "IFRAME", contentWindow: iframeContentWindow };
  const sdk = sdkModule.create(iframeEl, { targetOrigin: "https://parent.local" });

  const pending = sdk.readRootFile("/root/sample.bin");
  assert.equal(sentMessage.cmd, "read_root");

  harness.dispatch("message", {
    source: iframeContentWindow,
    origin: "https://parent.local",
    data: {
      source: "triagebox",
      type: "response",
      id: sentMessage.id,
      ok: true,
      payload: {
        path: "/root/sample.bin",
        bytes,
      },
    },
  });

  const result = await pending;
  assert.equal(result instanceof Uint8Array, true);
  assert.equal(result.length, 4);
  assert.equal(result[0], 1);

  sdk.destroy();
  global.window = prevWindow;
});
