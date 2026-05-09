# >>> c1-vega >>>
export PATH="$HOME/.c1-vega/bin:$PATH"
export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"
codex() {
  c1-vega-plen run --client codex --codex-auth chatgpt -- codex "$@"
}
# <<< c1-vega <<<
