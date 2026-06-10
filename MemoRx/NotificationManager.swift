//
//  NotificationManager.swift
//  MemoRx
//
//  Created by Charles Thomas Xavier Austin III on 3/30/26.
//

import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let identifier = "memorx.daily"
    private let defaultHour = 9
    private let defaultMinute = 0

    func refreshDailyReminderIfAuthorized() {
        guard UserDefaults.standard.bool(forKey: "dailyReminderEnabled") else {
            cancelDailyReminder()
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            self.scheduleDailyReminder()
        }
    }

    func enableDailyReminder(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                self.scheduleDailyReminder()
            } else {
                self.cancelDailyReminder()
            }
            completion?(granted)
        }
    }

    func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func scheduleDailyReminder() {
        cancelDailyReminder()

        let content = UNMutableNotificationContent()
        content.title = "Your daily drug is ready 💊"
        content.body = "Open MemoRx and keep your streak alive 🔥"
        content.sound = .default

        let defaults = UserDefaults.standard
        let rawHour: Int
        let rawMinute: Int
        if defaults.object(forKey: "dailyReminderHour") == nil {
            rawHour = defaultHour
            rawMinute = defaultMinute
        } else {
            rawHour = defaults.integer(forKey: "dailyReminderHour")
            rawMinute = defaults.integer(forKey: "dailyReminderMinute")
        }

        let hour = min(max(rawHour, 0), 23)
        let minute = min(max(rawMinute, 0), 59)
        if hour != rawHour || minute != rawMinute {
            defaults.set(hour, forKey: "dailyReminderHour")
            defaults.set(minute, forKey: "dailyReminderMinute")
        }

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error {
                print("Failed to schedule daily reminder: \(error)")
            }
            #endif
        }
    }

    func updateReminderTime(hour: Int, minute: Int) {
        UserDefaults.standard.set(hour, forKey: "dailyReminderHour")
        UserDefaults.standard.set(minute, forKey: "dailyReminderMinute")
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            DispatchQueue.main.async {
                self.scheduleDailyReminder()
            }
        }
    }
}
