import Foundation

/// Grades a lookup result's source URL into a `Provenance` (C3). Pure and table-driven so the
/// grading policy is pinned by tests, not scattered through engine code.
///
/// Reality check from the CQ1 spike: even seller-scoped searches mostly return aggregators —
/// `database` is the normal good outcome, `verified` (the seller's own domain) is a bonus.
public enum ProvenanceGrader {

    /// Open databases and menu aggregators we can name in the UI ("Open Food Facts", not a
    /// bare hostname). Anything not listed still grades `database`, named by its host —
    /// honest without requiring an exhaustive registry.
    private static let knownDatabases: [String: String] = [
        "openfoodfacts.org": "Open Food Facts",
        "fdc.nal.usda.gov": "USDA FoodData Central",
        "usda.gov": "USDA",
        "nutritionix.com": "Nutritionix",
        "menuwithnutrition.com": "Menu With Nutrition",
        "menuswithprice.com": "Menus With Price",
        "fastfoodnutrition.org": "Fast Food Nutrition",
        "calorieking.com": "CalorieKing",
        "myfitnesspal.com": "MyFitnessPal",
        "fatsecret.com": "FatSecret",
    ]

    public static func grade(sourceURL: URL?, seller: Seller?) -> Provenance {
        guard let sourceURL, let host = sourceURL.host?.lowercased() else {
            // A number with no source can't claim verification; it's a database-grade claim
            // with no citation — grade it an estimate-free "database" would overstate it, so
            // the caller should only reach here from sources that genuinely had no URL
            // (e.g. a printed label goes through `.verified(sourceURL: nil)` directly, not
            // through the grader).
            return .database(name: "unknown source", sourceURL: nil)
        }

        if let sellerDomain = seller?.domainHint?.lowercased(),
           host == sellerDomain || host.hasSuffix("." + sellerDomain) {
            return .verified(sourceURL: sourceURL)
        }

        for (domain, name) in knownDatabases {
            if host == domain || host.hasSuffix("." + domain) {
                return .database(name: name, sourceURL: sourceURL)
            }
        }

        return .database(name: host.replacingOccurrences(of: "www.", with: ""), sourceURL: sourceURL)
    }
}
