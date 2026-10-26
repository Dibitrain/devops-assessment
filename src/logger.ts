import { config } from "./config.js";

// Minimal structured (JSON-lines) logger. stdout is collected by the node's log agent and shipped to
// CloudWatch, so one JSON object per line is all that is needed and avoids another dependency.
const levels = { debug: 10, info: 20, warn: 30, error: 40 } as const;
type Level = keyof typeof levels;

const threshold = levels[(config.logLevel as Level) in levels ? (config.logLevel as Level) : "info"];

function write(level: Level, msg: string, fields: Record<string, unknown> = {}): void {
  if (levels[level] < threshold) return;
  const line = JSON.stringify({ time: new Date().toISOString(), level, msg, ...fields });
  if (levels[level] >= levels.error) process.stderr.write(line + "\n");
  else process.stdout.write(line + "\n");
}

export const logger = {
  debug: (msg: string, fields?: Record<string, unknown>) => write("debug", msg, fields),
  info: (msg: string, fields?: Record<string, unknown>) => write("info", msg, fields),
  warn: (msg: string, fields?: Record<string, unknown>) => write("warn", msg, fields),
  error: (msg: string, fields?: Record<string, unknown>) => write("error", msg, fields),
};
