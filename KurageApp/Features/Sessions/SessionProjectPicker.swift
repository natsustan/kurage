import SwiftUI
import KurageCore

/// Keep the project choice anchored to the row; only browsing folders opens a sheet.
struct SessionProjectMenu: View {
    let model: AppModel
    let current: SessionProject
    let workspaceGeneration: Int
    let onChoose: (SessionProject) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var projects: [SessionProject] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var attempt = 0
    @State private var catalogLoadID = UUID()
    @State private var folderSource: SessionProject?

    private var menuProjects: [SessionProject] {
        projects.contains(where: { $0.id == current.id }) ? projects : [current] + projects
    }

    var body: some View {
        Menu {
            Section("Projects") {
                ForEach(menuProjects) { project in
                    Button {
                        guard model.workspaceGeneration == workspaceGeneration else { return }
                        onChoose(project)
                    } label: {
                        Label(project.name, systemImage: project.id == current.id ? "checkmark" : "folder")
                    }
                    .accessibilityIdentifier("choose-project-\(project.id)")
                }
                if isLoading { Text("Loading projects…") }
                if failed {
                    Button("Reload projects", systemImage: "arrow.clockwise") { attempt += 1 }
                }
            }
            Button("Add new folder", systemImage: "plus") { folderSource = current }
                .accessibilityIdentifier("choose-machine-folder")
        } label: {
            HStack(spacing: 8) {
                NewSessionIcon(imageName: "folder-open")
                Text(current.name).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .font(.body)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuOrder(.fixed)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("new-session-project")
        .sheet(item: $folderSource) { source in
            NavigationStack {
                MachineFolderPicker(model: model, templateSessionID: source.templateSessionID,
                                    workspaceGeneration: workspaceGeneration, onChoose: onChoose)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task(id: "\(workspaceGeneration):\(current.templateSessionID):\(attempt):\(scenePhase)") {
            guard scenePhase == .active else { return }
            let loadID = UUID()
            catalogLoadID = loadID
            isLoading = true
            failed = false
            defer { if catalogLoadID == loadID { isLoading = false } }
            do {
                let result = try await model.sessionProjects(templateSessionID: current.templateSessionID, action: .catalog)
                try Task.checkCancellation()
                guard model.workspaceGeneration == workspaceGeneration, catalogLoadID == loadID else { return }
                projects = result.projects ?? []
            } catch {
                if !Task.isCancelled, catalogLoadID == loadID { failed = true }
            }
        }
    }
}

private struct MachineFolderPicker: View {
    let model: AppModel
    let templateSessionID: String
    let workspaceGeneration: Int
    let onChoose: (SessionProject) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private struct Request: Equatable {
        let id = UUID()
        var path: String?
        var cursor: String?
        var attempt = 0
        var isActive = true
    }
    @State private var request = Request()
    @State private var directory: MachineDirectory?
    @State private var isLoading = true
    @State private var isSelecting = false
    @State private var errorMessage: String?
    @State private var selectionTask: Task<Void, Never>?
    @ScaledMetric(relativeTo: .title2) private var folderIconWidth = 28

    var body: some View {
        List {
            if let directory {
                Section {
                    if let parent = directory.parentPath {
                        folderRow("Parent folder", systemImage: "arrow.up", identifier: "folder-parent") {
                            navigate(parent)
                        }
                    }
                    ForEach(directory.entries) { entry in
                        folderRow(entry.name, systemImage: "folder", identifier: "folder-\(entry.name)") {
                            navigate(entry.absolutePath)
                        }
                        .disabled(entry.error != nil)
                    }
                    if let cursor = directory.nextCursor {
                        Button("Load more folders") { request = Request(path: directory.path, cursor: cursor) }
                    }
                    if directory.entries.isEmpty && !isLoading { Text("No subfolders").foregroundStyle(.secondary) }
                } header: {
                    Text(directory.path)
                        .font(.body).fontWeight(.regular)
                        .foregroundStyle(.secondary)
                        .textCase(nil).lineLimit(3)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("folder-path")
                }
                .disabled(isLoading || isSelecting)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
                Button("Retry", systemImage: "arrow.clockwise") { request.attempt += 1 }
                    .disabled(isSelecting)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.secondarySystemBackground))
        .overlay {
            if isLoading || isSelecting {
                ProgressView()
                    .accessibilityLabel(isSelecting ? "Selecting folder…" : "Loading folders…")
                    .accessibilityIdentifier(isLoading ? "folder-loading" : "folder-selecting")
            }
        }
        .navigationTitle("Choose Folder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Choose this folder", systemImage: "checkmark") { select() }
                    .disabled(directory == nil || isLoading || isSelecting || errorMessage != nil)
                    .accessibilityIdentifier("choose-current-folder")
            }
        }
        .task(id: request) { if request.isActive { await load() } }
        .onChange(of: scenePhase) { _, phase in
            request.isActive = phase == .active
            if phase != .active { selectionTask?.cancel() }
        }
        .onDisappear { selectionTask?.cancel() }
    }

    private func folderRow(_ name: String, systemImage: String, identifier: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: folderIconWidth)
                Text(name).font(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .accessibilityIdentifier(identifier)
    }

    private func navigate(_ path: String) {
        guard !isLoading, !isSelecting else { return }
        isLoading = true
        // Always create a fresh request, including symlinks back to this directory.
        request = Request(path: path)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        let current = request
        do {
            let result = try await model.sessionProjects(templateSessionID: templateSessionID,
                action: .browse, path: current.path, cursor: current.cursor)
            try Task.checkCancellation()
            guard current == request, model.workspaceGeneration == workspaceGeneration,
                  var loaded = result.directory else { return }
            if current.cursor != nil, directory?.path == loaded.path {
                let existing = directory?.entries ?? []
                let ids = Set(existing.map(\.id))
                loaded.entries = existing + loaded.entries.filter { !ids.contains($0.id) }
            }
            directory = loaded
        } catch {
            guard !Task.isCancelled, current == request else { return }
            errorMessage = "Could not load folders. Check that the machine is online and try again."
        }
        if current == request { isLoading = false }
    }

    private func select() {
        guard let directory, !isSelecting, model.workspaceGeneration == workspaceGeneration else { return }
        isSelecting = true
        errorMessage = nil
        selectionTask = Task {
            defer { isSelecting = false }
            do {
                let result = try await model.sessionProjects(templateSessionID: templateSessionID,
                                                             action: .select, path: directory.path)
                try Task.checkCancellation()
                guard model.workspaceGeneration == workspaceGeneration, let project = result.project else { return }
                onChoose(project)
                dismiss()
            } catch {
                if !Task.isCancelled { errorMessage = "Could not select this folder. Try again." }
            }
        }
    }
}
