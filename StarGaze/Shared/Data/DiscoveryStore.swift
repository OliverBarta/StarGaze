import SwiftUI
import Observation

/// Everything the user has discovered in the sky, plus completed sets. Nothing is saved on the
/// device: finds are saved to Supabase (`saveCapture`) and loaded back with `refresh()`.
@Observable
final class DiscoveryStore {
    struct Discovery: Codable {
        var name: String
        var date: Date
        var place: String
        var stampSetIDs: [String] = []
        /// Spotted when a good sky photo backed the find; nil (older rows) means located.
        var level: FindLevel?
    }

    /// One completed set waiting for its cutscene.
    struct Completion: Identifiable, Equatable {
        let id = UUID()
        let set: ConstellationSet
        let names: [String]   // the constellations that completed it
        var isTest = false
    }

    private(set) var discoveries: [String: Discovery] = [:]
    private(set) var completedSetIDs: Set<String> = []
    /// Cutscenes to play, in order.
    var pendingCompletions: [Completion] = []
    /// The cutscene to show now, if any.
    var cutsceneToPlay: Completion? { pendingCompletions.first }
    /// Stamps that should "slam" in the next time the collection appears.
    var freshStamps: Set<String> = []

    /// TESTING: play a cutscene on every new discovery (doesn't stamp or complete sets).
    /// Set to false for the real "find 5 from a set" behaviour.
    static let cutsceneOnEveryFind = false
    /// TESTING: make this constellation the "runner" in every test cutscene (nil = the one you found).
    static let testHero: String? = nil

    /// Saves a new find (ContentView sets it to the Supabase insert). Nil in previews: finds stay in memory.
    @ObservationIgnored var saveCapture: ((Discovery) async throws -> Void)?
    /// Loads the user's finds (ContentView sets it to the Supabase fetch).
    @ObservationIgnored var fetchCaptures: (() async throws -> [Discovery])?

    /// Finds whose save is still in flight, so they can't be discovered twice meanwhile.
    @ObservationIgnored private var saving: Set<String> = []

    func isDiscovered(_ name: String) -> Bool { discoveries[name] != nil }

    /// Saves a discovery, and only records it once the save succeeds. Returns true if it's new;
    /// throws if it couldn't be saved (then nothing changes).
    @discardableResult
    func discover(_ name: String, place: String, level: FindLevel) async throws -> Bool {
        guard discoveries[name] == nil, !saving.contains(name) else { return false }
        let discovery = Discovery(name: name, date: .now, place: place, level: level)
        saving.insert(name)
        defer { saving.remove(name) }
        try await saveCapture?(discovery)
        guard discoveries[name] == nil else { return false }   // a refresh brought it in meanwhile

        discoveries[name] = discovery
        let before = pendingCompletions.count
        checkSets()
        if Self.cutsceneOnEveryFind && pendingCompletions.count == before {
            pendingCompletions.append(testCompletion(for: name))
        } else if name == "Auriga" {
            // Auriga always gets its own special cutscene when found (no stamps)
            let set = ConstellationSet.all.first { $0.members.contains("Auriga") } ?? ConstellationSet.all[0]
            pendingCompletions.insert(Completion(set: set, names: ["Auriga"], isTest: true), at: before)
        }
        return true
    }

    /// Loads the user's finds from Supabase and adds them to what's here (captures are never
    /// deleted, so merging can't bring back anything stale). Stamps and completed sets are
    /// recomputed from the finds without playing cutscenes.
    func refresh() async throws {
        guard let fetchCaptures else { return }
        let fetched = try await fetchCaptures()
        var merged = discoveries
        // The schema allows repeat captures of a constellation; the earliest one is the find.
        for row in fetched.sorted(by: { $0.date < $1.date }) {
            if var existing = merged[row.name] {
                if row.level == .spotted { existing.level = .spotted }
                merged[row.name] = existing
            } else {
                merged[row.name] = row
            }
        }
        for name in merged.keys { merged[name]?.stampSetIDs = [] }
        discoveries = merged
        completedSetIDs = []
        checkSets(queueCutscenes: false)
    }

    private func checkSets(queueCutscenes: Bool = true) {
        let sets = ConstellationSet.all
        for i in 0..<sets.count {
            let set = sets[i]
            guard !completedSetIDs.contains(set.id) else { continue }

            // found members, oldest first
            var found: [Discovery] = []
            for m in 0..<set.members.count {
                if let d = discoveries[set.members[m]] { found.append(d) }
            }
            guard found.count >= set.required else { continue }
            found.sort { $0.date < $1.date }

            var names: [String] = []
            for f in 0..<set.required {
                let name = found[f].name
                names.append(name)
                discoveries[name]?.stampSetIDs.append(set.id)
            }
            completedSetIDs.insert(set.id)
            if queueCutscenes { pendingCompletions.append(Completion(set: set, names: names)) }
        }
    }

    /// A preview cutscene for one find: the new constellation plus 4 companions from one of its sets
    /// (already-found ones first, preferring ones with illustrations).
    private func testCompletion(for name: String) -> Completion {
        let hero = Self.testHero ?? name
        let set = ConstellationSet.all.first { $0.members.contains(hero) } ?? ConstellationSet.all[0]
        var names = [hero]
        var others = set.members.filter { $0 != hero && SkyArt.entry(forName: $0) != nil }
        others.sort { (discoveries[$0] != nil ? 0 : 1) < (discoveries[$1] != nil ? 0 : 1) }
        for i in 0..<others.count where names.count < 5 {
            names.append(others[i])
        }
        return Completion(set: set, names: names, isTest: true)
    }

    /// Called when a cutscene finishes: its stamps get the slam animation in the collection.
    func finishCutscene(_ completion: Completion) {
        pendingCompletions.removeAll { $0.id == completion.id }
        guard !completion.isTest else { return }
        for i in 0..<completion.names.count {
            freshStamps.insert(completion.names[i])
        }
    }

    /// Cards for the Collection tab, stamped ones from the latest set first.
    var cards: [CaptureCardContent] {
        let catalog = JSONConstellationCatalog()
        var list = Array(discoveries.values)
        list.sort { a, b in
            let aFresh = freshStamps.contains(a.name), bFresh = freshStamps.contains(b.name)
            if aFresh != bFresh { return aFresh }
            return a.date > b.date
        }
        var result: [CaptureCardContent] = []
        for i in 0..<list.count {
            let d = list[i]
            let rarity = Rarity.forConstellation(d.name)
            let spotted = d.level == .spotted
            var stamps: [ConstellationSet] = []
            for s in 0..<d.stampSetIDs.count {
                if let set = ConstellationSet.all.first(where: { $0.id == d.stampSetIDs[s] }) {
                    stamps.append(set)
                }
            }
            result.append(CaptureCardContent(
                constellationName: d.name, locationName: d.place, date: d.date,
                image: catalog.image(for: d.name), rarity: rarity,
                points: rarity.points * (spotted ? 2 : 1),
                stamps: stamps, stampIsFresh: freshStamps.contains(d.name), isSpotted: spotted))
        }
        return result
    }
}
