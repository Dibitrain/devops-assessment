import client from "prom-client";
import { Service } from "typedi";

@Service()
export class MetricsService {
  readonly register = new client.Registry();

  private readonly httpRequestsTotal = new client.Counter({
    name: "http_requests_total",
    help: "Total number of HTTP requests received",
    labelNames: ["method", "route", "status_code"],
    registers: [this.register],
  });

  // Latency histogram: drives the p50/p95/p99 panels and the latency SLO alert.
  private readonly httpRequestDuration = new client.Histogram({
    name: "http_request_duration_seconds",
    help: "HTTP request duration in seconds",
    labelNames: ["method", "route", "status_code"],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
    registers: [this.register],
  });

  private readonly httpRequestsInFlight = new client.Gauge({
    name: "http_requests_in_flight",
    help: "HTTP requests currently being served",
    registers: [this.register],
  });

  constructor() {
    client.collectDefaultMetrics({ register: this.register });
  }

  get contentType(): string {
    return this.register.contentType;
  }

  requestStarted(): void {
    this.httpRequestsInFlight.inc();
  }

  // `route` must be a bounded value (a route template or "unmatched"), never the raw request path.
  observeRequest(method: string, route: string, statusCode: number, durationSeconds: number): void {
    const labels = { method, route, status_code: String(statusCode) };
    this.httpRequestsTotal.inc(labels);
    this.httpRequestDuration.observe(labels, durationSeconds);
    this.httpRequestsInFlight.dec();
  }

  async render(): Promise<string> {
    return this.register.metrics();
  }
}
