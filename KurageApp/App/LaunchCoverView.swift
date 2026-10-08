import SwiftUI
import KurageCore

/// Matches the system launch storyboard during the initial launch interval.
struct LaunchCoverView: View {
    var body: some View {
        Image("LaunchMark")
            .resizable()
            .scaledToFit()
            .frame(width: 64, height: 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("LaunchBackground").ignoresSafeArea())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Starting Kurage")
            .accessibilityIdentifier("launch-cover")
    }
}

#Preview("Light") {
    LaunchCoverView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LaunchCoverView()
        .preferredColorScheme(.dark)
}
