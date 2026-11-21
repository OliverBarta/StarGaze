import SwiftUI
import Observation

/// Everything the user has discovered in the sky, plus completed sets. Saved on the device.
@Observable
final class DiscoveryStore {
    struct Discovery: Codable {
        var name: String
        var date: Date
        var place: String
        var stampSetIDs: [String] = []
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
    /// Stamps that should "slam" in the next time the collection appears.
    var freshStamps: Set<String> = []

    /// TESTING: play a cutscene on every new discovery (doesn't stamp or complete sets).
    /// Set to false for the real "find 5 from a set" behaviour.
    static let cutsceneOnEveryFind = false
    /// TESTING: make this constellation the "runner" in every test cutscene (nil = the one you found).
    static let testHero: String? = nil

    /// Called after each new discovery is saved (ContentView uses it to share the find).
    @ObservationIgnored var onDiscover: ((Discovery) -> Void)?

    @ObservationIgnored private let saveKey = "StarGaze.discoveries.v1"
    @ObservationIgnored private let setsKey = "StarGaze.completedSets.v1"

    init() {
        // While testing, start with a clean slate every launch so cutscenes can be replayed.
        if Self.cutsceneOnEveryFind {
            save()
        } else {
            load()
        }
    }

    func isDiscovered(_ name: String) -> Bool { discoveries[name] != nil }

    /// Record a discovery. Returns true if it's new.
    @discardableResult
    func discover(_ name: String, place: String) -> Bool {
        guard discoveries[name] == nil else { return false }
        discoveries[name] = Discovery(name: name, date: .now, place: place)
        let before = pendingCompletions.count
        checkSets()
        if Self.cutsceneOnEveryFind && pendingCompletions.count == before {
            pendingCompletions.append(testCompletion(for: name))
        } else if name == "Auriga" {
            // Auriga always gets its own special cutscene when found (no stamps)
            let set = ConstellationSet.all.first { $0.members.contains("Auriga") } ?? ConstellationSet.all[0]
            pendingCompletions.insert(Completion(set: set, names: ["Auriga"], isTest: true), at: before)
        }
        save()
        if let discovery = discoveries[name] { onDiscover?(discovery) }
        return true
    }

    private func checkSets() {
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
            pendingCompletions.append(Completion(set: set, names: names))
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
        let catalog = AssetConstellationCatalog()
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
            var stamps: [ConstellationSet] = []
            for s in 0..<d.stampSetIDs.count {
                if let set = ConstellationSet.all.first(where: { $0.id == d.stampSetIDs[s] }) {
                    stamps.append(set)
                }
            }
            result.append(CaptureCardContent(
                constellationName: d.name, locationName: d.place, date: d.date,
                image: catalog.image(for: d.name), rarity: rarity, points: rarity.points,
                stamps: stamps, stampIsFresh: freshStamps.contains(d.name)))
        }
        return result
    }

    #if DEBUG
    func resetAll() {
        discoveries = [:]
        completedSetIDs = []
        pendingCompletions = []
        freshStamps = []
        save()
    }
    #endif

    // MARK: Saving

    private func save() {
        if let data = try? JSONEncoder().encode(discoveries) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
        UserDefaults.standard.set(Array(completedSetIDs), forKey: setsKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let saved = try? JSONDecoder().decode([String: Discovery].self, from: data) {
            discoveries = saved
        }
        completedSetIDs = Set(UserDefaults.standard.stringArray(forKey: setsKey) ?? [])
    }
}
