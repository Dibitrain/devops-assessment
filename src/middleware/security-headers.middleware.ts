import type { NextFunction, Request, Response } from "express";
import { ExpressMiddlewareInterface, Middleware } from "routing-controllers";
import { Service } from "typedi";

// Baseline headers for a JSON-only API. TLS terminates at the ALB, so HSTS is safe to send from here.
@Service()
@Middleware({ type: "before" })
export class SecurityHeadersMiddleware implements ExpressMiddlewareInterface {
  use(_req: Request, res: Response, next: NextFunction): void {
    res.set({
      "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "no-referrer",
      "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
      // Account data must never be cached by browsers or intermediaries.
      "Cache-Control": "no-store",
    });
    next();
  }
}
