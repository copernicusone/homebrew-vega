class C1VegaPl < Formula
  desc "Local PII-anonymizing proxy for Claude Code (Polish)"
  homepage "https://copernicusone.com/vega"
  version "0.1.0-rc.5"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/v0.1.0-rc.5/c1-vega-pl-0.1.0-rc.5-aarch64-apple-darwin.tar.gz"
      sha256 "3e8925793ba91da1697b5570626b13b084f4c83830ffbfe91d6f7d59708708d1"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/v0.1.0-rc.5/c1-vega-pl-0.1.0-rc.5-x86_64-apple-darwin.tar.gz"
      sha256 "80d1791e15d30c2902b9d82ea40fbdcc1f6c5108ca13812050f50b7efcc86b40"
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
    assert_match "c1-vega-pl", shell_output("#{bin}/c1-vega-pl --version")
    shell_output("#{bin}/c1-vega-pl --help")
    shell_output("#{bin}/c1-vega-pl license status")
    shell_output("#{bin}/c1-vega-pl install-shell --dry-run")
  end
end
