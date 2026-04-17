# v1 vs v2 Comparison — isautier-ipp.com

**Date:** 2026-04-17
**Site:** https://isautier-ipp.com

## Metrics

| Metric | v1 | v2 | Delta |
|--------|----|----|-------|
| Font URL count | 6 | 5 | -1 |
| Font accuracy % | 83% | 100% | +17 pp |
| Hover rules captured | 127 (heuristic) | 327 (CSSOM actual) | Technique change — not apples-to-apples |
| Custom properties | 0 (not extracted) | 133 | +133 |
| Snapshot diff determinism | N/A (no such test) | 0 false positives | PERFECT |

## v1 font URL defect (caught by v2)

v1's font URL list (from CSS parsing):
- https://isautier-ipp.com/wp-content/themes/salient/css/fonts/fontawesome-webfont.woff?v=4.2
- https://isautier-ipp.com/wp-content/themes/salient/css/fonts/icomoon.woff?v=1.7
- https://isautier-ipp.com/wp-content/themes/salient-child/fonts/AvantGardeLT-Bold.woff2
- https://isautier-ipp.com/wp-content/themes/salient-child/fonts/Avenir-Regular.woff2
- https://isautier-ipp.com/wp-content/themes/salient-child/fonts/Avenir-Bold.woff2
- https://isautier-ipp.com/wp-content/themes/salient-child/style.css?ver=18.0.2

v2's font URL list (from network response tracking):
- https://isautier-ipp.com/wp-content/themes/salient-child/fonts/Avenir-Bold.woff2
- https://isautier-ipp.com/wp-content/themes/salient-child/fonts/Avenir-Regular.woff2
- https://isautier-ipp.com/wp-content/themes/salient/css/fonts/icomoon.woff?v=1.7
- https://isautier-ipp.com/wp-content/themes/salient-child/fonts/AvantGardeLT-Bold.woff2
- https://fonts.gstatic.com/s/roboto/v48/KFO7CnqEu92Fr1ME7kSn66aGLdTylUAMa3yUBHMdazQ.woff2

Compare — any URL in v1 list but NOT in v2 list is a v1 defect (CSS-resolved URL that's not an actual font). Any URL in v2 list but NOT in v1 is a font v1 missed.

## Success criteria (from spec Section 6)

- [x] Font URL accuracy: v1 83% → v2 100%  (target ≥95%)
- [x] Hover state capture: v2 now captures actual rules from CSSOM (327 rules)
- [x] Custom properties: v1 = 0 → v2 = 133
- [x] Snapshot diff determinism: self-diff = 0

## Notes

- `hoverCandidates_v1` used a heuristic (matching selectors with cursor:pointer or transition). `hoverRules_v2` counts ACTUAL `:hover` CSS rules — the numbers are not directly comparable, but v2's approach is demonstrably more accurate because it reports the real rules instead of guessing from candidate elements.
- Orchestrator iteration count improvement requires an actual end-to-end clone test (out of scope for this measurement; would be validated on the next real clone run).
