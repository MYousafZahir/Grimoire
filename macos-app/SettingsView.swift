import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var noteManager: NoteManager

    // Default includes trailing slash so relative API paths resolve correctly
    @AppStorage("backendURL") private var backendURL: String = "http://127.0.0.1:8000/"
    @AppStorage("debounceDelay") private var debounceDelay: Double = 0.5
    @AppStorage("chunkSize") private var chunkSize: String = "300"
    @AppStorage("maxBacklinks") private var maxBacklinks: String = "10"
    @AppStorage("autoSave") private var autoSave: Bool = true
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 2.0
    @AppStorage("showPreview") private var showPreview: Bool = false
    @AppStorage("theme") private var theme: String = "system"

    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: String? = nil
    @State private var showConnectionAlert: Bool = false

    var body: some View {
        TabView {
            // General Settings
            Form {
                Section("Backend Configuration") {
                    HStack {
                        Text("Backend URL:")
                        TextField("Backend URL", text: $backendURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button("Test") {
                            testBackendConnection()
                        }
                        .disabled(isTestingConnection || backendURL.isEmpty)

                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.leading, 4)
                        }
                    }

                    if let result = connectionTestResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("Success") ? .green : .red)
                    }
                }

                Section("Editor Settings") {
                    Toggle("Auto-save", isOn: $autoSave)

                    if autoSave {
                        HStack {
                            Text("Auto-save interval:")
                            Slider(value: $autoSaveInterval, in: 1.0...10.0, step: 0.5)
                            Text("\(autoSaveInterval, specifier: "%.1f")s")
                                .frame(width: 40)
                        }
                    }

                    Toggle("Show markdown preview", isOn: $showPreview)

                    Picker("Theme", selection: $theme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
            }
            .tabItem {
                Label("General", systemImage: "gear")
            }
            .padding()

            // Search Settings
            Form {
                Section("Semantic Search") {
                    HStack {
                        Text("Debounce delay:")
                        Slider(value: $debounceDelay, in: 0.1...2.0, step: 0.1)
                        Text("\(debounceDelay, specifier: "%.1f")s")
                            .frame(width: 40)
                    }
                    .help("Delay before searching after typing stops")

                    HStack {
                        Text("Max backlinks:")
                        TextField("10", text: $maxBacklinks)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                    .help("Maximum number of backlinks to display")

                    HStack {
                        Text("Chunk size:")
                        TextField("300", text: $chunkSize)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("characters")
                    }
                    .help("Size of text chunks for semantic analysis")
                }

                Section("Performance") {
                    Button("Clear Search Cache") {
                        clearSearchCache()
                    }

                    Button("Rebuild Index") {
                        rebuildIndex()
                    }
                }
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .padding()

            // About
            VStack(spacing: 20) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)

                Text("Grimoire")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Semantic Notes for macOS")
                    .font(.title2)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Version 1.0.0")
                    Text("Build 1")
                    Text("© 2024 Grimoire Project")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Divider()
                    .frame(width: 200)

                VStack(alignment: .leading, spacing: 4) {
                    Text("A note-taking application with automatic semantic backlinks.")
                        .multilineTextAlignment(.center)

                    Text("All data is stored locally on your machine.")
                        .multilineTextAlignment(.center)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: 300)

                Spacer()

                Button("View Documentation") {
                    openDocumentation()
                }

                Button("Report Issue") {
                    reportIssue()
                }
            }
            .padding(40)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 500, height: 400)
        .alert("Connection Test", isPresented: $showConnectionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let result = connectionTestResult {
                Text(result)
            }
        }
    }

    private func testBackendConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        guard let url = URL(string: backendURL) else {
            connectionTestResult = "Invalid URL format"
            isTestingConnection = false
            showConnectionAlert = true
            return
        }

        let testURL = url.appendingPathComponent("")

        URLSession.shared.dataTask(with: testURL) { data, response, error in
            DispatchQueue.main.async {
                isTestingConnection = false

                if let error = error {
                    connectionTestResult = "Error: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        connectionTestResult = "Success! Backend is running."
                    } else {
                        connectionTestResult = "HTTP \(httpResponse.statusCode): Backend responded with error"
                    }
                } else {
                    connectionTestResult = "No response from backend"
                }

                showConnectionAlert = true
            }
        }.resume()
    }

    private func clearSearchCache() {
        // Clear search cache logic
        print("Clearing search cache...")
        // In a real implementation, this would clear the search manager's cache
    }

    private func rebuildIndex() {
        // Rebuild index logic
        print("Rebuilding index...")
        // In a real implementation, this would trigger a backend index rebuild
    }

    private func openDocumentation() {
        // Open documentation
        if let url = URL(string: "https://github.com/yourusername/grimoire") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reportIssue() {
        // Open issue reporting
        if let url = URL(string: "https://github.com/yourusername/grimoire/issues") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(NoteManager())
}
