## Summary

<!-- What does this change do and why? -->

## Changes

<!-- Bullet the notable changes. -->

## Scope guardrails

<!-- Confirm this change respects the project's standing scope rules. -->

- [ ] No new gameplay loop, currency, streamers, or monetization added out of scope
- [ ] Server stays authoritative (client never authors Bucks, stats, feed rows, ranks, or roll results)
- [ ] No offline income / idle simulation introduced

## Verification

- [ ] `stylua --check src` passes
- [ ] `rojo build default.project.json` succeeds
- [ ] Type check reviewed (`luau-lsp analyze`, advisory)
- [ ] Tested in Studio where applicable
