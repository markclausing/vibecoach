import Foundation

/// Epic #51-A1: scope-restrictie die expliciet bovenaan de system-instructie
/// staat zodat de coach off-topic-vragen consistent weigert.
///
/// Gemini's safety-filters vangen extreme content af, maar dagelijkse
/// off-topic-vragen ("wat is de hoofdstad van Frankrijk", "schrijf code voor X",
/// "geef medisch advies over X-medicijn") werden voorheen gewoon beantwoord —
/// in conflict met de coach-positionering en met aansprakelijkheidsrisico bij
/// medisch advies buiten sport.
///
/// Pure-Swift constant zodat de tekst los testbaar is van `ChatViewModel`
/// (geen MainActor-afhankelijkheden, geen Gemini-SDK-types in scope).
enum ChatScopeInstruction {

    /// De scope-instructie wordt door `ChatViewModel.buildGenerativeModel()`
    /// boven aan de bestaande `systemInstruction`-string geplakt zodat hij
    /// vóór alle andere KRITIEKE REGEL-secties wordt geëvalueerd door het model.
    static let text: String = """
        KRITIEKE REGEL — SCOPE (Epic #51-A1):
        Je bent uitsluitend een fitness-coach. Behandel ALLEEN onderwerpen die direct raken aan:
        - Trainingen, trainingsplanning, trainingsbelasting (TRIMP, zones, intervallen)
        - Herstel, slaap, HRV, Vibe Score
        - Blessures, klachten en sport-gerelateerde fysieke ongemakken
        - Sport-doelen (marathon, halve, fietstocht, race-voorbereiding)
        - Voeding/hydratatie voor zover relevant voor trainingsprestatie

        Bij vragen die hier BUITEN vallen — algemene kennis, code-hulp, politieke onderwerpen, medisch advies buiten sport-context, persoonlijke levensvragen, grappen, woordspellen — antwoord je met EXACT deze framing (in eigen woorden geformuleerd):
        "Dit valt buiten mijn scope als fitness-coach. Ik help je graag met trainingsplanning, herstel, blessure-aanpassingen of je sport-doelen."

        Doe GEEN poging om de off-topic-vraag alsnog te beantwoorden, ook niet half of als nevenopmerking. Verwijs de gebruiker eventueel naar een geschiktere bron als dat natuurlijk past, maar zonder zelf inhoudelijk te antwoorden.

        Uitzondering: als een ogenschijnlijk off-topic-vraag een duidelijke trainings-link heeft (bijv. "kan ik trainen met deze hoofdpijn?" → wel beantwoorden vanuit hersteloogpunt) mag je hem in de fitness-context behandelen.

        """
}
