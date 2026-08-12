import AppKit
import SwiftUI

struct ProviderLogoView: View {
    private static let logoImages: [ProviderID: NSImage] = Dictionary(
        uniqueKeysWithValues: ProviderID.allCases.compactMap { provider in
            loadLogo(for: provider).map { (provider, $0) }
        }
    )

    let provider: ProviderID
    var size: CGFloat = 16
    var foregroundColor: Color = .white

    var body: some View {
        Group {
            if let image = logoImage {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(foregroundColor)
            } else {
                Image(systemName: provider.symbolName)
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(foregroundColor)
            }
        }
        .frame(width: size, height: size)
    }

    private var logoImage: NSImage? {
        Self.logoImages[provider]
    }

    private static func loadLogo(for provider: ProviderID) -> NSImage? {
        if let url = Bundle.module.url(
            forResource: provider.logoResourceName,
            withExtension: "png",
            subdirectory: "Logos"
        ) {
            return NSImage(contentsOf: url)
        }

        if let url = Bundle.module.url(forResource: provider.logoResourceName, withExtension: "png") {
            return NSImage(contentsOf: url)
        }

        return nil
    }
}
