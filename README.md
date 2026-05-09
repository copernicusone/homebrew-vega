# homebrew-vega

Homebrew tap for [Copernicus One Vega](https://copernicusone.pl) — a local PII-anonymizing proxy for AI clients.

## Available Formulae

| Formula | Language | Description |
|---------|----------|-------------|
| `c1-vega-plen` | PL + EN | PL + EN regex detectors + bilingual NER model (recommended) |
| `c1-vega-en` | English | EN regex detectors + EN-only NER model |

## Quick Install

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/copernicusone/homebrew-vega/main/install.sh \
  | C1_VEGA_LICENSE_KEY=<your-key> sh
```

After installation, open a new terminal and run `claude` or `codex`. The
`codex` integration routes through Vega with ChatGPT auth by default; API-key
mode is still available with:

```bash
c1-vega-plen run --client codex --codex-auth api -- codex
```

### Windows (PowerShell)

```powershell
$env:C1_VEGA_LICENSE_KEY="<your-key>"
irm https://raw.githubusercontent.com/copernicusone/homebrew-vega/main/install.ps1 | iex
```

## Alternative: Homebrew (macOS & Linux)

```bash
brew tap copernicusone/vega
brew install c1-vega-plen   # bilingual PL+EN (recommended)
# or
brew install c1-vega-en     # English only
```
