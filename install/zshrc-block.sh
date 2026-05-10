# >>> c1-vega >>>
export PATH="$HOME/.c1-vega/bin:$PATH"

_c1_vega_claude() {
  c1-vega-plen run --client anthropic -- claude "$@"
}

claude() {
  _c1_vega_claude "$@"
}

_c1_vega_codex() {
  c1-vega-plen run --client codex --codex-auth chatgpt -- codex "$@"
}

codex() {
  _c1_vega_codex "$@"
}
# <<< c1-vega <<<
