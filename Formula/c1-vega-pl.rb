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

  service do
    run [opt_bin/"c1-vega-pl", "start"]
    keep_alive successful_exit: false
    log_path var/"log/c1-vega-pl.log"
    error_log_path var/"log/c1-vega-pl.log"
    environment_variables RUST_LOG: "info"
  end

  def caveats
    <<~EOS
      Activate your license:
        c1-vega-pl activate <your-license-key>

      Then point Claude Code at the proxy:
        export ANTHROPIC_BASE_URL="http://127.0.0.1:8787"

      Start the proxy as a launchd service:
        brew services start c1-vega-pl
    EOS
  end

  test do
    assert_match "c1-vega", shell_output("#{bin}/c1-vega-pl --version")
    shell_output("#{bin}/c1-vega-pl --help")
    shell_output("#{bin}/c1-vega-pl license status")
    shell_output("#{bin}/c1-vega-pl install-shell --dry-run")
  end
end
