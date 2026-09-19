import Foundation

public struct Streak: Sendable, Equatable {
    public var length: Int
    public var gracesUsed: Int
    public init(length: Int, gracesUsed: Int) { self.length = length; self.gracesUsed = gracesUsed }
    public static let zero = Streak(length: 0, gracesUsed: 0)
}

/// Streaks that forgive up to `graceMissesPerWeek` misses in any 7 consecutive obligations.
/// The unit is the obligation, not the day: a "three times a week" habit counts weeks, and
/// `length` must be read together with the schedule's period.
public enum StreakCalculator {
    /// `obligations` ascending. The still-running one counts only when already fulfilled, and
    /// never breaks the run — an unfinished week is not a missed week.
    public static func currentStreak(_ obligations: [ObligationResult], graceMissesPerWeek: Int) -> Streak {
        guard !obligations.isEmpty else { return .zero }

        var length = 0
        var graces = 0
        var recentWindow: [Bool] = []  // misses among the last ≤7 obligations walked (newest first)

        for obligation in obligations.reversed() {
            if obligation.isOpen {
                if obligation.fulfilled { length += 1; recentWindow.append(false) }
                continue
            }
            if obligation.fulfilled {
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

    /// Longest run ever, with the same grace rule applied chronologically.
    public static func bestStreak(_ obligations: [ObligationResult], graceMissesPerWeek: Int) -> Int {
        var best = 0
        var length = 0
        var window: [Bool] = []
        for obligation in obligations {
            if obligation.isOpen && !obligation.fulfilled { break }
            if obligation.fulfilled {
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
