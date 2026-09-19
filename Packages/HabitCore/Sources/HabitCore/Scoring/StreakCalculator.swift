import Foundation

public struct Streak: Sendable, Equatable {
    public var length: Int
    /// Obligations kept alive by a freeze, newest first, identified by their first day.
    /// The history views mark those days so a frozen day never passes for a day that was done.
    public var frozen: [DayKey]

    public init(length: Int, frozen: [DayKey] = []) {
        self.length = length
        self.frozen = frozen
    }

    public var gracesUsed: Int { frozen.count }
    public static let zero = Streak(length: 0)
}

/// Streaks with a freeze budget: a missed obligation is forgiven silently while the calendar
/// month it falls in still has freezes left, and breaks the run once the month is spent.
/// A freeze keeps the run alive but adds nothing to its length — it was not a kept obligation.
public enum StreakCalculator {
    /// `obligations` ascending. The still-running one counts only when already fulfilled, and
    /// never breaks the run — an unfinished week is not a missed week.
    ///
    /// Walking backwards means the month's freezes go to its most recent misses, which is the
    /// reading that matches how a user thinks about "I have two left this month".
    public static func currentStreak(_ obligations: [ObligationResult], freezesPerMonth: Int) -> Streak {
        guard !obligations.isEmpty else { return .zero }
        var length = 0
        var frozen: [DayKey] = []
        var spent: [String: Int] = [:]

        for obligation in obligations.reversed() {
            if obligation.isOpen {
                if obligation.fulfilled { length += 1 }
                continue
            }
            if obligation.fulfilled {
                length += 1
                continue
            }
            let month = monthKey(of: obligation.start)
            guard spent[month, default: 0] < freezesPerMonth else { break }
            spent[month, default: 0] += 1
            frozen.append(obligation.start)
        }
        return Streak(length: length, frozen: frozen)
    }

    /// Longest run ever, under the same budget. Walking forwards spends each month's freezes on
    /// its earliest misses; the budget itself is never reset by a broken run, because it belongs
    /// to the calendar month and not to the streak.
    public static func bestStreak(_ obligations: [ObligationResult], freezesPerMonth: Int) -> Int {
        var best = 0
        var length = 0
        var spent: [String: Int] = [:]

        for obligation in obligations {
            if obligation.isOpen && !obligation.fulfilled { break }
            if obligation.fulfilled {
                length += 1
                best = max(best, length)
                continue
            }
            let month = monthKey(of: obligation.start)
            if spent[month, default: 0] < freezesPerMonth {
                spent[month, default: 0] += 1
            } else {
                length = 0
            }
        }
        return best
    }

    /// Freezes still available in the month `key` belongs to, given what the current run spent.
    public static func freezesLeft(in key: DayKey, streak: Streak, freezesPerMonth: Int) -> Int {
        let month = monthKey(of: key)
        let used = streak.frozen.count { monthKey(of: $0) == month }
        return max(freezesPerMonth - used, 0)
    }

    private static func monthKey(of key: DayKey) -> String { String(key.raw.prefix(7)) }
}
