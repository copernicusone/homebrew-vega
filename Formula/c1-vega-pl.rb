class C1VegaPl < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PL)"
  homepage "https://copernicusone.com/vega"
  version "0.2.2"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-pl-v0.2.2/c1-vega-pl-0.2.2-aarch64-apple-darwin.tar.gz"
      sha256 "6c8600333711deef15ae94019fa6f76f59dd22e9a1df1d159aafcb12d60efb3d"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-pl-v0.2.2/c1-vega-pl-0.2.2-x86_64-apple-darwin.tar.gz"
      sha256 "f93e82d53695635942202733a9c20c2cb757c00a851618691915d0c442be4917"
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
