import Foundation

/// Goal-owned currency contract. ISO 4217 code is never a profile-wide
/// balance setting or an FX rate. Production numeric(15,2) supports only
/// currencies with 0 or 2 minor digits; others are deliberately excluded.
enum PipoGoalCurrency {
    static let fallbackCode = "IDR"
    static let serverMaximum = Decimal(string: "9999999999999.99")!

    static func isSupported(_ code: String) -> Bool {
        let canonical = code.uppercased()
        return canonical.count == 3
            && Locale.commonISOCurrencyCodes.contains(canonical)
            && PipoPlanV2Money.fractionDigits(for: canonical) <= 2
    }

    static func suggested(for locale: Locale = .current) -> String {
        let candidate = locale.currency?.identifier.uppercased() ?? fallbackCode
        return isSupported(candidate) ? candidate : fallbackCode
    }

    static var choices: [String] {
        Locale.commonISOCurrencyCodes
            .filter(isSupported)
            .sorted()
    }

    static func currencyName(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    static func parseMinor(_ input: String, code: String, locale: Locale? = nil) -> Int64? {
        guard isSupported(code),
              let decimal = PipoPlanV2Money.parse(input, currency: code, locale: locale)
        else { return nil }
        return minorUnits(decimal, code: code)
    }

    static func minorUnits(_ decimal: Decimal, code: String, allowZero: Bool = false) -> Int64? {
        guard isSupported(code), decimal >= 0,
              decimal <= serverMaximum,
              allowZero || decimal > 0
        else { return nil }
        let multiplier = Decimal(PipoPlanV2Money.fractionDigits(for: code) == 0 ? 1 : 100)
        let scaled = decimal * multiplier
        let number = NSDecimalNumber(decimal: scaled)
        guard number != .notANumber,
              number.decimalValue == scaled,
              let exact = Int64(number.stringValue),
              (allowZero ? exact >= 0 : exact > 0)
        else { return nil }
        return exact
    }

    static func decimal(_ minor: Int64, code: String) -> Decimal {
        let divisor = Decimal(PipoPlanV2Money.fractionDigits(for: code) == 0 ? 1 : 100)
        return Decimal(minor) / divisor
    }

    static func formatted(_ minor: Int64, code: String) -> String {
        PipoPlanV2Money.formatted(decimal(minor, code: code), currency: code)
    }

    /// Legacy Double fields remain view compatibility caches. The exact
    /// authenticated storage value is minor units, never a Double sum.
    static func legacyMinor(_ value: Double, code: String) -> Int64? {
        guard value.isFinite,
              let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return minorUnits(decimal, code: code, allowZero: true)
    }

    static func display(_ value: Double, code: String, exactMinor: Int64? = nil) -> String {
        if let exactMinor {
            return formatted(exactMinor, code: code)
        }
        guard let minor = legacyMinor(value, code: code) else { return "Amount unavailable" }
        return formatted(minor, code: code)
    }

    static func scheduleMinor(target: Int64, periods: Int) -> Int64? {
        guard target > 0, periods > 0 else { return nil }
        let n = Int64(periods)
        let quotient = target / n
        return target % n == 0 ? quotient : quotient + 1
    }
}
