import simd

/// A constellation's stick-figure geometry, computed once when the sky is built.
nonisolated struct TargetFigure: Sendable {
    let id: String
    let name: String
    let center: SIMD3<Float>
    /// Unique star directions.
    let stars: [SIMD3<Float>]
    let arcs: [FigureArc]
    /// Angle from the centre to the farthest star.
    let angularRadius: Float
    /// Basis of the plane tangent to the sky at `center`, for the gnomonic projection.
    let axisX: SIMD3<Float>
    let axisY: SIMD3<Float>
    /// Outline of the figure: convex hull of the projected stars, counter-clockwise.
    /// Gnomonic projection maps great circles to straight lines, so this is the angular convex hull.
    let hull: [SIMD2<Float>]

    init(id: String, name: String, center: SIMD3<Float>, segments: [[SIMD3<Float>]]) {
        self.id = id
        self.name = name
        self.center = center

        var stars: [SIMD3<Float>] = []
        var arcs: [FigureArc] = []
        for segment in segments {
            for i in 0..<segment.count {
                if !stars.contains(where: { simd_distance($0, segment[i]) < 1e-4 }) {
                    stars.append(segment[i])
                }
                if i + 1 < segment.count {
                    arcs.append(FigureArc(start: segment[i], end: segment[i + 1]))
                }
            }
        }
        self.stars = stars
        self.arcs = arcs
        angularRadius = stars.map { ConstellationTargeting.angle(center, $0) }.max() ?? 0

        let helper = abs(center.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let axisX = simd_normalize(simd_cross(helper, center))
        let axisY = simd_cross(center, axisX)
        self.axisX = axisX
        self.axisY = axisY
        let projected = stars.compactMap { Self.project($0, center: center, axisX: axisX, axisY: axisY) }
        hull = ConstellationTargeting.convexHull(projected)
    }

    /// Gnomonic projection onto the tangent plane, or nil if the point is 90° or more from the centre.
    func project(_ direction: SIMD3<Float>) -> SIMD2<Float>? {
        Self.project(direction, center: center, axisX: axisX, axisY: axisY)
    }

    private static func project(_ p: SIMD3<Float>, center: SIMD3<Float>,
                                axisX: SIMD3<Float>, axisY: SIMD3<Float>) -> SIMD2<Float>? {
        let d = simd_dot(p, center)
        guard d > 0.05 else { return nil }
        return SIMD2(simd_dot(p, axisX), simd_dot(p, axisY)) / d
    }
}
