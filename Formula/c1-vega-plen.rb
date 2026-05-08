class C1VegaPlen < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PLEN)"
  homepage "https://copernicusone.com/vega"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.5/c1-vega-plen-0.2.5-aarch64-apple-darwin.tar.gz"
      sha256 "e959a7d19c3f938f3702ad23ffdd45ac66ec08cee3515c94a667f927f65067aa"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.5/c1-vega-plen-0.2.5-x86_64-apple-darwin.tar.gz"
      sha256 "89429e9bfefcc3d4107d263246150cf60d997a07470252fda9ec022ef58fb258"
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
