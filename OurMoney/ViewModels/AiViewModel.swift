import Foundation
import Combine
import FirebaseFirestore

/// Mirror of `ui/ai/AiViewModel.kt`: Firestore-backed chats/messages + Gemini responses.
final class AiViewModel: ObservableObject {
    let currentUser: User
    let household: Household
    private let aiRepository = AiRepository()
    private let gemini = GeminiService()
    private let ledgerRepository: LedgerRepository
    private let contextEngine = AiFinancialContextEngine()

    @Published private(set) var scope: AiScope = .personal
    @Published private(set) var chats: [AiChat] = []
    @Published private(set) var currentChatId: String?
    @Published private(set) var currentMessages: [AiMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var lastFailedMessage: String?
    private var chatsListener: ListenerRegistration?
    private var messagesListener: ListenerRegistration?
    private let systemPromptTemplate = """
    You are OurMoney AI, a premium personal financial intelligence assistant.
    You are analyzing real data from the OurMoney app.

    IMPORTANT:
    DO NOT HALLUCINATE OR INVENT DATA. If a user asks about spending, budgets, or settlements, base your answer STRICTLY on the financial context provided below.

    1. CORE AI PERSONALITY
    OurMoney AI should feel like a friendly personal financial companion.
    Helpful, Friendly, Natural, Calm, Practical, Honest, Clear, Supportive, Easy to understand.
    Use natural language. It should sound like ChatGPT, engaging but very clear.

    2. NO MARKDOWN OR SPECIAL CHARACTERS
    CRITICAL: Do NOT use markdown formatting.
    - Do NOT use hashtags (#) for headings.
    - Do NOT use asterisks (*) for bold or italics.
    - Do NOT use backticks (`).
    - Avoid excessive emojis. Only use a single emoji if it perfectly fits (like 🟢 or 🔴 for affordability).
    Use ALL CAPS for emphasis if absolutely necessary, but prefer natural phrasing and blank lines (paragraphs) for structure.

    3. ANSWER LENGTH MUST BE DYNAMIC
    The response length must depend on the question.
    Simple question -> short answer.
    Complex question -> more complete answer with sections (but not an essay).

    4. ANSWER THE QUESTION FIRST
    Always answer the user's actual question near the beginning.

    5. USE A CLEAR RESPONSE STRUCTURE
    Depending on the question, use:
    1. Direct answer
    2. Important numbers
    3. Short explanation
    4. Recommendation/action
    Separate these with a blank line for readability.

    6. "CAN I SPEND?" RESPONSE FORMAT
    🟢 Yes, you can.
    ₹180 for dosa looks affordable right now.
    Why:
    Food budget remaining: ₹1,420
    Safe spending today: ₹620
    My take:
    Enjoy it, but keep the rest of today's spending moderate.
    If risky:
    🔴 I'd avoid it for now.
    After this purchase:
    Budget remaining: ₹800
    Projected overspend: ₹1,200
    My take:
    If it isn't urgent, waiting a few days would be better.

    7. OTHER RULES
    - NEVER OVER-EXPLAIN SIMPLE QUESTIONS
    - NEVER UNDER-EXPLAIN COMPLEX QUESTIONS
    - USE HUMAN-FRIENDLY MONEY LANGUAGE (e.g. "₹1,200 left" instead of "Remaining financial allocation")
    - FORMAT NUMBERS FOR MOBILE (e.g. ₹10,000 not 10000.00 INR)
    - DON'T SHOW RAW INTERNAL DATA (No Firestore IDs, User IDs, JSON)
    - AI SHOULD BE HONEST (If not enough data, say so)
    - DON'T MAKE FINANCIAL CLAIMS WITHOUT DATA
    - RECOMMENDATIONS MUST BE PRACTICAL
    - DON'T SOUND JUDGMENTAL
    - DON'T ALWAYS SAY NO (If user can afford, say yes)
    - RESPONSE PRIORITY (Answer -> Numbers -> Why -> Advice -> Next step)

    FINANCIAL CONTEXT:
    %@
    """

    init(currentUser: User, household: Household) {
        self.currentUser = currentUser
        self.household = household
        self.ledgerRepository = LedgerRepository(householdId: household.id, currentUserId: currentUser.id)
        Task { [weak self] in await self?.attachChatsListener() }
    }

    deinit {
        chatsListener?.remove()
        messagesListener?.remove()
    }

    @MainActor
    private func attachChatsListener() async {
        chatsListener?.remove()
        let userId = currentUser.id
        let householdId = household.id
        let currentScope = scope
        chatsListener = aiRepository.listenChats(userId: userId, householdId: householdId, scope: currentScope) { [weak self] chats in
            Task { @MainActor in self?.chats = chats }
        }
    }

    func setScope(_ newScope: AiScope) {
        guard newScope != scope else { return }
        scope = newScope
        currentChatId = nil
        Task { [weak self] in await self?.attachChatsListener() }
    }

    func openChat(chatId: String) {
        messagesListener?.remove()
        currentChatId = chatId
        messagesListener = aiRepository.listenMessages(chatId: chatId) { [weak self] messages in
            Task { @MainActor in self?.currentMessages = messages }
        }
    }

    func closeChat() {
        messagesListener?.remove()
        messagesListener = nil
        currentChatId = nil
        currentMessages = []
    }

    func createNewChat() {
        Task { [weak self] in
            guard let self else { return }
            let newChat = AiChat(
                ownerId: self.currentUser.id,
                householdId: self.household.id,
                scope: self.scope
            )
            try? await self.aiRepository.createChat(newChat)
            await MainActor.run { self.openChat(chatId: newChat.id) }
        }
    }

    func deleteChat(chatId: String) {
        Task { [weak self] in
            guard let self else { return }
            try? await self.aiRepository.deleteChat(chatId: chatId)
            await MainActor.run {
                if self.currentChatId == chatId { self.closeChat() }
            }
        }
    }

    func clearError() {
        error = nil
        lastFailedMessage = nil
    }

    func retryLastMessage() {
        guard let last = lastFailedMessage else { return }
        clearError()
        sendMessage(text: last)
    }

    /// Sends a user message: persists it, updates the title, builds the financial context,
    /// calls Gemini, and persists the model reply. Errors surface via `error` + retry.
    func sendMessage(text: String) {
        guard let chatId = currentChatId, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !isLoading else { return }
        isLoading = true
        error = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let userMsg = AiMessage(chatId: chatId, role: .user, content: text)
                try await self.aiRepository.addMessage(userMsg)

                // Auto-title from the first message (same 30-char rule as Android).
                let msgs = await MainActor.run { self.currentMessages }
                if msgs.count <= 1 {
                    let title = text.count > 30 ? String(text.prefix(27)) + "..." : text
                    try? await self.aiRepository.updateChatTitle(chatId: chatId, newTitle: title)
                }

                // Snapshot of real financial data (same context engine as Android).
                let txs = self.ledgerRepository.transactions
                let stls = self.ledgerRepository.settlements
                let buds = self.ledgerRepository.budgets
                let gols = self.ledgerRepository.goals
                let scope = await MainActor.run { self.scope }
                let contextStr = self.contextEngine.generateContext(
                    scope: scope,
                    currentUser: self.currentUser,
                    transactions: txs,
                    budgets: buds,
                    goals: gols,
                    settlements: stls
                )

                // Flatten the conversation (same approach as Android to keep roles strict).
                let history = msgs.filter { $0.id != userMsg.id }
                var prompt = ""
                for msg in history {
                    prompt += (msg.role == .user ? "User: " : "AI: ") + msg.content + "\n\n"
                }
                prompt += "User: \(text)"

                let systemInstruction = String(format: self.systemPromptTemplate, contextStr)
                let response = try await self.gemini.generateContent(prompt: prompt, systemInstruction: systemInstruction)

                let aiMsg = AiMessage(chatId: chatId, role: .model, content: response)
                try await self.aiRepository.addMessage(aiMsg)

                await MainActor.run { self.isLoading = false }
            } catch {
                await MainActor.run {
                    self.lastFailedMessage = text
                    self.error = "Sorry, I couldn't analyze that right now.\nYour financial data is safe. Try again."
                    self.isLoading = false
                }
            }
        }
    }
}
