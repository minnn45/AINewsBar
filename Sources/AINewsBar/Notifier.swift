import Foundation
import AppKit
import UserNotifications

/// Posts a macOS notification for each new Big news story. Clicking it opens the article.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private let notifiedKey = "notifiedBigNews"
    private let seededKey = "didSeedBigNews"

    /// Links we've already announced (or that existed before notifications were set up).
    private var notified: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(500)), forKey: notifiedKey) }
    }

    func start() {
        center.delegate = self
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        await center.notificationSettings().authorizationStatus == .authorized
    }

    /// Announce Big news stories that haven't been announced yet.
    /// - Parameter text: returns the (possibly translated) title and summary to show.
    func announce(_ big: [Article], text: (Article) -> (title: String, body: String), ko: Bool) async {
        // First run: treat what's already on screen as seen, so we don't fire a burst of old stories.
        if !UserDefaults.standard.bool(forKey: seededKey) {
            UserDefaults.standard.set(true, forKey: seededKey)
            notified.formUnion(big.map(\.link))
            return
        }

        let fresh = big.filter { !notified.contains($0.link) }
        guard !fresh.isEmpty, await isAuthorized() else { return }
        notified.formUnion(fresh.map(\.link))

        if fresh.count <= 3 {
            for a in fresh {
                let t = text(a)
                let content = UNMutableNotificationContent()
                content.title = "★ " + t.title
                content.subtitle = (a.source?.name ?? "") + (a.source?.official == true ? (ko ? " · 공식" : " · Official") : "")
                content.body = t.body
                content.sound = .default
                content.userInfo = ["link": a.link]
                content.threadIdentifier = "big-news"
                try? await center.add(UNNotificationRequest(identifier: a.link, content: content, trigger: nil))
            }
        } else {
            // Several at once (e.g. after the Mac was asleep): one summary notification instead of a flood.
            let content = UNMutableNotificationContent()
            content.title = ko ? "★ 주요 AI 뉴스 \(fresh.count)건" : "★ \(fresh.count) big AI stories"
            content.body = fresh.prefix(3).map { "• " + text($0).title }.joined(separator: "\n")
            content.sound = .default
            content.threadIdentifier = "big-news"
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Once a day: the morning briefing.
    func announceBriefing(title: String, headline: String, points: [String]) async {
        let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: "briefingNotifiedDay") != day, await isAuthorized() else { return }
        UserDefaults.standard.set(day, forKey: "briefingNotifiedDay")
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = headline
        content.body = points.prefix(4).map { "• " + $0 }.joined(separator: "\n")
        content.sound = .default
        content.threadIdentifier = "briefing"
        try? await center.add(UNNotificationRequest(identifier: "briefing-\(Int(day))", content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let link = response.notification.request.content.userInfo["link"] as? String
        await MainActor.run {
            if let link, let url = URL(string: link) {
                NewsStore.shared?.markRead(link: link)
                NSWorkspace.shared.open(url)
            }
        }
    }
}
