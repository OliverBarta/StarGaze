//
//  StargazingSpotsView.swift
//  Stargazing Spots feature — ENTRY VIEW
//
//  Drop into a tab:
//      StargazingSpotsView()
//          .tabItem { Label("Stargazing", systemImage: "sparkles") }
//
//  Shows the light-pollution map, the 3 best spots (darkness + cloud) within 25 km,
//  tonight's clouds and Moon with a time slider, and a detail card
//  with directions. Starts at the last saved location, then switches to live GPS.
//

import SwiftUI
import CoreLocation

// MARK: - Configuration

enum StargazingConfig {
    /// All 1,130 world tiles + index.json are bundled in the app (LightTiles folder),
    /// so this stays nil and everything works offline. Only set it if you later
    /// move the tiles to hosting, e.g.
    ///     URL(string: "https://<github-user>.github.io/<repo>/LightTiles/")
    static let tilesBaseURL: URL? = nil

    /// How far from the user to look for dark spots.
    static let searchRadiusKm: Double = 25
}

// MARK: - Entry view

struct StargazingSpotsView: View {
    @Environment(SupabaseService.self) private var supabase
    @State private var lightService = LightPollutionService(remoteBaseURL: StargazingConfig.tilesBaseURL)
    @State private var tonight = TonightConditionsService()
    @State private var location = SpotsLocationProvider()

    @State private var spots: [StargazingSpot] = []
    @State private var selectedSpot: StargazingSpot?
    @State private var drives: [String: DriveInfo] = [:]
    @State private var loadingDrives: Set<String> = []
    @State private var isSearching = false
    @State private var isReloading = false
    /// Set by the reload button so the next search also skips the 30-minute cloud cache.
    @State private var forceNextSearch = false

    @State private var hours: [Date] = TonightConditionsService.nightHours()
    @State private var hourIndex: Double = 0

    @State private var showClouds = true
    @State private var showLightPollution = true
    @State private var showHeatmap = false
    @State private var lightReadings: [LightReading] = []
    @State private var isLoadingReadings = false
    @State private var readingsError: String?

    private var selectedTime: Date {
        guard !hours.isEmpty else { return .now }
        return hours[min(hours.count - 1, max(0, Int(hourIndex.rounded())))]
    }

    /// Re-run the search whenever the location changes (to ~100 m) or a new GPS fix
    /// arrives, even one at the same place, so the first fix after launch reloads everything.
    private nonisolated struct SearchKey: Equatable {
        let lat: Int, lon: Int, fix: Int
    }
    private var searchKey: SearchKey? {
        guard let c = location.coordinate else { return nil }
        return SearchKey(lat: Int(c.latitude * 1000), lon: Int(c.longitude * 1000), fix: location.fixCount)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                LightPollutionMapView(
                    service: lightService,
                    tileCount: lightService.tiles.count,
                    centre: location.coordinate,
                    isSavedLocation: location.isUsingSavedLocation,
                    radiusKm: StargazingConfig.searchRadiusKm,
                    spots: spots,
                    cloudField: tonight.cloudField(at: selectedTime),
                    showClouds: showClouds,
                    showLightPollution: showLightPollution,
                    lightReadings: lightReadings,
                    showHeatmap: showHeatmap,
                    selectedSpot: $selectedSpot,
                    onRegionChange: { centre, visibleKm in
                        Task { await lightService.loadTiles(around: centre, radiusKm: min(visibleKm, 300)) }
                    }
                )
                .ignoresSafeArea()      // edge to edge, under the navigation bar

                bottomPanel
            }
            .safeAreaInset(edge: .top) { statusBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar { toolbarContent }
            .sheet(item: $selectedSpot) { spot in
                detail(for: spot)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task(id: searchKey) { await runSearch() }
            .task(id: showHeatmap) {
                if showHeatmap && lightReadings.isEmpty { await loadReadings() }
            }
            .onChange(of: selectedTime) {
                // clouds differ by hour, so the best spots can too
                pickSpots()
                Task { await loadDrives() }
            }
            .onAppear {
                hours = TonightConditionsService.nightHours()
                hourIndex = 0
            }
        }
    }

    // MARK: - Search

    private func runSearch() async {
        let force = forceNextSearch
        forceNextSearch = false
        // a reload's search is the forced one; the reload button stays disabled until it ends
        defer { if force { isReloading = false } }
        guard let centre = location.coordinate else { return }
        isSearching = true
        defer { isSearching = false }

        await lightService.loadTiles(around: centre, radiusKm: StargazingConfig.searchRadiusKm)
        drives = [:]
        pickSpots()     // darkness only (or the cached forecast) so pins show up right away

        await tonight.refreshClouds(around: centre, radiusKm: StargazingConfig.searchRadiusKm, force: force)
        pickSpots()     // again, now with the cloud forecast

        await loadDrives()
    }

    /// Chooses the spots from darkness and the cloud forecast at the selected hour.
    private func pickSpots() {
        guard let centre = location.coordinate else { return }
        let time = selectedTime
        spots = lightService.findDarkSpots(near: centre, radiusKm: StargazingConfig.searchRadiusKm,
                                           cloudCover: { tonight.cloudCover(at: $0, time: time) })
    }

    private func loadDrives() async {
        guard let centre = location.coordinate else { return }
        for spot in spots {
            await loadDrive(to: spot, from: centre)
        }
    }

    /// Reload button: re-check the location, then reload everything around it.
    private func reload() async {
        isReloading = true      // cleared when the forced search finishes (see runSearch)
        hours = TonightConditionsService.nightHours()
        hourIndex = 0
        forceNextSearch = true
        // A new fix changes `searchKey`, which re-runs the search by itself.
        // Without one (denied, failed, timed out), reload around the current location.
        if await !location.refresh() {
            await runSearch()
        }
    }

    /// Fetches the heatmap's readings from Supabase the first time the layer is turned on.
    private func loadReadings() async {
        guard !isLoadingReadings else { return }
        isLoadingReadings = true
        defer { isLoadingReadings = false }
        do {
            lightReadings = try await supabase.fetchLightReadings()
            readingsError = lightReadings.isEmpty ? "No light readings yet." : nil
        } catch is CancellationError {
        } catch {
            readingsError = "Couldn't load light readings: \(error.localizedDescription)"
        }
    }

    private func loadDrive(to spot: StargazingSpot, from centre: CLLocationCoordinate2D) async {
        guard drives[spot.id] == nil, !loadingDrives.contains(spot.id) else { return }
        loadingDrives.insert(spot.id)
        if let info = await Driving.info(from: centre, to: spot) {
            drives[spot.id] = info
        }
        loadingDrives.remove(spot.id)
    }

    // MARK: - Status bar

    /// Strip under the navigation bar, only shown when there's something to say.
    @ViewBuilder
    private var statusBar: some View {
        if let message = statusMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.regularMaterial)
        }
    }

    private var statusMessage: String? {
        if location.coordinate == nil {
            return location.status == .denied
                ? "Location is off. Allow it in Settings to find spots near you."
                : "Waiting for your location…"
        }
        if showHeatmap {
            if isLoadingReadings { return "Loading light readings…" }
            if let readingsError { return readingsError }
        }
        if isSearching && spots.isEmpty { return "Finding dark spots…" }
        if spots.isEmpty && !lightService.missingTiles.isEmpty {
            return "No light-pollution data here yet. Connect to the internet once to download it."
        }
        if spots.isEmpty { return "No dark land spots within \(Int(StargazingConfig.searchRadiusKm)) km." }
        if let error = tonight.lastError { return error }
        return nil
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            tonightSummary
            if hours.count > 1 {
                Slider(value: $hourIndex, in: 0...Double(hours.count - 1), step: 1) {
                    Text("Time")
                } minimumValueLabel: {
                    Text(hours.first!.formatted(date: .omitted, time: .shortened)).font(.caption2)
                } maximumValueLabel: {
                    Text(hours.last!.formatted(date: .omitted, time: .shortened)).font(.caption2)
                }
            }
            if showLightPollution {
                legend
            }
            if showHeatmap {
                heatmapLegend
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var tonightSummary: some View {
        HStack(spacing: 12) {
            Text(selectedTime.formatted(date: .omitted, time: .shortened)).font(.headline.monospacedDigit())
            // nothing to show until there's a location (first launch, before GPS answers)
            if let centre = location.coordinate {
                let sky = tonight.sky(at: centre, time: selectedTime)
                let cloud = tonight.cloudCover(at: centre, time: selectedTime)
                Label("\(Int((sky.moonIllumination * 100).rounded()))% \(sky.moonIsUp ? "up" : "set")",
                      systemImage: sky.moonIsUp ? "moon.fill" : "moon.zzz")
                Label(cloud.map { "\(Int($0.rounded()))%" } ?? "–", systemImage: "cloud.fill")
                if !sky.isAstronomicallyDark {
                    Label("twilight", systemImage: "sun.horizon")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ForEach(Bortle.legend.indices, id: \.self) { i in
                    let item = Bortle.legend[i]
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Bortle.color(item.range.lowerBound))
                            .frame(width: 12, height: 12)
                        Text(item.title)
                    }
                }
            }
            .font(.caption2)
//            Text("Light pollution: Falchi et al. 2016 (CC BY-NC) · Weather: Open-Meteo")
//                .font(.system(size: 9))
//                .foregroundStyle(.secondary)
        }
    }

    private var heatmapLegend: some View {
        HStack(spacing: 8) {
            Text("Readings: dark")
            LinearGradient(
                colors: LightReadingsRenderer.ramp.map { Color(red: $0.0, green: $0.1, blue: $0.2) },
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 10)
            .clipShape(Capsule())
            Text("bright")
        }
        .font(.caption2)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            layerButton("Clouds", systemImage: "cloud.fill", isOn: $showClouds)
            layerButton("Light pollution", systemImage: "lightbulb.fill", isOn: $showLightPollution)
            layerButton("Light readings heatmap", systemImage: "flame.fill", isOn: $showHeatmap)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isReloading)
            .accessibilityLabel("Reload location and spots")
        }
    }

    /// Icon-only toggle for a map layer: tinted when the layer is shown, grey when hidden.
    private func layerButton(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: systemImage)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
        }
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "Shown" : "Hidden")
    }

    // MARK: - Sheets

    @ViewBuilder
    private func detail(for spot: StargazingSpot) -> some View {
        let centre = location.coordinate ?? spot.coordinate
        let straightKm = LightPollutionService.distanceKm(centre.latitude, centre.longitude,
                                                          spot.latitude, spot.longitude)
        let best = tonight.bestHour(for: spot, in: hours)
        SpotDetailView(
            spot: spot,
            rank: spots.firstIndex(where: { $0.id == spot.id }).map { $0 + 1 },
            straightLineKm: straightKm,
            drive: drives[spot.id],
            isLoadingDrive: loadingDrives.contains(spot.id),
            tonight: tonight.score(for: spot, at: selectedTime),
            selectedTime: selectedTime,
            bestTime: best?.time,
            bestScore: best?.score,
            onDirections: { Driving.openInMaps(spot) }
        )
        .task {
            // in case a reload cleared the driving distances while the card is open
            if let c = location.coordinate { await loadDrive(to: spot, from: c) }
        }
    }
}

#Preview {
    StargazingSpotsView()
        .environment(SupabaseService.preview())
}
