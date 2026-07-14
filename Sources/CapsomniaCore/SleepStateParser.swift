import Foundation

public enum SleepStateParser {
    public static func parse(_ output: String) -> Bool? {
        var parsed: Bool?
        var matchCount = 0

        for line in output.split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 2,
                  fields[0].lowercased() == "sleepdisabled" else {
                continue
            }

            let value: Bool
            switch fields[1] {
            case "1": value = true
            case "0": value = false
            default: return nil
            }

            matchCount += 1
            parsed = value
        }

        return matchCount == 1 ? parsed : nil
    }
}

