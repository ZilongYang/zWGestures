import AppKit
import SwiftUI

/// The command half of the gesture editor: pick a kind, then fill it in.
///
/// Renders `CommandEditorModel` (in `ZWGCore`, fully unit-tested) and owns only the key-recording
/// interaction. Reused by `GestureEditorSheet`; keeping it separate makes it obvious that the
/// command is the *second* half of a gesture, after its shape.
struct CommandSectionView: View {
    @ObservedObject var model: CommandEditorModel

    /// `nil` when not recording; otherwise what the next recorded combination should do.
    @State private var recordingMode: RecordingMode?
    @State private var heldModifiers: [String] = []

    /// Recording one hotkey and appending a further step are separate, explicit actions.
    private enum RecordingMode: Equatable {
        /// 「录制按键」: the next combination becomes the whole sequence.
        case replace
        /// 「添加一步」: the next combination is appended, and recording continues.
        case append
    }

    private var isRecording: Bool { recordingMode != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isReplacingUnknownCommand {
                unknownCommandWarning
            }
            kindPicker
            editorForKind
        }
    }

    // MARK: - Unknown command

    private var unknownCommandWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.text(.cmdViewUnknownTypeBanner), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(L10n.format(.cmdViewUnknownTypeDetailFormat, model.unknownTypeName ?? "?"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(L10n.text(.cmdViewReplaceIt)) { model.beginReplacingUnknownCommand() }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Kind

    private var kindPicker: some View {
        Picker(L10n.text(.cmdViewKindLabel), selection: Binding(
            get: { model.kind },
            set: { model.setKind($0) }
        )) {
            ForEach(CommandEditorModel.Kind.allCases) { kind in
                Text(kind.localizedName).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.isReplacingUnknownCommand)
    }

    @ViewBuilder
    private var editorForKind: some View {
        switch model.kind {
        case .keySequence: keySequenceEditor
        case .webSearch: webSearchEditor
        case .shellScript: shellScriptEditor
        case .systemFunctionKey: systemFunctionEditor
        }
    }

    // MARK: - Key sequence

    private var keySequenceEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.keySteps.isEmpty {
                Text(L10n.text(.cmdViewNoKeysHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.keySteps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 8) {
                            Text(L10n.format(.cmdViewStepFormat, index + 1))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 46, alignment: .leading)
                            Text(step.map(WGCommand.keySymbol).joined(separator: "+"))
                                .font(.body.monospaced())
                            Spacer()
                            Button {
                                model.removeStep(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help(L10n.text(.cmdViewRemoveStepHelp))
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if isRecording {
                    Label(
                        heldModifiers.isEmpty
                            ? recordingHint
                            : L10n.text(.cmdViewHoldingPrefix) + heldModifiers.map(WGCommand.keySymbol).joined(separator: "+"),
                        systemImage: "record.circle"
                    )
                    .foregroundStyle(.red)
                    Button(L10n.text(.cmdViewStopRecording)) { stopRecording() }
                } else {
                    Button(model.keySteps.isEmpty ? L10n.text(.cmdViewRecordKeys) : L10n.text(.cmdViewReRecord)) {
                        recordingMode = .replace
                    }
                    .help(L10n.text(.cmdViewRecordReplaceHelp))
                    Button(L10n.text(.cmdViewAddStep)) { recordingMode = .append }
                        .disabled(model.keySteps.isEmpty)
                        .help(L10n.text(.cmdViewAddStepHelp))
                    Button(L10n.text(.cmdViewClear)) { model.clearKeys() }
                        .disabled(model.keySteps.isEmpty)
                }
                Spacer()
            }

            if !isRecording {
                Text(L10n.text(.cmdViewKeySequenceHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(L10n.text(.cmdViewSystemHotKey), isOn: $model.isSystemHotKey)
                .font(.caption)
        }
        .overlay(alignment: .topLeading) {
            // Zero-ish size focus sink: it only needs to exist to become first responder.
            KeyCaptureField(
                isRecording: isRecording,
                onStep: handleRecordedStep,
                onModifiersChange: { heldModifiers = $0 },
                onCancel: stopRecording
            )
            .frame(width: 1, height: 1)
            .opacity(0)
        }
    }

    private var recordingHint: String {
        switch recordingMode {
        case .replace: L10n.text(.cmdViewRecordingReplace)
        case .append: L10n.text(.cmdViewRecordingAppend)
        case nil: ""
        }
    }

    private func handleRecordedStep(_ step: [String]) {
        switch recordingMode {
        case .replace:
            // One hotkey, then out: "record" should not silently grow the sequence.
            if model.setSingleStep(step) { stopRecording() }
        case .append:
            // Multiple steps in one flow — the user asked for another step explicitly.
            model.appendStep(step)
        case nil:
            break
        }
    }

    private func stopRecording() {
        recordingMode = nil
        heldModifiers = []
    }

    // MARK: - Web search

    private var webSearchEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("https://www.google.com/search?q={0}", text: $model.searchEngine)
                .textFieldStyle(.roundedBorder)
            Text(L10n.text(.cmdViewPlaceholderNote))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shell script

    private var shellScriptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $model.script)
                .font(.body.monospaced())
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Text(L10n.text(.cmdViewShellNote))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - System function key

    private var systemFunctionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.text(.cmdViewFunctionLabel), selection: $model.functionIndex) {
                ForEach(WGSystemFunction.allCases, id: \.rawValue) { function in
                    Text(function.localizedName).tag(function.rawValue)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220, alignment: .leading)
        }
    }
}
