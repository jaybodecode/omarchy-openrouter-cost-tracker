# OpenRouter Cost Manager

An [Omarchy](https://omarchy.org/) bar widget for tracking and managing your OpenRouter spending: live credit balance in the status bar, per-key usage meters, and full API key management from a popup panel.

![preview](preview.png)

## Features

**Status bar pill**

- Live OpenRouter credit balance ($ remaining), refreshed on a 30s cache
- Hover glance — flips between remaining balance and "spent" view
- Turns **red when you're running low** on balance or any key nears its cap (≥ 90%)
- Right-click for a desktop notification with your balance; middle-click to force refresh
- Optional "true cost" mode: reset the local spend counter anytime and the pill shows spend since that point (e.g. "this month so far")

**Per-key usage monitor** (popup panel)

- Total and per-API-key usage, with a progress bar and % used for every capped key
- Works for all cap types — fixed caps compare lifetime spend; daily / weekly / monthly caps compare the matching period usage from OpenRouter (weeks are Monday–Sunday UTC, matching OpenRouter's reset schedule)
- **Red warning** on any key at ≥ 90% of its cap — both in the panel and in the bar pill
- Pin your favorite keys to the top of the list

**API key management**

- Create new keys with a credit limit and reset schedule (never / daily / weekly / monthly)
- Edit caps and reset schedules on existing keys, enable/disable, delete
- One-time plaintext key reveal for newly created keys

## Install

```bash
omarchy plugin add https://github.com/jaybodecode/omarchy-openrouter-cost-tracker --enable
```

Or enable it afterwards:

```bash
omarchy plugin enable openrouter.bar --section right
```

The plugin is self-contained — its OpenRouter API helper scripts ship inside the plugin folder, so no extra setup is needed after install.

## Configuration

On first open, the panel asks for an **OpenRouter Management key** (create one at [openrouter.ai/settings/management-keys](https://openrouter.ai/settings/management-keys)).

- The key is stored in your **system keyring** (libsecret / `secret-tool` under `openrouter` / `management-key`) — never written to a plaintext file
- Preferences (pinned keys, spend counter, bar display) live in `~/.config/openrouter-bar/config.json`
- Fetched data is cached in `~/.local/state/openrouter-bar/cache.json`

## Requirements

- Omarchy Quattro (4.x) with the Omarchy shell
- Python 3, `jq`, and `libsecret` (`secret-tool`) — all present on stock Omarchy
- An OpenRouter account with a Management API key

## Security

- The management key is stored in the system keyring only; it is sent exclusively to `openrouter.ai` over HTTPS
- No telemetry, no other network access, no elevated permissions
- All code is QML plus two small local helper scripts (Python/bash) that ship inside the plugin folder

## Remove

```bash
omarchy plugin remove openrouter.bar
```

Optionally delete leftover settings and forget the keyring entry:

```bash
rm -rf ~/.config/openrouter-bar ~/.local/state/openrouter-bar
secret-tool clear openrouter management-key
```

## License

[MIT](LICENSE)
