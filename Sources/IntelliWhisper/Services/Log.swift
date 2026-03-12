import Foundation
import SwiftyBeaver

let log = SwiftyBeaver.self

func setupLogging() {
    let console = ConsoleDestination()
    console.format = "$DHH:mm:ss.SSS$d $M"

    let file = FileDestination()
    let logDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/IntelliWhisper")
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    file.logFileURL = logDir.appendingPathComponent("intelliwhisper.log")
    file.format = "$DHH:mm:ss.SSS$d [$L] $M"
    file.minLevel = .debug
    file.logFileMaxSize = 5 * 1_048_576  // 5 MB
    file.logFileAmount = 3                // keep 3 rotated files

    log.addDestination(console)
    log.addDestination(file)
}
