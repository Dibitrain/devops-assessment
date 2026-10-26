// API key enforcement. Runs in its own process (node --test isolates files) so API_KEY can be set
// before the config module is first loaded.
import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

process.env.API_KEY = "test-key-not-a-secret";
process.env.LOG_LEVEL = "error";
const { app } = await import("../dist/app.js");

let api;
before(async () => {
  api = await new Promise((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
});
after(() => {
  api.closeAllConnections();
  api.close();
});
const url = (path) => `http://127.0.0.1:${api.address().port}${path}`;

describe("API key", () => {
  it("rejects /getAccount without a key", async () => {
    assert.equal((await fetch(url("/getAccount"))).status, 401);
  });

  it("rejects a wrong key", async () => {
    const res = await fetch(url("/getAccount"), { headers: { "x-api-key": "wrong" } });
    assert.equal(res.status, 401);
  });

  it("accepts the right key", async () => {
    const res = await fetch(url("/getAccount"), { headers: { "x-api-key": "test-key-not-a-secret" } });
    assert.equal(res.status, 200);
  });

  it("leaves probes unauthenticated", async () => {
    assert.equal((await fetch(url("/health"))).status, 200);
    assert.equal((await fetch(url("/ready"))).status, 200);
  });
});
