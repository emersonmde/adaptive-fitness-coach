import Foundation
import AdaptiveCore

/// Rung 1 transport: Open Food Facts v2 product lookup. All parsing lives in the package
/// (`OpenFoodFactsAPI`); this is URLSession + timeouts. Returns `nil` on *any* failure —
/// the ladder falls through to the next rung, it never blocks on this one.
struct OpenFoodFactsClient: BarcodeNutritionDatabase {
    var timeout: TimeInterval = 6

    func lookup(barcode: String) async throws -> ResolvedNutrition? {
        guard let url = OpenFoodFactsAPI.productURL(barcode: barcode) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        // OFF asks API users to identify themselves (no key required).
        request.setValue("AdaptiveFitnessCoach/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }
        return OpenFoodFactsAPI.decode(data, barcode: barcode)
    }
}
