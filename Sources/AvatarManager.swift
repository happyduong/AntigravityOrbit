import Foundation
import Cocoa
import SwiftUI

public class AvatarManager {
    public static let shared = AvatarManager()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let avatarsDir: URL

    private var activeDownloads = Set<String>()
    private let downloadLock = NSLock()

    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        avatarsDir = home.appendingPathComponent(".antigravity_orbit/avatars", isDirectory: true)
        try? fileManager.createDirectory(at: avatarsDir, withIntermediateDirectories: true)
    }

    /// Returns the cached avatar image from memory or local disk cache.
    /// If not yet cached and pictureUrl is provided, triggers a background fetch.
    public func getAvatarImage(accountId: String, pictureUrl: String?) -> NSImage? {
        let key = accountId as NSString
        if let mem = memoryCache.object(forKey: key) {
            return mem
        }

        let diskFile = avatarsDir.appendingPathComponent("\(accountId).png")
        if fileManager.fileExists(atPath: diskFile.path),
           let img = NSImage(contentsOf: diskFile) {
            memoryCache.setObject(img, forKey: key)
            return img
        }

        // Trigger background download if pictureUrl exists
        if let urlStr = pictureUrl, !urlStr.isEmpty {
            fetchAndCacheAvatar(accountId: accountId, pictureUrl: urlStr)
        }

        return nil
    }

    /// Downloads the avatar image from Google URL, saves to disk and memory cache.
    public func fetchAndCacheAvatar(accountId: String, pictureUrl: String, completion: (() -> Void)? = nil) {
        guard let url = URL(string: pictureUrl) else { return }

        downloadLock.lock()
        if activeDownloads.contains(accountId) {
            downloadLock.unlock()
            return
        }
        activeDownloads.insert(accountId)
        downloadLock.unlock()

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            self.downloadLock.lock()
            self.activeDownloads.remove(accountId)
            self.downloadLock.unlock()

            guard let data = data, error == nil, let img = NSImage(data: data) else { return }

            // Save to memory cache
            self.memoryCache.setObject(img, forKey: accountId as NSString)

            // Save to disk cache
            let diskFile = self.avatarsDir.appendingPathComponent("\(accountId).png")
            try? data.write(to: diskFile, options: .atomic)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .avatarDidChange, object: accountId)
                completion?()
            }
        }.resume()
    }

    /// Fetches Google UserInfo using an active access token to retrieve profile picture and name.
    public func fetchUserInfo(accessToken: String, completion: @escaping (_ picture: String?, _ name: String?) -> Void) {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else {
            completion(nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 4.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil, nil)
                return
            }

            let picture = json["picture"] as? String
            let name = json["name"] as? String
            completion(picture, name)
        }.resume()
    }
}

extension Notification.Name {
    public static let avatarDidChange = Notification.Name("AntigravityOrbitAvatarDidChange")
}

// MARK: - SwiftUI Account Avatar View
public struct AccountAvatarView: View {
    public let accountId: String
    public let pictureUrl: String?
    public let displayName: String
    public let isCurrent: Bool
    public let size: CGFloat

    public init(
        accountId: String,
        pictureUrl: String?,
        displayName: String,
        isCurrent: Bool = false,
        size: CGFloat = 28
    ) {
        self.accountId = accountId
        self.pictureUrl = pictureUrl
        self.displayName = displayName
        self.isCurrent = isCurrent
        self.size = size
    }

    public var body: some View {
        if let img = AvatarManager.shared.getAvatarImage(accountId: accountId, pictureUrl: pictureUrl) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isCurrent ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.2), lineWidth: 1)
                )
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isCurrent ? [Color.blue, Color.indigo] : [Color.gray.opacity(0.6), Color.gray.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                Text(avatarLetter)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    private var avatarLetter: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "A"
    }
}
