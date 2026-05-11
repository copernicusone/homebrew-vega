class C1VegaPlen < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PLEN)"
  homepage "https://copernicusone.com/vega"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.12/c1-vega-plen-0.2.12-aarch64-apple-darwin.tar.gz"
      sha256 "abf0dea3cbc2464a1a757241db843334da088695cb02dc55de356b977e2b3c15"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.12/c1-vega-plen-0.2.12-x86_64-apple-darwin.tar.gz"
      sha256 "8bd4cece5541a4af91ee5f4969245fcaeab703cc8486b596be7066858c30e514"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.12/c1-vega-plen-0.2.12-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "4343a41e44bf6f8a06741864a3f0184a0cbd22952beeb7cf46ffe51b0cfaf38e"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.12/c1-vega-plen-0.2.12-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "0d5ee05cceca6a1c9fb1d4c836cbc9e3406339023ea18717c1695692f6d6d507"
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
