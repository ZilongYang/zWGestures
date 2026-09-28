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
            Label("这条命令的类型本版本不认识", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("""
                配置里存的是「\(model.unknownTypeName ?? "?")」。本版本只能编辑按键序列、\
                Web 搜索、Shell 脚本和系统功能键，直接保存会把它替换掉。
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("我知道，要替换它") { model.beginReplacingUnknownCommand() }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Kind

    private var kindPicker: some View {
        Picker("命令类型", selection: Binding(
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
                Text("还没有按键。点「录制按键」后按下一个组合键（例如 ⌘C）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.keySteps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 8) {
                            Text("第 \(index + 1) 步")
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
                            .help("删除这一步")
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if isRecording {
                    Label(
                        heldModifiers.isEmpty
                            ? recordingHint
                            : "已按住 " + heldModifiers.map(WGCommand.keySymbol).joined(separator: "+"),
                        systemImage: "record.circle"
                    )
                    .foregroundStyle(.red)
                    Button("结束录制") { stopRecording() }
                } else {
                    Button(model.keySteps.isEmpty ? "录制按键" : "重新录制") {
                        recordingMode = .replace
                    }
                    .help("按下一个组合键，它会替换掉现在的整个序列")
                    Button("添加一步") { recordingMode = .append }
                        .disabled(model.keySteps.isEmpty)
                        .help("按下一个组合键，把它接到序列的最后（可连续添加多步）")
                    Button("清空") { model.clearKeys() }
                        .disabled(model.keySteps.isEmpty)
                }
                Spacer()
            }

            if !isRecording {
                Text("单个组合键就是一个步骤；需要多步序列（例如先 ⌘V 再 ↩）时用「添加一步」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("这是一个系统快捷键（发送前不激活目标应用）", isOn: $model.isSystemHotKey)
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
        case .replace: "正在录制，按下的组合键会成为整个序列…"
        case .append: "正在添加一步，按下的组合键会接到序列最后…"
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
            Text("{0} 会被替换成搜索词。")
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
            Text("脚本在 /bin/sh 下执行，可用的环境变量见 README。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - System function key

    private var systemFunctionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("功能", selection: $model.functionIndex) {
                ForEach(WGSystemFunction.allCases, id: \.rawValue) { function in
                    Text(function.localizedName).tag(function.rawValue)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220, alignment: .leading)
        }
    }
}
