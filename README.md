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
```

Upgrade an existing installation:

```bash
brew update && brew upgrade c1-vega-plen
```

For the English-only SKU, use the same commands with `c1-vega-en`:

```bash
brew tap copernicusone/vega && brew install c1-vega-en
c1-vega-en activate <your-license-key>
c1-vega-en install-shell
```

After installation, open a new terminal and run `claude` or `codex`. The shell
wrappers start the proxy on demand. The `codex` wrapper uses ChatGPT auth by
default; API-key mode remains available with:

```bash
c1-vega-plen run --client codex --codex-auth api -- codex
```

If you alias `claude` or `codex` to an absolute path, point the alias at the
shell helper wrappers or call `c1-vega-plen run` directly.

### Advanced fixed-port proxy

Most users should use the shell wrappers above. If a custom client cannot use
the wrappers and needs a stable local proxy URL, start the Homebrew service and
point that client at `http://127.0.0.1:8787`:

```bash
brew services start c1-vega-plen
```

### Windows (PowerShell)

```powershell
$env:C1_VEGA_LICENSE_KEY="<your-key>"
irm https://raw.githubusercontent.com/copernicusone/homebrew-vega/main/install.ps1 | iex
```

The PowerShell installer creates `claude.cmd` and `codex.cmd` wrappers in
`~\.c1-vega\bin`.
