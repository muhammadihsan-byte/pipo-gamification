import Foundation

struct WidgetSnapshot: Sendable {
    let streakDays: Int
    let totalXP: Int
    let currentLevel: Int
    let goalID: UUID?
    let goalTitle: String?
    let goalProgress: Double
    let nextDepositDate: Date?
    var ownerUserID: UUID? = nil
    var consistencyUnit: String? = nil
    var recordedCount: Int = 0

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
    static let appGroupIdentifier = "group.com.pipo.app"
    private static let snapshotKey = "pipo.widget.snapshot"
    private static let activeAccountKey = "pipo.widget.active.account"

    /// Change the widget's active account before the next account's data is saved.
    /// Old unowned snapshots become unreadable. Never infer ownership for them.
    static func activate(userID: UUID?) throws {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw WidgetSharedDataError.appGroupUnavailable
        }
        activate(userID: userID, in: defaults)
    }

    static func activate(userID: UUID?, in defaults: UserDefaults) {
        let previousUserID = defaults.string(forKey: activeAccountKey)
        let nextUserID = userID?.uuidString
        if previousUserID != nextUserID {
            defaults.removeObject(forKey: snapshotKey)
        }
        if let nextUserID {
            defaults.set(nextUserID, forKey: activeAccountKey)
        } else {
            defaults.removeObject(forKey: activeAccountKey)
        }
    }

    static func save(_ snapshot: WidgetSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw WidgetSharedDataError.appGroupUnavailable
        }

        try save(snapshot, in: defaults)
    }

    static func save(_ snapshot: WidgetSnapshot, in defaults: UserDefaults) throws {
        let activeUserID = defaults.string(forKey: activeAccountKey)
        if let ownerUserID = snapshot.ownerUserID {
            guard activeUserID == ownerUserID.uuidString else {
                throw WidgetSharedDataError.accountMismatch
            }
        } else if snapshot.goalID != nil || snapshot.totalXP != 0 || snapshot.streakDays != 0 {
            throw WidgetSharedDataError.accountMismatch
        }

        var values: [String: Any] = [
            "streakDays": max(snapshot.streakDays, 0),
            "totalXP": max(snapshot.totalXP, 0),
            "currentLevel": max(snapshot.currentLevel, 1),
            "goalProgress": min(max(snapshot.goalProgress, 0), 1)
        ]
        if let owner = snapshot.ownerUserID {
            values["ownerUserID"] = owner.uuidString
        }
        if let unit = snapshot.consistencyUnit {
            values["consistencyUnit"] = unit
        }
        values["recordedCount"] = max(snapshot.recordedCount, 0)
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
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return .empty
        }
        return load(from: defaults)
    }

    static func load(from defaults: UserDefaults) -> WidgetSnapshot {
        guard let currentAccount = defaults.string(forKey: activeAccountKey),
              let values = defaults.dictionary(forKey: snapshotKey),
              let owner = values["ownerUserID"] as? String,
              owner == currentAccount,
              let ownerUserID = UUID(uuidString: owner)
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
            nextDepositDate: values["nextDepositDate"] as? Date,
            ownerUserID: ownerUserID,
            consistencyUnit: values["consistencyUnit"] as? String,
            recordedCount: values["recordedCount"] as? Int ?? 0
        )
    }
}

enum WidgetSharedDataError: LocalizedError {
    case appGroupUnavailable
    case accountMismatch

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "The Pipo App Group is unavailable. Check the App Group capability for both app targets."
        case .accountMismatch:
            return "The widget snapshot doesn't belong to the active Pipo account."
        }
    }
}
