import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)

            Text("PortBar")
                .font(.title)
                .fontWeight(.bold)

            Text("Active port monitor for macOS")
                .foregroundColor(.secondary)

            Text("Version 1.0")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 280)
    }
}
