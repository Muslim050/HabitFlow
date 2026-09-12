import Foundation

public struct Streak: Sendable, Equatable {
    public var length: Int
    public var gracesUsed: Int
    public init(length: Int, gracesUsed: Int) { self.length = length; self.gracesUsed = gracesUsed }
    public static let zero = Streak(length: 0, gracesUsed: 0)
}

/// Streaks that forgive up to `graceMissesPerWeek` misses in any 7 consecutive scheduled days.
public enum StreakCalculator {
    /// `results` ascending; the last element is `today`. Today only counts when completed and never breaks the streak.
    public static func currentStreak(_ results: [DayResult], today: DayKey, graceMissesPerWeek: Int) -> Streak {
        let scheduled = results.filter(\.scheduled)
        guard !scheduled.isEmpty else { return .zero }

        var length = 0
        var graces = 0
        var recentWindow: [Bool] = []  // misses among the last ≤7 scheduled days walked (newest first)

        for result in scheduled.reversed() {
            if result.dayKey == today {
                if result.completed { length += 1; recentWindow.append(false) }
                continue
            }
            if result.dayKey > today { continue }

            if result.completed {
                length += 1
                recentWindow.append(false)
            } else {
                recentWindow.append(true)
                let misses = recentWindow.suffix(7).filter { $0 }.count
                if misses > graceMissesPerWeek { break }
                graces += 1
            }
            if recentWindow.count > 7 { recentWindow.removeFirst() }
        }
        return Streak(length: length, gracesUsed: graces)
    }

    /// Longest streak ever, with the same grace rule applied chronologically.
    public static func bestStreak(_ results: [DayResult], today: DayKey, graceMissesPerWeek: Int) -> Int {
        var best = 0
        var length = 0
        var window: [Bool] = []
        for result in results where result.scheduled && result.dayKey <= today {
            if result.dayKey == today && !result.completed { break }
            if result.completed {
                length += 1
                window.append(false)
            } else {
                window.append(true)
                if window.suffix(7).filter({ $0 }).count > graceMissesPerWeek {
                    length = 0
                    window.removeAll()
                }
            }
            if window.count > 7 { window.removeFirst() }
            best = max(best, length)
        }
        return best
    }
}
