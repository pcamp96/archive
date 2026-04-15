import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Archive V1 focuses on a local-first markdown workspace. Publishing connectors and additional preferences will land on top of this foundation.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 420)
    }
}
