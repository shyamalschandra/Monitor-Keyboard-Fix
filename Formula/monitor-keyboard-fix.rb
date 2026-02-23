class MonitorKeyboardFix < Formula
  desc "macOS menu bar app for keyboard brightness/volume control of Dell S2725QC monitors via DDC/CI"
  homepage "https://github.com/shyamalschandra/Monitor-Keyboard-Fix"
  url "https://github.com/shyamalschandra/Monitor-Keyboard-Fix/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "c29bcf65be18b5f6d27c47085ccca4457a35d8f64f6e7af59a7015d144212ee2"
  license "MIT"
  head "https://github.com/shyamalschandra/Monitor-Keyboard-Fix.git", branch: "main"

  depends_on xcode: ["14.0", :build]
  depends_on macos: :ventura
  depends_on arch: :arm64

  def install
    cd "MonitorKeyboardFix" do
      system "swift", "build",
             "-c", "release",
             "--arch", "arm64",
             "--disable-sandbox"
    end

    bin.install "MonitorKeyboardFix/.build/release/MonitorKeyboardFix" => "monitor-keyboard-fix"

    app_bundle = prefix/"Monitor Keyboard Fix.app"
    (app_bundle/"Contents/MacOS").mkpath
    (app_bundle/"Contents/Resources").mkpath

    cp bin/"monitor-keyboard-fix", app_bundle/"Contents/MacOS/MonitorKeyboardFix"
    cp "MonitorKeyboardFix/Info.plist", app_bundle/"Contents/Info.plist"
    (app_bundle/"Contents/PkgInfo").write "APPL????"
  end

  def caveats
    <<~EOS
      Monitor Keyboard Fix requires Accessibility permission to intercept
      keyboard brightness and volume keys.

      After first launch, grant access in:
        System Settings > Privacy & Security > Accessibility

      Your Dell monitors must have DDC/CI enabled:
        Monitor OSD > Others > DDC/CI > On

      To start the app from the command line:
        monitor-keyboard-fix

      To copy the .app bundle to /Applications:
        cp -r "$(brew --cellar)/monitor-keyboard-fix/#{version}/Monitor Keyboard Fix.app" /Applications/

      To start automatically at login, add it to:
        System Settings > General > Login Items
    EOS
  end

  test do
    assert_predicate bin/"monitor-keyboard-fix", :executable?
  end
end
