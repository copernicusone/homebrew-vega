class C1VegaEn < Formula
  desc "Local PII-anonymizing proxy for Claude Code (EN)"
  homepage "https://copernicusone.com/vega"
  version "0.1.2"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.2/c1-vega-en-0.1.2-aarch64-apple-darwin.tar.gz"
      sha256 "ad94bd0d6b762c89cafb7210402fb3b2bca1aad99f2f4bbaa5ebf1675473947e"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.2/c1-vega-en-0.1.2-x86_64-apple-darwin.tar.gz"
      sha256 "d5d4b46f93fc295f2a852f7c52ad799155b2d5b9221b34794019abb95d7659f8"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.2/c1-vega-en-0.1.2-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "PLACEHOLDER_AARCH64_LINUX_GNU"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.2/c1-vega-en-0.1.2-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "PLACEHOLDER_X86_64_LINUX_GNU"
    end
  end

  def install
    bin.install "c1-vega-en"
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
      if [ -z "${CLAUDECODE:-}" ] && command -v c1-vega-en >/dev/null 2>&1; then
        claude() { command c1-vega-en run -- claude "$@"; }
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
        c1-vega-en activate <your-license-key>

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

      Note: if you previously ran `c1-vega-en install-shell`, ~/.zshrc sources
      ~/.c1-vega/shell-init.sh (env var only). Replace that source line with
      claude-wrapper.sh above to enable the `claude` wrapper.

      Migrating from the launchd daemon: this version no longer registers a
      LaunchAgent. If you ran `brew services start c1-vega-en` previously,
      run `brew services stop c1-vega-en` once to remove the leftover unit.
    EOS
  end

  test do
    assert_match "c1-vega", shell_output("#{bin}/c1-vega-en --version")
    shell_output("#{bin}/c1-vega-en --help")
    shell_output("#{bin}/c1-vega-en license status")
    shell_output("#{bin}/c1-vega-en install-shell --dry-run")
  end
end
