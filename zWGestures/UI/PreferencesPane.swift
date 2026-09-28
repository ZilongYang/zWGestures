import AppKit
import SwiftUI

/// The preferences pane: the settings from `prefs.json` that this build actually honours.
///
/// Anything the code does not read is deliberately absent — see `PreferencesModel`. The pane edits
/// a copy; nothing is written until the window's「保存」.
struct PreferencesPane: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                timeoutSection
                Divider()
                trailSection
                Divider()
                targetSection
                Divider()
                notImplementedNote
            }
            .padding(18)
        }
    }

    /// `ClosedRange<Double>` for the slider, computed once here so the range literals stay in one
    /// place with the model's own bounds.
    private var timeoutBounds: ClosedRange<Double> {
        let lower = Double(PreferencesModel.timeoutRange.lowerBound)
        let upper = Double(PreferencesModel.timeoutRange.upperBound)
        return lower...upper
    }

    // MARK: - 手感

    private var timeoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("手势起始超时", detail: "按住触发键后多久之内开始移动才算画手势")
            HStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { Double(model.startDragTimeout) },
                        set: { model.startDragTimeout = Int($0.rounded()) }
                    ),
                    in: timeoutBounds,
                    step: 10
                )
                .frame(maxWidth: 320)
                Text("\(model.startDragTimeout) 毫秒")
                    .font(.callout.monospacedDigit())
                    .frame(width: 90, alignment: .leading)
            }
            Text("""
                超过这个时间还没有移动，就当作普通点击 —— 右键菜单照常弹出。\
                数值大：更容易画出手势，但点菜单略慢；数值小：点菜单更快，但起手要更干脆。
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 轨迹与手势名

    private var trailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("轨迹与手势名", detail: "画手势时的屏幕提示")

            HStack(spacing: 24) {
                Toggle("显示轨迹", isOn: $model.showPath)
                Toggle("显示手势名", isOn: $model.showGestureName)
            }

            HStack(spacing: 20) {
                colorWell("轨迹（未识别）", value: Binding(
                    get: { model.pathColorNormal.swiftUIColor },
                    set: { model.pathColorNormal = WGColor($0) }
                ))
                colorWell("轨迹（已识别）", value: Binding(
                    get: { model.pathColorRecognized.swiftUIColor },
                    set: { model.pathColorRecognized = WGColor($0) }
                ))
                colorWell("手势名（常态）", value: Binding(
                    get: { model.labelColorNormal.swiftUIColor },
                    set: { model.labelColorNormal = WGColor($0) }
                ))
                colorWell("手势名（已执行）", value: Binding(
                    get: { model.labelColorExecuted.swiftUIColor },
                    set: { model.labelColorExecuted = WGColor($0) }
                ))
            }

            HStack(spacing: 12) {
                Text("轨迹线宽")
                    .frame(width: 70, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { model.pathLineWidth },
                        set: { model.pathLineWidth = PreferencesModel.roundedLineWidth($0) }
                    ),
                    in: PreferencesModel.lineWidthRange,
                    step: 0.25
                )
                .frame(maxWidth: 260)
                Text(String(format: "%.2f", model.pathLineWidth))
                    .font(.callout.monospacedDigit())
                    .frame(width: 60, alignment: .leading)
            }

            HStack(spacing: 12) {
                Text("手势名位置")
                    .frame(width: 70, alignment: .leading)
                Slider(value: $model.gesturePos, in: PreferencesModel.gesturePositionRange)
                    .frame(maxWidth: 260)
                Text(String(format: "%.2f", model.gesturePos))
                    .font(.callout.monospacedDigit())
                    .frame(width: 60, alignment: .leading)
            }
            Text("手势名位置：0 在最上面，1 在最下面（按屏幕高度比例）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 目标模式

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("按哪个窗口选手势集", detail: "决定「按应用切换手势集」用哪个应用")
            Picker("", selection: $model.targetMode) {
                ForEach(WGTargetMode.allCases, id: \.self) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            Text("""
                应用目标会**替换**全局手势集，不叠加 —— 例如给 Finder 配了手势集，\
                在 Finder 里就只用 Finder 那一套。
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 未实现项

    private var notImplementedNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("原版里还有两项本版本没有实现", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("""
                「显示起始超时指示器」和「显示状态图标」在代码里都还没有被使用，\
                所以这里不提供开关 —— 提供了也是点了没反应。\
                （状态图标尤其要谨慎：本应用只有菜单栏图标一个入口，隐藏了就回不来。）
                """)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func heading(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func colorWell(_ label: String, value: Binding<Color>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ColorPicker(label, selection: value, supportsOpacity: true)
                .labelsHidden()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

extension WGColor {
    /// For `ColorPicker`. The colour is sRGB, matching how the original stores `#RRGGBBAA`.
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Back from a `ColorPicker` selection. `Color` has no components, so it goes through `NSColor`.
    init(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            alpha: Double(converted.alphaComponent)
        )
    }
}
