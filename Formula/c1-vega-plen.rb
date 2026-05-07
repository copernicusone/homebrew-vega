class C1VegaPlen < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PLEN)"
  homepage "https://copernicusone.com/vega"
  version "0.1.1"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.1.1/c1-vega-plen-0.1.1-aarch64-apple-darwin.tar.gz"
      sha256 "e27e18b9fed721f5d9a64fe0102c366a804a1781bef892cf156f8b0474ca8ab2"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.1.1/c1-vega-plen-0.1.1-x86_64-apple-darwin.tar.gz"
      sha256 "5ccb1b6128064b6d9b70c875180279981e47a90bc2e77e9496ae24e11571c236"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.1.1/c1-vega-plen-0.1.1-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "8e34d5fd84f4acaec39ea9b1941b104f116c15b719ccdf44fdc36aebd9ba8f7b"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.1.1/c1-vega-plen-0.1.1-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "e439227387c173df44cb8f8e8b12e5813a2ce4caba90f79918bec658355df9a5"
    end
  end

  def install
    bin.install "c1-vega-plen"
  end

  def post_install
    install_dir = Pathname.new(Dir.home)/".c1-vega"
    install_dir.mkpath
    wrapper = install_dir/"claude-wrapper.sh"
    wrapper.write <<~SH
      # Managed by c1-vega — do not edit manually
      # Wraps `claude` so it routes through the c1-vega proxy and prints the
      # privacy banner. Skipped when already inside a Claude Code session
      # (CLAUDECODE=1) to prevent recursion in nested Bash tool calls.
      if [ -z "${CLAUDECODE:-}" ] && command -v c1-vega-plen >/dev/null 2>&1; then
        claude() { command c1-vega-plen run -- claude "$@"; }
      fi
    SH
    wrapper.chmod 0644

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
        c1-vega-plen activate <your-license-key>

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

      Note: if you previously ran `c1-vega-plen install-shell`, ~/.zshrc
      sources ~/.c1-vega/shell-init.sh (env var only). Replace that source
      line with claude-wrapper.sh above to enable the `claude` wrapper.

      Migrating from the launchd daemon: this version no longer registers a
      LaunchAgent. If you ran `brew services start c1-vega-plen` previously,
      run `brew services stop c1-vega-plen` once to remove the leftover unit.
    EOS
  end

  test do
    assert_match "c1-vega", shell_output("#{bin}/c1-vega-plen --version")
    shell_output("#{bin}/c1-vega-plen --help")
    shell_output("#{bin}/c1-vega-plen license status")
    shell_output("#{bin}/c1-vega-plen install-shell --dry-run")
  end
end
