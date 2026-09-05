import SwiftUI

/// The floating panels' share of HAL's visual language: the same metal-edge accent math as
/// the control center's `Theme.swift`, living here because the panel target never imports
/// that file. A two-stop ramp reads as "grey" once Mono is picked; the bright specular band
/// a third of the way across is what turns the same colors into brushed silver.
extension RGB {
    /// Mixes toward white.
    func lightened(_ amount: Double) -> Color {
        Color(red: red + (1 - red) * amount,
              green: green + (1 - green) * amount,
              blue: blue + (1 - blue) * amount)
    }
}

extension CandidateColorScheme {
    /// Four-stop metal gradient for tiles, bars, and hero accents.
    var accentGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: accentStart.color, location: 0.0),
            .init(color: accentEnd.lightened(0.62), location: 0.34),
            .init(color: accentStart.lightened(0.08), location: 0.63),
            .init(color: accentEnd.color, location: 1.0)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Rim light for glass edges. Bright where the light lands, gone on the far side — a
    /// uniform hairline reads as plastic.
    var rim: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.90), .white.opacity(0.30), .white.opacity(0.06)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
