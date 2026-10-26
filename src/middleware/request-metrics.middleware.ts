import type { NextFunction, Request, Response } from "express";
import { ExpressMiddlewareInterface, Middleware } from "routing-controllers";
import { Service } from "typedi";
import { logger } from "../logger.js";
import { MetricsService } from "../services/metrics.service.js";

// Probe traffic is high-volume and uninteresting; it is still counted in metrics but not access-logged.
const QUIET_ROUTES = new Set(["/health", "/ready"]);

// Resolve the matched route *template* (e.g. "/getAccount"), never the raw path. Raw paths are
// attacker-controlled, so using them as a label lets anyone create unlimited time series.
function routeLabel(req: Request): string {
  const path: unknown = req.route?.path;
  return typeof path === "string" ? `${req.baseUrl}${path}` : "unmatched";
}

@Service()
@Middleware({ type: "before" })
export class RequestMetricsMiddleware implements ExpressMiddlewareInterface {
  constructor(private readonly metrics: MetricsService) {}

  use(req: Request, res: Response, next: NextFunction): void {
    const start = process.hrtime.bigint();
    this.metrics.requestStarted();

    // "close" fires for completed and aborted requests alike, so the in-flight gauge never leaks.
    res.once("close", () => {
      const seconds = Number(process.hrtime.bigint() - start) / 1e9;
      const route = routeLabel(req);
      this.metrics.observeRequest(req.method ?? "UNKNOWN", route, res.statusCode, seconds);

      if (!QUIET_ROUTES.has(route)) {
        logger.info("request", {
          method: req.method,
          route,
          path: req.path,
          status: res.statusCode,
          durationMs: Math.round(seconds * 1000),
          clientIp: req.ip,
          traceId: req.get("x-amzn-trace-id"),
          userAgent: req.get("user-agent"),
        });
      }
    });
    next();
  }
}
