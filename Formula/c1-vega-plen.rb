class C1VegaPlen < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PLEN)"
  homepage "https://copernicusone.com/vega"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.10/c1-vega-plen-0.2.10-aarch64-apple-darwin.tar.gz"
      sha256 "8560475ecc404fd49ad8d6358f4f46c3e41200e0d788debc4e37c2522b1f5c9d"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.10/c1-vega-plen-0.2.10-x86_64-apple-darwin.tar.gz"
      sha256 "3c3c8246e271b1b9098e7742f86ee680bf10401a7d750831f2aa1934003c8a88"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.10/c1-vega-plen-0.2.10-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "558afbbba06d08372d1eb0827c0a5247d0f23b5b5083b1952077ad95dd4224a1"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.10/c1-vega-plen-0.2.10-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "48ab4b1c98706a7042dabd21fcb47ee1700752802407c611f41751867137460a"
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
