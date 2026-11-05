import Foundation

public class QuotaService {
    public static let shared = QuotaService()

    private let homeDir: URL
    private let orbitDir: URL
    private let accountsFile: URL
    private let localApiUrl = URL(string: "http://127.0.0.1:8045/api/accounts")!
    private let googleQuotaUrl = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    private let googleCodeAssistUrl = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    private let userAgent = "antigravity/hub/2.23.1 (Windows NT 10.0; Win64; x64)"

    private init() {
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.orbitDir = homeDir.appendingPathComponent(".antigravity_orbit")
        self.accountsFile = orbitDir.appendingPathComponent("accounts.json")
    }

    public func getAccountDetailPath(accountId: String) -> URL {
        return orbitDir.appendingPathComponent("accounts").appendingPathComponent("\(accountId).json")
    }

    public func getApiKey() -> String {
        let configPath = orbitDir.appendingPathComponent("gui_config.json")
        guard let data = try? Data(contentsOf: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let proxy = json["proxy"] as? [String: Any],
              let apiKey = proxy["api_key"] as? String else {
            return "sk-2d9c1aad60db498ebdb8818970541d02"
        }
        return apiKey
    }

    public func loadAccountsFile() -> AccountsFile? {
        guard let data = try? Data(contentsOf: accountsFile) else { return nil }
        return try? JSONDecoder().decode(AccountsFile.self, from: data)
    }

    public func fetchAllQuotas(completion: @escaping ([AccountStatus]) -> Void) {
        guard let accountsFile = loadAccountsFile() else {
            completion([])
            return
        }

        let activeId = accountsFile.current_classic_account_id ?? accountsFile.current_ide_account_id ?? accountsFile.current_account_id ?? ""

        // Try local API first
        fetchFromLocalApi(accountsFile: accountsFile, activeId: activeId) { [weak self] localStatuses in
            guard let self = self else { return }
            if !localStatuses.isEmpty {
                completion(localStatuses)
                return
            }

            // Fallback to Google Cloud Code PA API
            self.fetchFromGoogleApi(accountsFile: accountsFile, activeId: activeId) { googleStatuses in
                completion(googleStatuses)
            }
        }
    }

    private func fetchFromLocalApi(accountsFile: AccountsFile, activeId: String, completion: @escaping ([AccountStatus]) -> Void) {
        var request = URLRequest(url: localApiUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        request.addValue("Bearer \(getApiKey())", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let resp = try? JSONDecoder().decode(LocalApiAccountsResponse.self, from: data),
                  let accounts = resp.accounts, !accounts.isEmpty else {
                completion([])
                return
            }

            var results: [AccountStatus] = []
            for acc in accounts {
                var minPercent = 100
                var gemini5h: Int?
                var geminiWeekly: Int?
                var other5h: Int?
                var otherWeekly: Int?
                var gemini5hResetTime: String?
                var geminiWeeklyResetTime: String?

                if let models = acc.quota?.models {
                    for m in models {
                        let lower = m.name.lowercased()
                        if lower.contains("gemini") {
                            minPercent = min(minPercent, m.percentage)
                            if lower.contains("flash") || lower.contains("5h") {
                                gemini5h = m.percentage
                                if gemini5hResetTime == nil {
                                    gemini5hResetTime = m.reset_time
                                }
                            } else if lower.contains("pro") || lower.contains("week") {
                                geminiWeekly = m.percentage
                                if geminiWeeklyResetTime == nil {
                                    geminiWeeklyResetTime = m.reset_time
                                }
                            } else {
                                if gemini5h == nil {
                                    gemini5h = m.percentage
                                    gemini5hResetTime = m.reset_time
                                } else if geminiWeekly == nil {
                                    geminiWeekly = m.percentage
                                    geminiWeeklyResetTime = m.reset_time
                                }
                            }
                        } else if lower.contains("claude") || lower.contains("gpt") {
                            other5h = m.percentage
                            otherWeekly = m.percentage
                        }
                    }
                }

                let primaryPercent = gemini5h ?? minPercent
                let isCurrent = (acc.id == activeId) || (acc.is_current == true)
                let currentModel = self.getCurrentAntigravityModel()
                let localTier = acc.quota?.subscription_tier
                let tierDisplayName = localTier.map { self.resolveTierDisplayName(tierId: $0, tierName: $0) } ?? L10n.tr("tier.free")
                let customName = accountsFile.accounts.first(where: { $0.id == acc.id })?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedName: String
                if let custom = customName, !custom.isEmpty {
                    resolvedName = custom
                } else {
                    resolvedName = acc.name ?? acc.email
                }
                let prefModel = accountsFile.accounts.first(where: { $0.id == acc.id })?.active_model ?? accountsFile.accounts.first(where: { $0.id == acc.id })?.model

                let matchedAcc = accountsFile.accounts.first(where: { $0.id == acc.id || $0.email.lowercased() == acc.email.lowercased() })
                var accountPic = matchedAcc?.picture
                if accountPic == nil {
                    let detailPath = self.getAccountDetailPath(accountId: acc.id)
                    if let detailData = try? Data(contentsOf: detailPath),
                       let detailJson = (try? JSONSerialization.jsonObject(with: detailData)) as? [String: Any] {
                        accountPic = detailJson["picture"] as? String
                    }
                }
                if let p = accountPic {
                    _ = AvatarManager.shared.getAvatarImage(accountId: acc.id, pictureUrl: p)
                }

                let status = AccountStatus(
                    id: acc.id,
                    email: acc.email,
                    name: resolvedName,
                    isCurrent: isCurrent,
                    remainingPercentage: primaryPercent,
                    gemini5hPercentage: gemini5h,
                    geminiWeeklyPercentage: geminiWeekly,
                    geminiResetTime: gemini5hResetTime,
                    geminiWeeklyResetTime: geminiWeeklyResetTime,
                    other5hPercentage: other5h,
                    otherWeeklyPercentage: otherWeekly,
                    lastUpdated: Date(),
                    activeModel: currentModel,
                    subscriptionTier: tierDisplayName,
                    tierId: localTier,
                    preferredModelId: prefModel,
                    picture: accountPic
                )
                results.append(status)
            }

            completion(results)
        }
        task.resume()
    }

    private func fetchFromGoogleApi(accountsFile: AccountsFile, activeId: String, completion: @escaping ([AccountStatus]) -> Void) {
        let dispatchGroup = DispatchGroup()
        var results: [AccountStatus] = []
        let lock = NSLock()

        for acc in accountsFile.accounts {
            if acc.disabled == true { continue }

            dispatchGroup.enter()
            fetchAccountQuota(acc: acc, activeId: activeId) { status in
                lock.lock()
                results.append(status)
                lock.unlock()
                dispatchGroup.leave()
            }
        }

        dispatchGroup.notify(queue: .main) {
            // Sort by order in accountsFile
            let idOrder = accountsFile.accounts.map { $0.id }
            results.sort { (a, b) -> Bool in
                let idxA = idOrder.firstIndex(of: a.id) ?? 999
                let idxB = idOrder.firstIndex(of: b.id) ?? 999
                return idxA < idxB
            }
            completion(results)
        }
    }

    public func getRawAntigravityModelId() -> String {
        let statePath = homeDir.appendingPathComponent(".gemini")
            .appendingPathComponent("antigravity")
            .appendingPathComponent("antigravity_state.pbtxt")
        if let content = try? String(contentsOf: statePath, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "last_selected_agent_model:") {
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count > 1 {
                        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
                    }
                }
            }
        }
        return ""
    }

    public func applyAntigravityModel(modelId: String) {
        let cleanId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return }

        let statePath = homeDir.appendingPathComponent(".gemini")
            .appendingPathComponent("antigravity")
            .appendingPathComponent("antigravity_state.pbtxt")

        guard FileManager.default.fileExists(atPath: statePath.path),
              let content = try? String(contentsOf: statePath, encoding: .utf8) else {
            return
        }

        var lines = content.components(separatedBy: .newlines)
        var found = false
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.starts(with: "last_selected_agent_model:") {
                lines[i] = "last_selected_agent_model:  \(cleanId)"
                found = true
                break
            }
        }
        if !found {
            lines.append("last_selected_agent_model:  \(cleanId)")
        }
        let newContent = lines.joined(separator: "\n")
        try? newContent.write(to: statePath, atomically: true, encoding: .utf8)
        print("[QuotaService] Applied model '\(cleanId)' to antigravity_state.pbtxt")
    }

    public func clearAntigravityModel() {
        let statePath = homeDir.appendingPathComponent(".gemini")
            .appendingPathComponent("antigravity")
            .appendingPathComponent("antigravity_state.pbtxt")

        guard FileManager.default.fileExists(atPath: statePath.path),
              let content = try? String(contentsOf: statePath, encoding: .utf8) else {
            return
        }

        var lines = content.components(separatedBy: .newlines)
        lines.removeAll(where: { $0.trimmingCharacters(in: .whitespaces).starts(with: "last_selected_agent_model:") })
        let newContent = lines.joined(separator: "\n")
        try? newContent.write(to: statePath, atomically: true, encoding: .utf8)
        print("[QuotaService] Cleared model override in antigravity_state.pbtxt")
    }

    public func getCurrentAntigravityModel() -> String {
        let raw = getRawAntigravityModelId()
        if !raw.isEmpty {
            let formatted = formatModelIdentifier(raw)
            if !formatted.isEmpty {
                return formatted
            }
        }
        return "Gemini 3.8 Flash (High)"
    }

    public func formatModelIdentifier(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "MODEL_PLACEHOLDER_M318", "gemini-3.8-flash-high":
            return "Gemini 3.8 Flash (High)"
        case "MODEL_PLACEHOLDER_M319", "gemini-3.8-flash-medium":
            return "Gemini 3.8 Flash (Medium)"
        case "MODEL_PLACEHOLDER_M320", "gemini-3.8-flash-low":
            return "Gemini 3.8 Flash (Low)"
        case "MODEL_PLACEHOLDER_M322", "gemini-3.8-flash-tiered":
            return "Gemini 3.8 Flash (Tiered)"
        case "MODEL_PLACEHOLDER_M26", "claude-opus-4-6-thinking":
            return "Claude Opus 4.6 (Thinking)"
        case "MODEL_PLACEHOLDER_M35", "claude-sonnet-4-6":
            return "Claude Sonnet 4.6 (Thinking)"
        case "MODEL_OPENAI_GPT_OSS_120B_MEDIUM", "gpt-oss-120b-medium":
            return "GPT-OSS 120B (Medium)"
        case "MODEL_PLACEHOLDER_M50", "gemini-3.1-flash-lite":
            return "Gemini 3.1 Flash Lite"
        case "MODEL_PLACEHOLDER_M21", "gemini-3.1-flash-image":
            return "Gemini 3.1 Flash Image"
        case "MODEL_TIER_FLASH", "gemini-3-flash":
            return "Gemini 3 Flash"
        case "claude-opus-5-5-high":
            return "Claude Opus 5.5 (High)"
        case "claude-opus-5-5-medium":
            return "Claude Opus 5.5 (Medium)"
        default:
            if key.isEmpty {
                return ""
            }
            return key
        }
    }

    public func resolveModelForAccount(acc: ManagedAccount, isActive: Bool) -> String? {
        // 1. If this is the active account in Antigravity:
        if isActive {
            let rawId = getRawAntigravityModelId()
            let detailPath = getAccountDetailPath(accountId: acc.id)
            if !rawId.isEmpty,
               let data = try? Data(contentsOf: detailPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let quota = json["quota"] as? [String: Any],
               let models = quota["models"] as? [[String: Any]] {
                for m in models {
                    let mId = (m["model"] as? String) ?? ""
                    let mName = (m["name"] as? String) ?? ""
                    if mId == rawId || mName == rawId {
                        if let dName = m["display_name"] as? String, !dName.isEmpty {
                            return dName
                        }
                    }
                }
            }
            return getCurrentAntigravityModel()
        }

        // 2. If this is an inactive/standby account:
        // Only return a model if this specific account has one explicitly configured or saved
        if let explicit = acc.active_model ?? acc.model, !explicit.isEmpty {
            return formatModelIdentifier(explicit)
        }
        let detailPath = getAccountDetailPath(accountId: acc.id)
        if let data = try? Data(contentsOf: detailPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let explicit = (json["active_model"] as? String) ?? (json["model"] as? String) ?? (json["last_used_model"] as? String) ?? (json["preferred_model"] as? String), !explicit.isEmpty {
                return formatModelIdentifier(explicit)
            }
        }

        // Standby accounts do not inherit the active account's model
        return nil
    }

    public func getCachedTierForAccount(acc: ManagedAccount) -> String? {
        let detailPath = getAccountDetailPath(accountId: acc.id)
        guard let data = try? Data(contentsOf: detailPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quota = json["quota"] as? [String: Any] else {
            return nil
        }
        if let tierId = quota["tier_id"] as? String, !tierId.isEmpty {
            return resolveTierDisplayName(tierId: tierId, tierName: quota["subscription_tier"] as? String)
        }
        if let tier = quota["subscription_tier"] as? String, !tier.isEmpty {
            return resolveTierDisplayName(tierId: tier, tierName: tier)
        }
        return nil
    }

    public func resolveTierFromCodeAssist(resp: LoadCodeAssistResponse?) -> (displayName: String, tierId: String?) {
        guard let resp = resp else {
            return (L10n.tr("tier.free"), nil)
        }

        // 1. Check paidTier FIRST (Matches Antigravity IDE behavior: s = iLo(r, i, a, { userTier: n.paidTier }))
        if let paidTier = resp.paidTier, let id = paidTier.id, !id.isEmpty {
            let pid = id.lowercased()
            let rawName = paidTier.name ?? paidTier.description
            if pid.contains("ultra") {
                return ("Google AI Ultra", id)
            } else if pid.contains("pro") {
                return ("Google AI Pro", id)
            } else if pid.contains("standard") || pid.contains("enterprise") {
                return ("Google Cloud / Enterprise", id)
            } else if let name = rawName, !name.isEmpty, name != "Antigravity" {
                return (name, id)
            } else {
                return (id, id)
            }
        }

        // 2. Fallback to currentTier if paidTier is not present
        if let currentTier = resp.currentTier, let id = currentTier.id, !id.isEmpty {
            let cid = id.lowercased()
            let rawName = currentTier.name ?? currentTier.description
            if cid.contains("ultra") {
                return ("Google AI Ultra", id)
            } else if cid.contains("pro") {
                return ("Google AI Pro", id)
            } else if cid.contains("free") {
                return (L10n.tr("tier.free"), id)
            } else if cid.contains("standard") || cid.contains("enterprise") {
                return ("Google Cloud / Enterprise", id)
            } else if let name = rawName, !name.isEmpty, name != "Antigravity" {
                return (name, id)
            } else {
                return (id, id)
            }
        }

        return (L10n.tr("tier.free"), "free-tier")
    }

    public func resolveTierDisplayName(tierId: String?, tierName: String?) -> String {
        guard let id = tierId?.lowercased(), !id.isEmpty else {
            if let name = tierName, !name.isEmpty, name != "Antigravity" {
                return name
            }
            return L10n.tr("tier.free")
        }

        if id.contains("ultra") {
            return "Google AI Ultra"
        } else if id.contains("pro") {
            return "Google AI Pro"
        } else if id.contains("free") {
            return L10n.tr("tier.free")
        } else if id.contains("standard") || id.contains("enterprise") {
            return "Google Cloud / Enterprise"
        } else if let name = tierName, !name.isEmpty, name != "Antigravity" {
            return name
        } else {
            return tierId ?? L10n.tr("tier.free")
        }
    }

    public func updateAccountSubscriptionTierOnDisk(accountId: String, tierName: String, tierId: String?) {
        let detailPath = getAccountDetailPath(accountId: accountId)
        guard let data = try? Data(contentsOf: detailPath),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

        var quotaDict = (json["quota"] as? [String: Any]) ?? [:]
        let currentDiskTier = quotaDict["subscription_tier"] as? String
        let currentDiskTierId = quotaDict["tier_id"] as? String

        if currentDiskTier != tierName || currentDiskTierId != tierId {
            quotaDict["subscription_tier"] = tierName
            if let tierId = tierId {
                quotaDict["tier_id"] = tierId
            }
            json["quota"] = quotaDict
            let targetAccountsDir = orbitDir.appendingPathComponent("accounts")
            try? FileManager.default.createDirectory(at: targetAccountsDir, withIntermediateDirectories: true)
            let writePath = targetAccountsDir.appendingPathComponent("\(accountId).json")
            if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
                try? updatedData.write(to: writePath, options: .atomic)
                print("[QuotaService] Updated account \(accountId) subscription_tier on disk to: \(tierName) (tier_id: \(tierId ?? "nil"))")
            }
        }
    }

    private func fetchAccountQuota(acc: ManagedAccount, activeId: String, completion: @escaping (AccountStatus) -> Void) {
        let isActive = (acc.id == activeId)
        let detailPath = getAccountDetailPath(accountId: acc.id)
        let modelName = resolveModelForAccount(acc: acc, isActive: isActive)
        let cachedTier = getCachedTierForAccount(acc: acc)

        var detailToken: AccountToken? = nil
        var accountPicture = acc.picture

        if let detailData = try? Data(contentsOf: detailPath) {
            if let detail = try? JSONDecoder().decode(AccountDetailFile.self, from: detailData) {
                detailToken = detail.token
                if accountPicture == nil {
                    accountPicture = detail.picture
                }
            } else if let dict = (try? JSONSerialization.jsonObject(with: detailData)) as? [String: Any] {
                if let tokenDict = dict["token"] as? [String: Any] {
                    detailToken = AccountToken(
                        access_token: tokenDict["access_token"] as? String,
                        refresh_token: tokenDict["refresh_token"] as? String,
                        expires_in: tokenDict["expires_in"] as? Int,
                        expiry_timestamp: tokenDict["expiry_timestamp"] as? Int,
                        email: tokenDict["email"] as? String
                    )
                }
                if accountPicture == nil {
                    accountPicture = dict["picture"] as? String
                }
            }
        }

        if let pic = accountPicture {
            _ = AvatarManager.shared.getAvatarImage(accountId: acc.id, pictureUrl: pic)
        }

        guard let token = detailToken else {
            completion(AccountStatus(
                id: acc.id,
                email: acc.email,
                name: acc.name ?? acc.email,
                isCurrent: isActive,
                remainingPercentage: -1,
                activeModel: modelName,
                subscriptionTier: cachedTier,
                preferredModelId: acc.active_model ?? acc.model,
                picture: accountPicture
            ))
            return
        }

        let now = Int(Date().timeIntervalSince1970)
        let expiry = token.expiry_timestamp ?? 0
        let currentAccessToken = token.access_token ?? ""
        let refreshToken = token.refresh_token ?? ""

        // Check if token needs proactive refresh (expired or expiring in <= 120s)
        let shouldRefresh = (expiry <= now + 120) || currentAccessToken.isEmpty

        if shouldRefresh && !refreshToken.isEmpty {
            refreshGoogleToken(accountId: acc.id, refreshToken: refreshToken, isActive: isActive) { [weak self] newToken in
                guard let self = self, let newToken = newToken else {
                    completion(AccountStatus(
                        id: acc.id,
                        email: acc.email,
                        name: acc.name ?? acc.email,
                        isCurrent: isActive,
                        remainingPercentage: -1,
                        activeModel: modelName,
                        subscriptionTier: cachedTier,
                        preferredModelId: acc.active_model ?? acc.model,
                        picture: accountPicture
                    ))
                    return
                }
                self.executeQuotaQuery(acc: acc, activeId: activeId, token: newToken, refreshToken: refreshToken, picture: accountPicture, canRetry: false, completion: completion)
            }
        } else {
            executeQuotaQuery(acc: acc, activeId: activeId, token: currentAccessToken, refreshToken: refreshToken, picture: accountPicture, canRetry: true, completion: completion)
        }
    }

    private func executeQuotaQuery(
        acc: ManagedAccount,
        activeId: String,
        token: String,
        refreshToken: String,
        picture: String?,
        canRetry: Bool,
        completion: @escaping (AccountStatus) -> Void
    ) {
        let isActive = (acc.id == activeId)
        let group = DispatchGroup()
        var quotaSummaryCode = -1
        var quotaSummaryResp: QuotaSummaryResponse?
        var codeAssistCode = -1
        var codeAssistResp: LoadCodeAssistResponse?

        // Proactively fetch avatar if missing
        if picture == nil && !token.isEmpty {
            AvatarManager.shared.fetchUserInfo(accessToken: token) { fetchedPic, _ in
                if let p = fetchedPic {
                    AccountManager.shared.updateAccountPicture(email: acc.email, picture: p)
                }
            }
        }

        group.enter()
        queryGoogleQuotaSummary(accessToken: token) { statusCode, summary in
            quotaSummaryCode = statusCode
            quotaSummaryResp = summary
            group.leave()
        }

        group.enter()
        queryGoogleCodeAssist(accessToken: token) { statusCode, codeAssist in
            codeAssistCode = statusCode
            codeAssistResp = codeAssist
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self = self else { return }

            // If 401 Unauthorized on either request and can retry, refresh token and retry once
            if (quotaSummaryCode == 401 || codeAssistCode == 401) && canRetry && !refreshToken.isEmpty {
                print("[QuotaService] Quota/CodeAssist API 401 for \(acc.email). Proactively refreshing token...")
                self.refreshGoogleToken(accountId: acc.id, refreshToken: refreshToken, isActive: isActive) { newToken in
                    guard let newToken = newToken else {
                        completion(AccountStatus(
                            id: acc.id,
                            email: acc.email,
                            name: acc.name ?? acc.email,
                            isCurrent: isActive,
                            remainingPercentage: -1,
                            activeModel: self.resolveModelForAccount(acc: acc, isActive: isActive),
                            subscriptionTier: self.getCachedTierForAccount(acc: acc),
                            preferredModelId: acc.active_model ?? acc.model,
                            picture: picture
                        ))
                        return
                    }
                    self.executeQuotaQuery(acc: acc, activeId: activeId, token: newToken, refreshToken: refreshToken, picture: picture, canRetry: false, completion: completion)
                }
                return
            }

            let modelName = self.resolveModelForAccount(acc: acc, isActive: isActive)

            // Resolve dynamic tier from Google Code Assist API (prioritizing paidTier over currentTier)
            var tierDisplayName: String = ""
            var resolvedTierId: String? = nil

            if codeAssistResp != nil {
                let resolved = self.resolveTierFromCodeAssist(resp: codeAssistResp)
                tierDisplayName = resolved.displayName
                resolvedTierId = resolved.tierId
            } else if let cached = self.getCachedTierForAccount(acc: acc), !cached.isEmpty {
                tierDisplayName = cached
            } else {
                tierDisplayName = L10n.tr("tier.free")
            }

            // Persist resolved tier to disk
            self.updateAccountSubscriptionTierOnDisk(accountId: acc.id, tierName: tierDisplayName, tierId: resolvedTierId)

            var status = AccountStatus(
                id: acc.id,
                email: acc.email,
                name: acc.name ?? acc.email,
                isCurrent: isActive,
                remainingPercentage: (quotaSummaryResp == nil ? -1 : 100),
                activeModel: modelName,
                subscriptionTier: tierDisplayName,
                tierId: resolvedTierId,
                preferredModelId: acc.active_model ?? acc.model,
                picture: picture
            )

            if let summary = quotaSummaryResp, let groups = summary.groups {
                var minFraction = 1.0
                for g in groups {
                    let isGemini = (g.displayName ?? "").lowercased().contains("gemini")
                    for b in (g.buckets ?? []) {
                        guard let frac = b.remainingFraction else { continue }
                        let pct = Int(round(frac * 100))
                        let window = (b.window ?? b.bucketId ?? "").lowercased()
                        if isGemini {
                            minFraction = min(minFraction, frac)
                            if window.contains("5h") || window.contains("5-hour") || window.contains("5 hour") {
                                status.gemini5hPercentage = pct
                                status.geminiResetTime = b.resetTime
                            } else if window.contains("week") || window.contains("7d") || window.contains("1w") {
                                status.geminiWeeklyPercentage = pct
                                status.geminiWeeklyResetTime = b.resetTime
                            }
                        } else {
                            if window.contains("5h") || window.contains("5-hour") || window.contains("5 hour") {
                                status.other5hPercentage = pct
                            } else if window.contains("week") || window.contains("7d") || window.contains("1w") {
                                status.otherWeeklyPercentage = pct
                            }
                        }
                    }
                }
                if let g5h = status.gemini5hPercentage {
                    status.remainingPercentage = g5h
                } else {
                    status.remainingPercentage = Int(round(minFraction * 100))
                }
                status.lastUpdated = Date()
            }

            completion(status)
        }
    }

    private func queryGoogleQuotaSummary(accessToken: String, completion: @escaping (Int, QuotaSummaryResponse?) -> Void) {
        var request = URLRequest(url: googleQuotaUrl)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 8.0
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let data = data, error == nil else {
                completion(statusCode, nil)
                return
            }
            let summary = try? JSONDecoder().decode(QuotaSummaryResponse.self, from: data)
            completion(statusCode, summary)
        }
        task.resume()
    }

    private func queryGoogleCodeAssist(accessToken: String, completion: @escaping (Int, LoadCodeAssistResponse?) -> Void) {
        var request = URLRequest(url: googleCodeAssistUrl)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 8.0
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let data = data, error == nil else {
                completion(statusCode, nil)
                return
            }
            let resp = try? JSONDecoder().decode(LoadCodeAssistResponse.self, from: data)
            completion(statusCode, resp)
        }
        task.resume()
    }

    public func refreshGoogleToken(accountId: String, refreshToken: String, isActive: Bool, completion: @escaping (String?) -> Void) {
        guard let tokenUrl = URL(string: "https://oauth2.googleapis.com/token") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        let params = [
            "client_id": OAuthServer.clientId,
            "client_secret": OAuthServer.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        let bodyString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = Data(bodyString.utf8)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String else {
                print("[QuotaService] Failed to refresh token for account \(accountId): \(error?.localizedDescription ?? "unknown")")
                completion(nil)
                return
            }

            let expiresIn = json["expires_in"] as? Int ?? 3599
            let idToken = json["id_token"] as? String
            let now = Int(Date().timeIntervalSince1970)
            let expiry = now + expiresIn

            // Update account detail JSON file
            let targetAccountsDir = self.orbitDir.appendingPathComponent("accounts")
            try? FileManager.default.createDirectory(at: targetAccountsDir, withIntermediateDirectories: true)
            let detailPath = self.getAccountDetailPath(accountId: accountId)
            let writePath = targetAccountsDir.appendingPathComponent("\(accountId).json")

            if let detailData = try? Data(contentsOf: detailPath),
               var detailDict = (try? JSONSerialization.jsonObject(with: detailData)) as? [String: Any],
               var tokenDict = detailDict["token"] as? [String: Any] {
                tokenDict["access_token"] = newAccessToken
                tokenDict["expires_in"] = expiresIn
                tokenDict["expiry_timestamp"] = expiry
                if let idToken = idToken {
                    tokenDict["id_token"] = idToken
                }
                detailDict["token"] = tokenDict

                if let updatedData = try? JSONSerialization.data(withJSONObject: detailDict, options: .prettyPrinted) {
                    try? updatedData.write(to: writePath, options: .atomic)
                    print("[QuotaService] Successfully refreshed token for account \(accountId) (expires in \(expiresIn)s)")
                }
            }

            // If active account, sync to IDE, agy CLI, and App
            if isActive {
                print("[QuotaService] Syncing refreshed token to active targets for account \(accountId)...")
                AccountRotator.shared.switchToAccount(id: accountId) { _ in }
            }

            completion(newAccessToken)
        }
        task.resume()
    }
}
