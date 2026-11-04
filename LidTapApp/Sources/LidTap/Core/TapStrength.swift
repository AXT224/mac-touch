import Foundation

/// How hard a tap must be before LidTap records or acts on it, learned from the Mac's own taps.
///
/// The same light flick twists a 13" MacBook Air far more than a 16" MacBook Pro, whose heavier base and
/// stiffer hinge damp it two to three times. A fixed limit that suits the Air (3.5 °/s, below which its
/// accuracy fell from 95% to 56%) refuses nearly every screen tap on the 16". So the limit is two thirds of
/// this Mac's typical tap, never above the Air's 3.5 °/s and never below 1 °/s, where taps vanish into the
/// sensor's background motion.
enum TapStrength {
    static let ceiling = 3.5
    static let floor = 1.0
    static let fraction = 2.0 / 3.0

    /// `strengths`: peak strengths (°/s) of the taps aimed at zones on this Mac, recorded or refused.
    static func learned(from strengths: [Double]) -> Double {
        guard !strengths.isEmpty else { return floor }
        let sorted = strengths.sorted()
        let n = sorted.count
        let median = n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        return min(ceiling, max(floor, fraction * median))
    }
}
