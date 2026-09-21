import Foundation
import FirebaseFirestore

/// Mirror of `data/AiRepository.kt`. Same collections (`ai_chats`, `ai_messages`),
/// same queries, same cascade delete of messages.
final class AiRepository {
    private let db = Firestore.firestore()

    private static func chatData(_ chat: AiChat) -> [String: Any] {
        [
            "id": chat.id,
            "title": chat.title,
            "createdAt": chat.createdAt,
            "updatedAt": chat.updatedAt,
            "ownerId": chat.ownerId,
            "householdId": chat.householdId,
            "scope": chat.scope.rawValue,
        ]
    }

    private static func messageData(_ message: AiMessage) -> [String: Any] {
        [
            "id": message.id,
            "chatId": message.chatId,
            "role": message.role.rawValue,
            "content": message.content,
            "timestamp": message.timestamp,
        ]
    }

    /// Chat list for the given scope — PERSONAL chats owned by me, or SHARED chats of my household.
    func listenChats(userId: String, householdId: String, scope: AiScope,
                     onChange: @escaping ([AiChat]) -> Void) -> ListenerRegistration {
        let base = db.collection("ai_chats")
        let query: Query = (scope == .personal)
            ? base.whereField("ownerId", isEqualTo: userId).whereField("scope", isEqualTo: AiScope.personal.rawValue)
            : base.whereField("householdId", isEqualTo: householdId).whereField("scope", isEqualTo: AiScope.shared.rawValue)

        return query.addSnapshotListener { snapshot, error in
            guard error == nil, let snapshot else { onChange([]); return }
            let chats = snapshot.documents.compactMap { doc -> AiChat? in
                let data = doc.data()
                guard let id = data["id"] as? String else { return nil }
                return AiChat(
                    id: id,
                    title: data["title"] as? String ?? "New Conversation",
                    createdAt: (data["createdAt"] as? NSNumber)?.int64Value ?? 0,
                    updatedAt: (data["updatedAt"] as? NSNumber)?.int64Value ?? 0,
                    ownerId: data["ownerId"] as? String ?? "",
                    householdId: data["householdId"] as? String ?? "",
                    scope: AiScope(rawValue: data["scope"] as? String ?? "PERSONAL") ?? .personal
                )
            }.sorted { $0.updatedAt > $1.updatedAt }
            onChange(chats)
        }
    }

    func createChat(_ chat: AiChat) async throws {
        try await db.collection("ai_chats").document(chat.id).setData(Self.chatData(chat))
    }

    func updateChatTitle(chatId: String, newTitle: String) async throws {
        try await db.collection("ai_chats").document(chatId).updateData([
            "title": newTitle,
            "updatedAt": Int64(Date().timeIntervalSince1970 * 1000),
        ])
    }

    /// Deletes a chat and cascades to its messages (same as Android).
    func deleteChat(chatId: String) async throws {
        try await db.collection("ai_chats").document(chatId).delete()
        let msgs = try await db.collection("ai_messages").whereField("chatId", isEqualTo: chatId).getDocuments()
        for doc in msgs.documents {
            try await doc.reference.delete()
        }
    }

    func listenMessages(chatId: String, onChange: @escaping ([AiMessage]) -> Void) -> ListenerRegistration {
        // Note: Android uses an unindexed whereEqualTo without orderBy; we sort by timestamp
        // client-side for identical behavior without a composite index.
        return db.collection("ai_messages").whereField("chatId", isEqualTo: chatId)
            .addSnapshotListener { snapshot, error in
                guard error == nil, let snapshot else { onChange([]); return }
                let messages = snapshot.documents.compactMap { doc -> AiMessage? in
                    let data = doc.data()
                    guard let id = data["id"] as? String else { return nil }
                    return AiMessage(
                        id: id,
                        chatId: data["chatId"] as? String ?? "",
                        role: AiMessageRole(rawValue: data["role"] as? String ?? "USER") ?? .user,
                        content: data["content"] as? String ?? "",
                        timestamp: (data["timestamp"] as? NSNumber)?.int64Value ?? 0
                    )
                }.sorted { $0.timestamp < $1.timestamp }
                onChange(messages)
            }
    }

    func addMessage(_ message: AiMessage) async throws {
        try await db.collection("ai_messages").document(message.id).setData(Self.messageData(message))
        try await db.collection("ai_chats").document(message.chatId)
            .updateData(["updatedAt": Int64(Date().timeIntervalSince1970 * 1000)])
    }
}
