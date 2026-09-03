# OpenRouter Cost Manager

An [Omarchy](https://omarchy.org/) bar widget that shows your OpenRouter credit balance in the status bar, with a popup panel for viewing and managing API keys.

![preview](preview.png)

## Features

- **Bar pill** — live OpenRouter credit balance at a glance
- **Popup panel** — manage API keys: create, view, and delete keys
- **Native theming** — follows the Omarchy theme (colors.toml) and switches live on theme change
- Hot-reloads on edit, like all Omarchy shell plugins

## Install

```bash
omarchy plugin add https://github.com/jaybodecode/omarchy-openrouter-cost-tracker --enable
```

Or enable it afterwards:

```bash
omarchy plugin enable openrouter.bar --section right
```

## Configuration

The plugin stores its settings (API key, refresh interval) in:

```
~/.config/openrouter-bar/config.json
```

Create a management key at [openrouter.ai/keys](https://openrouter.ai/keys) and add it through the panel, or edit the config file directly.

## Requirements

- Omarchy Quattro (4.x) with the Omarchy shell
- An OpenRouter account with API access

## Security

Your API key is stored locally in `~/.config/openrouter-bar/config.json` and is only sent to `openrouter.ai` over HTTPS. The plugin requests no other network access.

## License

[MIT](LICENSE)
