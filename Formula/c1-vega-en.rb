# frozen_string_literal: true

# Formula for c1-vega-en.
class C1VegaEn < Formula
  desc "Local PII-anonymizing proxy for Claude Code (EN)"
  homepage "https://copernicusone.com/vega"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.3/c1-vega-en-0.1.3-aarch64-apple-darwin.tar.gz"
      sha256 "0bcea3bc2d6347568cd35719cb4606a906a96db0305b59bb83d11a86b3fceb0b"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-en-v0.1.3/c1-vega-en-0.1.3-x86_64-apple-darwin.tar.gz"
      sha256 "f7805fcc1443fcfcc175136a28ac29810cb4e24c790f3f50a4d36fac14b1c7a6"
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
