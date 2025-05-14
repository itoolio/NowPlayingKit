//
//  NowPlayingKit.swift
//  NowPlayingKit
//
//  Created by Adrian Castro on 8/5/25.
//

import Combine
import Foundation
import MusicKit

public final class NowPlayingManager: @unchecked Sendable {
    public static let shared = NowPlayingManager()

    #if os(iOS)
        private let player = SystemMusicPlayer.shared
    #endif

    @Published public private(set) var isPlaying = false
    
    private var statusCheckTimer: Timer?

    private init() {
        #if os(iOS)
            self.isPlaying = player.state.playbackStatus == .playing
            setupPlaybackObservers()
        #endif
    }
    
    private func setupPlaybackObservers() {
        #if os(iOS)
            Task {
                print("🎵 Initial playback state: \(self.isPlaying)")
                for await _ in player.queue.objectWillChange.values {
                    await MainActor.run {
                        let newState = player.state.playbackStatus == .playing
                        print("🎵 Playback state updating: \(self.isPlaying) -> \(newState)")
                        self.isPlaying = newState
                    }
                }
            }
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePlaybackStateChange),
                name: SystemMusicPlayer.playbackStateDidChangeNotification,
                object: player
            )
            
            statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let currentState = self.player.state.playbackStatus == .playing
                if self.isPlaying != currentState {
                    print("🕒 Timer detected playback state change: \(self.isPlaying) -> \(currentState)")
                    self.isPlaying = currentState
                    
                    NotificationCenter.default.post(
                        name: SystemMusicPlayer.playbackStateDidChangeNotification,
                        object: nil
                    )
                }
            }
        #endif
    }
    
    @objc private func handlePlaybackStateChange() {
        #if os(iOS)
        Task { @MainActor in
            let newState = player.state.playbackStatus == .playing
            print("🔔 Notification - playback state changed: \(isPlaying) -> \(newState)")
            isPlaying = newState
        }
        #endif
    }

    public func authorize() async -> MusicAuthorization.Status {
        #if os(iOS)
            return await MusicAuthorization.request()
        #else
            return .notDetermined
        #endif
    }

    public func getCurrentPlayback() async throws -> NowPlayingData {
        #if os(iOS)
            let authStatus = MusicAuthorization.currentStatus
            guard authStatus == .authorized else {
                throw NowPlayingError.unauthorized
            }

            guard let entry = player.queue.currentEntry else {
                throw NowPlayingError.noCurrentEntry
            }

            var id = ""
            let title = entry.title
            let artworkURL = entry.artwork?.url(width: 300, height: 300)
            var artist = ""
            var album: String? = nil
            var duration: TimeInterval = 1

            if let item = entry.item {
                switch item {
                case .song(let song):
                    id = song.id.rawValue
                    duration = song.duration ?? 1
                    artist = song.artistName
                    album = song.albumTitle
                case .musicVideo(let musicVideo):
                    id = musicVideo.id.rawValue
                    duration = musicVideo.duration ?? 1
                    artist = musicVideo.artistName
                @unknown default:
                    duration = 1
                }
            }

            return NowPlayingData(
                id: id,
                title: title,
                artist: artist,
                album: album,
                artworkURL: artworkURL,
                playbackTime: player.playbackTime,
                duration: duration
            )
        #else
            throw NowPlayingError.unauthorized
        #endif
    }
    
    deinit {
        statusCheckTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

extension SystemMusicPlayer {
    public static let playbackStateDidChangeNotification = NSNotification.Name("SystemMusicPlayerPlaybackStateDidChange")
}