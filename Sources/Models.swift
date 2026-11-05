import Foundation

public struct ManagedAccount: Codable {
    public let id: String
    public let email: String
    public let name: String?
    public let disabled: Bool?
    public let proxy_disabled: Bool?
    public let created_at: Int?
    public let last_used: Int?
    public let model: String?
    public let active_model: String?
    public let picture: String?

    public init(
        id: String,
        email: String,
        name: String? = nil,
        disabled: Bool? = nil,
        proxy_disabled: Bool? = nil,
        created_at: Int? = nil,
        last_used: Int? = nil,
        model: String? = nil,
        active_model: String? = nil,
        picture: String? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.disabled = disabled
        self.proxy_disabled = proxy_disabled
        self.created_at = created_at
        self.last_used = last_used
        self.model = model
        self.active_model = active_model
        self.picture = picture
    }

    public func displayName(showAlias: Bool) -> String {
        if showAlias, let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return email
    }
}

public struct AccountsFile: Codable {
    public var version: String?
    public var accounts: [ManagedAccount]
    public var current_account_id: String?
    public var current_target_ide: String?
    public var current_classic_account_id: String?
    public var current_ide_account_id: String?
    public var current_agy_account_id: String?
}

public struct AccountToken: Codable {
    public let access_token: String?
    public let refresh_token: String?
    public let expires_in: Int?
    public let expiry_timestamp: Int?
    public let email: String?
}

public struct AccountDetailQuota: Codable {
    public let subscription_tier: String?
    public let tier_id: String?
    public let is_forbidden: Bool?
}

public struct AccountDetailFile: Codable {
    public let id: String
    public let email: String
    public let name: String?
    public let token: AccountToken?
    public let model: String?
    public let active_model: String?
    public let quota: AccountDetailQuota?
    public let picture: String?

    public init(
        id: String,
        email: String,
        name: String? = nil,
        token: AccountToken? = nil,
        model: String? = nil,
        active_model: String? = nil,
        quota: AccountDetailQuota? = nil,
        picture: String? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.token = token
        self.model = model
        self.active_model = active_model
        self.quota = quota
        self.picture = picture
    }
}

public struct QuotaBucket: Codable {
    public let bucketId: String?
    public let displayName: String?
    public let window: String?
    public let resetTime: String?
    public let description: String?
    public let remainingFraction: Double?
}

public struct QuotaGroup: Codable {
    public let displayName: String?
    public let description: String?
    public let buckets: [QuotaBucket]?
}

public struct QuotaSummaryResponse: Codable {
    public let groups: [QuotaGroup]?
    public let description: String?
}

// Model for Google Code Assist tier information
public struct CodeAssistTier: Codable {
    public let id: String?
    public let name: String?
    public let description: String?
    public let upgradeSubscriptionText: String?
    public let upgradeSubscriptionUri: String?
    public let upgradeSubscriptionType: String?
}

public struct LoadCodeAssistResponse: Codable {
    public let currentTier: CodeAssistTier?
    public let paidTier: CodeAssistTier?
    public let cloudaicompanionProject: String?
    public let gcpManaged: Bool?
}

// Model for local API on port 8045
public struct LocalApiAccountModelQuota: Codable {
    public let name: String
    public let percentage: Int
    public let reset_time: String?
}

public struct LocalApiAccountQuota: Codable {
    public let models: [LocalApiAccountModelQuota]?
    public let subscription_tier: String?
}

public struct LocalApiAccount: Codable {
    public let id: String
    public let email: String
    public let name: String?
    public let is_current: Bool?
    public let disabled: Bool?
    public let quota: LocalApiAccountQuota?
}

public struct LocalApiAccountsResponse: Codable {
    public let accounts: [LocalApiAccount]?
}

// Model Catalog & Options
public struct AIModelOption: Equatable {
    public let id: String
    public let displayName: String
    public let group: String

    public init(id: String, displayName: String, group: String) {
        self.id = id
        self.displayName = displayName
        self.group = group
    }
}

public struct AIModelCatalog {
    public static var auto: AIModelOption {
        return AIModelOption(id: "", displayName: L10n.tr("model.auto"), group: "System")
    }

    public static let geminiModels: [AIModelOption] = [
        AIModelOption(id: "MODEL_PLACEHOLDER_M318", displayName: "Gemini 3.8 Flash (High)", group: "Google Gemini"),
        AIModelOption(id: "MODEL_PLACEHOLDER_M319", displayName: "Gemini 3.8 Flash (Medium)", group: "Google Gemini"),
        AIModelOption(id: "MODEL_PLACEHOLDER_M320", displayName: "Gemini 3.8 Flash (Low)", group: "Google Gemini")
    ]

    public static let claudeModels: [AIModelOption] = [
        AIModelOption(id: "MODEL_PLACEHOLDER_M35", displayName: "Claude Sonnet 4.6 (Thinking)", group: "Anthropic Claude"),
        AIModelOption(id: "MODEL_PLACEHOLDER_M26", displayName: "Claude Opus 4.6 (Thinking)", group: "Anthropic Claude")
    ]

    public static let otherModels: [AIModelOption] = [
        AIModelOption(id: "MODEL_OPENAI_GPT_OSS_120B_MEDIUM", displayName: "GPT-OSS 120B (Medium)", group: "Other")
    ]

    public static var allModels: [AIModelOption] {
        return [auto] + geminiModels + claudeModels + otherModels
    }

    public static func displayName(forId id: String?) -> String {
        guard let id = id, !id.isEmpty else {
            return L10n.tr("model.auto")
        }
        if let found = allModels.first(where: { $0.id == id }) {
            return found.displayName
        }
        return QuotaService.shared.formatModelIdentifier(id)
    }
}

// Unified Account Status for UI and Rotation
public struct AccountStatus {
    public let id: String
    public let email: String
    public let name: String
    public var isCurrent: Bool
    public var remainingPercentage: Int
    public var gemini5hPercentage: Int?
    public var geminiWeeklyPercentage: Int?
    public var geminiResetTime: String?
    public var geminiWeeklyResetTime: String?
    public var other5hPercentage: Int?
    public var otherWeeklyPercentage: Int?
    public var lastUpdated: Date?
    public var activeModel: String?
    public var subscriptionTier: String?
    public var tierId: String?
    public var preferredModelId: String?
    public var picture: String?

    public init(
        id: String,
        email: String,
        name: String,
        isCurrent: Bool = false,
        remainingPercentage: Int = 100,
        gemini5hPercentage: Int? = nil,
        geminiWeeklyPercentage: Int? = nil,
        geminiResetTime: String? = nil,
        geminiWeeklyResetTime: String? = nil,
        other5hPercentage: Int? = nil,
        otherWeeklyPercentage: Int? = nil,
        lastUpdated: Date? = Date(),
        activeModel: String? = nil,
        subscriptionTier: String? = nil,
        tierId: String? = nil,
        preferredModelId: String? = nil,
        picture: String? = nil
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.isCurrent = isCurrent
        self.remainingPercentage = remainingPercentage
        self.gemini5hPercentage = gemini5hPercentage
        self.geminiWeeklyPercentage = geminiWeeklyPercentage
        self.geminiResetTime = geminiResetTime
        self.geminiWeeklyResetTime = geminiWeeklyResetTime
        self.other5hPercentage = other5hPercentage
        self.otherWeeklyPercentage = otherWeeklyPercentage
        self.lastUpdated = lastUpdated
        self.activeModel = activeModel
        self.subscriptionTier = subscriptionTier
        self.tierId = tierId
        self.preferredModelId = preferredModelId
        self.picture = picture
    }

    public var displayModelName: String {
        if let pref = preferredModelId, !pref.isEmpty {
            return AIModelCatalog.displayName(forId: pref)
        }
        if isCurrent {
            return activeModel ?? "Gemini 3.8 Flash (High)"
        }
        return L10n.tr("model.auto")
    }

    public var displayTierName: String {
        return subscriptionTier ?? "Free"
    }

    public var isExhausted: Bool {
        return remainingPercentage <= 0
    }

    public func displayName(showAlias: Bool) -> String {
        if showAlias {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return email
    }

    public var currentDisplayName: String {
        return displayName(showAlias: ConfigManager.shared.config.showAccountAlias)
    }
}

