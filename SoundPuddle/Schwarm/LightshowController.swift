import AVFoundation
import Foundation
import UIKit

@MainActor
final class LightshowController {
    private var torchOn = false
    private var pulseTask: Task<Void, Never>?
    private var lastBeatMs: Int64 = 0
    private var bpmEstimate: Double = 120
    private var envelopeHistory: [Float] = []

    var screenFlash: Double = 0
    var enabled = true
    var beatPhase: Double = 0

    func ingestLevel(_ level: Float, nowMs: Int64 = ClockSync.nowMs()) {
        guard enabled else { return }
        envelopeHistory.append(level)
        if envelopeHistory.count > 48 { envelopeHistory.removeFirst() }
        let avg = envelopeHistory.reduce(0, +) / Float(max(1, envelopeHistory.count))
        let isBeat = level > avg * 1.55 && level > 0.12 && (nowMs - lastBeatMs) > 280
        if isBeat {
            if lastBeatMs > 0 {
                let interval = Double(nowMs - lastBeatMs)
                let instant = 60_000.0 / max(280, interval)
                bpmEstimate = bpmEstimate * 0.7 + instant * 0.3
            }
            lastBeatMs = nowMs
            pulse()
        }
        beatPhase = (Double(nowMs % Int64(max(1, 60_000 / bpmEstimate)))) / (60_000 / bpmEstimate)
    }

    func applyCue(intensity: Float, colorHue: Float) {
        guard enabled else { return }
        screenFlash = Double(min(1, intensity))
        if intensity > 0.55 { flashTorch(ms: 60) }
        // colorHue reserved for UI binding
        _ = colorHue
    }

    func stop() {
        pulseTask?.cancel()
        pulseTask = nil
        setTorch(false)
        screenFlash = 0
        envelopeHistory.removeAll()
    }

    private func pulse() {
        screenFlash = 1
        flashTorch(ms: 50)
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard let self, !Task.isCancelled else { return }
            self.screenFlash = 0.15
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self.screenFlash = 0
        }
    }

    private func flashTorch(ms: Int) {
        setTorch(true)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            self?.setTorch(false)
        }
    }

    private func setTorch(_ on: Bool) {
        guard torchOn != on else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: 0.7)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
    }
}
