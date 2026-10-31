import {
  getAgentDir,
  hasTrustRequiringProjectResources,
  ProjectTrustStore,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { createMcpAdapter } from "./index.ts";
import { loadGlobalMcpConfig, loadMcpConfig } from "./config.ts";
import { logger } from "./logger.ts";
import { createRequiredMcpWarning, readRequiredMcpServers } from "./requirements.ts";

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
  // Initial registration sees global files only. The resolver runs afresh for
  // every session, including hosts that retain this extension across cwd changes.
  let warnRequired = createRequiredMcpWarning([]);
  createMcpAdapter({
    config: loadGlobalMcpConfig(),
    onSessionConnected(ctx, connected) {
      warnRequired(ctx, connected, message => logger.warn(message));
    },
    resolveSessionConfig(ctx) {
      warnRequired = createRequiredMcpWarning(readRequiredMcpServers());
      if (projectConfigTrusted(ctx)) {
        return loadMcpConfig(pi.getFlag("mcp-config") as string | undefined, ctx.cwd);
      }
      if (ctx.hasUI) {
        ctx.ui.notify("MCP: user servers only. Project MCP requires Pi project trust; use /trust and restart, or --approve for one run.", "info");
      }
      return loadGlobalMcpConfig();
    },
  })(pi);
}
