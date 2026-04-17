# Klonlama Skill v2 Changelog

**Release:** 2026-04-17
**Previous version:** v1 (2026-04-15)

## Summary

v2 is a **hardening release** — the v1 workflow (component-first, section-by-section, spec → builder → orchestrator) is unchanged. Four new techniques address specific v1 weaknesses, and tool usage is now explicit with `[TOOL: ...]` tags.

## New features

### 1. CSS custom properties extraction (Step 1.3b)
- **Problem:** v1 extracted computed colors (e.g. `rgb(0, 76, 147)`) but ignored `--primary: #004C93` design tokens
- **Fix:** extract `--X` vars from `:root`, `body`, and all CSS rules
- **Benefit:** Tailwind config maps to token variables, single-source color changes

### 2. Network response tracking (Step 1.3.5)
- **Problem:** v1's `@font-face` URL resolver sometimes downloaded HTML error pages or stylesheet URLs as fonts (verified 83% accuracy on real test site — 1 of 6 font URLs was a CSS file)
- **Fix:** `page.on('response')` listener logs the actual URLs the browser fetches
- **Benefit:** font URLs are verified against real network activity, not guessed via CSS parsing. Also catches dynamically-loaded fonts (e.g. Google Fonts injected via JS) that v1 misses entirely

### 3. CSSOM-based hover extraction (Step 3.3b revised)
- **Problem:** v1 required mouse-hover simulation + re-extraction (slow, flaky, restricted by Chrome MCP tier)
- **Fix:** read `:hover` rules directly from `document.styleSheets`
- **Benefit:** faster, no mouse simulation, works in Chrome MCP read-tier contexts. Verified 327 hover rules captured on real test site vs heuristic-only in v1

### 4. Computed-style snapshot diff (Step 3.6b)
- **Problem:** v1's pixel comparison was noisy — font anti-aliasing produced false positives
- **Fix:** snapshot computed CSS properties as JSON, diff between original and clone
- **Benefit:** exact property-level differences with node paths, fewer orchestrator iterations. Self-diff verified 0 false positives with 2s animation settle

## Breaking changes

None. All v1 steps still present and work as before. v2 adds alongside v1.

## Tool clarifications

Phase headings now carry `[TOOL: ...]` tags:

- `## PHASE 1: Reconnaissance [TOOL: Playwright primary, Chrome MCP for interaction sweep]`
- `## PHASE 2: Asset Collection [TOOL: Playwright (extraction) + Bash/curl (download)]`
- `## PHASE 3: Section-by-Section Cloning [TOOL: Playwright (extraction+diff), Chrome MCP (review)]`
- `## PHASE 4: Assembly & Final QA [TOOL: Playwright (screenshot), Chrome MCP (live review)]`

See `references/tool-selection.md` for the full decision matrix.

## Migration from v1

If you have a v1 in-progress clone:

1. Keep going with v1 steps — they still work
2. Where v2 adds a new step (1.3b, 1.3.5, 3.6b), run it as an additional extraction (non-destructive)
3. For Step 3.3b (hover), you can re-run the new CSSOM version; it replaces v1's output cleanly

If you're starting a new clone:

- Follow v2 from the start
- Use the updated checklist in SKILL.md's "Quick Reference" section (4 new v2 checkbox items marked with `**bold**`)

## Known limitations

- **CSSOM hover** extraction misses cross-origin stylesheets (CORS). Rare in practice; most sites self-host CSS.
- **Snapshot diff** is deterministic only when animations are paused. Use `page.waitForTimeout(2000)` before snapshotting or emulate `prefers-reduced-motion: reduce`.
- **Network tracking** may capture tracker/analytics requests. Apply the optional URL filter in Step 1.3.5.
- **Custom properties** extraction can't read CORS-blocked stylesheets (same as hover). Fallback: only `:root`/`body` computed vars are captured in that case.

## Test baseline (isautier-ipp.com, WordPress + Salient theme)

Real measurements from the v2 release test:

| Metric | v1 | v2 |
|--------|----|----|
| Font URLs captured | 6 (1 wrong = CSS file) | 5 real woff/woff2 + detected 1 v1-missed Google Font |
| Font URL accuracy | 83% | 100% |
| Hover rules captured | 127 (heuristic — elements matching `:hover`-likely selectors) | 327 (actual `:hover` CSS rules from CSSOM) |
| Custom properties | 0 (not extracted) | 133 root + 133 sheet vars |
| Snapshot diff self-test | N/A | 0 false-positive drift with 2s settle |

## References

- Full design spec: `docs/superpowers/specs/2026-04-17-klonlama-v2-design.md`
- Implementation plan: `docs/superpowers/plans/2026-04-17-klonlama-v2-hardening.md`
- Tool selection guide: `references/tool-selection.md`
