import Foundation

public class AccountManager {
    public static let shared = AccountManager()

    private let homeDir: URL
    private let orbitDir: URL
    private let accountsFile: URL
    private let accountsDir: URL
    private let geminiDir: URL

    private init() {
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.orbitDir = homeDir.appendingPathComponent(".antigravity_orbit")
        self.accountsFile = orbitDir.appendingPathComponent("accounts.json")
        self.accountsDir = orbitDir.appendingPathComponent("accounts")
        self.geminiDir = homeDir.appendingPathComponent(".gemini")

        try? FileManager.default.createDirectory(at: orbitDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: accountsDir, withIntermediateDirectories: true)

        ensureAccountsFileExists()
    }

    public func getOrCreateAccountsFile() -> AccountsFile {
        if let existing = QuotaService.shared.loadAccountsFile() {
            return existing
        }
        let empty = AccountsFile(
            version: "2.0",
            accounts: [],
            current_account_id: nil,
            current_target_ide: "antigravity",
            current_classic_account_id: nil,
            current_ide_account_id: nil,
            current_agy_account_id: nil
        )
        _ = saveAccountsFile(empty)
        return empty
    }

    private func ensureAccountsFileExists() {
        if !FileManager.default.fileExists(atPath: accountsFile.path) {
            _ = getOrCreateAccountsFile()
        }
    }

    // MARK: - 1. Import from Antigravity IDE
    public func importFromCurrentIdeLogin() -> (success: Bool, message: String) {
        let googleAccsPath = geminiDir.appendingPathComponent("google_accounts.json")
        let oauthCredsPath = geminiDir.appendingPathComponent("oauth_creds.json")

        guard FileManager.default.fileExists(atPath: googleAccsPath.path),
              FileManager.default.fileExists(atPath: oauthCredsPath.path) else {
            return (false, "Không tìm thấy thông tin đăng nhập trong ~/.gemini.")
        }

        guard let accsData = try? Data(contentsOf: googleAccsPath),
              let accsJson = try? JSONSerialization.jsonObject(with: accsData) as? [String: Any],
              let activeEmail = accsJson["active"] as? String, !activeEmail.isEmpty else {
            return (false, "Không đọc được email đang đăng nhập trong Antigravity.")
        }

        guard let credsData = try? Data(contentsOf: oauthCredsPath),
              let credsJson = try? JSONSerialization.jsonObject(with: credsData) as? [String: Any] else {
            return (false, "Không đọc được token đăng nhập từ oauth_creds.json.")
        }

        // Check if account already exists
        let accountsFileModel = getOrCreateAccountsFile()

        if let existing = accountsFileModel.accounts.first(where: { $0.email.lowercased() == activeEmail.lowercased() }) {
            return (false, "Tài khoản [\(activeEmail)] đã tồn tại trong danh sách xoay vòng (ID: \(existing.id)).")
        }

        let newId = UUID().uuidString.lowercased()
        let name = activeEmail.components(separatedBy: "@").first ?? activeEmail
        let now = Int(Date().timeIntervalSince1970)
        let rawExpiry = credsJson["expiry_date"] as? Int ?? (now + 3600)
        let expirySec = (rawExpiry > 100_000_000_000) ? (rawExpiry / 1000) : rawExpiry

        // Create detail account object
        let tokenObj: [String: Any] = [
            "access_token": credsJson["access_token"] as? String ?? "",
            "refresh_token": credsJson["refresh_token"] as? String ?? "",
            "expires_in": 3599,
            "expiry_timestamp": expirySec,
            "token_type": credsJson["token_type"] as? String ?? "Bearer",
            "email": activeEmail,
            "project_id": "",
            "oauth_client_key": "",
            "is_gcp_tos": false,
            "id_token": credsJson["id_token"] as? String ?? ""
        ]

        let accountDetail: [String: Any] = [
            "id": newId,
            "email": activeEmail,
            "name": name,
            "priority": 50,
            "token": tokenObj,
            "device_profile": [
                "profile": "custom",
                "machine_id": UUID().uuidString.lowercased(),
                "mac_machine_id": UUID().uuidString.lowercased(),
                "dev_device_id": UUID().uuidString.lowercased(),
                "sqm_id": ""
            ],
            "quota": [
                "models": [],
                "last_updated": ISO8601DateFormatter().string(from: Date()),
                "is_forbidden": false,
                "subscription_tier": "Free"
            ],
            "disabled": false,
            "proxy_disabled": false,
            "validation_blocked": false,
            "created_at": now,
            "last_used": now
        ]

        // Save account file
        do {
            try FileManager.default.createDirectory(at: accountsDir, withIntermediateDirectories: true)
            let detailFileUrl = accountsDir.appendingPathComponent("\(newId).json")
            let detailData = try JSONSerialization.data(withJSONObject: accountDetail, options: .prettyPrinted)
            try detailData.write(to: detailFileUrl, options: .atomic)
        } catch {
            return (false, "Lỗi ghi tệp tài khoản chi tiết: \(error.localizedDescription)")
        }

        // Update accounts.json
        let newManagedAccount = ManagedAccount(
            id: newId,
            email: activeEmail,
            name: name,
            disabled: false,
            proxy_disabled: false,
            created_at: now,
            last_used: now
        )

        var updatedAccounts = accountsFileModel.accounts
        updatedAccounts.append(newManagedAccount)

        let activeId = accountsFileModel.current_account_id ?? newId
        let activeIdeId = accountsFileModel.current_ide_account_id ?? newId
        let activeClassicId = accountsFileModel.current_classic_account_id ?? newId
        let activeAgyId = accountsFileModel.current_agy_account_id ?? newId

        let updatedAccountsFile = AccountsFile(
            version: accountsFileModel.version ?? "2.0",
            accounts: updatedAccounts,
            current_account_id: activeId,
            current_target_ide: accountsFileModel.current_target_ide ?? "antigravity",
            current_classic_account_id: activeClassicId,
            current_ide_account_id: activeIdeId,
            current_agy_account_id: activeAgyId
        )

        if saveAccountsFile(updatedAccountsFile) {
            return (true, "Đã thêm tài khoản [\(activeEmail)] vào danh sách xoay vòng thành công!")
        } else {
            return (false, "Lỗi cập nhật tệp accounts.json.")
        }
    }

    // MARK: - 2. Import from JSON File
    public func importFromJsonFile(url: URL) -> (success: Bool, message: String) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return (false, "Tệp không đúng định dạng JSON hợp lệ.")
        }

        var importedCount = 0

        // Case A: Export array format {"accounts": [...]} or [...]
        var accountEntries: [[String: Any]] = []
        if let dict = json as? [String: Any], let accs = dict["accounts"] as? [[String: Any]] {
            accountEntries = accs
        } else if let arr = json as? [[String: Any]] {
            accountEntries = arr
        } else if let single = json as? [String: Any], single["email"] != nil {
            accountEntries = [single]
        }

        guard !accountEntries.isEmpty else {
            return (false, "Không tìm thấy dữ liệu tài khoản trong tệp JSON.")
        }

        let accountsFileModel = getOrCreateAccountsFile()

        var updatedAccounts = accountsFileModel.accounts
        let now = Int(Date().timeIntervalSince1970)

        for entry in accountEntries {
            guard let email = entry["email"] as? String, !email.isEmpty else { continue }

            // Skip if email exists
            if updatedAccounts.contains(where: { $0.email.lowercased() == email.lowercased() }) {
                continue
            }

            let id = entry["id"] as? String ?? UUID().uuidString.lowercased()
            let name = entry["name"] as? String ?? email.components(separatedBy: "@").first ?? email

            // Save individual file
            let detailFileUrl = accountsDir.appendingPathComponent("\(id).json")
            if let entryData = try? JSONSerialization.data(withJSONObject: entry, options: .prettyPrinted) {
                try? entryData.write(to: detailFileUrl, options: .atomic)
            }

            let managed = ManagedAccount(
                id: id,
                email: email,
                name: name,
                disabled: entry["disabled"] as? Bool ?? false,
                proxy_disabled: entry["proxy_disabled"] as? Bool ?? false,
                created_at: now,
                last_used: now
            )
            updatedAccounts.append(managed)
            importedCount += 1
        }

        guard importedCount > 0 else {
            return (false, "Tất cả các tài khoản trong tệp đã tồn tại trong danh sách.")
        }

        let firstId = updatedAccounts.first?.id
        let activeId = accountsFileModel.current_account_id ?? firstId
        let activeIdeId = accountsFileModel.current_ide_account_id ?? firstId
        let activeClassicId = accountsFileModel.current_classic_account_id ?? firstId
        let activeAgyId = accountsFileModel.current_agy_account_id ?? firstId

        let updatedAccountsFile = AccountsFile(
            version: accountsFileModel.version ?? "2.0",
            accounts: updatedAccounts,
            current_account_id: activeId,
            current_target_ide: accountsFileModel.current_target_ide ?? "antigravity",
            current_classic_account_id: activeClassicId,
            current_ide_account_id: activeIdeId,
            current_agy_account_id: activeAgyId
        )

        if saveAccountsFile(updatedAccountsFile) {
            return (true, "Đã nhập thành công \(importedCount) tài khoản mới!")
        } else {
            return (false, "Lỗi cập nhật tệp accounts.json.")
        }
    }

    // MARK: - 3. Add Account via Web Browser OAuth
    public func addOAuthAccount(email: String, name: String, accessToken: String, refreshToken: String, idToken: String) -> (success: Bool, message: String) {
        guard !email.isEmpty else {
            return (false, "Email không hợp lệ.")
        }

        var accountsFileModel = getOrCreateAccountsFile()

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        let now = Int(Date().timeIntervalSince1970)

        // If account already exists, update its tokens
        if let existing = accountsFileModel.accounts.first(where: { $0.email.lowercased() == trimmedEmail }) {
            let detailFileUrl = accountsDir.appendingPathComponent("\(existing.id).json")
            if var detailJson = (try? Data(contentsOf: detailFileUrl)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) {
                var tokenObj = detailJson["token"] as? [String: Any] ?? [:]
                tokenObj["access_token"] = accessToken
                if !refreshToken.isEmpty {
                    tokenObj["refresh_token"] = refreshToken
                }
                tokenObj["id_token"] = idToken
                tokenObj["expiry_timestamp"] = now + 3600
                detailJson["token"] = tokenObj
                detailJson["disabled"] = false
                detailJson["last_used"] = now
                if let updatedData = try? JSONSerialization.data(withJSONObject: detailJson, options: .prettyPrinted) {
                    try? updatedData.write(to: detailFileUrl, options: .atomic)
                }
            }
            return (true, "Đã làm mới token cho tài khoản [\(trimmedEmail)] thành công!")
        }

        // Add new account
        let newId = UUID().uuidString.lowercased()
        let displayName = name.isEmpty ? (trimmedEmail.components(separatedBy: "@").first ?? trimmedEmail) : name

        let tokenObj: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "expires_in": 3599,
            "expiry_timestamp": now + 3600,
            "token_type": "Bearer",
            "email": trimmedEmail,
            "project_id": "",
            "oauth_client_key": "antigravity_enterprise",
            "is_gcp_tos": false,
            "id_token": idToken
        ]

        let accountDetail: [String: Any] = [
            "id": newId,
            "email": trimmedEmail,
            "name": displayName,
            "priority": 50,
            "token": tokenObj,
            "device_profile": [
                "profile": "custom",
                "machine_id": UUID().uuidString.lowercased(),
                "mac_machine_id": UUID().uuidString.lowercased(),
                "dev_device_id": UUID().uuidString.lowercased(),
                "sqm_id": ""
            ],
            "quota": [
                "models": [],
                "last_updated": ISO8601DateFormatter().string(from: Date()),
                "is_forbidden": false,
                "subscription_tier": "Free"
            ],
            "disabled": false,
            "proxy_disabled": false,
            "validation_blocked": false,
            "created_at": now,
            "last_used": now
        ]

        let detailFileUrl = accountsDir.appendingPathComponent("\(newId).json")
        if let detailData = try? JSONSerialization.data(withJSONObject: accountDetail, options: .prettyPrinted) {
            try? detailData.write(to: detailFileUrl, options: .atomic)
        }

        let newManagedAccount = ManagedAccount(
            id: newId,
            email: trimmedEmail,
            name: displayName,
            disabled: false,
            proxy_disabled: false,
            created_at: now,
            last_used: now
        )

        accountsFileModel.accounts.append(newManagedAccount)
        if accountsFileModel.current_account_id == nil || accountsFileModel.current_account_id?.isEmpty == true {
            accountsFileModel.current_account_id = newId
            accountsFileModel.current_ide_account_id = newId
            accountsFileModel.current_classic_account_id = newId
            accountsFileModel.current_agy_account_id = newId
        }

        if saveAccountsFile(accountsFileModel) {
            return (true, "Đã thêm tài khoản [\(trimmedEmail)] vào danh sách xoay vòng thành công!")
        } else {
            return (false, "Lỗi cập nhật tệp accounts.json.")
        }
    }

    // MARK: - 3. Add Manual Account
    public func addManualAccount(email: String, name: String, accessToken: String, refreshToken: String) -> (success: Bool, message: String) {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (false, "Email không được để trống.")
        }
        guard !accessToken.trimmingCharacters(in: .whitespaces).isEmpty || !refreshToken.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (false, "Vui lòng nhập Access Token hoặc Refresh Token.")
        }

        let accountsFileModel = getOrCreateAccountsFile()

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        if accountsFileModel.accounts.contains(where: { $0.email.lowercased() == trimmedEmail }) {
            return (false, "Tài khoản [\(trimmedEmail)] đã tồn tại.")
        }

        let newId = UUID().uuidString.lowercased()
        let displayName = name.isEmpty ? (trimmedEmail.components(separatedBy: "@").first ?? trimmedEmail) : name
        let now = Int(Date().timeIntervalSince1970)

        let tokenObj: [String: Any] = [
            "access_token": accessToken.trimmingCharacters(in: .whitespaces),
            "refresh_token": refreshToken.trimmingCharacters(in: .whitespaces),
            "expires_in": 3599,
            "expiry_timestamp": now + 3600,
            "token_type": "Bearer",
            "email": trimmedEmail,
            "project_id": "",
            "oauth_client_key": "",
            "is_gcp_tos": false,
            "id_token": ""
        ]

        let accountDetail: [String: Any] = [
            "id": newId,
            "email": trimmedEmail,
            "name": displayName,
            "priority": 50,
            "token": tokenObj,
            "device_profile": [
                "profile": "custom",
                "machine_id": UUID().uuidString.lowercased(),
                "mac_machine_id": UUID().uuidString.lowercased(),
                "dev_device_id": UUID().uuidString.lowercased(),
                "sqm_id": ""
            ],
            "quota": [
                "models": [],
                "last_updated": ISO8601DateFormatter().string(from: Date()),
                "is_forbidden": false,
                "subscription_tier": "Free"
            ],
            "disabled": false,
            "proxy_disabled": false,
            "validation_blocked": false,
            "created_at": now,
            "last_used": now
        ]

        let detailFileUrl = accountsDir.appendingPathComponent("\(newId).json")
        if let detailData = try? JSONSerialization.data(withJSONObject: accountDetail, options: .prettyPrinted) {
            try? detailData.write(to: detailFileUrl, options: .atomic)
        }

        let newManagedAccount = ManagedAccount(
            id: newId,
            email: trimmedEmail,
            name: displayName,
            disabled: false,
            proxy_disabled: false,
            created_at: now,
            last_used: now
        )

        var updatedAccounts = accountsFileModel.accounts
        updatedAccounts.append(newManagedAccount)

        let activeId = accountsFileModel.current_account_id ?? newId
        let activeIdeId = accountsFileModel.current_ide_account_id ?? newId
        let activeClassicId = accountsFileModel.current_classic_account_id ?? newId
        let activeAgyId = accountsFileModel.current_agy_account_id ?? newId

        let updatedAccountsFile = AccountsFile(
            version: accountsFileModel.version ?? "2.0",
            accounts: updatedAccounts,
            current_account_id: activeId,
            current_target_ide: accountsFileModel.current_target_ide ?? "antigravity",
            current_classic_account_id: activeClassicId,
            current_ide_account_id: activeIdeId,
            current_agy_account_id: activeAgyId
        )

        if saveAccountsFile(updatedAccountsFile) {
            return (true, "Đã thêm tài khoản [\(trimmedEmail)] thành công!")
        } else {
            return (false, "Lỗi cập nhật tệp accounts.json.")
        }
    }

    // MARK: - 4. Delete Account
    public func deleteAccount(id: String) -> (success: Bool, message: String) {
        var accountsFileModel = getOrCreateAccountsFile()

        let activeId = accountsFileModel.current_ide_account_id ?? accountsFileModel.current_account_id ?? ""
        if id == activeId {
            return (false, "Không thể xóa tài khoản đang kích hoạt trên Antigravity IDE. Vui lòng chuyển sang tài khoản khác trước khi xóa.")
        }

        guard let targetIndex = accountsFileModel.accounts.firstIndex(where: { $0.id == id }) else {
            return (false, "Không tìm thấy tài khoản cần xóa.")
        }

        let deletedEmail = accountsFileModel.accounts[targetIndex].email
        accountsFileModel.accounts.remove(at: targetIndex)

        // Remove detail JSON file
        let detailFileUrl = accountsDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: detailFileUrl)

        if saveAccountsFile(accountsFileModel) {
            return (true, "Đã xóa tài khoản [\(deletedEmail)] thành công.")
        } else {
            return (false, "Lỗi cập nhật tệp accounts.json.")
        }
    }

    private func saveAccountsFile(_ model: AccountsFile) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(model)
            try data.write(to: accountsFile, options: .atomic)
            return true
        } catch {
            print("[AccountManager] Save accounts.json error: \(error)")
            return false
        }
    }
}
