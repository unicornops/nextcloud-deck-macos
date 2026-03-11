import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CardDetailSheet: View {
    let card: Card
    let boardId: Int
    var onDismiss: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @State private var showCreateLabel = false
    @State private var newLabelTitle = ""
    @State private var newLabelColor = "31CC7C"
    @State private var isCreatingLabel = false
    @State private var attachments: [Attachment] = []
    @State private var isLoadingAttachments = false
    @State private var isUploadingAttachment = false
    @State private var showFileImporter = false
    @State private var attachmentError: String?

    private var board: Board? {
        guard let b = appState.selectedBoard, b.id == boardId else { return nil }
        return b
    }

    /// Latest card from stacks so label assign/remove updates in the sheet.
    private var currentCard: Card? {
        guard let stack = appState.stacks.first(where: { $0.id == card.stackId }) else { return nil }
        return stack.cards?.first(where: { $0.id == card.id })
    }

    private var cardLabels: [DeckLabel] {
        (currentCard ?? card).labels ?? []
    }

    /// Attachments to display: from API load, or from card (stacks may include attachments).
    private var displayedAttachments: [Attachment] {
        if !attachments.isEmpty { return attachments }
        return (currentCard ?? card).attachments ?? []
    }

    private var availableBoardLabels: [DeckLabel] {
        guard let board else { return [] }
        let assignedIds = Set(cardLabels.map(\.id))
        return board.labels.filter { !assignedIds.contains($0.id) }
    }

    init(card: Card, boardId: Int, onDismiss: @escaping () -> Void) {
        self.card = card
        self.boardId = boardId
        self.onDismiss = onDismiss
        _title = State(initialValue: card.title)
        _description = State(initialValue: card.description ?? "")
        _attachments = State(initialValue: card.attachments ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    dismiss()
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(minWidth: 44)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSaving || title.isEmpty)
            }
            .padding()
            Divider()

            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                        .font(.body)
                }
                Section("Labels") {
                    labelsContent
                }
                Section("Attachments") {
                    attachmentsContent
                }
                Section {
                    Button("Delete card", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 440, height: 520)
        .navigationTitle("Edit Card")
        .sheet(isPresented: $showCreateLabel) {
            createLabelSheet
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item, .data, .content],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result: result)
        }
        .task {
            await loadAttachments()
        }
        .confirmationDialog("Delete card?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteCard(boardId: boardId, stackId: card.stackId, cardId: card.id)
                    await MainActor.run {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: {
            Text("This card will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Attachments UI

    private var attachmentsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoadingAttachments {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading attachments…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if displayedAttachments.isEmpty {
                if let err = attachmentError {
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                } else {
                    Text("No attachments")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(displayedAttachments) { attachment in
                    AttachmentRowView(
                        attachment: attachment,
                        onDownload: { downloadAttachment(attachment) },
                        onDelete: {
                            Task {
                                await appState.deleteAttachment(
                                    boardId: boardId,
                                    stackId: card.stackId,
                                    cardId: card.id,
                                    attachmentId: attachment.id,
                                    type: attachment.type
                                )
                                await loadAttachments()
                            }
                        }
                    )
                }
            }
            HStack {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Add file…", systemImage: "paperclip")
                }
                .disabled(isUploadingAttachment)
                if isUploadingAttachment {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
    }

    private func loadAttachments() async {
        await MainActor.run {
            isLoadingAttachments = true
            attachmentError = nil
        }

        var loaded: [Attachment] = []

        // 1. Try full card fetch (may include attachments inline)
        let fullCard = await appState.getFullCard(boardId: boardId, stackId: card.stackId, cardId: card.id)
        if let atts = fullCard?.attachments, !atts.isEmpty {
            loaded = atts
        }

        // 2. Dedicated attachments endpoint
        if loaded.isEmpty {
            loaded = await appState.getAttachments(boardId: boardId, stackId: card.stackId, cardId: card.id)
        }

        // 3. Fall back to card data already in stacks
        if loaded.isEmpty {
            loaded = (currentCard ?? card).attachments ?? []
        }

        await MainActor.run {
            if !loaded.isEmpty {
                attachments = loaded
            } else if let count = (currentCard ?? card).attachmentCount, count > 0 {
                attachmentError = "Could not load \(count) attachment(s)."
            }
            isLoadingAttachments = false
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        let fileURLs = urls.filter { !$0.hasDirectoryPath }
        guard !fileURLs.isEmpty else { return }
        Task {
            await MainActor.run { isUploadingAttachment = true }
            for url in fileURLs {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                if await appState.uploadAttachment(
                    boardId: boardId,
                    stackId: card.stackId,
                    cardId: card.id,
                    fileURL: url
                ) != nil {
                    await loadAttachments()
                }
            }
            await MainActor.run { isUploadingAttachment = false }
        }
    }

    private func downloadAttachment(_ attachment: Attachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.displayName
        panel.allowedContentTypes = [.data]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                let success = await appState.downloadAttachment(
                    boardId: boardId,
                    stackId: card.stackId,
                    cardId: card.id,
                    attachment: attachment,
                    saveURL: url
                )
                if !success {
                    await MainActor.run {
                        appState.errorMessage = "Could not download attachment"
                    }
                }
            }
        }
    }

    // MARK: - Labels UI

    private var labelsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !cardLabels.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(cardLabels) { label in
                        LabelChip(label: label) {
                            Task {
                                await appState.removeLabel(
                                    boardId: boardId,
                                    stackId: card.stackId,
                                    cardId: card.id,
                                    labelId: label.id
                                )
                            }
                        }
                    }
                }
            }
            Menu {
                ForEach(availableBoardLabels) { label in
                    Button {
                        Task {
                            await appState.assignLabel(
                                boardId: boardId,
                                stackId: card.stackId,
                                cardId: card.id,
                                labelId: label.id
                            )
                        }
                    } label: {
                        Label(label.title, systemImage: "tag.fill")
                    }
                }
                if !availableBoardLabels.isEmpty {
                    Divider()
                }
                Button {
                    newLabelTitle = ""
                    newLabelColor = "31CC7C"
                    showCreateLabel = true
                } label: {
                    Label("Create new tag…", systemImage: "plus.circle")
                }
            } label: {
                Text("Add label")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(board == nil)
        }
    }

    private var createLabelSheet: some View {
        CreateLabelSheet(
            title: $newLabelTitle,
            color: $newLabelColor,
            isCreating: $isCreatingLabel,
            onCreate: {
                isCreatingLabel = true
                Task {
                    if let labelId = await appState.createLabel(
                        boardId: boardId,
                        title: newLabelTitle,
                        color: newLabelColor
                    ) {
                        await appState.assignLabel(
                            boardId: boardId,
                            stackId: card.stackId,
                            cardId: card.id,
                            labelId: labelId
                        )
                        await MainActor.run {
                            showCreateLabel = false
                            newLabelTitle = ""
                            newLabelColor = "31CC7C"
                        }
                    }
                    await MainActor.run { isCreatingLabel = false }
                }
            },
            onCancel: { showCreateLabel = false }
        )
    }

    private func save() {
        isSaving = true
        Task {
            await appState.updateCard(
                boardId: boardId,
                stackId: card.stackId,
                card: card,
                title: title,
                description: description
            )
            await MainActor.run {
                isSaving = false
                dismiss()
                onDismiss()
            }
        }
    }
}

// MARK: - Attachment row

private struct AttachmentRowView: View {
    let attachment: Attachment
    var onDownload: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                if let size = attachment.formattedSize {
                    Text(size)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onDownload()
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .help("Download")
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Label chip

private struct LabelChip: View {
    let label: DeckLabel
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(label.title)
                .font(.caption)
                .lineLimit(1)
            if onRemove != nil {
                Button {
                    onRemove?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: label.color ?? "cccccc") ?? .gray.opacity(0.3))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}

// MARK: - Create label sheet

private struct CreateLabelSheet: View {
    @Binding var title: String
    @Binding var color: String
    @Binding var isCreating: Bool
    var onCreate: () -> Void
    var onCancel: () -> Void

    private static let presetColors: [(name: String, hex: String)] = [
        ("Green", "31CC7C"),
        ("Blue", "317CCC"),
        ("Red", "FF7A66"),
        ("Yellow", "F1DB50"),
        ("Purple", "9C59B6"),
        ("Orange", "F39C12"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("New tag")
                .font(.headline)
            TextField("Tag name", text: $title)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Self.presetColors, id: \.hex) { preset in
                        Button {
                            color = preset.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex) ?? .gray)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            Color.primary.opacity(0.3),
                                            lineWidth: color == preset.hex ? 3 : 0
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
        }
        .padding(24)
        .frame(width: 280)
    }
}
