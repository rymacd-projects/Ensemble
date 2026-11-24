import Foundation
import AVFoundation

/// Estimates tempo from the loudness "pulse" of a track (energy-onset autocorrelation).
/// Fast and dependency-free; accurate for most beat-driven music, and the BPM column
/// is editable for the rest.
enum BPMDetector {
    static func detect(url: URL) -> Int? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate

        // Analyse up to 90 seconds from the middle of the track.
        let maxFrames = AVAudioFramePosition(90 * sampleRate)
        let frames = min(file.length, maxFrames)
        file.framePosition = max(0, (file.length - frames) / 2)

        let hop = 256
        var envelope: [Float] = []
        envelope.reserveCapacity(Int(frames) / hop + 1)

        let chunk: AVAudioFrameCount = 32768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return nil }
        var remaining = frames
        var leftover: [Float] = []

        while remaining > 0 {
            let toRead = AVAudioFrameCount(min(AVAudioFramePosition(chunk), remaining))
            do { try file.read(into: buffer, frameCount: toRead) } catch { break }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            remaining -= AVAudioFramePosition(n)
            guard let channels = buffer.floatChannelData else { return nil }
            let channelCount = Int(format.channelCount)

            var mono = leftover
            mono.reserveCapacity(leftover.count + n)
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<channelCount { sum += channels[c][i] }
                mono.append(sum / Float(channelCount))
            }

            var idx = 0
            while idx + hop <= mono.count {
                var energy: Float = 0
                for j in idx..<(idx + hop) { energy += mono[j] * mono[j] }
                envelope.append((energy / Float(hop)).squareRoot())
                idx += hop
            }
            leftover = Array(mono[idx...])
        }

        guard envelope.count > 400 else { return nil }
        let envRate = sampleRate / Double(hop)

        // Onset strength: positive change in log-compressed loudness.
        let compressed = envelope.map { log1p($0 * 60) }
        var onset = [Float](repeating: 0, count: compressed.count)
        for i in 1..<compressed.count {
            onset[i] = max(0, compressed[i] - compressed[i - 1])
        }
        let mean = onset.reduce(0, +) / Float(onset.count)
        for i in onset.indices { onset[i] = max(0, onset[i] - mean) }

        func autocorrelation(atLag lag: Double) -> Float {
            let whole = Int(lag)
            let frac = Float(lag - Double(whole))
            guard whole + 1 < onset.count else { return 0 }
            var sum: Float = 0
            for i in 0..<(onset.count - whole - 1) {
                let shifted = onset[i + whole] * (1 - frac) + onset[i + whole + 1] * frac
                sum += onset[i] * shifted
            }
            return sum / Float(onset.count - whole)
        }

        var bestBPM = 0.0
        var bestScore: Float = -1
        var bpm = 60.0
        while bpm <= 200 {
            let lag = envRate * 60 / bpm
            var score = autocorrelation(atLag: lag)
            score += 0.5 * autocorrelation(atLag: lag * 2)
            score += 0.25 * autocorrelation(atLag: lag * 4)
            // Gentle preference for common tempos (centered near 120 BPM).
            let distance = log2(bpm / 120)
            score *= Float(exp(-distance * distance / (2 * 0.55 * 0.55)))
            if score > bestScore {
                bestScore = score
                bestBPM = bpm
            }
            bpm += 0.5
        }

        guard bestScore > 0, bestBPM > 0 else { return nil }
        while bestBPM < 70 { bestBPM *= 2 }
        while bestBPM > 180 { bestBPM /= 2 }
        return Int(bestBPM.rounded())
    }
}
