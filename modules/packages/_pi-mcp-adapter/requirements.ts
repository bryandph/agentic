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

export function missingMcpServers(required: readonly string[], connected: readonly string[]): string[] {
  const live = new Set(connected);
  return [...new Set(required)].filter(name => !live.has(name));
}

/** One closure per session; observational only, including when UI/logging fails. */
export function createRequiredMcpWarning(required: readonly string[]) {
  let checked = false;
  return (ctx: { hasUI: boolean; ui: { notify(message: string, level: "warning"): void } }, connected: readonly string[], warn: (message: string) => void) => {
    if (checked) return;
    checked = true;
    try {
      const missing = missingMcpServers(required, connected);
      if (!missing.length) return;
      const message = `MCP: required servers not connected: ${missing.join(", ")}. Warning only; this session will continue.`;
      if (ctx.hasUI) ctx.ui.notify(message, "warning");
      else warn(message);
    } catch {
      // Unknown state and reporting failures must never affect the session.
    }
  };
}
