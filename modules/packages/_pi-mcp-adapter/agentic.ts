import {
  getAgentDir,
  hasTrustRequiringProjectResources,
  ProjectTrustStore,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { createMcpAdapter } from "./index.ts";
import { loadGlobalMcpConfig } from "./config.ts";

/** Pi 0.85.1 returns true without consulting trust when only .mcp.json exists.
 * Use Pi's own store for that case, never create another trust database.
 */
export function projectConfigTrusted(ctx: ExtensionContext): boolean {
  if (typeof ctx.isProjectTrusted !== "function" || !ctx.isProjectTrusted()) return false;
  if (hasTrustRequiringProjectResources(ctx.cwd)) return true;
  const end = process.argv.indexOf("--");
  const args = end === -1 ? process.argv : process.argv.slice(0, end);
  if (args.includes("--no-approve") || args.includes("-na")) return false;
  if (args.includes("--approve") || args.includes("-a")) return true;
  try {
    return new ProjectTrustStore(getAgentDir()).get(ctx.cwd) === true;
  } catch {
    return false;
  }
}

export default function agenticMcp(pi: ExtensionAPI) {
  // Flags must exist before CLI parsing; upstream registers this again later.
  pi.registerFlag("mcp-config", {description: "Path to MCP config file", type: "string"});
  let starts: Array<(event: unknown, ctx: ExtensionContext) => unknown> | undefined;
  pi.on("session_start", async (event, ctx) => {
    if (!starts) {
      starts = [];
      // Delay *all* upstream config discovery until Pi has resolved trust.
      // Replay its session_start handler once; other events retain normal Pi
      // registration and upstream owns shutdown, cancellation, and reload.
      const deferredPi = new Proxy(pi, {
        get(target, key) {
          if (key === "on") return (name: string, handler: (event: unknown, ctx: ExtensionContext) => unknown) => {
            if (name === "session_start") starts!.push(handler);
            else target.on(name as never, handler as never);
          };
          return Reflect.get(target, key);
        },
      });
      const trusted = projectConfigTrusted(ctx);
      const configPath = pi.getFlag("mcp-config") as string | undefined;
      createMcpAdapter(trusted
        ? {cwd: ctx.cwd, configPath}
        : {config: loadGlobalMcpConfig()})(deferredPi);
      if (!trusted && ctx.hasUI) {
        ctx.ui.notify("MCP: user servers only. Project MCP requires Pi project trust; use /trust and restart, or --approve for one run.", "info");
      }
    }
    for (const start of starts) await start(event, ctx);
  });
}
