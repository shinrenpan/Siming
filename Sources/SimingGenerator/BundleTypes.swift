import Foundation

struct ParamSpec {
    let code: String
    let type: String
    let expression: String
}

func loadParams(resourceType: String, bundlePath: String) throws -> [ParamSpec] {
    let data = try Data(contentsOf: URL(fileURLWithPath: bundlePath))
    let bundle = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let entries = (bundle["entry"] as? [[String: Any]]) ?? []

    return entries.compactMap { entry -> ParamSpec? in
        guard let resource = entry["resource"] as? [String: Any],
              resource["resourceType"] as? String == "SearchParameter",
              let code = resource["code"] as? String,
              let type_ = resource["type"] as? String,
              let bases = resource["base"] as? [String], bases.contains(resourceType),
              let expression = resource["expression"] as? String
        else { return nil }
        return ParamSpec(code: code, type: type_, expression: expression)
    }
}
