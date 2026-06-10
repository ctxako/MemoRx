import SwiftUI
struct HelpFeedbackView: View {
    @Environment(\.appTheme) private var theme
    private let gold = Color(red: 201/255, green: 185/255, blue: 154/255)
    /// Visible when `mailto:` open fails (no Mail.app handler) — auto-clears after a beat.
    @State private var supportFallbackMessage: String?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {

                    // SECTION 1 — Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MemoRx")
                            .font(theme.appFont(28, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Your NAPLEX study companion")
                            .font(theme.appFont(15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // SECTION 2 — How XP Works
                    sectionBlock(header: "How XP Works") {
                        bulletRow("Each day has one drug to study — your first attempt earns up to 50 XP")
                        bulletRow("XP scales with your score: ROUND(50 × correct ÷ total questions)")
                        bulletRow("100%  →  50 XP")
                        bulletRow("80%  →  40 XP")
                        bulletRow("50%  →  25 XP")
                        bulletRow("0%  →  0 XP")
                    }

                    // SECTION 3 — How to Rank Up
                    sectionBlock(header: "How to Rank Up") {
                        rankRow("Pharmacy Intern", xp: "0 XP")
                        rankRow("Pharmacy Technician", xp: "250 XP")
                        rankRow("Pharmacy Assistant", xp: "650 XP")
                        rankRow("Staff Pharmacist", xp: "2,140 XP")
                        rankRow("Senior Pharmacist", xp: "4,320 XP")
                        rankRow("Clinical Pharmacist", xp: "8,310 XP")
                        rankRow("PharmD Candidate", xp: "13,775 XP")
                        rankRow("Board Certified Pharmacist", xp: "22,090 XP")
                        rankRow("Master Pharmacist", xp: "27,310 XP")
                    }

                    // SECTION 4 — Bonus XP
                    sectionBlock(header: "Bonus XP") {
                        bulletRow("7-day streak  →  +50 XP")
                        bulletRow("14-day streak  →  +100 XP")
                        bulletRow("30-day streak  →  +250 XP")
                        bulletRow("90-day streak  →  +600 XP")
                    }

                    // SECTION 5 — Feedback
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Feedback")
                        Button {
                            SupportContact.openFeedbackMail { copied in
                                supportFallbackMessage = "Mail isn’t set up. Email copied — paste it into your inbox."
                                _ = copied
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "envelope.fill")
                                    .font(theme.appFont(16))
                                    .foregroundStyle(gold)
                                    .frame(width: 22)
                                Text("Send feedback")
                                    .font(theme.appFont(16))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(theme.appFont(13))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.appCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
        }
        .navigationTitle("Help & Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            if let supportFallbackMessage {
                SupportContactToast(message: supportFallbackMessage)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: supportFallbackMessage)
        .onChange(of: supportFallbackMessage) { _, message in
            guard message != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                supportFallbackMessage = nil
            }
        }
    }

    @ViewBuilder
    private func sectionBlock<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(header)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(Color.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(theme.appFont(12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(gold)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            Text(text)
                .font(theme.appFont(15))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func rankRow(_ rank: String, xp: String, locked: Bool = false) -> some View {
        HStack {
            Text(rank)
                .font(theme.appFont(15))
                .foregroundStyle(locked ? .secondary : .primary)
            Spacer()
            Text(xp)
                .font(theme.appFont(14, weight: .medium))
                .foregroundStyle(locked ? Color(UIColor.tertiaryLabel) : gold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
