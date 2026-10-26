import { createHash, timingSafeEqual } from "node:crypto";
import type { NextFunction, Request, Response } from "express";
import { ExpressMiddlewareInterface } from "routing-controllers";
import { Service } from "typedi";
import { config } from "../config.js";

const digest = (value: string) => createHash("sha256").update(value).digest();

// Protects account data with a shared API key when API_KEY is configured. Hashing both sides first
// gives equal-length buffers, so the comparison is constant-time and does not leak the key length.
@Service()
export class ApiKeyMiddleware implements ExpressMiddlewareInterface {
  private readonly expected = config.apiKey ? digest(config.apiKey) : undefined;

  use(req: Request, res: Response, next: NextFunction): void {
    if (!this.expected) {
      next();
      return;
    }

    const provided = req.get("x-api-key");
    if (provided && timingSafeEqual(digest(provided), this.expected)) {
      next();
      return;
    }

    res.status(401).json({ error: "Missing or invalid API key" });
  }
}
