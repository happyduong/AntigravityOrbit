import Foundation

public class AccountRotator {
    public static let shared = AccountRotator()

    private let homeDir: URL
    private let orbitDir: URL
    private let accountsFile: URL

    private init() {
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.orbitDir = homeDir.appendingPathComponent(".antigravity_orbit")
        self.accountsFile = orbitDir.appendingPathComponent("accounts.json")
    }

    public func findExecutablePath() -> String {
        let candidates = [
            homeDir.appendingPathComponent(".local/bin/antigravity-orbit").path,
            "/usr/local/bin/antigravity-orbit",
            "/Applications/Antigravity Orbit.app/Contents/MacOS/antigravity-orbit"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return candidates[0]
    }

    public func rotateToNext(currentStatuses: [AccountStatus], reason: String, completion: @escaping (Bool, AccountStatus?) -> Void) {
        guard let accountsFile = QuotaService.shared.loadAccountsFile(), !accountsFile.accounts.isEmpty else {
            completion(false, nil)
            return
        }

        let activeId = accountsFile.current_classic_account_id ?? accountsFile.current_ide_account_id ?? accountsFile.current_account_id ?? ""
        let accounts = accountsFile.accounts.filter { $0.disabled != true }
        guard accounts.count > 1 else {
            print("[AccountRotator] Only 1 account available, cannot rotate.")
            completion(false, nil)
            return
        }

        // Find current index
        let currentIndex = accounts.firstIndex(where: { $0.id == activeId }) ?? 0
        let currentAccount = accounts[currentIndex]

        // Candidate accounts in round-robin order
        var bestCandidate: ManagedAccount? = nil
        var bestStatus: AccountStatus? = nil
        let threshold = ConfigManager.shared.config.thresholdPercentage

        for offset in 1..<accounts.count {
            let nextIndex = (currentIndex + offset) % accounts.count
            let candidate = accounts[nextIndex]
            let candidateStatus = currentStatuses.first(where: { $0.id == candidate.id })

            let remainingPct = candidateStatus?.remainingPercentage ?? 100
            if remainingPct > threshold {
                bestCandidate = candidate
                bestStatus = candidateStatus
                break
            }
        }

        // If all accounts are under threshold, pick the one with highest quota
        if bestCandidate == nil {
            let sortedCandidates = accounts.filter({ $0.id != activeId }).sorted { (a, b) -> Bool in
                let pctA = currentStatuses.first(where: { $0.id == a.id })?.remainingPercentage ?? 0
                let pctB = currentStatuses.first(where: { $0.id == b.id })?.remainingPercentage ?? 0
                return pctA > pctB
            }
            bestCandidate = sortedCandidates.first
            if let chosen = bestCandidate {
                bestStatus = currentStatuses.first(where: { $0.id == chosen.id })
            }
        }

        guard let target = bestCandidate else {
            print("[AccountRotator] No valid rotation target found.")
            completion(false, nil)
            return
        }

        executeSwitch(toAccountId: target.id) { success in
            if success {
                let showAlias = ConfigManager.shared.config.showAccountAlias
                let oldDisplay = currentAccount.displayName(showAlias: showAlias)
                let newDisplay = target.displayName(showAlias: showAlias)
                let newPct = bestStatus?.remainingPercentage ?? 100
                NotificationManager.shared.sendRotationNotification(
                    oldAccount: oldDisplay,
                    newAccount: newDisplay,
                    newQuota: newPct,
                    reason: reason
                )
                completion(true, bestStatus)
            } else {
                completion(false, nil)
            }
        }
    }

    public func switchToAccount(id: String, completion: @escaping (Bool) -> Void) {
        executeSwitch(toAccountId: id) { success in
            completion(success)
        }
    }

    private func executeSwitch(toAccountId accountId: String, completion: @escaping (Bool) -> Void) {
        let binPath = findExecutablePath()
        DispatchQueue.global(qos: .userInitiated).async {
            var cliSuccess = false
            if FileManager.default.isExecutableFile(atPath: binPath) {
                let classicSuccess = self.runSwitchCommand(binPath: binPath, accountId: accountId, target: "classic")
                let ideSuccess = self.runSwitchCommand(binPath: binPath, accountId: accountId, target: "ide")
                let agySuccess = self.runSwitchCommand(binPath: binPath, accountId: accountId, target: "agy")
                cliSuccess = (classicSuccess || ideSuccess || agySuccess)
            }

            // Always execute native direct synchronization for .antigravity_orbit targets
            let nativeSuccess = self.executeNativeSwitch(accountId: accountId)

            DispatchQueue.main.async {
                completion(cliSuccess || nativeSuccess)
            }
        }
    }

    private func executeNativeSwitch(accountId: String) -> Bool {
        guard var accountsFileModel = QuotaService.shared.loadAccountsFile() else { return false }
        guard let targetAccount = accountsFileModel.accounts.first(where: { $0.id == accountId }) else { return false }

        let targetEmail = targetAccount.email
        let detailPath = orbitDir.appendingPathComponent("accounts").appendingPathComponent("\(accountId).json")
        guard let data = try? Data(contentsOf: detailPath),
              var detailJson = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }

        let token = detailJson["token"] as? [String: Any] ?? [:]
        let accessToken = token["access_token"] as? String ?? ""
        let refreshToken = token["refresh_token"] as? String ?? ""
        let idToken = token["id_token"] as? String ?? ""
        let tokenType = token["token_type"] as? String ?? "Bearer"
        let expiry = token["expiry_timestamp"] as? Int ?? (Int(Date().timeIntervalSince1970) + 3600)
        let now = Int(Date().timeIntervalSince1970)

        // 1. Update accounts.json in .antigravity_orbit
        accountsFileModel.current_ide_account_id = accountId
        accountsFileModel.current_agy_account_id = accountId
        accountsFileModel.current_account_id = accountId
        accountsFileModel.current_classic_account_id = accountId
        for i in 0..<accountsFileModel.accounts.count {
            if accountsFileModel.accounts[i].id == accountId {
                let acc = accountsFileModel.accounts[i]
                accountsFileModel.accounts[i] = ManagedAccount(
                    id: acc.id,
                    email: acc.email,
                    name: acc.name,
                    disabled: acc.disabled,
                    proxy_disabled: acc.proxy_disabled,
                    created_at: acc.created_at,
                    last_used: now,
                    model: acc.model,
                    active_model: acc.active_model
                )
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let encData = try? encoder.encode(accountsFileModel) {
            try? encData.write(to: accountsFile, options: .atomic)
        }

        // 2. Update account detail JSON last_used
        detailJson["last_used"] = now
        if let updatedDetail = try? JSONSerialization.data(withJSONObject: detailJson, options: .prettyPrinted) {
            try? updatedDetail.write(to: detailPath, options: .atomic)
        }

        // 3. Update ~/.gemini credentials for classic app and CLI
        let geminiDir = homeDir.appendingPathComponent(".gemini")
        try? FileManager.default.createDirectory(at: geminiDir, withIntermediateDirectories: true)

        let googleAccountsPath = geminiDir.appendingPathComponent("google_accounts.json")
        let googleAccountsDict: [String: Any] = ["active": targetEmail, "old": []]
        if let gaData = try? JSONSerialization.data(withJSONObject: googleAccountsDict, options: .prettyPrinted) {
            try? gaData.write(to: googleAccountsPath, options: .atomic)
        }

        let oauthCredsPath = geminiDir.appendingPathComponent("oauth_creds.json")
        let credsDict: [String: Any] = [
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "token_type": tokenType,
            "expiry_date": expiry < 10000000000 ? (expiry * 1000) : expiry,
            "id_token": idToken,
            "scope": "openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/cde"
        ]
        if let credsData = try? JSONSerialization.data(withJSONObject: credsDict, options: .prettyPrinted) {
            try? credsData.write(to: oauthCredsPath, options: .atomic)
        }

        // 4. Update Keychain for Go CLI & agy
        let formatter = ISO8601DateFormatter()
        let expiryString = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(expiry)))
        let keyringPayload: [String: Any] = [
            "token": [
                "access_token": accessToken,
                "token_type": tokenType,
                "refresh_token": refreshToken,
                "expiry": expiryString,
                "expires_in": 3599
            ],
            "auth_method": "consumer",
            "id_token_email": targetEmail,
            "writer_id": "NvKBhN12_VheJ5FGOlmYSg"
        ]
        if let keyringData = try? JSONSerialization.data(withJSONObject: keyringPayload) {
            let b64Keyring = keyringData.base64EncodedString()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            proc.arguments = [
                "add-generic-password", "-U",
                "-s", "gemini",
                "-a", "antigravity",
                "-w", "go-keyring-base64:\(b64Keyring)"
            ]
            try? proc.run()
            proc.waitUntilExit()
        }

        print("[AccountRotator] Native switch to account [\(targetEmail)] successful.")
        return true
    }

    private func runSwitchCommand(binPath: String, accountId: String, target: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: binPath) else {
            print("[AccountRotator] Executable not found or not executable at \(binPath)")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = ["switch", accountId, "--target", target]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if process.terminationStatus == 0 {
                print("[AccountRotator] Switch target '\(target)' success: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                return true
            } else {
                print("[AccountRotator] Switch target '\(target)' failed (code \(process.terminationStatus)): \(output)")
                return false
            }
        } catch {
            print("[AccountRotator] Error running switch command for target \(target): \(error)")
            return false
        }
    }
}
