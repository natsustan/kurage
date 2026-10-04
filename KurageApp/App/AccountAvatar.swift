import SwiftUI

struct AccountAvatar: View {
    let account: Account?
    var size: CGFloat = 34

    private var initial: String {
        let name = account?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = account?.email.split(separator: "@", maxSplits: 1).first.map(String.init)
        return String((name?.isEmpty == false ? name : fallback)?.prefix(1) ?? "?").uppercased()
    }

    var body: some View {
        Group {
            if let image = account?.image, let url = URL(string: image) {
                AsyncImage(url: url) { phase in
                    if let loadedImage = phase.image {
                        loadedImage.resizable().scaledToFill()
                    } else {
                        AccountInitial(initial: initial)
                    }
                }
            } else {
                AccountInitial(initial: initial)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary, in: Circle())
        .clipShape(Circle())
        .accessibilityLabel("Account")
    }
}

private struct AccountInitial: View {
    let initial: String

    var body: some View {
        Text(initial)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
