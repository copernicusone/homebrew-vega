# frozen_string_literal: true

# Formula for c1-vega-plen.
class C1VegaPlen < Formula
  desc "Local PII-anonymizing proxy for Claude Code (PLEN)"
  homepage "https://copernicusone.com/vega"
  license :cannot_represent

  on_macos do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.7/c1-vega-plen-0.2.7-aarch64-apple-darwin.tar.gz"
      sha256 "16ddbbe888932fc7b610a7b25d66822aea38c775556f62afb6fcd8a19d6edd9d"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.7/c1-vega-plen-0.2.7-x86_64-apple-darwin.tar.gz"
      sha256 "9845660db3d7ff2d978d810bf1a8664866501e64f4c2828bdc0e0edeaa41f589"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.7/c1-vega-plen-0.2.7-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "334b8c4c68572d10d12aee8c55e36e4d6b9be376c3eff113baa8105b094d5f05"
    end
    on_intel do
      url "https://github.com/copernicusone/homebrew-vega/releases/download/c1-vega-plen-v0.2.7/c1-vega-plen-0.2.7-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "3cc67a400dd58eed9b56b609da43bed20a3a239dcda196904bac53625b0124c3"
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
