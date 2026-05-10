# homebrew-vega

Homebrew tap for [Copernicus One Vega](https://copernicusone.pl) — a local PII-anonymizing proxy for AI clients.

## Available Formulae

| Formula | Language | Description |
|---------|----------|-------------|
| `c1-vega-plen` | PL + EN | PL + EN regex detectors + bilingual NER model (recommended) |
| `c1-vega-en` | English | EN regex detectors + EN-only NER model |

## Quick Install

### PLEN (recommended, macOS / Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/copernicusone/homebrew-vega/main/install-plen.sh \
  | C1_VEGA_LICENSE_KEY=<your-key> bash
```

### English-only (macOS / Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/copernicusone/homebrew-vega/main/install-en.sh \
  | C1_VEGA_LICENSE_KEY=<your-key> bash
```

### Windows (PowerShell)

```powershell
$env:C1_VEGA_LICENSE_KEY="<your-key>"
irm https://raw.githubusercontent.com/copernicusone/homebrew-vega/main/install.ps1 | iex
```

## Alternative: Homebrew (macOS & Linux)

Homebrew installation supports both macOS and Linux.

```bash
brew tap copernicusone/vega
brew install c1-vega-plen   # bilingual PL+EN (recommended)
# or
brew install c1-vega-en     # English only
```
