import AppKit
import SwiftUI

/// The gesture editor: **shape first, then what it does.**
///
/// A gesture in WGestures is a trigger plus a trajectory plus an action. This sheet follows that
/// order top to bottom — draw the shape, name it, then choose the command it runs — because the
/// shape is what the user is actually editing when they say "I want a different gesture to trigger
/// copy".
///
/// All the rules live in `GestureEditorModel` (`ZWGCore`, unit-tested); this file only renders and
/// routes the drawing surface.
struct GestureEditorSheet: View {
    let onCancel: () -> Void
    /// Called with the finished gesture when the user confirms.
    let onCommit: (WGIntent) -> Void
    /// Asks the window controller to start full-screen shape recording.
    let onRecordOnScreen: () -> Void

    @StateObject private var model: GestureEditorModel

    init(
        model: GestureEditorModel,
        onRecordOnScreen: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onCommit: @escaping (WGIntent) -> Void
    ) {
        _model = StateObject(wrappedValue: model)
        self.onRecordOnScreen = onRecordOnScreen
        self.onCancel = onCancel
        self.onCommit = onCommit
    }

    private var isNew: Bool { model.mode == .new }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    strokeSection
                    Divider()
                    nameSection
                    Divider()
                    commandSection
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 640)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: isNew ? "plus.circle" : "hand.draw")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(isNew ? "新建手势" : "编辑手势")
                    .font(.headline)
                Text("触发方式：鼠标右键（本版本只实现了右键手势）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 1. Shape

    private var strokeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("1. 手势形状", detail: "左边是现在的手势；点右边可以在全屏幕上画一个新手势")

            HStack(alignment: .top, spacing: 12) {
                currentShapeColumn
                newShapeColumn
            }

            // Two gestures with the same shape fight for the same input; the list order decides
            // which one wins, so this is advice rather than a refusal.
            if let conflict = model.shapeConflictDescription {
                VStack(alignment: .leading, spacing: 4) {
                    Label("这个形状与另一条手势相同", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(conflict)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    /// What the gesture uses today.
    private var currentShapeColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("现在的手势")
                .font(.caption)
                .foregroundStyle(.secondary)
            StrokeShapeView(
                points: model.currentStroke?.drawingOrderPoints ?? [],
                lineWidth: 3,
                placeholder: "（原本没有形状）"
            )
            .frame(width: 200, height: 110)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Text(model.currentStrokeDescription)
                .font(.callout.monospaced())
        }
    }

    /// Where a new shape is drawn. Clicking starts full-screen recording, because that is how the
    /// gesture will actually be drawn in daily use.
    private var newShapeColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("新手势")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onRecordOnScreen) {
                Group {
                    if model.hasPendingStroke {
                        StrokeShapeView(points: model.pendingStroke?.drawingOrderPoints ?? [], lineWidth: 3)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "hand.draw")
                                .font(.title2)
                            Text("点击这里在全屏幕上画一个")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200, height: 110)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("点一下，然后在屏幕任意位置按住拖动，画出新手势")

            HStack(spacing: 8) {
                Text(model.hasPendingStroke ? model.pendingStrokeDescription : "（还没画）")
                    .font(.callout.monospaced())
                Spacer()
                // 重画：丢掉刚画的，重新进入全屏录制。
                Button("重画") { onRecordOnScreen() }
                    .help("丢掉刚画的形状，重新在全屏幕上画一个")
                // 不想改：丢掉刚画的，保留原来那条。
                Button("不改了") { model.discardPendingStroke() }
                    .disabled(!model.hasPendingStroke)
                    .help("放弃新手势，这条手势保持原来的形状")
            }
            .frame(width: 200)
        }
    }

    // MARK: - 2. Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("2. 名称", detail: nil)
            TextField("手势名称", text: $model.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - 3. Action

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("3. 这个手势做什么", detail: "形状定下来之后，再选它要触发的动作")
            CommandSectionView(model: model.commandEditor)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Toggle("启用这条手势", isOn: $model.enabled)
                Text("取消勾选后，这条手势会保留在列表里但不再生效（画这个形状不会有任何反应）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("识别手势后立即执行", isOn: $model.executeOnRecognize)
                Text("""
                    勾选后，笔画一被识别就执行命令，不再等待后面的手势修饰键；\
                    同一条轨迹用修饰键区分多个命令时不要勾选。
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let error = model.validationError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Label(isNew ? "可以添加了" : "可以保存了", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
            Button("取消", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "添加" : "完成") { onCommit(model.intent) }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canCommit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
