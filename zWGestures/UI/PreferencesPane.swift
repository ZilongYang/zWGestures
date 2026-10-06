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
                languageSection
                Divider()
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

    // MARK: - 语言

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L10n.text(.languageSection), detail: nil)
            Picker("", selection: $model.language) {
                ForEach(WGLanguagePreference.allCases, id: \.self) { preference in
                    Text(preference.localizedName).tag(preference)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            Text(L10n.text(.prefsLanguageHelp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 手感

    private var timeoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L10n.text(.prefsStartDragTimeout), detail: L10n.text(.prefsTimeoutDetail))
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
                Text(L10n.format(.prefsMillisecondsFormat, model.startDragTimeout))
                    .font(.callout.monospacedDigit())
                    .frame(width: 90, alignment: .leading)
            }
            Text(L10n.text(.prefsTimeoutHelp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 轨迹与手势名

    private var trailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(L10n.text(.prefsTrailSection), detail: L10n.text(.prefsTrailSectionDetail))

            HStack(spacing: 24) {
                Toggle(L10n.text(.prefsShowTrail), isOn: $model.showPath)
                Toggle(L10n.text(.prefsShowGestureName), isOn: $model.showGestureName)
            }

            HStack(spacing: 20) {
                colorWell(L10n.text(.prefsTrailNormal), value: Binding(
                    get: { model.pathColorNormal.swiftUIColor },
                    set: { model.pathColorNormal = WGColor($0) }
                ))
                colorWell(L10n.text(.prefsTrailRecognized), value: Binding(
                    get: { model.pathColorRecognized.swiftUIColor },
                    set: { model.pathColorRecognized = WGColor($0) }
                ))
                colorWell(L10n.text(.prefsLabelNormal), value: Binding(
                    get: { model.labelColorNormal.swiftUIColor },
                    set: { model.labelColorNormal = WGColor($0) }
                ))
                colorWell(L10n.text(.prefsLabelExecuted), value: Binding(
                    get: { model.labelColorExecuted.swiftUIColor },
                    set: { model.labelColorExecuted = WGColor($0) }
                ))
            }

            HStack(spacing: 12) {
                Text(L10n.text(.prefsTrailLineWidth))
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
                Text(L10n.text(.prefsGestureNamePosition))
                    .frame(width: 70, alignment: .leading)
                Slider(value: $model.gesturePos, in: PreferencesModel.gesturePositionRange)
                    .frame(maxWidth: 260)
                Text(String(format: "%.2f", model.gesturePos))
                    .font(.callout.monospacedDigit())
                    .frame(width: 60, alignment: .leading)
            }
            Text(L10n.text(.prefsGestureNamePositionHelp))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 目标模式

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading(L10n.text(.prefsTargetModeSection), detail: L10n.text(.prefsTargetModeDetail))
            Picker("", selection: $model.targetMode) {
                ForEach(WGTargetMode.allCases, id: \.self) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            Text(L10n.text(.prefsTargetModeHelp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 未实现项

    private var notImplementedNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L10n.text(.prefsNotImplementedNote), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.text(.prefsNotImplementedHelp))
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
