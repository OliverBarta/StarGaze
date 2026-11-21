//
//  CollectionView.swift
//  StarGaze
//
//  Created by Oliver Barta on 2026-11-20.
//

import SwiftUI

struct CollectionView: View {
    
    
    
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Image(systemName: "person.fill")
                    Text("Joe")
                }
                
                Text("Collection:")
                    .font( .headline)
            }
        }
    }
}

#Preview {
    CollectionView()
}
