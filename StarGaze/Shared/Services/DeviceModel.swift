//
//  DeviceModel.swift
//  StarGaze
//

import Foundation

/// The hardware model identifier, e.g. "iPhone15,2". Sky glow is only comparable within one model.
nonisolated enum DeviceModel {
    static let identifier: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()
}
