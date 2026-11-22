//
//  SkyReadingTestView.swift
//  StarGaze
//

import PhotosUI
import SwiftUI

/// Runs Gemini's sky check on a photo from the library. For testing, and as an indoor demo.
/// Library photos are never live measurements, so they never count toward the light-pollution map.
struct SkyReadingTestView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var analysis: SkyAnalysis?
    @State private var errorMessage: String?
    @State private var isAnalyzing = false

    init(image: UIImage? = nil, analysis: SkyAnalysis? = nil, errorMessage: String? = nil) {
        _image = State(initialValue: image)
        _analysis = State(initialValue: analysis)
        _errorMessage = State(initialValue: errorMessage)
    }

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(image == nil ? "Choose a sky photo" : "Choose another photo", systemImage: "photo.on.rectangle")
                }
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.imageCornerRadius, style: .continuous))
                        .accessibilityLabel("Selected sky photo")
                }
            } footer: {
                Text("Library photos are for testing only and never appear on the light-pollution map.")
            }

            if isAnalyzing {
                Section {
                    HStack(spacing: Metrics.small) {
                        SwiftUI.ProgressView()
                        Text("Analyzing sky…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    if image != nil {
                        Button("Try Again") {
                            Task { await analyze() }
                        }
                    }
                }
            } else if let analysis {
                result(analysis)
            }
        }
        .navigationTitle("Analyze a Sky Photo")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    private func result(_ analysis: SkyAnalysis) -> some View {
        let level = FindLevel(analysis: analysis)
        let issues = SkyReadingIssue.issues(from: analysis)
        return Section {
            LabeledContent("Result") {
                Label(level.label, systemImage: level == .spotted ? "checkmark.seal.fill" : "mappin.circle")
                    .foregroundStyle(level == .spotted ? Rarity.legendary.color : .secondary)
            }
            LabeledContent("Night sky", value: analysis.isNightSky ? "Yes" : "No")
            LabeledContent("Clouds", value: analysis.cloudCover.label)
            LabeledContent("Obstructions", value: analysis.obstructions.isEmpty ? "None" : analysis.obstructions.map(\.label).joined(separator: ", "))
            LabeledContent("Quality", value: issues.isEmpty ? "Usable" : issues.map(\.label).joined(separator: ", "))
            LabeledContent("Visible stars", value: "\(analysis.estimatedVisibleStars)")
            LabeledContent("Sky brightness", value: "\(analysis.skyBrightness) of 9")
            LabeledContent("Confidence", value: analysis.confidence.label)
            Text(analysis.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            Text("Gemini's check")
        } footer: {
            Text("Spotted needs a night sky that isn't overcast, with at least 3 stars visible.")
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        analysis = nil
        errorMessage = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let loaded = UIImage(data: data) else {
            image = nil
            errorMessage = GeminiError.unreadableImage.localizedDescription
            return
        }
        image = loaded
        await analyze()
    }

    private func analyze() async {
        guard let image, !isAnalyzing else { return }
        isAnalyzing = true
        errorMessage = nil
        analysis = nil
        defer { isAnalyzing = false }
        do {
            analysis = try await GeminiService().analyzeSky(image)
        } catch let error as GeminiError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = GeminiError.badResponse.localizedDescription
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        SkyReadingTestView()
    }
}

#Preview("Spotted") {
    NavigationStack {
        SkyReadingTestView(image: UIImage(systemName: "moon.stars.fill"), analysis: .previewSpotted)
    }
}

#Preview("Located") {
    NavigationStack {
        SkyReadingTestView(image: UIImage(systemName: "building.2.fill"), analysis: .previewLocated)
    }
}

#Preview("Error") {
    NavigationStack {
        SkyReadingTestView(image: UIImage(systemName: "moon.stars.fill"), errorMessage: GeminiError.rateLimited.localizedDescription)
    }
}
