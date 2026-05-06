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

  def install
    bin.install "c1-vega-en"
  end

  service do
    run [opt_bin/"c1-vega-en", "start"]
    keep_alive successful_exit: false
    log_path var/"log/c1-vega-en.log"
    error_log_path var/"log/c1-vega-en.log"
    environment_variables RUST_LOG: "info"
  end

  def caveats
    <<~EOS
      Activate your license:
        c1-vega-en activate <your-license-key>

      Then point Claude Code at the proxy:
        export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"

      Start the proxy as a launchd service:
        brew services start c1-vega-en
    EOS
  end

  test do
    assert_match "c1-vega", shell_output("#{bin}/c1-vega-en --version")
    shell_output("#{bin}/c1-vega-en --help")
    shell_output("#{bin}/c1-vega-en license status")
    shell_output("#{bin}/c1-vega-en install-shell --dry-run")
  end
end
