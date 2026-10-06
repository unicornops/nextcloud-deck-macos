import SwiftUI

// MARK: - CardCommentsView

/// The Comments section of the card sheet: the card's comments, oldest first, and a box to add one.
/// Deck returns comments newest first in pages of `pageSize`; older pages load on demand.
struct CardCommentsView: View {
    let card: Card
    @EnvironmentObject private var appState: AppState

    /// Loaded comments, oldest first.
    @State private var comments: [CardComment] = []
    @State private var hasOlder = false
    @State private var isLoading = false
    @State private var draft = ""
    @State private var isPosting = false
    @State private var editingId: Int?
    @State private var editDraft = ""
    @State private var pendingDelete: CardComment?

    private static let pageSize = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasOlder {
                Button("Show older comments") {
                    Task { await loadPage(offset: comments.count) }
                }
                .buttonStyle(.link)
                .disabled(isLoading)
            }
            if isLoading && comments.isEmpty {
                ProgressView()
                    .controlSize(.small)
            } else if comments.isEmpty {
                Text("No comments yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(comments) { comment in
                commentRow(comment)
            }
            composer
        }
        .task(id: card.id) {
            comments = []
            await loadPage(offset: 0)
        }
        .confirmationDialog(
            "Delete comment?",
            isPresented: Binding(get: { pendingDelete != nil }, set: {
                if !$0 {
                    pendingDelete = nil
                }
            })
        ) {
            Button("Delete", role: .destructive) {
                guard let comment = pendingDelete else { return }
                pendingDelete = nil
                Task { await delete(comment) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("The comment will be permanently deleted.")
        }
    }

    // MARK: - Rows

    private func commentRow(_ comment: CardComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarBadge(user: comment.author)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author.displayName)
                        .font(.subheadline.weight(.semibold))
                    if let date = comment.createdAt {
                        Text(date, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Spacer()
                    if isOwn(comment), editingId != comment.id {
                        ownCommentMenu(comment)
                    }
                }
                if editingId == comment.id {
                    editor(for: comment)
                } else {
                    Text(comment.message)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func ownCommentMenu(_ comment: CardComment) -> some View {
        Menu {
            Button("Edit") {
                editDraft = comment.message
                editingId = comment.id
            }
            Button("Delete", role: .destructive) {
                pendingDelete = comment
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Comment actions")
    }

    private func editor(for comment: CardComment) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Comment", text: $editDraft, axis: .vertical)
                .lineLimit(1 ... 6)
                .textFieldStyle(.roundedBorder)
            HStack {
                characterCount(editDraft)
                Spacer()
                Button("Cancel") {
                    editingId = nil
                }
                Button("Save") {
                    Task { await saveEdit(of: comment) }
                }
                .disabled(!CardComment.isPostable(editDraft))
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .lineLimit(1 ... 6)
                .textFieldStyle(.roundedBorder)
            HStack {
                characterCount(draft)
                Spacer()
                Button {
                    Task { await post() }
                } label: {
                    if isPosting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Comment")
                    }
                }
                .disabled(isPosting || !CardComment.isPostable(draft))
            }
        }
    }

    @ViewBuilder
    private func characterCount(_ text: String) -> some View {
        if text.count > CardComment.maximumLength - 100 {
            Text("\(text.count)/\(CardComment.maximumLength)")
                .font(.caption)
                .foregroundStyle(text.count > CardComment.maximumLength ? .red : .secondary)
        }
    }

    // MARK: - Actions

    private func isOwn(_ comment: CardComment) -> Bool {
        comment.actorId == appState.currentUserId
    }

    private func loadPage(offset: Int) async {
        isLoading = true
        defer { isLoading = false }
        guard let page = await appState.comments(for: card, offset: offset) else { return }
        // Pages arrive newest first; older comments go above the ones already shown.
        comments = page.reversed() + comments
        hasOlder = page.count == Self.pageSize
    }

    private func post() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isPosting = true
        defer { isPosting = false }
        if let comment = await appState.addComment(message, to: card) {
            comments.append(comment)
            draft = ""
        }
    }

    private func saveEdit(of comment: CardComment) async {
        let message = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let updated = await appState.updateComment(comment, message: message, on: card) else { return }
        if let index = comments.firstIndex(where: { $0.id == comment.id }) {
            comments[index] = updated
        }
        editingId = nil
    }

    private func delete(_ comment: CardComment) async {
        if await appState.deleteComment(comment, from: card) {
            comments.removeAll { $0.id == comment.id }
        }
    }
}
