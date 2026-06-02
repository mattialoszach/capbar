import AppKit
import SwiftUI

struct ProviderLogoView: View {
    let provider: ProviderID
    var size: CGFloat = 16
    var fallbackColor: Color = .white

    var body: some View {
        Group {
            if let image = logoImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: provider.symbolName)
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(fallbackColor)
            }
        }
        .frame(width: size, height: size)
    }

    private var logoImage: NSImage? {
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
