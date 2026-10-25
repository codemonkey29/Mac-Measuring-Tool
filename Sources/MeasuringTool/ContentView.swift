import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        VStack(spacing: 0) {
            RibbonView()
            Divider()
            CanvasRepresentable(workspace: workspace)
            Divider()
            StatusBar()
        }
        .frame(minWidth: 780, minHeight: 480)
        .navigationTitle(workspace.imageName.isEmpty ? "Measuring Tool" : workspace.imageName)
        .sheet(isPresented: $workspace.isAskingForScale) {
            ScaleSheet(workspace: workspace)
        }
        .alert("Couldn’t Open Image", isPresented: $workspace.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(workspace.errorMessage ?? "")
        }
    }
}

struct StatusBar: View {
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        HStack(spacing: 10) {
            Text(workspace.hint)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 10)
            if workspace.image != nil {
                Text(workspace.scaleDescription)
                    .lineLimit(1)
                Divider()
                    .frame(height: 14)
                Button { workspace.canvas?.zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom out (⌘-)")
                Text("\(workspace.zoomPercent)%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
                Button { workspace.canvas?.zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom in (⌘=)")
                Button("Fit") { workspace.canvas?.zoomToFit() }
                    .help("Zoom to fit (⌘0)")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.bar)
    }
}

/// Asks for the real length of the scale line that was just drawn.
struct ScaleSheet: View {
    @ObservedObject var workspace: Workspace
    @State private var text = ""
    @State private var unit = LengthUnit.millimeters
    @FocusState private var isFieldFocused: Bool

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    private var length: Double? { LengthUnit.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set Scale")
                .font(.headline)
            Text(prompt)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Known length", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .onSubmit(apply)
                Picker("Unit", selection: $unit) {
                    ForEach(LengthUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { workspace.pendingReference = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Set Scale", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(length == nil)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            unit = workspace.referenceUnit
            if workspace.isScaled {
                text = workspace.referenceLength.formatted(.number.grouping(.never))
            }
            isFieldFocused = true
        }
    }

    private var prompt: String {
        guard let pending = workspace.pendingReference else { return "How long is the line you drew?" }
        return "How long is the line you drew? It’s \(workspace.pixelText(pending.length)) in the image."
    }

    private func apply() {
        guard let length else { return }
        workspace.confirmPendingReference(length: length, unit: unit)
    }
}
