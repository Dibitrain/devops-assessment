import { Service } from "typedi";

// Tracks whether the process is draining so /ready can tell the load balancer to stop sending traffic.
@Service()
export class LifecycleService {
  private shuttingDown = false;

  get isShuttingDown(): boolean {
    return this.shuttingDown;
  }

  beginShutdown(): void {
    this.shuttingDown = true;
  }
}
