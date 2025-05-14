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
    #endif

    @Published public private(set) var isPlaying = false
    
    // Observation-related properties
    private var playerObserver: NSKeyValueObservation?
    private var nowPlayingObserver: NSKeyValueObservation?
    private var remoteCommandObservers: [Any] = []
    private var notificationObservers: [NSObjectProtocol] = []
    
    // Publisher for immediate state changes
    private let playbackStateSubject = PassthroughSubject<Bool, Never>()
    public var playbackStatePublisher: AnyPublisher<Bool, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    private init() {
        #if os(iOS)
            self.isPlaying = player.state.playbackStatus == .playing
            setupPlaybackObservers()
        #endif
    }
    
    private func setupPlaybackObservers() {
        #if os(iOS)
            // 1. MusicKit queue observation 
            Task {
                print("🎵 Initial playback state: \(self.isPlaying)")
                for await _ in player.queue.objectWillChange.values {
                    await MainActor.run {
                        self.checkAndUpdatePlaybackState()
                    }
                }
            }
            
            // 2. Direct KVO observation of player state
            playerObserver = player.observe(\.state, options: [.new, .initial]) { [weak self] _, _ in
                guard let self = self else { return }
                self.checkAndUpdatePlaybackState()
            }
            
            // 3. System notifications
            setupNotificationObservers()
            
            // 4. Remote command center
            setupRemoteCommandCenter()
            
            // 5. Now Playing Info Center observation
            setupNowPlayingInfoMonitoring()
            
            // Initial publish of state
            playbackStateSubject.send(isPlaying)
        #endif
    }
    
    private func setupNotificationObservers() {
        #if os(iOS)
            let notificationCenter = NotificationCenter.default
            
            // System notifications that could indicate playback state changes
            let notifications: [Notification.Name] = [
                SystemMusicPlayer.playbackStateDidChangeNotification,
                UIApplication.didBecomeActiveNotification,
                NSNotification.Name.MPMusicPlayerControllerPlaybackStateDidChange,
                NSNotification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
                AVAudioSession.interruptionNotification,
                AVAudioSession.routeChangeNotification
            ]
            
            for notification in notifications {
                let observer = notificationCenter.addObserver(
                    forName: notification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self = self else { return }
                    self.checkAndUpdatePlaybackState()
                }
                notificationObservers.append(observer)
            }
        #endif
    }
    
    private func setupRemoteCommandCenter() {
        #if os(iOS)
            let commandCenter = MPRemoteCommandCenter.shared()
            
            // Play command
            remoteCommandObservers.append(
                commandCenter.playCommand.addTarget { [weak self] _ in
                    self?.checkAndUpdatePlaybackState()
                    return .success
                }
            )
            
            // Pause command
            remoteCommandObservers.append(
                commandCenter.pauseCommand.addTarget { [weak self] _ in
                    self?.checkAndUpdatePlaybackState()
                    return .success
                }
            )
            
            // Toggle play/pause command
            remoteCommandObservers.append(
                commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                    self?.checkAndUpdatePlaybackState()
                    return .success
                }
            )
            
            // Next track
            remoteCommandObservers.append(
                commandCenter.nextTrackCommand.addTarget { [weak self] _ in
                    self?.checkAndUpdatePlaybackState()
                    return .success
                }
            )
            
            // Previous track
            remoteCommandObservers.append(
                commandCenter.previousTrackCommand.addTarget { [weak self] _ in
                    self?.checkAndUpdatePlaybackState()
                    return .success
                }
            )
        #endif
    }
    
    private func setupNowPlayingInfoMonitoring() {
        #if os(iOS)
            // Monitor Now Playing Info Center changes with KVO since it doesn't have notifications
            let infoCenter = MPNowPlayingInfoCenter.default()
            nowPlayingObserver = infoCenter.observe(\.nowPlayingInfo, options: [.new]) { [weak self] _, _ in
                self?.checkAndUpdatePlaybackState()
            }
        #endif
    }
    
    // Consolidated method to check and update playback state
    private func checkAndUpdatePlaybackState() {
        #if os(iOS)
            DispatchQueue.main.async {
                let currentState = self.player.state.playbackStatus == .playing
                if self.isPlaying != currentState {
                    print("⚡ Playback state change detected: \(self.isPlaying) -> \(currentState)")
                    self.isPlaying = currentState
                    
                    // Emit through the publisher for immediate updates
                    self.playbackStateSubject.send(currentState)
                    
                    // Post notification to ensure all observers are updated
                    NotificationCenter.default.post(
                        name: SystemMusicPlayer.playbackStateDidChangeNotification,
                        object: nil,
                        userInfo: ["isPlaying": currentState]
                    )
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
        // Clean up observers
        playerObserver?.invalidate()
        nowPlayingObserver?.invalidate()
        
        // Remote command center observers
        for observer in remoteCommandObservers {
            if let token = observer as? Any {
                MPRemoteCommandCenter.shared().playCommand.removeTarget(token)
                MPRemoteCommandCenter.shared().pauseCommand.removeTarget(token)
                MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(token)
                MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(token)
                MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(token)
            }
        }
        
        // Notification observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        
        NotificationCenter.default.removeObserver(self)
    }
}

// Notification name extensions
extension SystemMusicPlayer {
    public static let playbackStateDidChangeNotification = NSNotification.Name("SystemMusicPlayerPlaybackStateDidChange")
}