import type { Server } from "node:http";
import { Container } from "typedi";
import { app, metricsApp } from "./app.js";
import { config } from "./config.js";
import { logger } from "./logger.js";
import { LifecycleService } from "./services/lifecycle.service.js";

const server: Server = app.listen(config.port, () => {
  logger.info("API listening", { port: config.port });
});
// Node closes idle keep-alive sockets after 5s by default, which races the ALB (60s idle timeout) and
// causes sporadic 502s. Keep sockets open longer than the ALB does.
server.keepAliveTimeout = config.keepAliveTimeoutMs;
server.headersTimeout = config.keepAliveTimeoutMs + 1000;

const metricsServer: Server = metricsApp.listen(config.metricsPort, () => {
  logger.info("Metrics listening", { port: config.metricsPort });
});

const lifecycle = Container.get(LifecycleService);

// Graceful shutdown. Kubernetes sends SIGTERM and removes the pod from endpoints at the same time, but
// the ALB takes a few seconds to stop routing to it. So: fail readiness, keep serving for
// SHUTDOWN_DELAY_MS, then stop accepting connections and let in-flight requests finish.
function shutdown(signal: string): void {
  if (lifecycle.isShuttingDown) return;
  lifecycle.beginShutdown();
  logger.info("shutdown started", { signal, delayMs: config.shutdownDelayMs });

  const forceExit = setTimeout(() => {
    logger.error("shutdown timed out, forcing exit", { timeoutMs: config.shutdownTimeoutMs });
    process.exit(1);
  }, config.shutdownTimeoutMs);
  forceExit.unref();

  setTimeout(() => {
    server.close((err) => {
      metricsServer.close();
      if (err) {
        logger.error("error while closing server", { error: err.message });
        process.exit(1);
      }
      logger.info("shutdown complete");
      process.exit(0);
    });
    // Close idle keep-alive sockets now; busy ones close once their response is sent.
    server.closeIdleConnections();
  }, config.shutdownDelayMs);
}

// Registering handlers matters when Node runs as PID 1 in a container: PID 1 ignores signals that have
// no handler, which would otherwise turn every rollout into a 30s wait followed by SIGKILL.
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
