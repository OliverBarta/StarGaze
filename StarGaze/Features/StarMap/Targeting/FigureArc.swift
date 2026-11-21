import simd

/// One stick-figure line of a constellation: the great-circle arc between two stars.
nonisolated struct FigureArc: Sendable {
    let start: SIMD3<Float>
    let end: SIMD3<Float>
    /// Unit normal of the arc's great-circle plane, or nil if the two stars coincide.
    let normal: SIMD3<Float>?

    init(start: SIMD3<Float>, end: SIMD3<Float>) {
        self.start = start
        self.end = end
        let cross = simd_cross(start, end)
        normal = simd_length(cross) > 1e-6 ? simd_normalize(cross) : nil
    }
}
