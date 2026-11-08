import Foundation

/// Regeln für „Weiterschauen“ – übernommen aus der Android-App (PlayerLogic.Resume):
///  - Keine Rückfrage in den ersten 10 Sekunden.
///  - Keine Rückfrage kurz vor dem Ende (letzte 15 Sekunden bzw. letzte 3 %): Der Film gilt dann als gesehen.
///  - Wurde die Datei inzwischen durch eine andere ersetzt (andere Größe), wird die Position verworfen.
public enum ResumePolicy {
    public static let minimumPosition: Double = 10
    public static let endMarginSeconds: Double = 15
    public static let endMarginFraction: Double = 0.03
    /// So lange muss tatsächlich abgespielt worden sein, damit die Wiedergabe als „abgespielt“ zählt (Android: 3 s)
    public static let countAsPlayedAfter: Double = 3
    /// Intervall für das Zwischenspeichern der Position während der Wiedergabe
    public static let saveInterval: Double = 10

    public enum Decision: Equatable, Sendable {
        case startFromBeginning
        case offerResume(at: Double)
    }

    /// Nah am Ende? (dann gilt der Film als gesehen, Position wird nicht gespeichert)
    public static func isNearEnd(position: Double, duration: Double?) -> Bool {
        guard let d = duration, d > 0 else { return false }
        let margin = max(endMarginSeconds, d * endMarginFraction)
        // Sehr kurze Videos (unter 30 s): erst das letzte Viertel zählt als Ende, damit nicht schon der Anfang „gesehen“ ist
        let effectiveMargin = d < 30 ? d * 0.25 : margin
        return position >= d - effectiveMargin
    }

    /// Soll die Position gespeichert werden?
    public static func shouldStore(position: Double, duration: Double?) -> Bool {
        position >= minimumPosition && !isNearEnd(position: position, duration: duration)
    }

    /// Angefangen, aber nicht beendet?
    public static func isInProgress(position: Double, duration: Double?) -> Bool {
        position >= minimumPosition && !isNearEnd(position: position, duration: duration)
    }

    /// Entscheidung beim Öffnen eines Films
    public static func decide(position: Double, duration: Double?, storedSize: Int64?, currentSize: Int64?) -> Decision {
        if let a = storedSize, let b = currentSize, a != b { return .startFromBeginning }
        guard position.isFinite, shouldStore(position: position, duration: duration) else { return .startFromBeginning }
        return .offerResume(at: position)
    }

    /// Fortschritt für den Balken auf Kachel/Zeile (nil = nichts anzeigen)
    public static func displayProgress(position: Double, duration: Double?) -> Double? {
        guard let d = duration, d > 0, position > 0, position.isFinite else { return nil }
        guard position >= minimumPosition else { return nil }
        return min(1, max(0, position / d))
    }
}

/// Sprünge im Player – nie vor den Anfang, nie hinter das Ende.
public enum SeekMath {
    public static func clamp(_ target: Double, duration: Double?) -> Double {
        let lower = max(0, target.isFinite ? target : 0)
        guard let d = duration, d > 0, d.isFinite else { return lower }
        // Knapp vor dem Ende anhalten, damit die Engine nicht sofort „beendet“ meldet
        return min(lower, max(0, d - 0.25))
    }

    public static let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    public static func speedLabel(_ s: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: s)) ?? "\(s)") + "×"
    }
}
