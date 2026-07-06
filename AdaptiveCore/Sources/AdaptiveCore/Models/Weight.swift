import Foundation

/// A training load, stored canonically in **pounds**.
///
/// This is a plain value type rather than Foundation's `Measurement<UnitMass>` on purpose:
/// `Measurement` carries an `NSUnit` class, which complicates the `Sendable` conformance every
/// model in this package relies on. Pounds is the unit the seed weights are authored in and the
/// unit the watch's ± adjust steps in; the UI converts to kilograms for locales that prefer it
/// (`displayString(locale:)`). It is a seed, not a log (N7).
public struct Weight: Codable, Sendable, Hashable, Comparable {
    /// Canonical magnitude in pounds.
    public var pounds: Double

    public init(pounds: Double) {
        self.pounds = pounds
    }

    /// Convenience constructor reading as `.lb(15)`.
    public static func lb(_ pounds: Double) -> Weight { Weight(pounds: pounds) }

    public var kilograms: Double { pounds * 0.45359237 }

    public static func < (lhs: Weight, rhs: Weight) -> Bool { lhs.pounds < rhs.pounds }

    /// Add/subtract a delta (in pounds), clamped at zero so a load can never go negative.
    public func adjusted(byPounds delta: Double) -> Weight {
        Weight(pounds: max(0, pounds + delta))
    }

    /// The real-dumbbell grid: every proposed load is a multiple of 5 lb (user decision
    /// 2026-07-05 — racks come in 5s; the earlier 2.5 lb isolation steps left users stuck
    /// on values like 22.5 that the ±5 controls could never bring back onto the grid).
    public static let gridPounds: Double = 5

    /// Steps the load along the 5 lb grid. An on-grid value moves by the full delta; an
    /// off-grid value (a legacy 2.5-step seed, e.g. 22.5) snaps to the ADJACENT grid point
    /// in the delta's direction — 22.5 steps down to 20 and up to 25, never 17.5/27.5.
    /// Clamped at zero.
    public func stepped(byPounds delta: Double, grid: Double = Weight.gridPounds) -> Weight {
        let remainder = pounds.truncatingRemainder(dividingBy: grid)
        let isOnGrid = min(remainder, grid - remainder) < 0.001
        let target: Double
        if isOnGrid {
            target = pounds + delta
        } else if delta > 0 {
            target = (pounds / grid).rounded(.up) * grid
        } else {
            target = (pounds / grid).rounded(.down) * grid
        }
        return Weight(pounds: max(0, target))
    }

    /// Snaps to the nearest grid point; an exact midpoint (22.5) rounds DOWN — the cheap
    /// error is the recoverable one (design principle 10).
    public func snappedToGrid(_ grid: Double = Weight.gridPounds) -> Weight {
        let lower = (pounds / grid).rounded(.down) * grid
        let upper = lower + grid
        return Weight(pounds: (pounds - lower) > (upper - pounds) ? upper : lower)
    }

    /// A localized display string, e.g. `"15 lb"` or `"7 kg"`, using the locale's preferred
    /// mass unit. Rounds kilograms to the nearest whole number (dumbbell granularity).
    public func displayString(locale: Locale = .current) -> String {
        let usesMetric = locale.measurementSystem == .metric
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = usesMetric ? 0 : 1
        let measurement = usesMetric
            ? Measurement(value: (kilograms).rounded(), unit: UnitMass.kilograms)
            : Measurement(value: pounds, unit: UnitMass.pounds)
        return formatter.string(from: measurement)
    }
}
