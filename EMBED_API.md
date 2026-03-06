# TriageBox Embed API

## Query Params

- `embed=1`
  - Enables embed UI mode.
- `embed_layout=serial|vga|both`
  - Default: `serial`.
- `autostart=1|0`
  - Default: `0`.
- `autoload_src=<url-or-path>`
  - `http/https` only.
  - Same-origin is enforced by default.
- `autoload_dst=/root/<name>`
  - Required when `autoload_src` is used.
  - Sanitized to a basename under `/root/` for autoload.
- `autoload_mode=stage|runtime`
  - Default: `stage`.
  - `stage`: queue one-shot boot import.
  - `runtime`: inject into running VM (or queue for next start).
- `parent_origin=<origin>` or `parent_origins=<origin1,origin2>`
  - Allowed parent origins for command API.

Example:

```text
/triagebox/?embed=1&embed_layout=serial&autostart=1&autoload_src=/malware/sample.bin&autoload_dst=/root/sample.bin&autoload_mode=stage&parent_origin=https://malsite.example
```

## postMessage Contract

Primary contract is `source/type/cmd`. Legacy `tb.command` / `tb.response` / `tb.event` is still accepted and emitted for compatibility.

### Parent -> iframe command

```json
{
  "source": "host",
  "type": "command",
  "id": "req-123",
  "cmd": "inject",
  "payload": {
    "src": "/malware/sample.bin",
    "dst": "/root/sample.bin",
    "mode": "stage"
  }
}
```

### Iframe -> parent response

```json
{
  "source": "triagebox",
  "type": "response",
  "id": "req-123",
  "ok": true,
  "payload": {}
}
```

On failure:

```json
{
  "source": "triagebox",
  "type": "response",
  "id": "req-123",
  "ok": false,
  "error": "reason",
  "payload": {
    "code": "CODE",
    "message": "reason"
  }
}
```

### Iframe -> parent event

```json
{
  "source": "triagebox",
  "type": "event",
  "event": "ready",
  "payload": {
    "api_version": "1.0",
    "capabilities": ["start", "stop", "inject", "list_root", "read_root", "download_root"]
  }
}
```

## Commands

- `start`
- `stop`
- `inject`
  - Payload:
    - `src` (required)
    - `dst` (required, must be under `/root`)
    - `mode`: `stage|runtime` (default `runtime`)
    - `overwrite`: `true|false` (default `true`)
- `list_root`
- `read_root`
  - Payload: `{ "path": "/root/file.bin" }`
  - Returns bytes in `payload.bytes` as transferable `ArrayBuffer`.
- `download_root`
  - Payload: `{ "path": "/root/file.bin" }`
  - Returns download metadata including `download_url`.
- Legacy alias: `download`.

## Events

- `ready`
- `vm_ready`
- `vm_started`
- `vm_stopped`
- `inject_ok`
- `inject_error`
- `root_files_changed`
- `read_root_ok`
- `read_root_error`
- `download_done`
- `download_error`
- `error`

`root_files_changed` payload:

```json
{
  "files": [
    {
      "name": "out.bin",
      "path": "/root/out.bin",
      "size": 1234,
      "mtime_epoch": 1772709999,
      "sha256": null,
      "kind": "file"
    }
  ]
}
```

## Minimal iframe integration

```html
<iframe id="tb" src="/triagebox/?embed=1&autostart=1&autoload_src=/samples/a.bin&autoload_dst=/root/a.bin&parent_origin=https://malsite.example"></iframe>
<script>
  const frame = document.getElementById("tb");
  const targetOrigin = "https://triagebox.example";

  function send(cmd, payload) {
    const id = crypto.randomUUID();
    frame.contentWindow.postMessage({ source: "host", type: "command", id, cmd, payload: payload || {} }, targetOrigin);
    return id;
  }

  window.addEventListener("message", (event) => {
    if (event.origin !== targetOrigin) return;
    const msg = event.data;
    if (!msg || msg.source !== "triagebox") return;
    if (msg.type === "event" && msg.event === "ready") {
      send("start", {});
    }
  });
</script>
```
