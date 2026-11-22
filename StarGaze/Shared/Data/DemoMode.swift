//
//  DemoMode.swift
//  StarGaze
//

import Foundation

/// Profile → "Demo mode: allow indoor captures". For demos indoors: the ring fills at any angle and
/// the capture button collects instantly, with no sky photo and no Gemini check (so no reading).
nonisolated enum DemoMode {
    static let defaultsKey = "StarGaze.demoIndoorCaptures"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }
}
