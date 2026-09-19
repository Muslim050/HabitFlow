import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import HabitCore

/// Export and restore. Personal history is irreplaceable and lives only on this device until
/// iCloud sync exists, so this is the only thing standing between a reinstall and losing it.
struct BackupSection: View {
    @Environment(AppEnvironment.self) private var env

    @State private var share: SharePayload?
    @State private var importing = false
    @State private var report: ImportReport?

    var body: some View {
        Section {
            Button { export(.json) } label: {
                Label("Export backup", systemImage: "square.and.arrow.up")
            }
            Button { export(.csv) } label: {
                Label("Export spreadsheet", systemImage: "tablecells")
            }
            Button { importing = true } label: {
                Label("Restore from a backup", systemImage: "square.and.arrow.down")
            }
            // Presentation modifiers hang off a row rather than the Section: a Section is not a
            // view in the presentation hierarchy, and sheets attached to one misbehave in a Form.
            .sheet(item: $share) { payload in
                ShareSheet(items: [payload.url])
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                restore(from: result)
            }
            .alert(report?.title ?? "", isPresented: Binding(get: { report != nil },
                                                             set: { if !$0 { report = nil } })) {
                Button("OK", role: .cancel) { report = nil }
            } message: {
                Text(report?.message ?? "")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("The backup holds every habit, day and pause, and restores them exactly. The spreadsheet is one row per day, for reading elsewhere.")
        }
    }

    // MARK: Export

    private enum Format { case json, csv }

    private func export(_ format: Format) {
        do {
            let day = env.currentDayKey
            let (data, name): (Data, String) = switch format {
            case .json: (try BackupExporter.json(from: env.repository),
                         BackupExporter.fileName(for: day, extension: "json"))
            case .csv: (try BackupExporter.csv(from: env.repository),
                        BackupExporter.fileName(for: day, extension: "csv"))
            }
            // A real file rather than raw data, so the share sheet offers Files and Mail
            // rather than only the clipboard.
            let url = URL.temporaryDirectory.appending(path: name)
            try data.write(to: url, options: .atomic)
            share = SharePayload(url: url)
        } catch {
            Log.app.error("Export failed: \(error.localizedDescription)")
            report = ImportReport(title: String(localized: "Export failed"),
                                  message: error.localizedDescription)
        }
    }

    // MARK: Restore

    private func restore(from result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            // A file picked outside the sandbox needs the door held open while it is read.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let summary = try BackupImporter.merge(json: try Data(contentsOf: url), into: env.repository)
            env.engine.pausesDidChange()
            env.habitDidChange(nil)
            report = ImportReport(title: String(localized: "Restored"), message: describe(summary))
        } catch {
            Log.app.error("Restore failed: \(error.localizedDescription)")
            report = ImportReport(title: String(localized: "Could not read that file"),
                                  message: error.localizedDescription)
        }
    }

    private func describe(_ summary: ImportSummary) -> String {
        guard !summary.isEmpty else {
            return String(localized: "Everything in that file was already here.")
        }
        var parts: [String] = []
        let habits = summary.habitsInserted + summary.habitsUpdated
        let logs = summary.logsInserted + summary.logsUpdated
        if habits > 0 { parts.append(String(localized: "\(habits) habits")) }
        if logs > 0 { parts.append(String(localized: "\(logs) days")) }
        if summary.pausesInserted > 0 { parts.append(String(localized: "\(summary.pausesInserted) pauses")) }
        return parts.joined(separator: ", ")
    }
}

private struct SharePayload: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct ImportReport: Identifiable {
    let title: String
    let message: String
    var id: String { title + message }
}

/// SwiftUI's `ShareLink` wants its content up front; building the whole archive on every render
/// of Settings would be wasteful, so the sheet is presented once the file exists.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
