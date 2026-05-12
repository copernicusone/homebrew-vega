class C1VegaPlen < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PLEN)"
  homepage "https://copernicusone.com/vega"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.13/c1-vega-plen-0.2.13-aarch64-apple-darwin.tar.gz"
      sha256 "008e02784dc5f9caf8579aceabebff24c1f391e5188e2b95dadc5c420c046bf5"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.13/c1-vega-plen-0.2.13-x86_64-apple-darwin.tar.gz"
      sha256 "4da1074ad775fe4fcdd0207c399aee91d010355fbe7b2018733db2effa1faf1c"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.13/c1-vega-plen-0.2.13-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "ec7ab72f3f9025896be98b4a534e4433abcc9cf6dcf9ffd20ff07f6a7fd06c04"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.13/c1-vega-plen-0.2.13-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "bf96395dbd437e713a907c6c8cb9ec1a7a2c8643a3e4f4682957cbe6905d35bd"
    end
  end

  def install
    bin.install "c1-vega-plen"
  end

  service do
    run [opt_bin/"c1-vega-plen", "start"]
    keep_alive successful_exit: false
    log_path var/"log/c1-vega-plen.log"
    error_log_path var/"log/c1-vega-plen.log"
    environment_variables RUST_LOG: "info"
  end

  def caveats
    <<~EOS
      Activate your license:
        c1-vega-plen activate <your-license-key>

      Then point Claude Code at the proxy:
        export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"

      Start the proxy as a launchd service:
        brew services start c1-vega-plen
    EOS
  end

  test do
    assert_match "c1-vega", shell_output("#{bin}/c1-vega-plen --version")
    shell_output("#{bin}/c1-vega-plen --help")
    shell_output("#{bin}/c1-vega-plen license status")
    shell_output("#{bin}/c1-vega-plen install-shell --dry-run")
  end
end
