import SwiftUI

// MARK: - Sources

struct SourcesView: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Drug card details are derived from and cross-referenced against the sources listed below.")
                        .font(theme.appFont(14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        sourceLinkRow(
                            name: "Drugs.com",
                            description: "Drug Information Reference",
                            urlString: "https://www.drugs.com"
                        )
                        Divider().padding(.leading, 16)
                        sourceLinkRow(
                            name: "MedlinePlus (NIH)",
                            description: "Medical Reference (NIH)",
                            urlString: "https://medlineplus.gov"
                        )
                    }
                    .background(Color.appCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text("This app is intended for educational and study purposes only. It is not a substitute for professional medical advice, diagnosis, or treatment.")
                        .font(theme.appFont(14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private func sourceLinkRow(name: String, description: String, urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(theme.appFont(16, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(description)
                            .font(theme.appFont(14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.appTertiaryText)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
        }
    }
}

#Preview("Sources") {
    NavigationStack { SourcesView() }
}


// MARK: - Terms of Use

struct TermsOfUseView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Text("Opening Terms of Use\u{2026}")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .navigationTitle("Terms of Use")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let url = URL(string: "https://memorx.app/terms") {
                openURL(url)
            }
        }
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Text("Opening Privacy Policy\u{2026}")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let url = URL(string: "https://memorx.app/privacy") {
                openURL(url)
            }
        }
    }
}
