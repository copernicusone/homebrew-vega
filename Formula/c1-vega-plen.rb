class C1VegaPlen < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PLEN)"
  homepage "https://copernicusone.com/vega"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.11/c1-vega-plen-0.2.11-aarch64-apple-darwin.tar.gz"
      sha256 "4575abc55aab55c13ff1f64c120c59de36f6fc405ed53b50c7eb3ac0dca211f3"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.11/c1-vega-plen-0.2.11-x86_64-apple-darwin.tar.gz"
      sha256 "92decb503e6ed993364a8e07f59c10ef89ae5cd91989e63a6e0e8716cc34fdde"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.11/c1-vega-plen-0.2.11-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "9bc3d7d30c3d48a479f71873d70ef044dd2c1a287f481ed7a9ae732cd6f62f4d"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.11/c1-vega-plen-0.2.11-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "8533dbc107e7911915c4e51cbc53a4a7c11d2fad2373dabda647ea6a016304cf"
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
