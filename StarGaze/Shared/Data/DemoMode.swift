//
//  DemoMode.swift
//  StarGaze
//

import Foundation

/// Profile → "Demo mode: allow indoor captures". Skips the point-up and not-a-sky checks so the
/// app can be demoed indoors. Readings taken in demo mode never go to the light-pollution map.
nonisolated enum DemoMode {
    static let defaultsKey = "StarGaze.demoIndoorCaptures"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }
}
