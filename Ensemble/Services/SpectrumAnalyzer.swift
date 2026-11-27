import Foundation
import AVFoundation

/// Per-moment loudness of 48 pitch bands (low to high) for one song, computed once when
/// the song starts. The player bar reads it at the current playback time to move the bars.
struct SpectrumData {
    let bands: Int
    let fps: Double
    /// frames x bands, each 0...1
    let values: [Float]

    var frameCount: Int { values.count / bands }

    /// Level (0...1) of one band at a point in the song, blended between neighboring frames.
    func level(at time: Double, band: Int) -> Float {
        guard frameCount > 1, band >= 0, band < bands else { return 0 }
        let position = max(0, time) * fps
        let i = min(Int(position), frameCount - 2)
        let fraction = Float(min(max(position - Double(i), 0), 1))
        let a = values[i * bands + band]
        let b = values[(i + 1) * bands + band]
        return a + (b - a) * fraction
    }
}

enum SpectrumAnalyzer {
    static let bands = 48
    private static let framesPerSecond = 30.0
    private static let fftSize = 2048
    private static let log2n = 11

    /// Reads the whole file once and measures how strong each pitch band is, about 30 times a second.
    /// Runs in the background; takes a second or two for a typical song.
    static func analyze(url: URL) -> SpectrumData? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let n = fftSize
        let hop = max(512, Int(sampleRate / framesPerSecond))

        // Hann window, FFT twiddle factors and bit-reversal table.
        let window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n))) }
        var cosT = [Float](repeating: 0, count: n / 2)
        var sinT = [Float](repeating: 0, count: n / 2)
        for k in 0..<(n / 2) {
            let angle = 2 * Double.pi * Double(k) / Double(n)
            cosT[k] = Float(cos(angle))
            sinT[k] = Float(-sin(angle))
        }
        var reversed = [Int](repeating: 0, count: n)
        for i in 0..<n {
            var x = i
            var r = 0
            for _ in 0..<log2n { r = (r << 1) | (x & 1); x >>= 1 }
            reversed[i] = r
        }

        // Which FFT bins make up each band (log-spaced from 40 Hz to about 14 kHz).
        let nyquist = sampleRate / 2
        let fMin = 40.0
        let fMax = min(14000.0, nyquist * 0.95)
        var edges: [Int] = []
        for b in 0...bands {
            let frequency = fMin * pow(fMax / fMin, Double(b) / Double(bands))
            edges.append(Int(frequency / nyquist * Double(n / 2)))
        }
        for b in 1...bands where edges[b] <= edges[b - 1] { edges[b] = edges[b - 1] + 1 }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768) else { return nil }
        var re = [Float](repeating: 0, count: n)
        var im = [Float](repeating: 0, count: n)
        var pending: [Float] = []
        var decibels: [Float] = []   // frames x bands

        while file.framePosition < file.length {
            if Task.isCancelled { return nil }
            do { try file.read(into: buffer, frameCount: 32768) } catch { break }
            let count = Int(buffer.frameLength)
            if count == 0 { break }
            guard let channels = buffer.floatChannelData else { return nil }
            for i in 0..<count {
                var sum: Float = 0
                for c in 0..<channelCount { sum += channels[c][i] }
                pending.append(sum / Float(channelCount))
            }

            var consumed = 0
            while pending.count - consumed >= n {
                for i in 0..<n {
                    re[i] = pending[consumed + i] * window[i]
                    im[i] = 0
                }
                re.withUnsafeMutableBufferPointer { r in
                    im.withUnsafeMutableBufferPointer { m in
                        fft(r.baseAddress!, m.baseAddress!, n: n, cosT: cosT, sinT: sinT, reversed: reversed)
                    }
                }
                for b in 0..<bands {
                    let lo = min(edges[b], n / 2 - 1)
                    let hi = min(max(edges[b + 1], lo + 1), n / 2)
                    var total: Float = 0
                    for k in lo..<hi { total += (re[k] * re[k] + im[k] * im[k]).squareRoot() }
                    let mean = total / Float(hi - lo)
                    decibels.append(20 * log10(mean + 1e-7))
                }
                consumed += hop
            }
            pending.removeFirst(min(consumed, pending.count))
        }

        let frameCount = decibels.count / bands
        guard frameCount > 2 else { return nil }

        // Scale each band against its own loudest moment (but not far below the loudest band),
        // so every bar gets room to move without quiet noise being blown up.
        let globalPeak = decibels.max() ?? -140
        var values = [Float](repeating: 0, count: decibels.count)
        for b in 0..<bands {
            var peak: Float = -200
            for f in 0..<frameCount { peak = max(peak, decibels[f * bands + b]) }
            let reference = max(peak, globalPeak - 50)
            let range: Float = 36
            var previous: Float = 0
            for f in 0..<frameCount {
                let raw = min(max((decibels[f * bands + b] - (reference - range)) / range, 0), 1)
                let shaped = globalPeak < -100 ? 0 : powf(raw, 1.4)
                // Quick rise, gentle fall, so it feels alive without flickering.
                let smoothed = shaped > previous ? previous + (shaped - previous) * 0.6 : previous * 0.9
                values[f * bands + b] = smoothed
                previous = smoothed
            }
        }
        return SpectrumData(bands: bands, fps: sampleRate / Double(hop), values: values)
    }

    /// In-place radix-2 FFT.
    private static func fft(_ re: UnsafeMutablePointer<Float>, _ im: UnsafeMutablePointer<Float>,
                            n: Int, cosT: [Float], sinT: [Float], reversed: [Int]) {
        for i in 0..<n {
            let j = reversed[i]
            if j > i {
                let tr = re[i]; re[i] = re[j]; re[j] = tr
                let ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var size = 2
        while size <= n {
            let half = size / 2
            let step = n / size
            var start = 0
            while start < n {
                var k = 0
                for j in start..<(start + half) {
                    let wr = cosT[k]
                    let wi = sinT[k]
                    let xr = re[j + half]
                    let xi = im[j + half]
                    let tr = wr * xr - wi * xi
                    let ti = wr * xi + wi * xr
                    re[j + half] = re[j] - tr
                    im[j + half] = im[j] - ti
                    re[j] += tr
                    im[j] += ti
                    k += step
                }
                start += size
            }
            size <<= 1
        }
    }
}
