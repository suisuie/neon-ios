import Foundation

/// Exact port of `java.util.Random` (48-bit LCG).
///
/// The arena grid, crate lattice and pickup spots are generated from a seeded
/// `java.util.Random`, so an iOS host and an Android host must roll the very same
/// numbers or the two builds would disagree about where the walls and medkits are.
/// Reproducing the LCG bit-for-bit is what keeps a mixed phone match consistent.
struct JavaRandom {
    private static let mask: UInt64 = (1 << 48) - 1
    private static let multiplier: UInt64 = 0x5DEECE66D
    private static let addend: UInt64 = 0xB

    private var seed: UInt64

    init(_ s: Int64) {
        seed = (UInt64(bitPattern: s) ^ JavaRandom.multiplier) & JavaRandom.mask
    }

    private mutating func next(_ bits: Int) -> Int32 {
        seed = (seed &* JavaRandom.multiplier &+ JavaRandom.addend) & JavaRandom.mask
        return Int32(truncatingIfNeeded: seed >> (48 - bits))
    }

    /// `nextInt(bound)` exactly as the JDK implements it, including the rejection loop.
    mutating func nextInt(_ bound: Int) -> Int {
        precondition(bound > 0, "bound must be positive")
        let r = next(31)
        let m = bound - 1
        if (bound & m) == 0 {
            return Int((Int64(bound) &* Int64(r)) >> 31)
        }
        var u = r
        var v = u % Int32(bound)
        while u &- v &+ Int32(m) < 0 {
            u = next(31)
            v = u % Int32(bound)
        }
        return Int(v)
    }

    mutating func nextFloat() -> Float {
        return Float(next(24)) / Float(1 << 24)
    }

    mutating func nextBoolean() -> Bool {
        return next(1) != 0
    }
}

/// `java.lang.Math.round(float)`: floor(x + 0.5), with the float kept as a float.
func jround(_ x: Float) -> Float {
    return (x + 0.5).rounded(.down)
}

func jroundI(_ x: Float) -> Int {
    return Int(jround(x))
}

/// `java.lang.Math.round(double)`.
func jround(_ x: Double) -> Double {
    return (x + 0.5).rounded(.down)
}

/// Java's `%` on floats/doubles is a truncated remainder (sign of the dividend).
func jmod(_ a: Float, _ b: Float) -> Float {
    return a.truncatingRemainder(dividingBy: b)
}