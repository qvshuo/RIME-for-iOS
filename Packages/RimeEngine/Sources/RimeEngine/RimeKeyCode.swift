import Foundation

public let XK_BackSpace: Int32 = 0xff08
public let XK_Return: Int32 = 0xff0d
public let XK_space: Int32 = 0x0020

public func rimeKeyCode(forCharacter character: String) -> Int32? {
    guard let scalar = character.unicodeScalars.first else { return nil }
    let value = scalar.value
    if value < 0x80 {
        return Int32(value)
    }
    // 非 ASCII 按 X11 Unicode keysym 规范加 0x01000000 平面位（squirrel/fcitx 同款），
    // 否则 CJK 码点会落进 kana/Cyrillic 等遗留 keysym 区间被 librime 误判。
    return Int32(bitPattern: 0x01000000 | value)
}
