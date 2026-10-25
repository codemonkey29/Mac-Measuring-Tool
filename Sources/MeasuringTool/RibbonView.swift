import SwiftUI

/// The bar across the top: the four tool buttons on the left, the latest result on the right.
struct RibbonView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var showsCopied = false

    var body: some View {
        HStack(spacing: 4) {
            RibbonButton(title: "Import", systemImage: "photo.badge.plus", help: "Import an image (⌘O)") {
                workspace.importImage()
            }
            Divider()
                .frame(height: 40)
                .padding(.horizontal, 6)
            Group {
                toolButton(.scale, title: "Scale", systemImage: "ruler",
                           help: "Set the scale from a known distance (S)")
                toolButton(.measure, title: "Measure", systemImage: "lines.measurement.horizontal",
                           help: "Measure between two points (M)")
                toolButton(.pan, title: "Zoom / Pan", systemImage: "hand.raised",
                           help: "Drag to pan, scroll or pinch to zoom (P)")
            }
            .disabled(workspace.image == nil)

            Spacer(minLength: 20)
            result
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func toolButton(_ tool: Tool, title: String, systemImage: String, help: String) -> some View {
        RibbonButton(title: title, systemImage: systemImage, isSelected: workspace.image != nil && workspace.tool == tool, help: help) {
            workspace.tool = tool
        }
    }

    private var result: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("Last measurement")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(workspace.latestMeasurementText ?? "–")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(minWidth: 130, alignment: .trailing)

            Button(action: copy) {
                Label(showsCopied ? "Copied" : "Copy", systemImage: showsCopied ? "checkmark" : "doc.on.doc")
                    .frame(minWidth: 66)
            }
            .disabled(workspace.latestMeasurementText == nil)
            .help("Copy the last measurement (⌘C)")

            Picker("Units", selection: $workspace.displayUnit) {
                ForEach(LengthUnit.allCases) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            .labelsHidden()
            .frame(width: 64)
            .disabled(!workspace.isScaled)
            .help("Units to show measurements in")

            Button("Clear") { workspace.clearMeasurements() }
                .disabled(workspace.measurements.isEmpty)
                .help("Remove all measurements")
        }
    }

    private func copy() {
        guard workspace.copyLatestMeasurement() else { return }
        showsCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showsCopied = false
        }
    }
}

struct RibbonButton: View {
    let title: String
    let systemImage: String
    var isSelected = false
    let help: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 19))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .frame(width: 76, height: 50)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovered = $0 }
        .help(help)
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.16) }
        return isHovered && isEnabled ? Color.primary.opacity(0.07) : .clear
    }
}
