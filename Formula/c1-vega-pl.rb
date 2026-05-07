class C1VegaPl < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PL)"
  homepage "https://copernicusone.com/vega"
  version "0.2.3"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-pl-v0.2.3/c1-vega-pl-0.2.3-aarch64-apple-darwin.tar.gz"
      sha256 "500fa0730bcd6a275e8eb347322be5671c18b21084e473791343ac93b9e258da"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-pl-v0.2.3/c1-vega-pl-0.2.3-x86_64-apple-darwin.tar.gz"
      sha256 "192050c8375bbefdd3cfa789ce0e757d123aaaf82c398a8046db59de29982336"
    end
  end

  def install
    bin.install "c1-vega-pl"
  end

  def post_install
    # Drop a `claude` shell wrapper so the proxy starts on demand and prints the
    # privacy banner. Sourced from the user's ~/.zshrc per the caveats below.
    install_dir = Pathname.new(Dir.home)/".c1-vega"
    install_dir.mkpath
    wrapper = install_dir/"claude-wrapper.sh"
    wrapper.write <<~SH
      # Managed by c1-vega — do not edit manually
      # Wraps `claude` so it routes through the c1-vega proxy and prints the
      # privacy banner. Skipped when already inside a Claude Code session
      # (CLAUDECODE=1) to prevent recursion in nested Bash tool calls.
      if [ -z "${CLAUDECODE:-}" ] && command -v c1-vega-pl >/dev/null 2>&1; then
        claude() { command c1-vega-pl run -- claude "$@"; }
      fi
    SH
    wrapper.chmod 0644

    # Install Claude Code slash commands so the user gets autocomplete for the
    # in-chat `c1-vega:*` directives. No-op when ~/.claude is absent.
    claude_dir = Pathname.new(Dir.home)/".claude"
    return unless claude_dir.directory?

    commands_dir = claude_dir/"commands"
    commands_dir.mkpath
    tap_commands = tap.path/"install/claude-commands"
    return unless tap_commands.directory?

    tap_commands.glob("c1-vega-*.md").each do |src|
      FileUtils.cp(src, commands_dir/src.basename)
    end
  end

  def caveats
    <<~EOS
      Activate your license:
        c1-vega-pl activate <your-license-key>

      Wire the shell wrapper so plain `claude` routes through the proxy and
      prints the privacy banner. Add to ~/.zshrc (or ~/.bashrc):

        export PATH="$HOME/.c1-vega/bin:$PATH"
        source "$HOME/.c1-vega/claude-wrapper.sh"

      Open a new terminal and run:
        claude

      Inside Claude Code, slash commands (autocomplete enabled):
        /c1-vega-help    /c1-vega-status   /c1-vega-stats
        /c1-vega-mappings /c1-vega-settings /c1-vega-disable
        /c1-vega-enable   /c1-vega-tech-bundle

      Note: if you previously ran `c1-vega-pl install-shell`, ~/.zshrc sources
      ~/.c1-vega/shell-init.sh (env var only). Replace that source line with
      claude-wrapper.sh above to enable the `claude` wrapper.

      Migrating from the launchd daemon: this version no longer registers a
      LaunchAgent. If you ran `brew services start c1-vega-pl` previously,
      run `brew services stop c1-vega-pl` once to remove the leftover unit.
    EOS
  end

  test do
    assert_match "c1-vega", shell_output("#{bin}/c1-vega-pl --version")
    shell_output("#{bin}/c1-vega-pl --help")
    shell_output("#{bin}/c1-vega-pl license status")
    shell_output("#{bin}/c1-vega-pl install-shell --dry-run")
  end
end
