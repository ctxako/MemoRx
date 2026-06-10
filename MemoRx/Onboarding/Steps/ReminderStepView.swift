import SwiftUI
import UserNotifications

private let warmGold = Color(red: 201 / 255, green: 185 / 255, blue: 154 / 255)

private struct TimeSlot: Identifiable {
    let id: Int        // hour in 24h
    let hour: Int
    let display: String
    let label: String
}

private let timeSlots: [TimeSlot] = [
    TimeSlot(id: 6,  hour: 6,  display: "6 AM",  label: "Early"),
    TimeSlot(id: 9,  hour: 9,  display: "9 AM",  label: "Morning"),
    TimeSlot(id: 12, hour: 12, display: "12 PM", label: "Midday"),
    TimeSlot(id: 18, hour: 18, display: "6 PM",  label: "Evening"),
]

struct ReminderStepView: View {
    @ObservedObject var vm: OnboardingViewModel
    @State private var selectedHour: Int = 9
    @State private var showCustomPicker = false
    @State private var permissionRequested = false

    var body: some View {
        OnboardingShell(
            eyebrow: "STAY ON TRACK",
            title: "Daily Reminder",
            customTitle: Text("Daily ") + Text("Reminder").italic().foregroundColor(warmGold),
            bodyText: "We\u{2019}ll nudge you once a day. You can change this anytime in Settings.",
            progress: (current: 5, total: 7),
            primaryTitle: "Continue",
            primaryAction: {
                applySelectedTime()
                requestPermissionIfNeeded()
                if vm.notificationStatus == .denied {
                    vm.showPermissionDeniedToast()
                }
                vm.commitReminder()
                vm.advance()
            },
            backAction: vm.goBack
        ) {
            VStack(spacing: 10) {
                quickSelectCard

                reminderSetStrip

                if vm.notificationStatus == .notDetermined {
                    permissionCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.bottom, 8)
            .animation(.easeInOut(duration: 0.2), value: vm.notificationStatus)
        }
        .onAppear {
            vm.refreshNotificationStatus()
            // Seed selectedHour from vm.reminderTime
            let h = Calendar.current.component(.hour, from: vm.reminderTime)
            if timeSlots.contains(where: { $0.hour == h }) {
                selectedHour = h
            }
        }
        .sheet(isPresented: $showCustomPicker) {
            customTimeSheet
        }
    }

    // MARK: - Quick-select grid

    private var quickSelectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(warmGold.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(warmGold.opacity(0.25), lineWidth: 1)
                        )
                        .frame(width: 44, height: 44)
                    Text("\u{1F514}")
                        .font(.system(size: 22))
                }
                Text("When do you study best?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(.label))
            }

            HStack(spacing: 8) {
                ForEach(timeSlots) { slot in
                    timeSlotButton(slot)
                }
            }

            HStack(spacing: 4) {
                Text("Want a different time?")
                    .font(.system(size: 13))
                    .foregroundColor(Color.appSecondaryText)
                Spacer()
                Button {
                    showCustomPicker = true
                } label: {
                    HStack(spacing: 3) {
                        Text("Set custom")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(warmGold)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.appSecondaryText.opacity(0.12), lineWidth: 1)
        )
    }

    private func timeSlotButton(_ slot: TimeSlot) -> some View {
        let isSelected = selectedHour == slot.hour
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedHour = slot.hour
            }
            applySelectedTime()
            requestPermissionIfNeeded()
        } label: {
            VStack(spacing: 2) {
                Text(slot.display)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? warmGold : Color(.label))
                Text(slot.label)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? warmGold.opacity(0.8) : Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Color.appCardBackground
                    .overlay(isSelected ? warmGold.opacity(0.07) : Color.clear)
            )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? warmGold.opacity(0.65) : Color.appSecondaryText.opacity(0.15),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    // MARK: - "Reminder set for" strip

    private var reminderSetStrip: some View {
        let formatted = formattedTime(from: vm.reminderTime)
        return HStack {
            Text("Reminder set for")
                .font(.system(size: 14))
                .foregroundColor(Color.appSecondaryText)
            Spacer()
            Text(formatted)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundColor(warmGold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appCardBackground)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.appSecondaryText.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Allow notifications card

    private var permissionCard: some View {
        Button {
            requestPermissionIfNeeded()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(warmGold.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(warmGold.opacity(0.25), lineWidth: 1)
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "bell.badge")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(warmGold)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow notifications")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(.label))
                    Text("Required to receive daily reminders")
                        .font(.system(size: 13))
                        .foregroundColor(Color.appSecondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appSecondaryText.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCardBackground)
            .cornerRadius(14)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(warmGold.opacity(0.35))
                    .frame(width: 3)
                    .cornerRadius(2)
                    .padding(.vertical, 12)
                    .padding(.leading, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.appSecondaryText.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Allow notifications")
        .accessibilityHint("Required to receive daily reminders")
    }

    // MARK: - Custom time sheet

    private var customTimeSheet: some View {
        VStack(spacing: 0) {
            DatePicker(
                "Custom reminder time",
                selection: $vm.reminderTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(warmGold)
            .padding(.top, 16)
            .onChange(of: vm.reminderTime) { _, _ in
                // Clear preset selection when user picks custom
                let h = Calendar.current.component(.hour, from: vm.reminderTime)
                if !timeSlots.contains(where: { $0.hour == h }) {
                    selectedHour = -1
                } else {
                    selectedHour = h
                }
            }

            Button {
                requestPermissionIfNeeded()
                showCustomPicker = false
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(warmGold)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .background(Color.appBackground)
    }

    // MARK: - Helpers

    private func applySelectedTime() {
        guard selectedHour >= 0 else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = selectedHour
        comps.minute = 0
        if let date = Calendar.current.date(from: comps) {
            vm.reminderTime = date
        }
    }

    private func requestPermissionIfNeeded() {
        guard !permissionRequested, vm.notificationStatus == .notDetermined else { return }
        permissionRequested = true
        vm.requestNotificationPermission()
    }

    private func formattedTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
