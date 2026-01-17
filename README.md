# cc-minimal-statusline

A minimal status line for [Claude Code](https://github.com/anthropics/claude-code).

![Preview](https://raw.githubusercontent.com/runsonmypc/cc-minimal-statusline/main/preview.png)

## Features

- Version with update indicator (↑)
- Model name
- Smart path truncation (`~code/project/…/current`)
- Git branch + worktree indicator
- File & line changes (includes untracked files, unlike Claude Code's footer)
- Context usage with gradient bar + autocompact indicator

## Install

Requires a [Nerd Font](https://www.nerdfonts.com/). To install Meslo:

```bash
brew install --cask font-meslo-lg-nerd-font
```

Then select "MesloLGM Nerd Font" in your terminal settings.

```bash
npm install -g cc-minimal-statusline
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "cc-minimal-statusline",
    "padding": 0
  }
}
```

## Colors

Edit these variables in the script:

| Element | Variable | Default |
|---------|----------|---------|
| Version/separators | `C_DIM` | Gray (239) |
| Model | `C_ORANGE` | #E6714E |
| Directory | `C_BLUE` | Blue (75) |
| Worktree | `C_CYAN` | Cyan (80) |
| Branch | `C_PURPLE` | Purple (141) |
| +lines | `C_GREEN` | Green (108) |
| -lines | `C_RED` | Red (167) |

## License

MIT
