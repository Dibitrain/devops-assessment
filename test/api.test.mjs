// Integration tests against the compiled app (run `npm run build` first; `npm test` does this).
import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

process.env.API_KEY = "";
process.env.LOG_LEVEL = "error";
const { app, metricsApp } = await import("../dist/app.js");

let api;
let metrics;
const listen = (server) =>
  new Promise((resolve) => {
    const s = server.listen(0, "127.0.0.1", () => resolve(s));
  });
const url = (s, path) => `http://127.0.0.1:${s.address().port}${path}`;

before(async () => {
  api = await listen(app);
  metrics = await listen(metricsApp);
});
after(() => {
  api.closeAllConnections();
  api.close();
  metrics.closeAllConnections();
  metrics.close();
});

describe("public API", () => {
  it("GET /health returns ok with uptime", async () => {
    const res = await fetch(url(api, "/health"));
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.status, "ok");
    assert.equal(typeof body.uptimeSeconds, "number");
  });

  it("GET /ready returns ready", async () => {
    const res = await fetch(url(api, "/ready"));
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: "ready" });
  });

  it("GET /getAccount lists every account", async () => {
    const res = await fetch(url(api, "/getAccount"));
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.count, 3);
    assert.equal(new Set(body.accounts.map((a) => a.id)).size, 3, "account ids must be unique");
  });

  it("GET /getAccount?id= returns the matching account", async () => {
    const list = await (await fetch(url(api, "/getAccount"))).json();
    for (const account of list.accounts) {
      const res = await fetch(url(api, `/getAccount?id=${account.id}`));
      assert.equal(res.status, 200);
      assert.equal((await res.json()).account_number, account.account_number);
    }
  });

  it("GET /getAccount?id=<unknown> returns 404", async () => {
    const res = await fetch(url(api, "/getAccount?id=does-not-exist"));
    assert.equal(res.status, 404);
  });

  it("unknown routes return 404 and non-GET methods return 405", async () => {
    assert.equal((await fetch(url(api, "/nope"))).status, 404);
    const res = await fetch(url(api, "/health"), { method: "POST" });
    assert.equal(res.status, 405);
    assert.equal(res.headers.get("allow"), "GET, HEAD");
  });

  it("sends security headers and hides the framework", async () => {
    const res = await fetch(url(api, "/getAccount"));
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    assert.equal(res.headers.get("cache-control"), "no-store");
    assert.equal(res.headers.get("x-powered-by"), null);
  });

  it("does not serve /metrics on the public port", async () => {
    assert.equal((await fetch(url(api, "/metrics"))).status, 404);
  });
});

describe("metrics", () => {
  it("labels by route template so unknown paths cannot create new series", async () => {
    for (let i = 0; i < 5; i++) await fetch(url(api, `/random-${i}`));
    const text = await (await fetch(url(metrics, "/metrics"))).text();
    assert.doesNotMatch(text, /route="\/random-/);
    assert.match(text, /http_requests_total\{method="GET",route="unmatched",status_code="404"\} \d+/);
    assert.match(text, /http_requests_total\{method="GET",route="\/getAccount",status_code="200"\} \d+/);
  });

  it("exposes a latency histogram and an in-flight gauge", async () => {
    const text = await (await fetch(url(metrics, "/metrics"))).text();
    assert.match(text, /http_request_duration_seconds_bucket\{le="0.005",method="GET",route="\/health",status_code="200"\}/);
    assert.match(text, /http_requests_in_flight 0/);
  });
});
