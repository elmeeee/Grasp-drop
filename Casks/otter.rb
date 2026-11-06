cask "otter" do
  version "1.0.0"
  sha256 "ba0ea38b5320bc131547bbd071200b37232ce697b64c27556fc72df04b2bd5cd"

  url "https://otterr.web.app/downloads/Otter-macOS.zip"
  name "Otter"
  desc "Send files between your devices over local Wi-Fi"
  homepage "https://otterr.web.app/"

  depends_on :macos
  container nested: "Otter.dmg"

  app "Otter.app"

  zap trash: "~/Downloads/Otter"
end
