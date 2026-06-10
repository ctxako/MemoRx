import SwiftUI
import UIKit

private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

struct IdentityStepView: View {
    @ObservedObject var vm: OnboardingViewModel
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        let isApple = vm.signedInWithApple
        let title: String = isApple ? "Pick your year" : "Choose a username"
        let customTitle: Text = isApple
            ? (Text("Pick your ") + Text("year").italic().foregroundColor(warmGold))
            : (Text("Choose a ") + Text("username").italic().foregroundColor(warmGold))

        OnboardingShell(
            title: title,
            customTitle: customTitle,
            progress: (current: 0, total: 7),
            primaryTitle: "Continue",
            primaryEnabled: true,
            primaryAction: {
                nameFieldFocused = false
                if vm.nameTrimmed.isEmpty {
                    vm.name = "PharmacyStudent\(Int.random(in: 100...999))"
                }
                vm.commitIdentity()
                vm.advance()
            }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isApple {
                        appleNameBadge
                    } else {
                        nameField
                        nameCounter
                    }
                    levelCards
                }
                .padding(.top, 0)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .contentShape(Rectangle())
        .onTapGesture { nameFieldFocused = false }
    }

    // Shown instead of the text field when the user signed in with Apple.
    // Their name was already collected by the Authentication Services framework —
    // we just confirm it read-only so we never re-ask for it (Guideline 4).
    private var appleNameBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 22))
                .foregroundColor(warmGold)
            VStack(alignment: .leading, spacing: 3) {
                Text("Display name")
                    .font(.system(size: 11, weight: .semibold).smallCaps())
                    .tracking(1)
                    .foregroundColor(Color.appSecondaryText)
                Text(vm.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(.label))
            }
            Spacer()
            Text("Apple ID")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.appSecondaryText.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appCardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(warmGold.opacity(0.30), lineWidth: 1)
        )
    }

    private var nameField: some View {
        ZStack(alignment: .trailing) {
            TextField("Display name", text: $vm.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFieldFocused)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.trailing, 40)
                .frame(minHeight: 52)
                .background(Color.appCardBackground)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            nameFieldFocused
                                ? warmGold.opacity(0.4)
                                : Color.appSecondaryText.opacity(0.12),
                            lineWidth: nameFieldFocused ? 1.5 : 1
                        )
                )
                .shadow(
                    color: nameFieldFocused ? warmGold.opacity(0.15) : .clear,
                    radius: 4, x: 0, y: 0
                )
                .animation(.easeInOut(duration: 0.2), value: nameFieldFocused)
                .onChange(of: vm.name) { _, newVal in
                    let filtered = newVal.unicodeScalars.filter { s in
                        (s.value >= 65 && s.value <= 90) ||
                        (s.value >= 97 && s.value <= 122) ||
                        (s.value >= 48 && s.value <= 57) ||
                        s.value == 32
                    }.reduce("") { $0 + String($1) }
                    var next = filtered
                    if next.count > 20 { next = String(next.prefix(20)) }
                    if next != newVal { vm.name = next }
                }

            if !vm.name.isEmpty {
                Image(systemName: vm.nameIsValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(vm.nameIsValid ? .green : Color.appSecondaryText.opacity(0.5))
                    .padding(.trailing, 14)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: vm.nameIsValid)
        .animation(.easeInOut(duration: 0.15), value: vm.name.isEmpty)
    }

    private var nameCounter: some View {
        HStack {
            Spacer()
            Text("\(vm.nameTrimmed.count)/20")
                .font(.system(size: 12))
                .foregroundColor(
                    vm.nameTrimmed.count > 17
                        ? .orange
                        : Color.appSecondaryText.opacity(0.5)
                )
                .animation(.none, value: vm.nameTrimmed.count)
        }
        .padding(.horizontal, 4)
    }

    private var levelCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Year of Study")
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .tracking(1.5)
                .foregroundColor(Color.appSecondaryText)
                .padding(.bottom, 2)

            levelCard(.prePharm)

            HStack(spacing: 10) {
                levelCard(.p1)
                levelCard(.p2)
            }

            HStack(spacing: 10) {
                levelCard(.p3)
                levelCard(.p4)
            }

            levelCard(.graduate)
        }
        .padding(.top, 8)
    }

    private func levelCard(_ level: StudentLevel) -> some View {
        let isSelected = vm.selectedLevel == level
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                vm.selectedLevel = isSelected ? nil : level
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.tag)
                        .font(.system(size: 11, weight: .semibold).smallCaps())
                        .tracking(1.0)
                        .foregroundColor(
                            isSelected
                                ? warmGold.opacity(0.85)
                                : Color.appSecondaryText.opacity(0.6)
                        )
                    Text(level.displayLabel)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(.label))
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(warmGold)
                        .padding(11)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            .background(
                Color.appCardBackground.overlay(isSelected ? warmGold.opacity(0.07) : Color.clear)
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
        .accessibilityLabel(level.displayLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Double tap to select")
    }
}
