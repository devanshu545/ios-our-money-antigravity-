import Foundation

// MARK: - Enums (raw values must match Firestore strings written by the Android app)

enum TransactionType: String, Codable, CaseIterable {
    case expense = "EXPENSE"
    case income = "INCOME"
    case transfer = "TRANSFER"
}

enum SplitMethod: String, Codable, CaseIterable {
    case equal = "EQUAL"
    case exact = "EXACT"
    case percentage = "PERCENTAGE"
    case shares = "SHARES"
}

enum AiScope: String, Codable, CaseIterable {
    case personal = "PERSONAL"
    case shared = "SHARED"
}

enum AiMessageRole: String, Codable {
    case user = "USER"
    case model = "MODEL"
    case system = "SYSTEM"
}

// MARK: - Split

struct SplitAmount: Codable, Hashable, Identifiable {
    var userId: String
    var amountPaise: Int64

    var id: String { userId }
}

// MARK: - Transaction

struct Transaction: Codable, Hashable, Identifiable {
    var id: String
    var amountPaise: Int64
    var category: String
    var dateMillis: Int64
    var paidBy: String
    var createdBy: String
    var personal: Bool
    var splitMethod: SplitMethod
    var splits: [SplitAmount]
    var notes: String
    var type: TransactionType
    var paymentMethod: String
    var isDeleted: Bool

    /// Local-only mirror of Android's `@Exclude var isPending`.
    var isPending: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, amountPaise, category, dateMillis, paidBy, createdBy, personal
        case splitMethod, splits, notes, type, paymentMethod, isDeleted
    }

    init(id: String = UUID().uuidString,
         amountPaise: Int64 = 0,
         category: String = "",
         dateMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
         paidBy: String = "",
         createdBy: String = "",
         personal: Bool = false,
         splitMethod: SplitMethod = .equal,
         splits: [SplitAmount] = [],
         notes: String = "",
         type: TransactionType = .expense,
         paymentMethod: String = "UPI",
         isDeleted: Bool = false,
         isPending: Bool = false) {
        self.id = id
        self.amountPaise = amountPaise
        self.category = category
        self.dateMillis = dateMillis
        self.paidBy = paidBy
        self.createdBy = createdBy
        self.personal = personal
        self.splitMethod = splitMethod
        self.splits = splits
        self.notes = notes
        self.type = type
        self.paymentMethod = paymentMethod
        self.isDeleted = isDeleted
        self.isPending = isPending
    }

    /// Firestore documents written by Android may omit new/optional fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        amountPaise = try c.decodeIfPresent(Int64.self, forKey: .amountPaise) ?? 0
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        dateMillis = try c.decodeIfPresent(Int64.self, forKey: .dateMillis) ?? 0
        paidBy = try c.decodeIfPresent(String.self, forKey: .paidBy) ?? ""
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        personal = try c.decodeIfPresent(Bool.self, forKey: .personal) ?? false
        splitMethod = (try? c.decode(SplitMethod.self, forKey: .splitMethod)) ?? .equal
        splits = try c.decodeIfPresent([SplitAmount].self, forKey: .splits) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        type = (try? c.decode(TransactionType.self, forKey: .type)) ?? .expense
        paymentMethod = try c.decodeIfPresent(String.self, forKey: .paymentMethod) ?? "UPI"
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
}

// MARK: - User

struct User: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var email: String
    var householdId: String?
    var connectedAt: Int64?
    var createdAt: Int64

    init(id: String = UUID().uuidString,
         name: String = "",
         email: String = "",
         householdId: String? = nil,
         connectedAt: Int64? = nil,
         createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.name = name
        self.email = email
        self.householdId = householdId
        self.connectedAt = connectedAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case id, name, email, householdId, connectedAt, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        householdId = try c.decodeIfPresent(String.self, forKey: .householdId)
        connectedAt = try c.decodeIfPresent(Int64.self, forKey: .connectedAt)
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }
}

// MARK: - Household

struct Household: Codable, Hashable, Identifiable {
    var id: String
    var code: String
    var members: [String]
    var createdAt: Int64

    init(id: String = UUID().uuidString,
         code: String = "",
         members: [String] = [],
         createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.code = code
        self.members = members
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case id, code, members, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        members = try c.decodeIfPresent([String].self, forKey: .members) ?? []
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }
}

// MARK: - Settlement

struct Settlement: Codable, Hashable, Identifiable {
    var id: String
    var amountPaise: Int64
    var paidBy: String
    var receivedBy: String
    var dateMillis: Int64
    var paymentMethod: String
    var notes: String
    var createdBy: String
    var createdAt: Int64

    var isPending: Bool = false

    init(id: String = UUID().uuidString,
         amountPaise: Int64 = 0,
         paidBy: String = "",
         receivedBy: String = "",
         dateMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
         paymentMethod: String = "",
         notes: String = "",
         createdBy: String = "",
         createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
         isPending: Bool = false) {
        self.id = id
        self.amountPaise = amountPaise
        self.paidBy = paidBy
        self.receivedBy = receivedBy
        self.dateMillis = dateMillis
        self.paymentMethod = paymentMethod
        self.notes = notes
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.isPending = isPending
    }

    enum CodingKeys: String, CodingKey {
        case id, amountPaise, paidBy, receivedBy, dateMillis
        case paymentMethod, notes, createdBy, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        amountPaise = try c.decodeIfPresent(Int64.self, forKey: .amountPaise) ?? 0
        paidBy = try c.decodeIfPresent(String.self, forKey: .paidBy) ?? ""
        receivedBy = try c.decodeIfPresent(String.self, forKey: .receivedBy) ?? ""
        dateMillis = try c.decodeIfPresent(Int64.self, forKey: .dateMillis) ?? 0
        paymentMethod = try c.decodeIfPresent(String.self, forKey: .paymentMethod) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }
}

// MARK: - Goal

struct Goal: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var targetAmountPaise: Int64
    var currentAmountPaise: Int64
    var personal: Bool
    var createdBy: String
    var createdAt: Int64

    var isPending: Bool = false

    init(id: String = UUID().uuidString,
         name: String = "",
         targetAmountPaise: Int64 = 0,
         currentAmountPaise: Int64 = 0,
         personal: Bool = false,
         createdBy: String = "",
         createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
         isPending: Bool = false) {
        self.id = id
        self.name = name
        self.targetAmountPaise = targetAmountPaise
        self.currentAmountPaise = currentAmountPaise
        self.personal = personal
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.isPending = isPending
    }

    enum CodingKeys: String, CodingKey {
        case id, name, targetAmountPaise, currentAmountPaise, personal, createdBy, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        targetAmountPaise = try c.decodeIfPresent(Int64.self, forKey: .targetAmountPaise) ?? 0
        currentAmountPaise = try c.decodeIfPresent(Int64.self, forKey: .currentAmountPaise) ?? 0
        personal = try c.decodeIfPresent(Bool.self, forKey: .personal) ?? false
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }
}

// MARK: - Budget

struct Budget: Codable, Hashable, Identifiable {
    var id: String
    var category: String
    var limitAmountPaise: Int64
    var personal: Bool
    var createdBy: String
    var monthYear: String
    var createdAt: Int64

    var isPending: Bool = false

    init(id: String = UUID().uuidString,
         category: String = "",
         limitAmountPaise: Int64 = 0,
         personal: Bool = false,
         createdBy: String = "",
         monthYear: String = "",
         createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
         isPending: Bool = false) {
        self.id = id
        self.category = category
        self.limitAmountPaise = limitAmountPaise
        self.personal = personal
        self.createdBy = createdBy
        self.monthYear = monthYear
        self.createdAt = createdAt
        self.isPending = isPending
    }

    enum CodingKeys: String, CodingKey {
        case id, category, limitAmountPaise, personal, createdBy, monthYear, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        limitAmountPaise = try c.decodeIfPresent(Int64.self, forKey: .limitAmountPaise) ?? 0
        personal = try c.decodeIfPresent(Bool.self, forKey: .personal) ?? false
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        monthYear = try c.decodeIfPresent(String.self, forKey: .monthYear) ?? ""
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }
}

// MARK: - Custom category

struct CustomCategory: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var createdBy: String
    var createdAt: Int64

    init(id: String = UUID().uuidString,
         name: String = "",
         createdBy: String = "",
         createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case id, name, createdBy, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? ""
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }
}

// MARK: - AI models

struct AiChat: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var createdAt: Int64
    var updatedAt: Int64
    var ownerId: String
    var householdId: String
    var scope: AiScope

    init(id: String = UUID().uuidString,
         title: String = "New Conversation",
         createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
         updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
         ownerId: String = "",
         householdId: String = "",
         scope: AiScope = .personal) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ownerId = ownerId
        self.householdId = householdId
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, ownerId, householdId, scope
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "New Conversation"
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId) ?? ""
        householdId = try c.decodeIfPresent(String.self, forKey: .householdId) ?? ""
        scope = (try? c.decode(AiScope.self, forKey: .scope)) ?? .personal
    }
}

struct AiMessage: Codable, Hashable, Identifiable {
    var id: String
    var chatId: String
    var role: AiMessageRole
    var content: String
    var timestamp: Int64

    init(id: String = UUID().uuidString,
         chatId: String = "",
         role: AiMessageRole = .user,
         content: String = "",
         timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.chatId = chatId
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey { case id, chatId, role, content, timestamp }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        chatId = try c.decodeIfPresent(String.self, forKey: .chatId) ?? ""
        role = (try? c.decode(AiMessageRole.self, forKey: .role)) ?? .user
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        timestamp = try c.decodeIfPresent(Int64.self, forKey: .timestamp) ?? 0
    }
}

// MARK: - Auth state (mirror of Android sealed class AuthState)

enum AuthState: Equatable {
    case idle
    case loading
    case requiresName(uid: String)
    case requiresPairing(user: User, household: Household?, error: String?)
    case authenticated(user: User, household: Household)
    case error(message: String)

    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading): return true
        case (.requiresName(let a), .requiresName(let b)): return a == b
        case (.requiresPairing(let a1, let a2, let a3), .requiresPairing(let b1, let b2, let b3)):
            return a1 == b1 && a2 == b2 && a3 == b3
        case (.authenticated(let a1, let a2), .authenticated(let b1, let b2)):
            return a1 == b1 && a2 == b2
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}
