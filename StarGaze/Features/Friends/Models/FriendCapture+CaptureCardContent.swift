//
//  FriendCapture+CaptureCardContent.swift
//  StarGaze
//

import Foundation

extension FriendCapture {
    /// The single place where a friend's capture is mapped to the shared card's input.
    /// The image comes from local constellation data, not from the friend's capture.
    func cardContent(using catalog: any ConstellationCatalog) -> CaptureCardContent {
        CaptureCardContent(
            constellationName: constellationName,
            locationName: locationName,
            date: date,
            image: catalog.image(for: constellationName),
            rarity: rarity,
            points: points,
            isFirstFind: isFirstFind
        )
    }
}
