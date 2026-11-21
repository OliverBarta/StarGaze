//
//  StargazingSpotsView.swift
//  Stargazing Spots feature — ENTRY VIEW
//
//  Drop into a tab:
//      StargazingSpotsView()
//          .tabItem { Label("Stargazing", systemImage: "sparkles") }
//
//  Shows the light-pollution map, the 5 best dark spots within 25/50/100 km,
//  tonight's clouds and Moon with a time slider, favourites, and a detail card
//  with directions. Uses the London, ON test location until switched off.
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
}

// MARK: - Entry view

struct StargazingSpotsView: View {
    @State private var lightService = LightPollutionService(remoteBaseURL: StargazingConfig.tilesBaseURL)
    @State private var tonight = TonightConditionsService()
    @State private var location = LocationProvider(useTestLocation: true)
    @State private var favorites = FavoriteSpotsStore()

    @State private var radius: SearchRadius = .km50
    @State private var spots: [StargazingSpot] = []
    @State private var selectedSpot: StargazingSpot?
    @State private var drives: [String: DriveInfo] = [:]
    @State private var loadingDrives: Set<String> = []
    @State private var isSearching = false

    @State private var hours: [Date] = TonightConditionsService.nightHours()
    @State private var hourIndex: Double = 0

    @State private var showClouds = true
    @State private var showLightPollution = true
    @State private var showFavorites = false
    @State private var pendingFavorite: StargazingSpot?

    private var selectedTime: Date {
        guard !hours.isEmpty else { return .now }
        return hours[min(hours.count - 1, max(0, Int(hourIndex.rounded())))]
    }

    /// Re-run the search whenever the location (to ~100 m) or radius changes.
    private nonisolated struct SearchKey: Equatable {
        let lat: Int, lon: Int, radius: Int
    }
    private var searchKey: SearchKey? {
        guard let c = location.coordinate else { return nil }
        return SearchKey(lat: Int(c.latitude * 1000), lon: Int(c.longitude * 1000), radius: radius.rawValue)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                LightPollutionMapView(
                    service: lightService,
                    tileCount: lightService.tiles.count,
                    centre: location.coordinate,
                    isTestLocation: location.useTestLocation,
                    radiusKm: radius.km,
                    spots: spots,
                    favorites: favorites.spots,
                    cloudCells: tonight.cloudCells(at: selectedTime),
                    showClouds: showClouds,
                    showLightPollution: showLightPollution,
                    selectedSpot: $selectedSpot,
                    onRegionChange: { centre, visibleKm in
                        Task { await lightService.loadTiles(around: centre, radiusKm: min(visibleKm, 300)) }
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                bottomPanel
            }
            .safeAreaInset(edge: .top) { topBar }
            .navigationTitle("Stargazing Spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $selectedSpot) { spot in
                detail(for: spot)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showFavorites, onDismiss: {
                if let spot = pendingFavorite {
                    pendingFavorite = nil
                    selectedSpot = spot
                }
            }) {
                favoritesList
            }
            .task(id: searchKey) { await runSearch() }
            .onAppear {
                hours = TonightConditionsService.nightHours()
                hourIndex = 0
            }
        }
    }

    // MARK: - Search

    private func runSearch() async {
        guard let centre = location.coordinate else { return }
        isSearching = true
        defer { isSearching = false }

        await lightService.loadTiles(around: centre, radiusKm: radius.km)
        spots = lightService.findDarkSpots(near: centre, radiusKm: radius.km)
        drives = [:]

        await tonight.refreshClouds(around: centre, radiusKm: radius.km)

        for spot in spots {
            await loadDrive(to: spot, from: centre)
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

    // MARK: - Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: location.useTestLocation ? "mappin.circle.fill" : "location.fill")
                    .foregroundStyle(.secondary)
                Text(location.displayName).font(.subheadline.weight(.medium))
                Spacer()
                Toggle("Test location", isOn: $location.useTestLocation)
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
            Picker("Radius", selection: $radius) {
                ForEach(SearchRadius.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if let message = statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var statusMessage: String? {
        if location.coordinate == nil {
            return location.status == .denied
                ? "Location is off. Allow it in Settings, or use the test location."
                : "Waiting for your location…"
        }
        if isSearching && spots.isEmpty { return "Finding dark spots…" }
        if spots.isEmpty && !lightService.missingTiles.isEmpty {
            return "No light-pollution data here yet. Connect to the internet once to download it."
        }
        if spots.isEmpty { return "No dark land spots within \(radius.label)." }
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
            spotCards
            legend
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var tonightSummary: some View {
        let centre = location.coordinate ?? TestLocation.londonON
        let sky = tonight.sky(at: centre, time: selectedTime)
        let cloud = tonight.cloudCover(at: centre, time: selectedTime)
        return HStack(spacing: 12) {
            Text(selectedTime.formatted(date: .omitted, time: .shortened)).font(.headline.monospacedDigit())
            Label("\(Int((sky.moonIllumination * 100).rounded()))% \(sky.moonIsUp ? "up" : "set")",
                  systemImage: sky.moonIsUp ? "moon.fill" : "moon.zzz")
            Label(cloud.map { "\(Int($0.rounded()))%" } ?? "–", systemImage: "cloud.fill")
            if !sky.isAstronomicallyDark {
                Label("twilight", systemImage: "sun.horizon")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var spotCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(spots.enumerated()), id: \.element.id) { index, spot in
                    Button { selectedSpot = spot } label: { spotCard(rank: index + 1, spot: spot) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func spotCard(rank: Int, spot: StargazingSpot) -> some View {
        let score = tonight.score(for: spot, at: selectedTime)
        let km = drives[spot.id]?.distanceKm ?? spot.straightLineKm
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(rank)")
                    .font(.caption.bold())
                    .frame(width: 22, height: 22)
                    .background(Bortle.color(spot.bortle), in: Circle())
                    .foregroundStyle(spot.bortle <= 4 ? Color.white : Color.black)
                Text("Bortle \(spot.bortle)").font(.subheadline.weight(.semibold))
            }
            Text("Tonight \(score.score)").font(.caption.weight(.medium))
            Text(StargazingFormat.km(km) + (drives[spot.id] == nil ? " away" : " drive"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 120, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            Text("Light pollution: Falchi et al. 2016 (CC BY-NC) · Weather: Open-Meteo")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Toggle("Light pollution", isOn: $showLightPollution)
                Toggle("Clouds", isOn: $showClouds)
            } label: {
                Image(systemName: "square.3.layers.3d")
            }
            .accessibilityLabel("Map layers")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showFavorites = true } label: {
                Image(systemName: favorites.spots.isEmpty ? "star" : "star.fill")
            }
            .accessibilityLabel("Favourites")
        }
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
            isFavorite: favorites.contains(spot),
            onToggleFavorite: { favorites.toggle(spot) },
            onDirections: { Driving.openInMaps(spot) }
        )
        .task {
            // favourites outside the current top 5 don't have a driving distance yet
            if let c = location.coordinate { await loadDrive(to: spot, from: c) }
        }
    }

    private var favoritesList: some View {
        NavigationStack {
            List {
                if favorites.spots.isEmpty {
                    ContentUnavailableView("No favourites yet", systemImage: "star",
                                           description: Text("Tap the star on a spot to save it."))
                }
                ForEach(favorites.spots) { spot in
                    Button {
                        pendingFavorite = spot
                        showFavorites = false
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(Bortle.color(spot.bortle)).frame(width: 14, height: 14)
                            VStack(alignment: .leading) {
                                Text("Bortle \(spot.bortle) · \(Bortle.label(spot.bortle))")
                                Text(String(format: "%.4f, %.4f", spot.latitude, spot.longitude))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { favorites.remove(atOffsets: $0) }
            }
            .navigationTitle("Favourites")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFavorites = false }
                }
            }
        }
    }
}

#Preview {
    StargazingSpotsView()
}
