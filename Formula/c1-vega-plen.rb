class C1VegaPlen < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PLEN)"
  homepage "https://copernicusone.com/vega"
  version "0.2.4"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.4/c1-vega-plen-0.2.4-aarch64-apple-darwin.tar.gz"
      sha256 "df2bc6357fa9e7cf139bb8d649ffa7bbc58c2d7267a0f398e6dd747d8417431a"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.4/c1-vega-plen-0.2.4-x86_64-apple-darwin.tar.gz"
      sha256 "4fd627c7dca0e1fe5969ac149a2ed73ea4462ec4d429612ce60948d6ac8f5b1b"
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
