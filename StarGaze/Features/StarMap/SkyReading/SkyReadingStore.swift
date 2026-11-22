import Foundation
import Observation
import os

/// Sky readings saved on the device (Application Support, snake_case JSON). Reliable camera
/// readings are inserted into Supabase's `light_readings`; failed inserts stay pending and are
/// retried on launch and after sign-in. Nothing here can block collecting.
@Observable
final class SkyReadingStore {
    private(set) var readings: [SkyPhotoReading] = []

    /// Called after a reading is saved (ContentView uses it to upload).
    @ObservationIgnored var onAdd: ((SkyPhotoReading) -> Void)?

    @ObservationIgnored private var isUploading = false
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let logger = Logger(subsystem: "com.oliver.StarGaze", category: "SkyReading")

    init(fileURL: URL? = SkyReadingStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    var pendingUploads: [SkyPhotoReading] { readings.filter(\.needsUpload) }

    func add(_ reading: SkyPhotoReading) {
        readings.append(reading)
        save()
        onAdd?(reading)
    }

    /// Inserts every pending reading, oldest first. Stops at the first failure and tries again next time.
    func uploadPending(_ insert: (SkyPhotoReading) async throws -> Void) async {
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        for reading in pendingUploads {
            do {
                try await insert(reading)
                if let index = readings.firstIndex(where: { $0.id == reading.id }) {
                    readings[index].uploaded = true
                    save()
                }
            } catch {
                logger.error("Light reading upload failed, will retry: \(String(describing: error))")
                return
            }
        }
    }

    // MARK: Saving

    static var defaultFileURL: URL? {
        guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return folder.appending(path: "StarGaze/sky-readings.json")
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try encoder.encode(readings).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Couldn't save sky readings: \(String(describing: error))")
        }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        readings = (try? decoder.decode([SkyPhotoReading].self, from: data)) ?? []
    }
}
