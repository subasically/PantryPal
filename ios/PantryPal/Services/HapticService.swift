import UIKit
import AVFoundation

@MainActor
final class HapticService {
    static let shared = HapticService()
    
    private var audioPlayer: AVAudioPlayer?
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    
    private init() {
        prepareHaptics()
        prepareSound()
    }
    
    private func prepareHaptics() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }
    
    private func prepareSound() {
        guard let url = Bundle.main.url(forResource: "barcode-beep", withExtension: "mp3") else {
            print("Barcode beep sound not found")
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } catch {
            print("Failed to setup audio: \(error)")
        }
    }
    
    // MARK: - Haptic Feedback
    
    func lightImpact() {
        lightGenerator.impactOccurred()
    }
    
    func mediumImpact() {
        mediumGenerator.impactOccurred()
    }
    
    func heavyImpact() {
        heavyGenerator.impactOccurred()
    }
    
    func success() {
        notificationGenerator.notificationOccurred(.success)
    }
    
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }
    
    func error() {
        notificationGenerator.notificationOccurred(.error)
    }
    
    func selection() {
        selectionGenerator.selectionChanged()
    }
    
    // MARK: - Sound Feedback
    
    func playBarcodeBeep() {
        audioPlayer?.currentTime = 0
        audioPlayer?.play()
    }
    
    // MARK: - Combined Feedback
    
    func barcodeScanSuccess() {
        playBarcodeBeep()
        success()
    }
    
    func itemAdded() {
        success()
    }
    
    func itemRemoved() {
        mediumImpact()
    }
    
    func itemDeleted() {
        warning()
    }
    
    func buttonTap() {
        lightImpact()
    }
    
    func toggleChanged() {
        selection()
    }
    
    func errorOccurred() {
        error()
    }
}
