import Foundation
import TUIHostBase

enum DemoFixtures {
    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let json = rawJSON(name),
              let resolved = try? JSONSerialization.data(withJSONObject: resolveStringRefs(json)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: resolved)
    }

    static func rawJSON(_ name: String) -> Any? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "demo-fixtures")
            ?? Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func resolvedJSON(_ name: String) -> Any? {
        rawJSON(name).map { resolveStringRefs($0) }
    }

    private static func resolveStringRefs(_ node: Any) -> Any {
        if let text = node as? String, text.hasPrefix("@demo_") { return DemoText.get(String(text.dropFirst())) }
        if let dict = node as? [String: Any] { return dict.mapValues { resolveStringRefs($0) } }
        if let list = node as? [Any] { return list.map { resolveStringRefs($0) } }
        return node
    }
}
