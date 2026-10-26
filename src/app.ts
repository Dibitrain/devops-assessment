import "reflect-metadata";
import express from "express";
import { createExpressServer, useContainer } from "routing-controllers";
import { Container } from "typedi";
import { config } from "./config.js";
import { AccountController } from "./controllers/account.controller.js";
import { HealthController } from "./controllers/health.controller.js";
import { ErrorHandlerMiddleware } from "./middleware/error-handler.middleware.js";
import { NotFoundMiddleware } from "./middleware/not-found.middleware.js";
import { RequestMetricsMiddleware } from "./middleware/request-metrics.middleware.js";
import { SecurityHeadersMiddleware } from "./middleware/security-headers.middleware.js";
import { MetricsService } from "./services/metrics.service.js";

useContainer(Container);

// Public API: served on PORT and exposed through the load balancer.
export const app: express.Express = createExpressServer({
  controllers: [HealthController, AccountController],
  middlewares: [RequestMetricsMiddleware, SecurityHeadersMiddleware, NotFoundMiddleware, ErrorHandlerMiddleware],
  defaultErrorHandler: false,
});
app.disable("x-powered-by");
app.set("trust proxy", config.trustProxyHops);

// Internal metrics endpoint: served on METRICS_PORT, scraped by Prometheus inside the cluster and never
// routed by the Ingress. Keeping it off the public port removes it from the attack surface entirely.
export const metricsApp: express.Express = express();
metricsApp.disable("x-powered-by");
metricsApp.get("/metrics", async (_req, res, next) => {
  try {
    const metrics = Container.get(MetricsService);
    res.set("Content-Type", metrics.contentType).send(await metrics.render());
  } catch (err) {
    next(err);
  }
});
