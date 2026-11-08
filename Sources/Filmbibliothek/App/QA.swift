import Foundation
import os

/// Protokoll für automatische Prüfungen (GitHub Actions) und Fehlersuche.
///
/// Schreibt in das macOS-Protokoll (Subsystem „de.privateapp.filmbibliothek“, abrufbar mit
/// `log show --predicate 'subsystem == "de.privateapp.filmbibliothek"'`) und – nur wenn die Umgebungsvariable
/// FB_QA=1 gesetzt ist – zusätzlich auf die Standardausgabe. Es werden keine Daten gesendet.
enum QA {
    private static let logger = Logger(subsystem: "de.privateapp.filmbibliothek", category: "app")
    static let enabled = ProcessInfo.processInfo.environment["FB_QA"] == "1"

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        if enabled {
            print("[FB] \(message)")
            fflush(stdout)
        }
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unbekannt"
        #endif
    }

    /// Läuft der Intel-Teil über Rosetta auf Apple Silicon?
    static var isTranslated: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0) == 0 && value == 1
    }

    /// Läuft die App in der App-Sandbox?
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
