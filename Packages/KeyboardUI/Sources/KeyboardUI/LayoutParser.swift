import Foundation
import KeyboardModels
import Synchronization

public enum LayoutParserError: Error, LocalizedError {
    case missingResource

    public var errorDescription: String? {
        "找不到键盘布局 JSON"
    }
}

public enum LayoutParser {
    /// 缓存不可变布局，避免控制器重建时重复解码。
    private static let cache = Mutex<[String: LayoutDescriptor]>([:])

    public static func load(_ name: String, from bundle: Bundle? = nil) throws -> LayoutDescriptor {
        let bundle = bundle ?? Bundle.module
        let key = "\(bundle.bundleURL.path)/\(name)"

        if let cached = cache.withLock({ $0[key] }) {
            return cached
        }

        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Layouts") ??
                        bundle.url(forResource: name, withExtension: "json") else {
            throw LayoutParserError.missingResource
        }
        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(LayoutDTO.self, from: data)
        let descriptor = descriptor(from: dto)

        cache.withLock { $0[key] = descriptor }
        return descriptor
    }

    private static func descriptor(from dto: LayoutDTO) -> LayoutDescriptor {
        LayoutDescriptor(
            rows: dto.rows.map { row in
                RowDescriptor(
                    keys: row.keys.map { key in
                        KeyDescriptor(
                            label: key.label,
                            action: action(from: key.action),
                            style: KeyStyle(rawValue: key.style ?? "normal") ?? .normal,
                            width: key.width ?? 1.0,
                            fixedWidth: key.fixed
                        )
                    },
                    leadingPadding: row.padding ?? 0
                )
            }
        )
    }

    private static func action(from dto: KeyActionDTO) -> KeyAction {
        switch dto.type {
        case "character":
            return .character(dto.value ?? "")
        case "backspace":
            return .backspace
        case "space":
            return .space
        case "return":
            return .return
        case "shift":
            return .shift
        case "numbers":
            return .numbers
        case "letters":
            return .letters
        case "symbols":
            return .symbols
        case "toggleLanguage":
            return .toggleLanguage
        default:
            return .character(dto.value ?? "")
        }
    }
}

private struct LayoutDTO: Decodable {
    let rows: [RowDTO]
}

private struct RowDTO: Decodable {
    let keys: [KeyDTO]
    let padding: CGFloat?
}

private struct KeyDTO: Decodable {
    let label: String
    let action: KeyActionDTO
    let style: String?
    let width: CGFloat?
    let fixed: CGFloat?
}

private struct KeyActionDTO: Decodable {
    let type: String
    let value: String?
}
