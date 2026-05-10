class C1VegaEn < Formula
  desc "Local PII-anonymizing proxy for Claude Code (EN)"
  homepage "https://copernicusone.com/vega"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.4/c1-vega-en-0.1.4-aarch64-apple-darwin.tar.gz"
      sha256 "260114411fad18935de93453bb66518a17b16d72e5b0c438e2c88de006670d09"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.4/c1-vega-en-0.1.4-x86_64-apple-darwin.tar.gz"
      sha256 "37eb394448ab22805632ba318192089f7315261c55ab62c781c0563dda7a42b3"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.4/c1-vega-en-0.1.4-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "63211adc99bc45a98adfdc843b16d0ae7457dd35de8432794d10dfd02f7ad8ef"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.4/c1-vega-en-0.1.4-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "4ad5febf3acfa83fe4926d02278ae8d8b7e6fa37b1c9e2cec57b51d1329d1bfa"
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
