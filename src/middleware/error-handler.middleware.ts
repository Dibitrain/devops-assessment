import type { NextFunction, Request, Response } from "express";
import { ExpressErrorMiddlewareInterface, HttpError, Middleware } from "routing-controllers";
import { Service } from "typedi";
import { logger } from "../logger.js";

@Service()
@Middleware({ type: "after" })
export class ErrorHandlerMiddleware implements ExpressErrorMiddlewareInterface {
  error(error: unknown, req: Request, res: Response, next: NextFunction): void {
    if (res.headersSent) {
      next();
      return;
    }

    const status = error instanceof HttpError ? error.httpCode : 500;

    // Client errors carry a deliberate message. Server errors may carry internals (stack details,
    // hostnames, SQL), so the caller gets a generic message and the detail goes to the logs only.
    if (status >= 500) {
      logger.error("unhandled error", {
        method: req.method,
        path: req.path,
        traceId: req.get("x-amzn-trace-id"),
        error: error instanceof Error ? { name: error.name, message: error.message, stack: error.stack } : String(error),
      });
      res.status(status).json({ error: "Internal server error" });
      return;
    }

    const message = error instanceof Error && error.message ? error.message : "Request failed";
    res.status(status).json({ error: message });
  }
}
