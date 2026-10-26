import type { Response } from "express";
import { Get, JsonController, Res } from "routing-controllers";
import { Service } from "typedi";
import { LifecycleService } from "../services/lifecycle.service.js";

const startedAt = Date.now();

@Service()
@JsonController()
export class HealthController {
  constructor(private readonly lifecycle: LifecycleService) {}

  // Liveness: the process is up. Never depends on downstreams, so a slow dependency cannot cause restarts.
  @Get("/health")
  health(): { status: string; uptimeSeconds: number } {
    return {
      status: "ok",
      uptimeSeconds: Math.floor((Date.now() - startedAt) / 1000),
    };
  }

  // Readiness: should this pod receive traffic? Fails as soon as shutdown begins so the ALB drains it.
  @Get("/ready")
  ready(@Res() res: Response): Response {
    if (this.lifecycle.isShuttingDown) {
      return res.status(503).json({ status: "draining" });
    }
    return res.status(200).json({ status: "ready" });
  }
}
