import type { NextFunction, Request, Response } from "express";
import { ExpressMiddlewareInterface, Middleware } from "routing-controllers";
import { Service } from "typedi";

@Service()
@Middleware({ type: "after" })
export class NotFoundMiddleware implements ExpressMiddlewareInterface {
  use(req: Request, res: Response, next: NextFunction): void {
    if (res.headersSent) {
      next();
      return;
    }

    if (req.method !== "GET" && req.method !== "HEAD") {
      res.set("Allow", "GET, HEAD");
      res.status(405).json({
        error: "Method not allowed. This API only supports GET requests.",
      });
      return;
    }

    res.status(404).json({
      error: "Not found",
      availableEndpoints: [
        "GET /health",
        "GET /ready",
        "GET /getAccount",
        "GET /getAccount?id=<account id>",
      ],
    });
  }
}
