import CoreLocation
import MapKit
import SwiftUI

struct PlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var radius: Double
    @Binding var placeName: String

    @State private var position: MapCameraPosition = .automatic
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !results.isEmpty {
                    List(results, id: \.self) { item in
                        Button {
                            select(item)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? String(localized: "Unnamed"))
                                if let subtitle = item.placemark.title {
                                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }

                MapReader { proxy in
                    Map(position: $position) {
                        if let coordinate {
                            Annotation(placeName.isEmpty ? String(localized: "Place") : placeName, coordinate: coordinate) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.red)
                            }
                            MapCircle(center: coordinate, radius: radius)
                                .foregroundStyle(.blue.opacity(0.15))
                                .stroke(.blue, lineWidth: 1)
                        }
                        UserAnnotation()
                    }
                    .mapControls { MapUserLocationButton() }
                    .onTapGesture { point in
                        if let tapped = proxy.convert(point, from: .local) {
                            coordinate = tapped
                            if placeName.isEmpty { placeName = String(localized: "Pinned place") }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Place name", text: $placeName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("Radius \(Int(radius)) m")
                        Slider(value: $radius, in: 100...500, step: 25)
                    }
                    Text("Tap the map or search. Radius below 100 m is unreliable on iOS.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .searchable(text: $query, prompt: "Search a place")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("Choose a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(coordinate == nil)
                }
            }
            .onAppear {
                if let coordinate {
                    position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
                }
            }
        }
    }

    private func select(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        coordinate = c
        placeName = item.name ?? placeName
        results = []
        position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 1200, longitudinalMeters: 1200))
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let coordinate {
            request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        }
        do {
            results = try await MKLocalSearch(request: request).start().mapItems
        } catch {
            results = []
        }
    }
}
