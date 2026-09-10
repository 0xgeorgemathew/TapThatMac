import Foundation
import TapCore

// Development-only diagnostic. No actions, key monitoring, files, or UI.
let interval = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 1000
let reader = SensorReader(reportInterval: interval)
reader.onStatus = { print($0) }
reader.start()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 5))
print("Reports: \(reader.sampleCount); rejected: \(reader.rejectedReports); measured rate: \(String(format: "%.1f", reader.rate)) Hz")
reader.stop()
