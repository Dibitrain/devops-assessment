// Runtime configuration, read once from the environment (12-factor).
function int(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`Environment variable ${name} must be a non-negative integer, got '${raw}'`);
  }
  return value;
}

export const config = {
  port: int("PORT", 3000),
  // /metrics is served on its own port so it is never reachable through the public load balancer.
  metricsPort: int("METRICS_PORT", 9100),
  // When set, GET /getAccount requires a matching `x-api-key` header. Injected from AWS Secrets Manager in EKS.
  apiKey: process.env.API_KEY ?? "",
  // Number of reverse proxies in front of the app (1 behind the AWS ALB) so req.ip is the real client.
  trustProxyHops: int("TRUST_PROXY_HOPS", 0),
  // On SIGTERM, keep serving while the load balancer deregisters the pod, then drain connections.
  shutdownDelayMs: int("SHUTDOWN_DELAY_MS", 5000),
  shutdownTimeoutMs: int("SHUTDOWN_TIMEOUT_MS", 20000),
  // Must exceed the ALB idle timeout (60s) so the ALB, not Node, closes idle keep-alive connections.
  keepAliveTimeoutMs: int("KEEP_ALIVE_TIMEOUT_MS", 65000),
  logLevel: process.env.LOG_LEVEL ?? "info",
};
