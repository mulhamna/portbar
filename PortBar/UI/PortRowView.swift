import SwiftUI

struct PortRowView: View {
    let entry: PortEntry

    var body: some View {
        HStack {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)

            Text(":\(entry.port)")
                .fontWeight(.bold)
                .monospacedDigit()

            Text(entry.framework.rawValue)
                .foregroundColor(.secondary)

            if let project = entry.projectName {
                Text(project)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(formatUptime(entry.uptime))
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private var healthColor: Color {
        switch entry.health {
        case .healthy: return .green
        case .orphaned: return .yellow
        case .zombie: return .red
        }
    }
}
