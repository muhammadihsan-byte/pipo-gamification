import Foundation

struct WidgetSnapshot: Sendable {
    let streakDays: Int
    let totalXP: Int
    let currentLevel: Int
    let goalID: UUID?
    let goalTitle: String?
    let goalProgress: Double
    let nextDepositDate: Date?

    static let empty = WidgetSnapshot(
        streakDays: 0,
        totalXP: 0,
        currentLevel: 1,
        goalID: nil,
        goalTitle: nil,
        goalProgress: 0,
        nextDepositDate: nil
    )
}

enum WidgetSharedData {
    static let appGroupIdentifier = "group.com.satusaku.app"
    private static let snapshotKey = "satusaku.widget.snapshot"

    static func save(_ snapshot: WidgetSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw WidgetSharedDataError.appGroupUnavailable
        }

        var values: [String: Any] = [
            "streakDays": max(snapshot.streakDays, 0),
            "totalXP": max(snapshot.totalXP, 0),
            "currentLevel": max(snapshot.currentLevel, 1),
            "goalProgress": min(max(snapshot.goalProgress, 0), 1)
        ]
        if let goalID = snapshot.goalID {
            values["goalID"] = goalID.uuidString
        }
        if let goalTitle = snapshot.goalTitle {
            values["goalTitle"] = goalTitle
        }
        if let nextDepositDate = snapshot.nextDepositDate {
            values["nextDepositDate"] = nextDepositDate
        }

        defaults.set(values, forKey: snapshotKey)
    }

    static func load() -> WidgetSnapshot {
        guard
            let values = UserDefaults(suiteName: appGroupIdentifier)?
                .dictionary(forKey: snapshotKey)
        else {
            return .empty
        }

        return WidgetSnapshot(
            streakDays: values["streakDays"] as? Int ?? 0,
            totalXP: values["totalXP"] as? Int ?? 0,
            currentLevel: values["currentLevel"] as? Int ?? 1,
            goalID: (values["goalID"] as? String).flatMap(UUID.init(uuidString:)),
            goalTitle: values["goalTitle"] as? String,
            goalProgress: values["goalProgress"] as? Double ?? 0,
            nextDepositDate: values["nextDepositDate"] as? Date
        )
    }
}

enum WidgetSharedDataError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        "The Satu Saku App Group is unavailable. Check the App Group capability for both app targets."
    }
}
