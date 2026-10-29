import Foundation

/// Jackbox-style room codes: four letters, easy to read out loud.
///
/// Vowels are excluded so codes can never spell words (rude or otherwise), and
/// lookalike letters are excluded so codes survive being read off a phone across a tee box.
public enum JoinCode {
    public static let alphabet: [Character] = Array("BCDFGHJKLMNPQRSTVWXZ")
    public static let length = 4

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    public static func generate<G: RandomNumberGenerator>(using generator: inout G) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    /// Uppercases, trims and removes anything that can't be part of a code.
    public static func normalize(_ input: String) -> String {
        String(input.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }

    public static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { alphabet.contains($0) }
    }

    /// How a code should be read aloud: "K P L T".
    public static func spaced(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }
}
