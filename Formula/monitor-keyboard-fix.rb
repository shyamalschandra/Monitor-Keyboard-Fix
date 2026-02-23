class MonitorKeyboardFix < Formula
  desc "Control Dell S2725QC monitor brightness and volume from macOS keyboard keys via DDC/CI"
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
    cp "MonitorKeyboardFix/Sources/MonitorKeyboardFix/Resources/AppIcon.icns", app_bundle/"Contents/Resources/AppIcon.icns"
    (app_bundle/"Contents/PkgInfo").write "APPL????"

    system "codesign", "--force", "--deep", "--sign", "-", app_bundle
  end

  def caveats
    <<~EOS
      Monitor Keyboard Fix intercepts keyboard brightness and volume keys
      and sends DDC/CI commands to your Dell S2725QC monitors. Both monitors
      are controlled simultaneously from a single key press.

      REQUIRED: Grant both permissions on first launch:
        1. System Settings > Privacy & Security > Accessibility
        2. System Settings > Privacy & Security > Input Monitoring

      Input Monitoring is needed for brightness keys on Mac Studio/Mac Mini
      (macOS consumes brightness events before CGEvent taps on these Macs).

      REQUIRED: DDC/CI must be enabled on your Dell monitors:
        Monitor OSD > Others > DDC/CI > On

      To start the app:
        monitor-keyboard-fix

      To copy the .app bundle to /Applications:
        cp -r "$(brew --cellar)/monitor-keyboard-fix/#{version}/Monitor Keyboard Fix.app" /Applications/

      To start automatically at login, add it to:
        System Settings > General > Login Items

      For troubleshooting, run from Terminal to see diagnostic logs:
        monitor-keyboard-fix
    EOS
  end

  test do
    assert_predicate bin/"monitor-keyboard-fix", :executable?
  end
end
