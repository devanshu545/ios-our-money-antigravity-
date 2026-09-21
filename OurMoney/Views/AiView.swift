import SwiftUI

/// Mirror of `ui/ai/AiScreen.kt`: scope toggle, chat list, chat thread, send bar.
struct AiView: View {
    let user: User
    let household: Household

    @StateObject private var viewModel: AiViewModel

    init(user: User, household: Household) {
        self.user = user
        self.household = household
        _viewModel = StateObject(wrappedValue: AiViewModel(currentUser: user, household: household))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()
                if viewModel.currentChatId == nil {
                    chatList
                } else {
                    chatThread
                }
            }
            .navigationTitle("AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.currentChatId != nil {
                        Button {
                            viewModel.closeChat()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Picker("Scope", selection: Binding(
                        get: { viewModel.scope },
                        set: { viewModel.setScope($0) })) {
                        Text("Personal").tag(AiScope.personal)
                        Text("Shared").tag(AiScope.shared)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.createNewChat()
                    } label: {
                        Image(systemName: "plus.message")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Chat list

    private var chatList: some View {
        Group {
            if viewModel.chats.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("No conversations yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Start a new chat to ask about your money.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        viewModel.createNewChat()
                    } label: {
                        Label("New chat", systemImage: "plus.message")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.tealDeep)
                }
            } else {
                List {
                    ForEach(viewModel.chats) { chat in
                        Button {
                            viewModel.openChat(chatId: chat.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chat.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(Formatters.dayFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(chat.updatedAt) / 1000)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.deleteChat(chatId: chat.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Chat thread

    private var chatThread: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.currentMessages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                Text("Thinking…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.currentMessages.count) { _ in
                    if let last = viewModel.currentMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let error = viewModel.error {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                    Button {
                        viewModel.retryLastMessage()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            inputBar
        }
    }

    @State private var draft = ""

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your money…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button {
                let text = draft
                draft = ""
                viewModel.sendMessage(text: text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.teal)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

private struct ChatBubble: View {
    let message: AiMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .font(.subheadline)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(12)
                .background(message.role == .user ? AnyShapeStyle(Theme.tealDeep) : AnyShapeStyle(.thinMaterial),
                            in: RoundedRectangle(cornerRadius: 16))
            if message.role == .model { Spacer(minLength: 40) }
        }
    }
}
