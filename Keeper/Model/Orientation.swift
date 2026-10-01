/// EXIF orientation, 1 to 8. Rotating a photo only changes this tag, so the pixels stay untouched.
enum Orientation {
    private static let clockwise: [UInt32: UInt32] = [1: 6, 6: 3, 3: 8, 8: 1, 2: 7, 7: 4, 4: 5, 5: 2]

    /// The tag after turning a photo clockwise by `turns` quarter turns. Negative turns go counterclockwise.
    static func turned(_ orientation: UInt32, by turns: Int) -> UInt32 {
        var value = (1...8).contains(orientation) ? orientation : 1
        for _ in 0..<((turns % 4) + 4) % 4 { value = clockwise[value]! }
        return value
    }
}
