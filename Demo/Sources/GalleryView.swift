//
//  GalleryView.swift
//  SurfaceRecorderSDKDemo
//
//  Created by Nazar Kozak on 05.06.2026.
//

import SwiftUI
import AVKit

/// A simple gallery of recorded videos with playback.
struct GalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [URL] = RecordingStore.all()

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No recordings yet",
                                           systemImage: "film.stack",
                                           description: Text("Record something, then it shows up here."))
                } else {
                    List {
                        ForEach(items, id: \.self) { url in
                            NavigationLink {
                                PlayerView(url: url)
                            } label: {
                                Label(url.lastPathComponent, systemImage: "play.rectangle.fill")
                                    .lineLimit(1)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { items = RecordingStore.all() }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { RecordingStore.delete(items[index]) }
        items = RecordingStore.all()
    }
}

private struct PlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                let player = AVPlayer(url: url)
                self.player = player
                player.play()
            }
            .onDisappear { player?.pause() }
    }
}
