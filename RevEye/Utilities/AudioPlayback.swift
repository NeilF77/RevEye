// AudioPlayback.swift
// RevEye
//
// Small wrapper around AVAudioPlayer that plays back saved M4A clips.
// Lives as an ObservableObject so SwiftUI views can hold it with
// @StateObject and keep the player alive across re-renders. Using plain
// @State for AVAudioPlayer was unreliable - if the parent view rebuilt
// mid-playback the player would deallocate and the audio would cut off.
//
// The "currentId" handle lets views show a per-row play/stop state in
// lists (e.g. Garage), where multiple rows share one playback controller.

import Foundation
import Combine
import AVFoundation

final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    // Optional identifier for the item currently playing. Views can tag
    // their play call with a detection id (or anything Hashable) so they
    // know which row's button to highlight.
    @Published private(set) var currentId: AnyHashable?

    private var player: AVAudioPlayer?

    override init() {
        super.init()
        // Listen for audio session interruptions (phone calls, Siri, other
        // apps starting audio). Without this, the player silently stops
        // when something else grabs the session and we never find out.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    var isPlaying: Bool { player?.isPlaying == true }

    // Starts playback of the file at `url`. If something is already
    // playing it gets stopped first. Returns true if playback started.
    @discardableResult
    func play(url: URL, id: AnyHashable? = nil) -> Bool {
        stop()

        do {
            // .playback plays through the main speaker even when the ringer
            // switch is on silent. .mixWithOthers lets us coexist with any
            // background audio the user has playing without the OS killing
            // our player after a few seconds.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()

            print("AudioPlayback: playing \(url.lastPathComponent) duration=\(String(format: "%.2f", p.duration))s")

            player = p
            currentId = id
            return true
        } catch {
            print("AudioPlayback: failed to play \(url.lastPathComponent) - \(error.localizedDescription)")
            player = nil
            currentId = nil
            return false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentId = nil
    }

    // AVAudioPlayerDelegate - clears state when the clip finishes on its own.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("AudioPlayback: finished successfully=\(flag)")
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.currentId = nil
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .began {
            print("AudioPlayback: interrupted by another audio source")
            DispatchQueue.main.async { [weak self] in
                self?.player = nil
                self?.currentId = nil
            }
        }
    }
}
