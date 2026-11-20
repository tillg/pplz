import Foundation

/// Reads what has a fixed shape on a business card — mail address, phone numbers, website, postal
/// address — from the recognised text, by rule. Name, title and company are the language model's part.
public enum BusinessCard {
    /// Text that is not a profile screenshot (those carry a connection degree, connections or followers).
    public static func isCard(_ lines: [String]) -> Bool {
        guard !lines.isEmpty, ProfileReader.nameLineIndex(in: lines) == nil else { return false }
        return !lines.contains { $0.firstMatch(of: /(?i)\b(connections|followers|mutual connection)/) != nil }
    }

    /// Puts what is found into the profile; what is not found stays as it is.
    public static func fill(_ profile: inout CapturedProfile, from lines: [String]) {
        let text = lines.joined(separator: "\n")
        let email = text.firstMatch(of: /(?i)[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}/).map { String($0.0) } ?? ""
        if !email.isEmpty { profile.email = email }

        let numbers = lines.flatMap(phones(in:))
        if let phone = numbers.first(where: { $0.kind == .phone }) { profile.phone = phone.number }
        if let mobile = numbers.first(where: { $0.kind == .mobile }) { profile.mobile = mobile.number }

        let site = website(in: lines, email: email)
        if !site.isEmpty { profile.website = site }

        let address = address(in: lines)
        if !address.street.isEmpty { profile.street = address.street }
        if !address.postalCode.isEmpty { profile.postalCode = address.postalCode }
        if !address.city.isEmpty { profile.city = address.city }
        if !address.country.isEmpty { profile.country = address.country }
    }

    /// What the model returned, kept only if every word of it is written in the text: the model has
    /// made names up from other words on the page ("Frank" from "Frankfurt").
    public static func onlyWhatIsWritten(_ value: String, in lines: [String]) -> String {
        func words(_ text: String) -> [String] {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        let written = Set(lines.flatMap(words))
        let wanted = words(value)
        return !wanted.isEmpty && wanted.allSatisfy(written.contains) ? value.trimmed : ""
    }

    // MARK: Phone numbers

    enum PhoneKind { case phone, mobile, fax }

    /// The numbers in one line, each with what the text in front of it says it is ("T", "Mobil:", "Fax").
    static func phones(in line: String) -> [(kind: PhoneKind, number: String)] {
        var found: [(PhoneKind, String)] = []
        var labelStart = line.startIndex
        for match in line.matches(of: /\+?\(?\d[\d\s()\/.\-]{5,}\d/) {
            let number = formatted(String(match.0))
            defer { labelStart = match.range.upperBound }
            guard number.filter(\.isNumber).count >= 7 else { continue }
            let label = line[labelStart..<match.range.lowerBound].lowercased()
            let kind: PhoneKind
            if label.contains("fax") || label.firstMatch(of: /\bf\b/) != nil {
                kind = .fax
            } else if label.firstMatch(of: /mob|cell|handy|\bm\b/) != nil || number.firstMatch(of: /^(?:\+49 ?|0049 ?|0)1[567]\d/) != nil {
                kind = .mobile      // labelled so, or a German mobile prefix (015x, 016x, 017x)
            } else {
                kind = .phone
            }
            found.append((kind, number))
        }
        return found
    }

    /// A number as cardXchange writes it: groups separated by blanks only — no dots, slashes, hyphens or
    /// brackets — and without the "(0)" that is not dialled after a country code.
    static func formatted(_ number: String) -> String {
        number.replacing(/\(0\)/, with: " ")
            .replacing(/[.\/\-()]/, with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Whether two phone numbers are the same, however they are written: "040 5550123" is "+49 40 555 01 23".
    static func isSamePhone(_ a: String, _ b: String) -> Bool {
        func digits(_ text: String) -> String { String(text.filter(\.isNumber).drop { $0 == "0" }) }
        let (a, b) = (digits(a), digits(b))
        guard min(a.count, b.count) >= 7 else { return a == b }
        return a.hasSuffix(b) || b.hasSuffix(a)
    }

    // MARK: Website

    /// An address counts as the website if it starts with "www." or "http", is labelled as one, or
    /// is the mail address's domain standing by itself — never the domain inside the mail address,
    /// and never a profile on a social network.
    static func website(in lines: [String], email: String) -> String {
        let mailDomain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        for line in lines where !line.contains("@") {
            let isLabelled = line.firstMatch(of: /(?i)^\s*(web|website|internet|homepage|url)\b/) != nil
            for match in line.matches(of: /(?i)(?:https?:\/\/)?(?:www\.)?[a-z0-9][a-z0-9\-]*(?:\.[a-z0-9\-]+)*\.[a-z]{2,}(?:\/[^\s|,;]*)?/) {
                let address = String(match.0)
                let lower = address.lowercased()
                guard !lower.contains("linkedin.com"), !lower.contains("xing.com") else { continue }
                let host = host(of: address)
                if lower.hasPrefix("www.") || lower.hasPrefix("http") || isLabelled || (!mailDomain.isEmpty && host == mailDomain) {
                    return address
                }
            }
        }
        return ""
    }

    /// "https://www.Example.com/team/" → "example.com".
    static func host(of address: String) -> String {
        var text = address.lowercased()
        for prefix in ["https://", "http://", "www."] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        return String(text.split(separator: "/").first ?? "")
    }

    // MARK: Postal address

    struct Address: Equatable {
        var street = ""
        var postalCode = ""
        var city = ""
        var country = ""
    }

    /// The address in the form "Street 12" / "12345 City[, Country]" — in one line or two. Other
    /// forms (US, UK, …) are left to the system's address detector.
    static func address(in lines: [String]) -> Address {
        for (index, line) in lines.enumerated() where phones(in: line).isEmpty {
            guard let match = line.firstMatch(of: /(?:^|[\s,])(?:[A-Z]{1,2}-)?(\d{4,5})\s+(\p{Lu}[\p{L}.\- ]*\p{L})/) else { continue }
            var address = Address(postalCode: String(match.1), city: String(match.2).trimmed)
            let after = line[match.range.upperBound...].split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
            address.country = after.last ?? ""
            let before = String(line[..<match.range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
            if !before.isEmpty {
                address.street = before
            } else if index > 0, lines[index - 1].firstMatch(of: /^\p{L}.*\s\d+\s?[a-zA-Z]?$|^\d+[a-zA-Z]?,?\s+\p{L}/) != nil {
                address.street = lines[index - 1].trimmed
            }
            return address
        }
        return detectedAddress(in: lines.joined(separator: "\n"))
    }

    private static func detectedAddress(in text: String) -> Address {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue),
              let parts = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.addressComponents else { return Address() }
        return Address(street: parts[.street] ?? "", postalCode: parts[.zip] ?? "", city: parts[.city] ?? "", country: parts[.country] ?? "")
    }
}
