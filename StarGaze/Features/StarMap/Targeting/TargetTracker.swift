/// Decides which constellation is targeted and how far collecting it has progressed.
/// Pure state: feed it each frame's candidates and the elapsed time.
nonisolated struct TargetTracker: Sendable {
    /// The constellation currently targeted, if any.
    private(set) var currentID: String?
    /// The constellation the dwell progress belongs to (can outlive `currentID` while it drains).
    private(set) var progressID: String?
    /// 0...1; reaching 1 means collect.
    private(set) var progress: Double = 0

    private var challengerID: String?
    private var challengerTime: Double = 0

    mutating func update(candidates: [TargetCandidate], dt: Double) {
        updateTarget(candidates, dt: dt)
        updateProgress(candidates, dt: dt)
    }

    /// Call after collecting so the finished constellation starts fresh.
    mutating func clearProgress() {
        progress = 0
        progressID = nil
    }

    private mutating func updateTarget(_ candidates: [TargetCandidate], dt: Double) {
        let best = candidates.min { $0.score.isBetter(than: $1.score) }
        guard let currentID, let current = candidates.first(where: { $0.id == currentID }) else {
            // nothing targeted, or the target is out of reach: take the best right away
            self.currentID = best?.id
            resetChallenger()
            return
        }
        guard let best, best.id != currentID,
              best.score.isClearlyBetter(than: current.score, ratio: TargetingTuning.switchRatio) else {
            resetChallenger()
            return
        }
        if challengerID == best.id {
            challengerTime += dt
        } else {
            challengerID = best.id
            challengerTime = dt
        }
        if challengerTime >= TargetingTuning.switchHold {
            self.currentID = best.id
            resetChallenger()
        }
    }

    private mutating func updateProgress(_ candidates: [TargetCandidate], dt: Double) {
        let current = candidates.first { $0.id == currentID }
        if let current, current.isCollectible {
            if progressID != current.id {
                progressID = current.id
                progress = 0
            }
            progress = min(1, progress + dt / TargetingTuning.dwellNeeded)
        } else if progressID != nil {
            progress -= TargetingTuning.decayRate * dt / TargetingTuning.dwellNeeded
            if progress <= 0 { clearProgress() }
        }
    }

    private mutating func resetChallenger() {
        challengerID = nil
        challengerTime = 0
    }
}
