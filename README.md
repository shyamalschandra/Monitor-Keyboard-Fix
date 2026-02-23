# Monitor Keyboard Fix

A macOS menu bar app that enables keyboard brightness and volume control for Dell S2725QC external monitors over DDC/CI.

## Problem

The Dell S2725QC advertises macOS compatibility, but macOS keyboard brightness (F1/F2) and volume (F10/F11/F12) keys only control the built-in display and internal speakers -- not external monitors. macOS has no public API for external monitor hardware control.

## Solution

This app intercepts keyboard media keys and sends DDC/CI commands directly to your Dell monitors via the `IOAVService` I2C interface on Apple Silicon, controlling hardware brightness and volume in real time.

### Features

- Keyboard brightness keys (F1/F2) adjust external monitor backlight brightness
- Keyboard volume keys (F10/F11/F12) adjust external monitor speaker volume
- Native macOS-style OSD (on-screen display) overlay for visual feedback
- Menu bar popover with per-monitor brightness/volume sliders
- Automatic detection of multiple monitors
- Automatic re-scan when displays are connected/disconnected

## Install

### Homebrew (recommended)

```bash
brew tap shyamalschandra/monitor-keyboard-fix https://github.com/shyamalschandra/Monitor-Keyboard-Fix.git
brew install monitor-keyboard-fix
```

Then run:

```bash
monitor-keyboard-fix
```

To copy the `.app` bundle to Applications (optional):

```bash
cp -r "$(brew --cellar)/monitor-keyboard-fix/1.0.0/Monitor Keyboard Fix.app" /Applications/
```

### Download from GitHub Releases

1. Go to [Releases](https://github.com/shyamalschandra/Monitor-Keyboard-Fix/releases)
2. Download `MonitorKeyboardFix-<version>-macOS-arm64.tar.gz`
3. Extract and move `Monitor Keyboard Fix.app` to `/Applications`
4. Launch from Applications or Spotlight

### Build from Source

```bash
git clone https://github.com/shyamalschandra/Monitor-Keyboard-Fix.git
cd Monitor-Keyboard-Fix

# Debug build
cd MonitorKeyboardFix && swift build && swift run

# Release build + install to /usr/local/bin
make install

# Or build a .app bundle
make app-bundle
# Output: MonitorKeyboardFix/.build/Monitor Keyboard Fix.app
```

## Requirements

- macOS 13.0+ (Ventura or later)
- Apple Silicon Mac (M1/M2/M3/M4)
- Dell S2725QC monitor(s) connected via USB-C
- DDC/CI enabled in the monitor's OSD settings (usually on by default)

## Permissions

On first launch, the app will prompt for **Accessibility** permission. This is required to intercept keyboard media key events. Grant access in:

**System Settings > Privacy & Security > Accessibility**

## Monitor Setup

Ensure DDC/CI is enabled on your Dell monitors:

1. Press the joystick button on the back of the monitor
2. Navigate to **Others** > **DDC/CI**
3. Set to **On**

## How It Works

1. **Monitor Discovery**: Enumerates `DCPAVServiceProxy` / `AppleCLCD2` IOKit nodes to find external displays and create `IOAVService` references
2. **Key Interception**: Uses a `CGEvent` tap to capture system-defined media key events (brightness, volume, mute)
3. **DDC/CI Commands**: Constructs VESA MCCS VCP packets and sends them over I2C using `IOAVServiceWriteI2C` with retry logic
4. **OSD Overlay**: Displays a native-style translucent overlay with a segmented level bar

### VCP Codes Used

| Code | Feature |
|------|---------|
| 0x10 | Brightness |
| 0x12 | Contrast |
| 0x62 | Volume |
| 0x8D | Audio Mute |

## Creating a Release

```bash
# Tag a new version
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions will automatically build and create the release.
# Then update the Homebrew formula SHA:
./scripts/update-formula-sha.sh v1.0.0
git add Formula/monitor-keyboard-fix.rb
git commit -m "Update formula SHA for v1.0.0"
git push
```

## Known Limitations

- USB-C DDC/CI is less reliable than DisplayPort -- occasional commands may fail (retry logic mitigates this)
- Physical button changes on the monitor won't sync back to the app
- `IOAVService` APIs are private Apple APIs (stable since M1 launch in 2020, but could change)
- Using a USB-C dock may degrade DDC reliability; direct connection is recommended

## License

[MIT](LICENSE)
