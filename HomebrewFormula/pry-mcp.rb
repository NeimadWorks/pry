# Homebrew formula for pry-mcp.
#
# Place in a tap repository at Formula/pry-mcp.rb. After each tagged release,
# update `url` and `sha256` to match the signed archive uploaded by CI.
#
# Users install with:
#     brew install neimad/tap/pry-mcp
#
# Pry is MIT-licensed. The binary needs Accessibility permission on first use
# — the formula post-install note reminds the user.

class PryMcp < Formula
  desc "Markdown-driven test runner for macOS apps"
  homepage "https://github.com/neimad/pry"
  version "0.2.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/neimad/pry/releases/download/v#{version}/pry-mcp-v#{version}-arm64.tar.gz"
      # Replace with the SHA256 of the uploaded archive per release.
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  depends_on :macos => :sonoma

  def install
    bin.install "pry-mcp"
  end

  def caveats
    <<~EOS
      pry-mcp needs Accessibility permission to drive macOS apps.

      Grant it to your terminal (Terminal.app, iTerm, Ghostty, ...) in:
          System Settings → Privacy & Security → Accessibility

      Then quit and relaunch that terminal so the grant takes effect.

      The Markdown test spec format is documented at:
          https://github.com/neimad/pry/blob/main/docs/design/spec-format.md
    EOS
  end

  test do
    assert_match "pry-mcp", shell_output("#{bin}/pry-mcp version")
  end
end
