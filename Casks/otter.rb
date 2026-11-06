cask "otter" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/elmeeee/Grasp-drop/releases/download/v#{version}/Otter-macOS.zip"
  name "Otter"
  desc "macOS Quick Share Receiver & Cross-Platform File Hub"
  homepage "https://github.com/elmeeee/Grasp-drop"

  app "Otter.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-rd", "com.apple.quarantine", "#{appdir}/Otter.app"],
                   sudo: false
  end

  zap trash: [
    "~/Downloads/Otter",
  ]
end
