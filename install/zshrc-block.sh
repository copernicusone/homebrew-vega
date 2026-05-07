# >>> c1-vega >>>
export PATH="$HOME/.c1-vega/bin:$PATH"
# Wrap `claude` so it always routes through the c1-vega proxy and prints the
# privacy banner. Skip when already inside a Claude Code session
# (CLAUDECODE=1) so nested Bash tool calls don't recurse.
if [ -z "${CLAUDECODE:-}" ] && command -v c1-vega-plen >/dev/null 2>&1; then
  claude() { command c1-vega-plen run -- claude "$@"; }
fi
# <<< c1-vega <<<
