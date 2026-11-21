//
//  SpotDetailView.swift
//  Stargazing Spots feature
//
//  The card shown when a spot is tapped: darkness (Bortle + SQM), Tonight's
//  score with its reason, clouds / Moon / twilight, distance (straight-line
//  and driving) and a Directions button for Apple Maps.
//

import SwiftUI

struct SpotDetailView: View {
    let spot: StargazingSpot
    let rank: Int?                         // nil if the spot left the top 3 while the card was open
    let straightLineKm: Double             // from the current search centre
    let drive: DriveInfo?
    let isLoadingDrive: Bool
    let tonight: TonightScore
    let selectedTime: Date
    let bestTime: Date?
    let bestScore: TonightScore?
    let onDirections: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                darknessRow
                tonightCard
                conditionsGrid
                distanceSection
                Button(action: onDirections) {
                    Label("Directions in Apple Maps", systemImage: "car.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text(String(format: "%.4f, %.4f", spot.latitude, spot.longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text(rank.map { "Spot \($0)" } ?? "Spot")
                .font(.title2.bold())
            Spacer()
            ShareLink(item: mapsURL,
                      subject: Text("Stargazing spot"),
                      message: Text("Stargazing spot: Bortle \(spot.bortle), \(Bortle.label(spot.bortle).lowercased())")) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
            }
            .accessibilityLabel("Share spot")
        }
    }

    /// Apple Maps link to the spot, opens a pin on any device (or the web on non-Apple ones).
    private var mapsURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        let ll = String(format: "%.5f,%.5f", spot.latitude, spot.longitude)
        components.queryItems = [
            .init(name: "ll", value: ll),
            .init(name: "q", value: "Stargazing spot"),
        ]
        return components.url!
    }

    private var darknessRow: some View {
        HStack(spacing: 12) {
            Text("Bortle \(spot.bortle)")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Bortle.color(spot.bortle), in: Capsule())
                .foregroundStyle(spot.bortle <= 4 ? Color.white : Color.black)
            VStack(alignment: .leading, spacing: 2) {
                Text(Bortle.label(spot.bortle)).font(.subheadline.weight(.semibold))
                Text(StargazingFormat.sqm(spot.sqm)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var tonightCard: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(tonight.score) / 100)
                    .stroke(scoreColor(tonight.score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(tonight.score)").font(.title.bold().monospacedDigit())
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tonight's score at \(selectedTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(tonight.reason).font(.subheadline.weight(.medium))
                if let bestTime, let bestScore, bestScore.score > tonight.score {
                    Text("Best tonight: \(bestTime.formatted(date: .omitted, time: .shortened)) (score \(bestScore.score))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var conditionsGrid: some View {
        let sky = tonight.sky
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Image(systemName: "cloud.fill").foregroundStyle(.secondary)
                Text("Clouds")
                Text(tonight.cloudPercent.map { "\(Int($0.rounded()))%" } ?? "No forecast (offline)")
                    .foregroundStyle(.secondary)
            }
            GridRow {
                Image(systemName: "moon.fill").foregroundStyle(.secondary)
                Text("Moon")
                Text("\(sky.moonPhaseName), \(Int((sky.moonIllumination * 100).rounded()))% lit, "
                     + (sky.moonIsUp ? "up" : "below horizon"))
                    .foregroundStyle(.secondary)
            }
            GridRow {
                Image(systemName: "sun.horizon.fill").foregroundStyle(.secondary)
                Text("Sky")
                Text(skyText(sky)).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(StargazingFormat.km(straightLineKm)) straight line", systemImage: "location.north.line")
            if let drive {
                Label("\(StargazingFormat.km(drive.distanceKm)) by road · about \(StargazingFormat.minutes(drive.minutes))",
                      systemImage: "car")
            } else if isLoadingDrive {
                Label("Checking driving distance…", systemImage: "car")
                    .foregroundStyle(.secondary)
            } else {
                Label("Driving distance needs internet", systemImage: "car")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    // MARK: Helpers

    private func scoreColor(_ score: Int) -> Color {
        score >= 70 ? .green : score >= 40 ? .yellow : .red
    }

    private func skyText(_ sky: SkyAstronomy) -> String {
        if sky.sunAltitudeDeg > -6 { return "Too bright (Sun barely down)" }
        if sky.sunAltitudeDeg > -18 { return "Twilight" }
        return "Fully dark"
    }
}
