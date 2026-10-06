// CoreCatalog/PixelPalette.swift: the game's 32-colour pixel palette. Airline colours and logo pixels are indices into it, so every livery stays 8-bit.
// Index 0 means "no colour" (transparent in a logo). The app turns an index into a screen colour.

public enum PixelPalette {
    /// 0xRRGGBB for each index; index 0 is a placeholder for "none".
    public static let colors: [UInt32] = [
        0x000000,
        0x0B1020, 0x2B3350, 0x5A6482, 0x9AA7C2, 0xD7DEEE, 0xFFFFFF,     // ink, slate and white
        0x7A1F2B, 0xC0392B, 0xF0706A, 0xFF9F43, 0xFFC857, 0xFFE9A8,     // maroon, red, coral, orange, amber, cream
        0x1E6B3A, 0x3FA34D, 0x8FD16A, 0x0F5C63, 0x2DB5A8, 0x8DE3D1,     // forest, green, lime, deep teal, teal, mint
        0x12356B, 0x1F6FA0, 0x4FB6F0, 0xA8DCF8, 0x4B2A7B, 0x8A5CC9,     // navy, blue, sky, ice, indigo, violet
        0xCDB4F0, 0xA23B72, 0xF08CC0, 0x5B3A29, 0x9C6B3F, 0xD9B382,     // lilac, magenta, pink, brown, tan, sand
        0x151515,                                                       // black
    ]

    public static let count = colors.count

    /// The colour for an index; out-of-range indexes read as white so a bad save never crashes drawing.
    public static func rgb(_ index: Int) -> UInt32 { index > 0 && index < colors.count ? colors[index] : 0xFFFFFF }

    public static let white = 6
    public static let ink = 1
    public static let sky = 21
    public static let orange = 10
}
