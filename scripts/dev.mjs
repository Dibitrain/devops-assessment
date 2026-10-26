// Watch mode for local development: `tsc --watch` recompiles, `node --watch` restarts on output changes.
//
// The previous `tsx watch` script compiled with esbuild, which does not emit decorator metadata.
// TypeDI needs that metadata for constructor injection, so every request crashed under `npm run dev`.
// Compiling with tsc keeps dev identical to the production build.
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";

const isWindows = process.platform === "win32";
const children = [];
const run = (cmd, args) => {
  const child = spawn(cmd, args, { stdio: "inherit", shell: isWindows });
  children.push(child);
  return child;
};

run("npx", ["tsc", "--watch", "--preserveWatchOutput"]);
while (!existsSync("dist/server.js")) await sleep(250);
run(process.execPath, ["--watch", "dist/server.js"]);

const stop = () => {
  for (const child of children) child.kill();
  process.exit(0);
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
