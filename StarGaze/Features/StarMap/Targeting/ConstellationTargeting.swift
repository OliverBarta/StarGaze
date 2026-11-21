import simd

/// Pure geometry for deciding which constellation the user is aiming at.
/// No SceneKit, so every function can be unit-tested with plain vectors.
nonisolated enum ConstellationTargeting {
    /// Angle between two unit vectors (stable for small angles).
    static func angle(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        atan2(simd_length(simd_cross(a, b)), simd_dot(a, b))
    }

    /// Shortest angle from `p` to the arc: perpendicular if `p` falls alongside it, else the nearer end.
    static func arcDistance(from p: SIMD3<Float>, to arc: FigureArc) -> Float {
        let toEnds = min(angle(p, arc.start), angle(p, arc.end))
        guard let n = arc.normal else { return toEnds }
        let q = p - simd_dot(p, n) * n  // p dropped onto the arc's great-circle plane
        let alongside = simd_dot(simd_cross(arc.start, q), n) >= 0 && simd_dot(simd_cross(q, arc.end), n) >= 0
        guard alongside, simd_length(q) > 1e-6 else { return toEnds }
        return min(toEnds, asin(min(1, abs(simd_dot(p, n)))))
    }

    /// Whether `p` lies inside the figure's outline.
    static func isInsideHull(_ p: SIMD3<Float>, of figure: TargetFigure) -> Bool {
        guard figure.hull.count >= 3, let point = figure.project(p) else { return false }
        return isInside(point, convexPolygon: figure.hull)
    }

    /// Point-in-polygon for a counter-clockwise convex polygon (edges count as inside).
    static func isInside(_ point: SIMD2<Float>, convexPolygon polygon: [SIMD2<Float>]) -> Bool {
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            if cross(b - a, point - a) < 0 { return false }
        }
        return true
    }

    /// Convex hull (Andrew's monotone chain), counter-clockwise, without collinear points.
    static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard sorted.count >= 3 else { return sorted }
        var lower: [SIMD2<Float>] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 1] - lower[lower.count - 2], p - lower[lower.count - 2]) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [SIMD2<Float>] = []
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 1] - upper[upper.count - 2], p - upper[upper.count - 2]) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Allowed distance outside the figure, growing with the figure's size.
    static func tolerance(forAngularRadius radius: Float) -> Float {
        let span = TargetingTuning.largeFigureRadius - TargetingTuning.smallFigureRadius
        let t = min(1, max(0, (radius - TargetingTuning.smallFigureRadius) / span))
        return TargetingTuning.minTolerance + t * (TargetingTuning.maxTolerance - TargetingTuning.minTolerance)
    }

    /// The score for aiming along `p`, or nil if `p` is beyond this figure's tolerance.
    static func score(_ p: SIMD3<Float>, figure: TargetFigure) -> TargetScore? {
        let tolerance = tolerance(forAngularRadius: figure.angularRadius)
        let toCenter = angle(p, figure.center)
        guard toCenter <= figure.angularRadius + tolerance else { return nil }  // cheap early out
        let centerRatio = toCenter / max(figure.angularRadius, 1e-3)

        if isInsideHull(p, of: figure) {
            return TargetScore(distance: 0, centerRatio: centerRatio)
        }
        var nearest = figure.stars.map { angle(p, $0) }.min() ?? toCenter
        for arc in figure.arcs {
            nearest = min(nearest, arcDistance(from: p, to: arc))
        }
        guard nearest <= tolerance else { return nil }
        return TargetScore(distance: nearest, centerRatio: centerRatio)
    }

    /// Every figure within reach of `p`, in no particular order.
    static func candidates(for p: SIMD3<Float>, among figures: [TargetFigure],
                           isCollectible: (TargetFigure) -> Bool) -> [TargetCandidate] {
        figures.compactMap { figure in
            score(p, figure: figure).map {
                TargetCandidate(id: figure.id, score: $0, isCollectible: isCollectible(figure))
            }
        }
    }

    private static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        a.x * b.y - a.y * b.x
    }
}
