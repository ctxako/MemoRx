import SwiftUI

private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

struct GoalStepView: View {
    @ObservedObject var vm: OnboardingViewModel

    private var minimumExamDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    var body: some View {
        OnboardingShell(
            eyebrow: "YOUR GOAL",
            title: "NAPLEX Exam Date",
            customTitle: Text("NAPLEX ") + Text("Exam").italic().foregroundColor(warmGold) + Text(" Date"),
            bodyText: "Set a date and we'll show your countdown throughout the app.",
            progress: (current: 1, total: 7),
            primaryTitle: "Continue",
            primaryAction: {
                vm.commitNaplex()
                vm.advance()
            },
            backAction: vm.goBack
        ) {
            VStack(alignment: .leading, spacing: 12) {
                choiceCard(
                    title: "Not yet, I'll set it later",
                    subtitle: "You can always add this in Settings.",
                    icon: "clock",
                    isSelected: !vm.naplexToggleOn
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        vm.naplexToggleOn = false
                    }
                }

                choiceCard(
                    title: "Yes, I have a date",
                    subtitle: "I'll set it now and track my countdown.",
                    icon: "calendar",
                    isSelected: vm.naplexToggleOn
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        vm.naplexToggleOn = true
                    }
                }

                if vm.naplexToggleOn {
                    DatePicker(
                        "Exam Date",
                        selection: $vm.selectedExamDate,
                        in: minimumExamDate...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(warmGold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appCardBackground)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(warmGold.opacity(0.35), lineWidth: 1)
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        )
                    )
                }
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            if vm.selectedExamDate < minimumExamDate {
                vm.selectedExamDate = minimumExamDate
            }
        }
    }

    private func choiceCard(
        title: String,
        subtitle: String?,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(white: 0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(isSelected ? warmGold : Color(.secondaryLabel))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(.label))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundColor(
                                    isSelected
                                        ? warmGold.opacity(0.85)
                                        : Color.appSecondaryText
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(warmGold)
                        .padding(14)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                Color.appCardBackground
                    .overlay(isSelected ? warmGold.opacity(0.07) : Color.clear)
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? warmGold.opacity(0.65) : Color.appSecondaryText.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? warmGold.opacity(0.18) : .clear,
                radius: 8, x: 0, y: 0
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
