//
//  NowPlayingKit.swift
//  NowPlayingKit
//
//  Created by Adrian Castro on 8/5/25.
//

import Combine
import Foundation
import MusicKit
import UIKit
import MediaPlayer

public enum NowPlayingError: Error {
    case noCurrentEntry
    case unauthorized
}

public struct NowPlayingData: Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let playbackTime: TimeInterval
    public let duration: TimeInterval

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        playbackTime: TimeInterval = 0,
        duration: TimeInterval = 1
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.playbackTime = playbackTime
        self.duration = duration
    }
}

public final class NowPlayingManager: @unchecked Sendable {
    public static let shared = NowPlayingManager()
    
    #if os(iOS)
    private let player = SystemMusicPlayer.shared
    private var stateObservation: NSKeyValueObservation?
    #endif

    @Published public private(set) var isPlaying = false

    private init() {
        #if os(iOS)
        self.isPlaying = player.state.playbackStatus == .playing

        stateObservation = player.observe(\.state, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            let newState = player.state.playbackStatus == .playing
            if self.isPlaying != newState {
                print("🎵 Playback state updating: \(self.isPlaying) -> \(newState)")
                DispatchQueue.main.async {
                    self.isPlaying = newState
                }
            }
        }
        
        Task {
            for await _ in player.queue.objectWillChange.values {
                await MainActor.run {
                    let newState = player.state.playbackStatus == .playing
                    if self.isPlaying != newState {
                        print("🎵 Playback state updating from queue change: \(self.isPlaying) -> \(newState)")
                        self.isPlaying = newState
                    }
                }
            }
        }
        #endif
    }
    
    @objc private func handlePlaybackStateChange() {
        checkAndUpdatePlaybackState()
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
        #if os(iOS)
        stateObservation?.invalidate()
        #endif
    }
}

extension SystemMusicPlayer {
    public static let playbackStateDidChangeNotification = NSNotification.Name("SystemMusicPlayerPlaybackStateDidChange")
}