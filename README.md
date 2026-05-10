# homebrew-vega

Homebrew tap for [Copernicus One Vega](https://copernicusone.pl) — a local PII-anonymizing proxy for AI clients.

## Available Formulae

| Formula | Language | Description |
|---------|----------|-------------|
| `c1-vega-plen` | PL + EN | PL + EN regex detectors + bilingual NER model (recommended) |
| `c1-vega-en` | English | EN regex detectors + EN-only NER model |

## Quick Install

### macOS / Linux (Homebrew)

```bash
brew tap copernicusone/vega && brew install c1-vega-plen
c1-vega-plen activate <your-license-key>
c1-vega-plen install-shell
brew services start c1-vega-plen
```

Upgrade an existing installation:

```bash
brew update && brew upgrade c1-vega-plen && brew services restart c1-vega-plen
```

For the English-only SKU, use the same commands with `c1-vega-en`:

```bash
brew tap copernicusone/vega && brew install c1-vega-en
c1-vega-en activate <your-license-key>
c1-vega-en install-shell
brew services start c1-vega-en
```

After installation, open a new terminal and run `claude` or `codex`. The
`codex` wrapper uses ChatGPT auth by default; API-key mode remains available
with:

```bash
c1-vega-plen run --client codex --codex-auth api -- codex
```

If you alias `claude` or `codex` to an absolute path, point the alias at the
shell helper wrappers or call `c1-vega-plen run` directly.

### Windows (PowerShell)

```powershell
$env:C1_VEGA_LICENSE_KEY="<your-key>"
irm https://raw.githubusercontent.com/copernicusone/homebrew-vega/main/install.ps1 | iex
```

The PowerShell installer creates `claude.cmd` and `codex.cmd` wrappers in
`~\.c1-vega\bin`.
