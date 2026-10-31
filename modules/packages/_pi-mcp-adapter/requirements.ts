import { readFileSync } from "node:fs";

/** This sentence is a renderer contract, exercised with renderCotal in checks. */
export function parseRequiredMcpServers(persona: string): string[] {
  const match = persona.match(/^[\t ]*MCP[\t ]+servers[\t ]+required[\t ]+for[\t ]+this[\t ]+role[\t ]*:[\t ]*([^\r\n]+?)[\t ]*\.[\t ]*$/m);
  if (!match) return [];
  const items = match[1].split(",");
  if (!items.every(item => /^[\t ]*`[^`\s,]+`[\t ]*$/.test(item))) return [];
  return [...new Set(items.map(item => item.trim().slice(1, -1)))];
}

export function readRequiredMcpServers(path = process.env.COTAL_AGENT_FILE): string[] {
  try {
    return path ? parseRequiredMcpServers(readFileSync(path, "utf8")) : [];
  } catch {
    return [];
  }
}

export interface McpAvailability {
  configured: string[];
  disabled: string[];
  failed: string[];
  needsAuth: string[];
}

/** Lazy servers need not connect at startup: only known unavailability warns. */
export function missingMcpServers(required: readonly string[], state: McpAvailability): string[] {
  return [...new Set(required)].flatMap(name => {
    const reason = !state.configured.includes(name) ? "not configured"
      : state.disabled.includes(name) ? "disabled"
      : state.needsAuth.includes(name) ? "needs auth"
      : state.failed.includes(name) ? "failed"
      : undefined;
    return reason ? [`${reason}: ${name}`] : [];
  });
}

/** One closure per session; observational only, including when UI/logging fails. */
export function createRequiredMcpWarning(required: readonly string[]) {
  let checked = false;
  return (ctx: { hasUI: boolean; ui: { notify(message: string, level: "warning"): void } }, state: McpAvailability, warn: (message: string) => void) => {
    if (checked) return;
    checked = true;
    try {
      const missing = missingMcpServers(required, state);
      if (!missing.length) return;
      const message = `MCP: required servers unavailable (${missing.join("; ")}). Warning only; this session will continue.`;
      if (ctx.hasUI) ctx.ui.notify(message, "warning");
      else warn(message);
    } catch {
      // Unknown state and reporting failures must never affect the session.
    }
  };
}
