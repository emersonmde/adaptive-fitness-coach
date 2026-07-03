import Foundation

/// Open Food Facts v2 — the rung-1 barcode fast path (CQ1c). Free, keyless, no LLM.
/// Pure request/response: the URL builder and decoder live here (testable with fixture JSON);
/// the URLSession transport is a thin phone-side client.
public enum OpenFoodFactsAPI {

    /// Product endpoint asking only for the fields we use — keeps responses small.
    /// API: https://openfoodfacts.github.io/openfoodfacts-server/api/ (v2 product read).
    public static func productURL(barcode: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "world.openfoodfacts.org"
        components.path = "/api/v2/product/\(barcode)"
        components.queryItems = [
            URLQueryItem(
                name: "fields",
                value: "product_name,brands,nutriments,serving_size,nutrition_data_per"
            )
        ]
        return components.url
    }

    /// Publicly viewable product page — used as the provenance source URL.
    public static func productPageURL(barcode: String) -> URL? {
        URL(string: "https://world.openfoodfacts.org/product/\(barcode)")
    }

    /// Decodes a v2 product response into a resolved nutrition value.
    /// Returns `nil` when the product is missing or carries no usable energy value —
    /// the ladder falls through rather than logging a hollow entry.
    ///
    /// Serving handling: prefer `energy-kcal_serving` (with the printed `serving_size`);
    /// fall back to per-100g values labeled honestly as "per 100 g" — never an invented
    /// portion (C3).
    public static func decode(_ data: Data, barcode: String) -> ResolvedNutrition? {
        guard let response = try? JSONDecoder().decode(ProductResponse.self, from: data),
              response.status == 1,
              let product = response.product,
              let nutriments = product.nutriments else {
            return nil
        }

        let facts: NutritionFacts
        if let kcalServing = nutriments.energyKcalServing {
            facts = NutritionFacts(
                energy: .exact(kcal: kcalServing),
                proteinGrams: nutriments.proteinsServing,
                carbGrams: nutriments.carbohydratesServing,
                fatGrams: nutriments.fatServing,
                servingDescription: product.servingSize ?? "1 serving"
            )
        } else if let kcal100g = nutriments.energyKcal100g {
            facts = NutritionFacts(
                energy: .exact(kcal: kcal100g),
                proteinGrams: nutriments.proteins100g,
                carbGrams: nutriments.carbohydrates100g,
                fatGrams: nutriments.fat100g,
                servingDescription: "per 100 g"
            )
        } else {
            return nil
        }

        let name = [product.brands, product.productName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return ResolvedNutrition(
            facts: facts,
            provenance: .database(
                name: name.isEmpty ? "Open Food Facts" : "Open Food Facts — \(name)",
                sourceURL: productPageURL(barcode: barcode)
            )
        )
    }

    // MARK: - Wire DTOs (private — nothing downstream sees OFF's shape)

    private struct ProductResponse: Decodable {
        var status: Int
        var product: Product?
    }

    private struct Product: Decodable {
        var productName: String?
        var brands: String?
        var servingSize: String?
        var nutriments: Nutriments?

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case brands
            case servingSize = "serving_size"
            case nutriments
        }
    }

    private struct Nutriments: Decodable {
        var energyKcalServing: Double?
        var energyKcal100g: Double?
        var proteinsServing: Double?
        var proteins100g: Double?
        var carbohydratesServing: Double?
        var carbohydrates100g: Double?
        var fatServing: Double?
        var fat100g: Double?

        enum CodingKeys: String, CodingKey {
            case energyKcalServing = "energy-kcal_serving"
            case energyKcal100g = "energy-kcal_100g"
            case proteinsServing = "proteins_serving"
            case proteins100g = "proteins_100g"
            case carbohydratesServing = "carbohydrates_serving"
            case carbohydrates100g = "carbohydrates_100g"
            case fatServing = "fat_serving"
            case fat100g = "fat_100g"
        }
    }
}
