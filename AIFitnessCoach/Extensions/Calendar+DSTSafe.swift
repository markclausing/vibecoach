import Foundation

// CLAUDE.md §3 — DST-veilige tijdsberekeningen.
// `TimeInterval`-wiskunde (delen door 86400 of 7*86400) is fout rond zomertijd-overgangen,
// omdat een dag dan 23 of 25 uur kan zijn. Deze extensies gebruiken `Calendar.dateComponents`
// zodat alle berekeningen automatisch met de tijdzone-regels rekening houden.
extension Calendar {

    /// Fractioneel aantal dagen tussen twee `Date`s — DST-veilig.
    ///
    /// Gebruikt voor weergave van resterende tijd met sub-dag precisie (bijv. "12.5 dagen").
    /// Negatief als `end` vóór `start` ligt.
    func fractionalDays(from start: Date, to end: Date) -> Double {
        let comps = dateComponents([.day, .hour, .minute], from: start, to: end)
        let days = Double(comps.day ?? 0)
        let hours = Double(comps.hour ?? 0)
        let minutes = Double(comps.minute ?? 0)
        return days + hours / 24.0 + minutes / (24.0 * 60.0)
    }

    /// Fractioneel aantal weken tussen twee `Date`s — DST-veilig.
    ///
    /// Gebaseerd op `fractionalDays` / 7. Negatief als `end` vóór `start` ligt.
    func fractionalWeeks(from start: Date, to end: Date) -> Double {
        return fractionalDays(from: start, to: end) / 7.0
    }

    /// Integer aantal volledige dagen tussen twee `Date`s — DST-veilig.
    ///
    /// Gebruik dit voor "X dagen geleden"- of cooldown-checks waar fractie er niet toe doet.
    func wholeDays(from start: Date, to end: Date) -> Int {
        return dateComponents([.day], from: start, to: end).day ?? 0
    }
}
