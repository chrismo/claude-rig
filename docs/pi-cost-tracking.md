# Why pi shows no cost in the footer

Verified against **pi 0.85.1** (`@earendil-works/pi-coding-agent`). Everything
below came from reading the shipped bundle and docs, not from the pi website.

The short version: **pi computes cost locally from its own model catalog.** It
never reads a cost field off the provider response. If your `models.json` entry
has no `cost` block, pi has no rates, the total is 0, and the footer silently
drops the `$` segment. That looks exactly like "the provider isn't returning
cost data" but has nothing to do with the provider.

## The footer is three lines

`dist/bundle/chunks/chunk-JVUZSMYM.js`, the footer component's `render()`:

```js
lines = [
  truncateToWidth(theme.fg("dim", pwd), width, ...),   // 0: cwd (+ git branch, + session name)
  dimStatsLeft + dimRemainder,                          // 1: stats ....... (provider) model • thinking
]
extensionStatuses = this.footerData.getExtensionStatuses();
if (extensionStatuses.size > 0) {
  lines.push(...)                                       // 2: extension statuses, omitted when none
}
```

| Line | Content | Reachable from an extension |
|------|---------|------------------------------|
| 0 | cwd, git branch, session name | `ctx.ui.setFooter()` only |
| 1 | token stats, cost, context %, model | `ctx.ui.setFooter()` only |
| 2 | extension statuses | `ctx.ui.setStatus(id, text)` |

`setStatus` can only ever write line 2. Several extensions share it — pi sorts
them by key and joins with a space. `setFooter` replaces all three, so a custom
footer has to call `getExtensionStatuses()` itself or other extensions' statuses
vanish.

## Every stats part is conditional

Still line 1, building `statsParts`:

```js
usageTotals.input      && statsParts.push(`↑${formatTokens(usageTotals.input)}`)
usageTotals.output     && statsParts.push(`↓${formatTokens(usageTotals.output)}`)
usageTotals.cacheRead  && statsParts.push(`R${formatTokens(usageTotals.cacheRead)}`)
usageTotals.cacheWrite && statsParts.push(`W${formatTokens(usageTotals.cacheWrite)}`)
;(usageTotals.cacheRead > 0 || usageTotals.cacheWrite > 0) && latestCacheHitRate !== undefined
  && statsParts.push(`CH${latestCacheHitRate.toFixed(1)}%`)

if (usageTotals.cost || usingSubscription) {
  statsParts.push(`$${usageTotals.cost.toFixed(3)}${usingSubscription ? " (sub)" : ""}`)
}
statsParts.push(contextPercentStr)   // always
```

A zero value is falsy, so it is **omitted entirely** — pi does not render
`$0.000`, it renders nothing. Only the context percentage is unconditional,
which is why a fresh session collapses to just:

```
0.0%/1.3M (auto)                                    (cloudflare-ai-gateway) workers-ai/@cf/zai-org/glm-5.3-flash • medium
```

Other line-1 behaviour worth knowing:

- The `(provider)` prefix only appears when more than one provider is
  configured, and it is the first thing dropped when the terminal is too narrow.
- `• medium` is the thinking level, shown only for models with `reasoning: true`.
- Context % is colored: yellow above 70%, red above 90%.

## Cost is computed, not reported

`node_modules/@earendil-works/pi-ai/dist/models.js:530`:

```js
export function calculateCost(model, usage) {
    const inputTokens = usage.input + usage.cacheRead + usage.cacheWrite;
    let rates = model.cost;
    let matchedThreshold = -1;
    for (const tier of model.cost.tiers ?? []) {
        if (inputTokens > tier.inputTokensAbove && tier.inputTokensAbove > matchedThreshold) {
            rates = tier;
            matchedThreshold = tier.inputTokensAbove;
        }
    }
    usage.cost.input  = (rates.input  / 1000000) * usage.input;
    usage.cost.output = (rates.output / 1000000) * usage.output;
    ...
}
```

Catalog rates × token counts. The provider's own accounting is never consulted.
LiteLLM can report its computed cost back (via response headers / hidden params
— recollection, not verified here), and pi will ignore it regardless.

## The zero default

`docs/models.md` in the pi package:

| Field | Required | Default |
|-------|----------|---------|
| `cost` | No | **all zeros** |

So a custom provider entry that omits `cost` gets zeros and therefore no `$` in
the footer. pi's own Ollama example ships exactly that:

```json
{
  "id": "llama3.1:8b",
  "contextWindow": 128000,
  "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
}
```

Easy to copy that shape into a LiteLLM provider block and inherit the zeros.

## Diagnosing it on the work stack

Look at whether the **token counts** appear on line 1:

- **`↑12.4k ↓1.8k` shows, no `$`** → catalog rates are zeros. Fix is adding real
  `cost` values to the `models.json` entries. LiteLLM is fine.
- **No token counts either** → usage genuinely isn't coming back, which *is* a
  stack problem. OpenAI-compatible streaming omits usage unless the request sets
  `stream_options: {include_usage: true}`, and a proxy can strip it.

The context percentage moves in both cases, so it tells you nothing.

## The fix shape

Real per-MTok rates in the `models.json` entry:

```json
{
  "providers": {
    "litellm": {
      "baseUrl": "https://litellm.internal/v1",
      "apiKey": "$LITELLM_API_KEY",
      "api": "openai-completions",
      "models": [
        {
          "id": "claude-sonnet-4-5",
          "reasoning": true,
          "input": ["text", "image"],
          "cost": { "input": 3, "output": 15, "cacheRead": 0.3, "cacheWrite": 3.75 }
        }
      ]
    }
  }
}
```

`cost` also takes `tiers` — a complete alternate rate set applied to the whole
request when `input + cacheRead + cacheWrite` exceeds `inputTokensAbove`, with
the highest matching threshold winning. That models long-context surcharges.

## Don't bother writing an extension for this

The obvious move is a `setStatus` extension that tallies
`ctx.sessionManager.getBranch()` and renders session spend. It is redundant with
line 1, and worse, it reads the same `usage.cost.total` — so on a zero-rate
catalog it prints `$0.000` and fixes nothing. Zeros in, zeros out.

`setFooter` is only worth it if you actually want to restructure lines 0 and 1,
and it means re-implementing the cwd line, the context-percent coloring, and
truncation by hand.

## Appendix: a provider that does have rates

The built-in `cloudflare-ai-gateway` provider ships real rates for all 18
Workers AI models that support function calling — $0.017/$0.112 per MTok for
`granite-4.0-h-micro` up to $1.40/$4.40 for `glm-5.3`. That is why cost shows up
there and not behind LiteLLM. Nothing about the gateway is special; it just has
a populated catalog.

Dumping the catalog rates, if you need the same trick for another provider:

```bash
cd "$(npm root -g)/@earendil-works/pi-coding-agent"
node -e '
const s=require("fs").readFileSync("dist/bundle/chunks/chunk-JVUZSMYM.js","utf8");
const start=s.indexOf("var cloudflare_ai_gateway_default=");
const seg=s.slice(start, s.indexOf("var CLOUDFLARE_AI_GATEWAY", start));
const re=/id:"(workers-ai\/[^"]+)"[\s\S]{0,600}?cost:\{input:([\d.e-]+),output:([\d.e-]+)/g;
let m; while((m=re.exec(seg))) console.log(m[2].padStart(8), m[3].padStart(8), " ", m[1]);
' | sort -k1 -n
```

The chunk hash moves between pi releases — re-find it with
`grep -rl "cloudflare-ai-gateway" dist/bundle/chunks/`.
