//
//  ConstellationImageName.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-21.
//

import SwiftData

@Model
class ConstellationImageName {
    var name: String
    var image: String
    
    init(name: String, image: String) {
        self.name = name
        self.image = image
    }
}
