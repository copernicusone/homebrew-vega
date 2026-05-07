# homebrew-vega

Homebrew tap for [Copernicus One Vega](https://copernicusone.pl) — a local PII-anonymizing proxy for AI clients.

## Available Formulae

| Formula | Language | Description |
|---------|----------|-------------|
| `c1-vega-plen` | PL + EN | PL + EN regex detectors + bilingual NER model (recommended) |
| `c1-vega-en` | English | EN regex detectors + EN-only NER model |

## Install

```bash
brew tap copernicusone/vega
brew install c1-vega-plen   # bilingual PL+EN (recommended)
# or
brew install c1-vega-en     # English only
```

Or use the one-liner install script (see releases).
