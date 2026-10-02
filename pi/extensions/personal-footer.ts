import { homedir } from "node:os";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

function tokens(n: number) {
  return n < 1000 ? `${n}` : n < 10000 ? `${(n / 1000).toFixed(1)}k` : `${Math.round(n / 1000)}k`;
}

export default function (pi: ExtensionAPI) {
  let timer: ReturnType<typeof setInterval> | undefined;
  let hud = "";
  let renderFooter = () => {};

  async function refreshHud(ctx: ExtensionContext) {
    try {
      const result = await pi.exec("hud", ["bar"], { timeout: 3000, cwd: ctx.cwd });
      hud = result.code === 0 ? result.stdout.trim().replace(/[\r\n]/g, " ") : "";
    } catch {
      hud = "";
    }
    renderFooter();
  }

  async function refreshPr(ctx: ExtensionContext) {
    try {
      const root = await pi.exec("git", ["rev-parse", "--show-toplevel"], { cwd: ctx.cwd, timeout: 3000 });
      if (root.code !== 0) {
        ctx.ui.setStatus("personal-pr", undefined);
        return;
      }
      const result = await pi.exec("gh", ["pr", "view", "--json", "url,state"], { cwd: root.stdout.trim(), timeout: 5000 });
      const pr = result.code === 0 ? JSON.parse(result.stdout) : null;
      ctx.ui.setStatus("personal-pr", pr?.url ? `${pr.url}${pr.state === "OPEN" ? "" : ` (${pr.state.toLowerCase()})`}` : undefined);
    } catch {
      ctx.ui.setStatus("personal-pr", undefined);
    }
  }

  pi.on("session_start", async (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    ctx.ui.setFooter((tui, theme, data) => {
      const unsubscribe = data.onBranchChange(() => tui.requestRender());
      renderFooter = () => tui.requestRender();
      return {
        dispose() { unsubscribe(); renderFooter = () => {}; },
        invalidate() {},
        render(width: number): string[] {
          const cwd = ctx.sessionManager.getCwd();
          const home = homedir();
          const path = cwd === home ? "~" : cwd.startsWith(`${home}/`) ? `~${cwd.slice(home.length)}` : cwd;
          const branch = data.getGitBranch();
          const name = ctx.sessionManager.getSessionName();
          const location = `${path}${branch ? ` (${branch})` : ""}${name ? ` • ${name}` : ""}`;

          let input = 0, output = 0, cacheRead = 0, cacheWrite = 0, cost = 0;
          for (const entry of ctx.sessionManager.getEntries()) {
            if (entry.type === "message" && entry.message.role === "assistant") {
              const usage = (entry.message as AssistantMessage).usage;
              input += usage.input;
              output += usage.output;
              cacheRead += usage.cacheRead;
              cacheWrite += usage.cacheWrite;
              cost += usage.cost.total;
            }
          }
          const usage = ctx.getContextUsage();
          const percent = usage?.percent == null ? "?" : `${usage.percent.toFixed(1)}%`;
          const window = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
          const stats = [
            input && `↑${tokens(input)}`, output && `↓${tokens(output)}`,
            cacheRead && `R${tokens(cacheRead)}`, cacheWrite && `W${tokens(cacheWrite)}`,
            cost && `$${cost.toFixed(3)}`, `${percent}/${tokens(window)}`,
          ].filter(Boolean).join(" ");
          const model = ctx.model?.id ?? "no-model";
          const right = ctx.model?.reasoning ? `${model} • ${ctx.thinkingLevel ?? "off"}` : model;
          const gap = " ".repeat(Math.max(2, width - visibleWidth(stats) - visibleWidth(right)));
          const lines = [
            truncateToWidth(theme.fg("dim", location), width),
            truncateToWidth(theme.fg("dim", stats + gap + right), width),
          ];
          const statuses = [...data.getExtensionStatuses().entries()]
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([, text]) => text.replace(/[\r\n\t]/g, " "));
          if (statuses.length) lines.push(truncateToWidth(statuses.join(" "), width));
          if (hud) lines.push(truncateToWidth(hud, width));
          return lines;
        },
      };
    });
    await Promise.all([refreshHud(ctx), refreshPr(ctx)]);
    if (timer) clearInterval(timer);
    timer = setInterval(() => void refreshHud(ctx), 30_000);
    timer.unref();
  });

  pi.on("turn_end", async (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    await Promise.all([refreshHud(ctx), refreshPr(ctx)]);
  });

  pi.on("session_shutdown", () => {
    if (timer) clearInterval(timer);
    timer = undefined;
    renderFooter = () => {};
  });
}
