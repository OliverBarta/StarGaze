import SwiftUI
import PhotosUI

// MARK: - Data models (match the JSON that GeminiService asks Gemini for)
// Like a Python dataclass: Codable lets Swift turn JSON straight into these.

struct GeminiResult: Codable {
    let constellations: [Constellation]
}

struct Constellation: Codable, Identifiable {
    var id: String { name }
    let name: String
    let stars: [Star]
    let lines: [[Int]]     // pairs of indexes into `stars`, e.g. [[0, 1], [1, 2]]
    let fact: String?
}

struct Star: Codable {
    let name: String?
    let x: Double          // 0...1 across the image width
    let y: Double          // 0...1 down the image height
}

// MARK: - Screen: pick a photo, ask Gemini, draw the constellations

struct ConstellationView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var constellations: [Constellation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // One colour per constellation so overlapping ones are easy to tell apart
    private let colours: [Color] = [.cyan, .yellow, .pink, .green, .orange, .purple]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // For testing indoors: choose a star photo from the photo library.
                // Later, pass in the photo from your camera screen instead.
                PhotosPicker("Choose a star photo", selection: $pickerItem, matching: .images)
                    .buttonStyle(.borderedProminent)

                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        // The overlay is exactly the size of the fitted image,
                        // so 0...1 positions map straight onto it.
                        .overlay {
                            GeometryReader { geo in
                                overlay(size: geo.size)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if isLoading {
                    ProgressView("Finding constellations…")
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                // List of what was found, with the matching colour
                ForEach(constellations.indices, id: \.self) { i in
                    let c = constellations[i]
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(colours[i % colours.count]).frame(width: 12, height: 12)
                            Text(c.name).font(.headline)
                        }
                        Text(starNames(of: c)).font(.subheadline).foregroundStyle(.secondary)
                        if let fact = c.fact {
                            Text(fact).font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadAndAnalyse(newItem) }
        }
    }

    // Draws lines, star dots and the constellation name on top of the photo
    @ViewBuilder
    private func overlay(size: CGSize) -> some View {
        ZStack {
            ForEach(constellations.indices, id: \.self) { i in
                let c = constellations[i]
                let colour = colours[i % colours.count]

                // Lines between stars
                Path { path in
                    for j in 0..<c.lines.count {
                        let pair = c.lines[j]
                        // Skip bad pairs instead of crashing
                        if pair.count == 2,
                           pair[0] >= 0, pair[0] < c.stars.count,
                           pair[1] >= 0, pair[1] < c.stars.count {
                            path.move(to: point(c.stars[pair[0]], size))
                            path.addLine(to: point(c.stars[pair[1]], size))
                        }
                    }
                }
                .stroke(colour, lineWidth: 2)

                // Star dots
                ForEach(c.stars.indices, id: \.self) { k in
                    Circle()
                        .fill(colour)
                        .frame(width: 8, height: 8)
                        .position(point(c.stars[k], size))
                }

                // Name label next to the first star
                if c.stars.count > 0 {
                    Text(c.name)
                        .font(.caption.bold())
                        .padding(4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(colour)
                        .position(x: point(c.stars[0], size).x,
                                  y: point(c.stars[0], size).y - 18)
                }
            }
        }
    }

    // Converts Gemini's 0...1 position into points on the displayed image
    private func point(_ star: Star, _ size: CGSize) -> CGPoint {
        CGPoint(x: star.x * size.width, y: star.y * size.height)
    }

    private func starNames(of c: Constellation) -> String {
        var names: [String] = []
        for i in 0..<c.stars.count {
            if let n = c.stars[i].name { names.append(n) }
        }
        return names.isEmpty ? "" : "Stars: " + names.joined(separator: ", ")
    }

    private func loadAndAnalyse(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        photo = image
        constellations = []
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let json = try await GeminiService().identifyConstellations(in: image)
            let result = try JSONDecoder().decode(GeminiResult.self, from: Data(json.utf8))
            constellations = result.constellations
            if constellations.isEmpty {
                errorMessage = "No constellations found — try a clearer photo."
            }
        } catch {
            errorMessage = "Something went wrong: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ConstellationView()
}
