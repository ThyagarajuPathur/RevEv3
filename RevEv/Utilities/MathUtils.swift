import Foundation

/// Clamp a value between min and max
func clamp<T: Comparable>(_ value: T, _ min: T, _ max: T) -> T {
    return Swift.max(min, Swift.min(max, value))
}

/// Calculate normalized ratio (0-1) of value between min and max
func ratio(_ value: Double, _ min: Double, _ max: Double) -> Double {
    return clamp((value - min) / (max - min), 0, 1)
}

/// Equal power crossfade between two values
/// Returns (gain1, gain2) where gain1 fades in and gain2 fades out
func crossFade(_ value: Double, start: Double, end: Double) -> (gain1: Double, gain2: Double) {
    let x = clamp((value - start) / (end - start), 0, 1)
    let gain1 = cos((1.0 - x) * 0.5 * .pi)
    let gain2 = cos(x * 0.5 * .pi)
    return (gain1, gain2)
}

/// Smoothstep interpolation (GLSL-style)
func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}

/// Linear interpolation
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    return a + (b - a) * t
}
