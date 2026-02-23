import SwiftUI

/// A labeled slider for controlling a single monitor's brightness or volume.
struct MonitorSliderView: View {
    let monitorName: String
    @Binding var brightness: Double
    @Binding var volume: Double
    let onBrightnessChange: (UInt16) -> Void
    let onVolumeChange: (UInt16) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monitorName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .frame(width: 14)
                    .foregroundColor(.secondary)
                Slider(value: $brightness, in: 0...100, step: 1) { editing in
                    if !editing {
                        onBrightnessChange(UInt16(brightness))
                    }
                }
                Text("\(Int(brightness))%")
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 32, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .frame(width: 14)
                    .foregroundColor(.secondary)
                Slider(value: $volume, in: 0...100, step: 1) { editing in
                    if !editing {
                        onVolumeChange(UInt16(volume))
                    }
                }
                Text("\(Int(volume))%")
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// The full popover view containing sliders for all monitors.
struct StatusBarPopoverView: View {
    @ObservedObject var monitorManager: MonitorManager
    @Binding var isEnabled: Bool
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "display.2")
                Text("Monitor Keyboard Fix")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()
                .padding(.horizontal, 8)

            if monitorManager.monitors.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("No external monitors detected")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ForEach(Array(monitorManager.monitors.enumerated()), id: \.element.id) { index, monitor in
                    MonitorSliderView(
                        monitorName: "\(monitor.name) (\(index + 1))",
                        brightness: Binding(
                            get: { Double(monitor.brightness) },
                            set: { monitor.brightness = UInt16($0) }
                        ),
                        volume: Binding(
                            get: { Double(monitor.volume) },
                            set: { monitor.volume = UInt16($0) }
                        ),
                        onBrightnessChange: { value in
                            DispatchQueue.global(qos: .userInitiated).async {
                                monitor.setBrightness(value)
                            }
                        },
                        onVolumeChange: { value in
                            DispatchQueue.global(qos: .userInitiated).async {
                                monitor.setVolume(value)
                            }
                        }
                    )

                    if index < monitorManager.monitors.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }

            Divider()
                .padding(.horizontal, 8)

            HStack {
                Toggle("Keyboard Control", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            HStack {
                Button("Rescan Monitors") {
                    monitorManager.discoverMonitors()
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)

                Spacer()

                Button("Quit") {
                    onQuit()
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 280)
    }
}
