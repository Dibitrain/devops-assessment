// Graceful shutdown: on SIGTERM the server must fail readiness, keep serving during the drain delay,
// then exit 0. Windows has no POSIX signals, so this runs on Linux/macOS (CI and the container build).
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { describe, it } from "node:test";

const PORT = 3190;
const METRICS_PORT = 9190;

describe("graceful shutdown", { skip: process.platform === "win32" && "POSIX signals unavailable" }, () => {
  it("drains on SIGTERM and exits cleanly", async () => {
    const child = spawn(process.execPath, ["dist/server.js"], {
      env: { ...process.env, PORT: String(PORT), METRICS_PORT: String(METRICS_PORT), SHUTDOWN_DELAY_MS: "1000", LOG_LEVEL: "error" },
      stdio: "ignore",
    });

    const base = `http://127.0.0.1:${PORT}`;
    for (let i = 0; i < 50; i++) {
      try {
        if ((await fetch(`${base}/ready`)).ok) break;
      } catch {
        await new Promise((r) => setTimeout(r, 100));
      }
    }

    child.kill("SIGTERM");
    await new Promise((r) => setTimeout(r, 200));

    // During the drain delay: still serving, but no longer ready.
    assert.equal((await fetch(`${base}/ready`)).status, 503);
    assert.equal((await fetch(`${base}/health`)).status, 200);

    const [code] = await once(child, "exit");
    assert.equal(code, 0);
  });
});
