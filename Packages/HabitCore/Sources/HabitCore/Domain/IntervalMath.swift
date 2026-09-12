import Foundation

/// Pure helpers for merging and clipping time intervals (sleep samples, mindful sessions, visits).
public enum IntervalMath {
    /// Merges overlapping/touching intervals. Result is sorted by start.
    public static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                let end = max(last.end, interval.end)
                result[result.count - 1] = DateInterval(start: last.start, end: end)
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// Total non-overlapping duration of `intervals` inside `window`, in seconds.
    public static func totalDuration(of intervals: [DateInterval], clippedTo window: DateInterval) -> TimeInterval {
        merged(intervals).reduce(0) { sum, interval in
            guard let clipped = interval.intersection(with: window) else { return sum }
            return sum + clipped.duration
        }
    }

    /// Longest single interval inside `window` (after clipping, without merging), in seconds.
    public static func longestDuration(of intervals: [DateInterval], clippedTo window: DateInterval) -> TimeInterval {
        intervals.compactMap { $0.intersection(with: window)?.duration }.max() ?? 0
    }
}
