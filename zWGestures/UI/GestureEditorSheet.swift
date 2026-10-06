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
        .frame(width: 780, height: 740)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: isNew ? "plus.circle" : "hand.draw")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(isNew ? L10n.text(.gestureNewName) : L10n.text(.gestureSheetEditTitle))
                    .font(.headline)
                Text(L10n.text(.gestureSheetTriggerNote))
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
            sectionTitle(L10n.text(.gestureSheetShapeTitle), detail: L10n.text(.gestureSheetShapeDetail))

            if model.hasUnsupportedTrigger {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.text(.gestureSheetUnsupportedTrigger), systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(L10n.text(.gestureSheetUnsupportedTriggerDetail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            // 两列等宽自适应：英文比中文长，写死 200pt 会把「(nothing drawn yet)」挤成四行、
            // 把右边那排按钮挤出去（2026-10-06 作者验收截图）。
            HStack(alignment: .top, spacing: 16) {
                currentShapeColumn.frame(maxWidth: .infinity, alignment: .leading)
                newShapeColumn.frame(maxWidth: .infinity, alignment: .leading)
            }

            modifierRow
            Text(L10n.text(.gestureSheetModifierNote))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Two gestures with the same shape fight for the same input; the list order decides
            // which one wins, so this is advice rather than a refusal.
            if let conflict = model.shapeConflictDescription {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.text(.gestureSheetConflictBanner), systemImage: "exclamationmark.triangle.fill")
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

    /// The 手势修饰键 of this gesture, editable.
    private var modifierRow: some View {
        HStack(spacing: 6) {
            Text(L10n.text(.gestureSheetModifiers))
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.modifiers.isEmpty {
                Text(L10n.text(.gestureSheetNoModifier))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(model.modifiers, id: \.key) { modifier in
                    HStack(spacing: 4) {
                        Text(modifier.localizedName)
                            .font(.caption2)
                        Button {
                            model.removeModifier(modifier)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.text(.gestureSheetRemoveModifier))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                }
            }

            Spacer()

            Menu(L10n.text(.gestureSheetAddModifier)) {
                ForEach(WGModifierKind.allCases, id: \.key) { kind in
                    Button(kind.localizedName) { model.addModifier(kind) }
                        .disabled(!model.canAddModifier(kind))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L10n.text(.gestureSheetModifierHelp))
        }
    }

    /// What the gesture uses today.
    private var currentShapeColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(.gestureSheetCurrentShape))
                .font(.caption)
                .foregroundStyle(.secondary)
            StrokeShapeView(
                points: model.currentStroke?.drawingOrderPoints ?? [],
                lineWidth: 3,
                placeholder: L10n.text(.gestureSheetOriginalShapePlaceholder)
            )
            .frame(minWidth: 200, maxWidth: .infinity, minHeight: 120)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Text(model.currentStrokeDescription)
                .font(.callout.monospaced())
        }
    }

    /// Where a new shape is drawn. Clicking starts full-screen recording, because that is how the
    /// gesture will actually be drawn in daily use.
    private var newShapeColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(.gestureSheetNewShape))
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
                            Text(L10n.text(.gestureSheetClickToDraw))
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 200, maxWidth: .infinity, minHeight: 120)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text(.gestureSheetDrawHelp))

            HStack(spacing: 8) {
                Text(model.hasPendingStroke ? model.pendingStrokeDescription : L10n.text(.gestureNothingDrawn))
                    .font(.callout.monospaced())
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                // 重画：丢掉刚画的，重新进入全屏录制。
                Button(L10n.text(.gestureSheetRedraw)) { onRecordOnScreen() }
                    .help(L10n.text(.gestureSheetRedrawHelp))
                // 不想改：丢掉刚画的，保留原来那条。
                Button(L10n.text(.gestureSheetKeepOld)) { model.discardPendingStroke() }
                    .disabled(!model.hasPendingStroke)
                    .help(L10n.text(.gestureSheetKeepOldHelp))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 2. Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L10n.text(.gestureSheetNameTitle), detail: nil)
            TextField(L10n.text(.dialogGestureName), text: $model.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - 3. Action

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.text(.gestureSheetActionTitle), detail: L10n.text(.gestureSheetActionDetail))
            CommandSectionView(model: model.commandEditor)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Toggle(L10n.text(.settingsEnableGesture), isOn: $model.enabled)
                Text(L10n.text(.gestureSheetEnabledDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(L10n.text(.gestureSheetExecuteNow), isOn: $model.executeOnRecognize)
                Text(L10n.text(.gestureSheetExecuteNowDetail))
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
                Label(isNew ? L10n.text(.gestureSheetReadyAdd) : L10n.text(.gestureSheetReadySave), systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
            Button(L10n.text(.dialogCancel), action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(isNew ? L10n.text(.addAppSheetAdd) : L10n.text(.gestureSheetDone)) { onCommit(model.intent) }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canCommit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
