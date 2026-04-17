# Tool Selection Guide — Playwright vs Chrome MCP

**TL;DR:** Playwright primary for extraction (network hooks, clip screenshot, parallel context). Chrome MCP secondary for orchestrator review + authenticated sites + live user feedback.

## Decision matrix per step

| Step | Playwright | Chrome MCP | Primary tool | Reason |
|------|------------|------------|--------------|--------|
| 1.1 Screenshot 3 viewport | ✅ `fullPage:true` + viewport switch native | ⚠️ scroll+stitch workaround | **Playwright** | full-page stitched |
| 1.2 Section map | ✅ `evaluate` | ✅ `javascript_tool` | Either | DOM query |
| 1.2b Visual wrapper scan | ✅ | ✅ | Either | DOM query |
| 1.3 Design tokens | ✅ | ✅ | Either | |
| 1.3b Custom properties (v2) | ✅ | ✅ | Either | |
| 1.3.5 Network tracking (v2) | ✅ `page.on('response')` | ❌ no equivalent | **Playwright only** | network listener required |
| 1.4 Scroll lib detection | ✅ | ✅ | Either | |
| 1.5 Interaction sweep | ⚠️ scripted | ✅ live click/scroll | **Chrome MCP** | iterative exploration |
| 1.6 Responsive comparison | ✅ viewport switch batch | ✅ resize_window | Either | |
| 2.1-2.3 Asset download | — | — | **Bash (wget/curl)** | no browser needed |
| 2.4 Binding map | ✅ | ✅ | Either | |
| 3.1 Section screenshot (clip) | ✅ `clip:{x,y,w,h}` | ⚠️ post-process crop | **Playwright** | native clip |
| 3.2 Deep CSS extract | ✅ | ✅ | Either | |
| 3.2b Component tree | ✅ | ✅ | Either | |
| 3.3b CSSOM hover (v2) | ✅ | ✅ | Either | CSSOM read, no mouse needed |
| 3.5 Visual comparison | ⚠️ scripted | ✅ live review | **Chrome MCP** | user sees differences |
| 3.6 Orchestrator diff | ✅ snapshot diff | ⚠️ limited | **Playwright (diff) + Chrome MCP (show)** | JSON analysis + live show |
| 3.6b Snapshot diff (v2) | ✅ | ⚠️ limited eval chain | **Playwright** | two-context parallel |
| 4.x Full-page QA | ✅ fullPage screenshot | ✅ live browser | Either | |

## When Chrome MCP is required (not optional)

- **Authenticated pages** — Playwright fresh context has no login; Chrome MCP uses user's Chrome profile
- **User wants to watch the process live** — orchestrator review, debugging a failed clone
- **Claude needs to verify a single CSS property interactively** — faster than writing a script

## When Playwright is required (not optional)

- **Network request interception** — font URL validation, asset discovery (Step 1.3.5)
- **Viewport-clipped section screenshot** — section-by-section comparison (Step 3.1)
- **Parallel contexts** — compare two sites at once (Step 3.6)
- **Full-page stitched screenshot** — reference images (Step 1.1)
- **Headless CI execution** — when skill is run as part of an automated pipeline

## When either works

- Plain DOM queries via `evaluate` / `javascript_tool`
- Single-viewport screenshots (no clip, no full-page stitch)
- Simple navigation + page load

## Browser tier caveat (computer-use)

Chrome MCP tools run at Chrome's "read" tier by default:
- ✅ Read DOM, take screenshots, run JS
- ❌ Simulate mouse hover (may be restricted)
- ❌ Type into inputs (restricted)

For form-filling, clicking, navigation flows → Chrome MCP handles these through dedicated tools (`left_click`, `form_input`, `navigate`), not raw computer-use.

For hover state extraction → use CSSOM approach (Step 3.3b v2), no mouse simulation needed.

## Tool setup checklist

**Playwright:**

```bash
node --version  # 18+
npx playwright --version
# If missing:
npx -y playwright install chromium
```

**Chrome MCP:**

- Extension must be installed in Chrome
- Use ToolSearch with `select:mcp__claude-in-chrome__<name>` to load specific tools
- Call `tabs_context_mcp` at session start to discover existing tabs
