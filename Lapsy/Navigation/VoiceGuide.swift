import AVFoundation

/// Speaks turn directions. Quiets other audio (music, podcasts) while it talks and
/// works with the screen locked.
@MainActor
final class VoiceGuide: NSObject, AVSpeechSynthesizerDelegate {
    static let enabledKey = "voiceGuidance"

    private let synthesizer = AVSpeechSynthesizer()
    private var pending = 0

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard Self.enabled, !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        pending += 1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pending = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.pending = max(0, self.pending - 1)
            if self.pending == 0 {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    // MARK: - Wording

    /// "In 150 metres, turn left onto High Street."
    static func phrase(_ step: RouteStep, in distanceM: Double) -> String {
        let instruction = step.instruction
        guard let first = instruction.first else { return "" }
        return "In \(spoken(distanceM)), \(first.lowercased())\(instruction.dropFirst())"
    }

    static func spoken(_ meters: Double) -> String {
        if meters >= 950 {
            let km = (meters / 100).rounded() / 10
            return km == 1 ? "1 kilometre" : "\(km) kilometres"
        }
        let rounded = max(10, Int((meters / 10).rounded()) * 10)
        return "\(rounded) metres"
    }
}
