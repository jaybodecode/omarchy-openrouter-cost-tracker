# Marketplace submission notes

Ready-to-paste values for the `submit-plugin.yml` issue form at
`omacom/omarchy-plugin-marketplace`. Listing pins the exact current commit —
push all changes before submitting.

- **Submitted:** not yet (held until validated on a clean machine)
- **Listing commit:** see `git rev-parse main` after final push

## Form values

- **Title:** `[Plugin]: OpenRouter Cost Manager`
- **Repository URL:** https://github.com/jaybodecode/omarchy-openrouter-cost-tracker
- **Category:** Developer Tools
- **Tags:** `Bar`, `AI`, `Quickshell`
- **Suggested missing tag:** (none)

## Maintainer notes

OpenRouter credit balance bar widget (`bar-widget` kind) with popup panel for
API key management.

Capabilities:

- Live credit balance pill with hover glance and red low-balance warning
- Per-API-key usage totals with progress bar and % used; supports fixed caps
  and daily/weekly/monthly period caps (uses OpenRouter's usage_daily /
  usage_weekly / usage_monthly fields, matching their UTC reset schedule)
- Create / edit (cap, reset schedule) / disable / delete API keys
- Red ≥ 90%-of-cap warning in both the panel and the bar pill
- Local "true cost" spend counter with user-resettable baseline
- Pins for favorite keys; right-click balance notification; middle-click refresh

Security / permissions:

- Management key stored in the system keyring (libsecret secret-tool);
  never written to disk in plaintext
- Network: HTTPS to openrouter.ai only; no telemetry
- No elevated permissions; no sandbox escape; QML + two local helper scripts
  (Python/bash) shipped inside the plugin folder — self-contained after
  `omarchy plugin add`
- External dependencies (all stock on Omarchy): python3, jq, libsecret

Install and removal instructions are in the README (including keyring cleanup
on removal).
