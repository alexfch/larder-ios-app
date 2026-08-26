import SwiftUI
import UIKit

/// Photo thumbnail for an item; falls back to a monogram square when no photo is set,
/// per FR-3.2's acceptance criteria.
struct ItemThumbnail: View {
    let photoData: Data?
    let monogram: String
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.larderMonogramDark
                    Text(monogram)
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}
