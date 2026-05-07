# homebrew-vega

Homebrew tap for [Copernicus One Vega](https://copernicusone.pl) — a local PII-anonymizing proxy for AI clients.

## Available Formulae

| Formula | Language | Description |
|---------|----------|-------------|
| `c1-vega-pl` | Polish | PL regex detectors + bilingual NER model |
| `c1-vega-en` | English | EN regex detectors + EN-only NER model |
| `c1-vega-plen` | PL + EN | PL + EN regex detectors + bilingual NER model |

## Install

```bash
brew tap copernicusone/vega
brew install c1-vega-plen   # bilingual (recommended)
# or
brew install c1-vega-pl     # Polish
brew install c1-vega-en     # English
```

Or use the one-liner install script (see releases).
