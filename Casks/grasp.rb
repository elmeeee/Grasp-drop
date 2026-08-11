cask "grasp" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/elmeeee/Grasp-drop/releases/download/v#{version}/Grasp-macOS.zip"
  name "Grasp"
  desc "macOS Quick Share Receiver & Cross-Platform File Hub"
  homepage "https://github.com/elmeeee/Grasp-drop"

  app "Grasp.app"

  zap trash: [
    "~/Downloads/Grasp",
  ]
end
