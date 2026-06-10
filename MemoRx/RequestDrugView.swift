import SwiftUI

struct RequestDrugView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var drugName = ""
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            if submitted {
                confirmationView
            } else {
                formView
            }
        }
        .navigationTitle("Request a Drug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Drug Name")
                        .font(theme.appFont(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    TextField("e.g. Metformin", text: $drugName)
                        .padding(14)
                        .background(Color.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: drugName) { _, newValue in
                            if newValue.count > 100 { drugName = String(newValue.prefix(100)) }
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Reason")
                            .font(theme.appFont(13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text("Optional")
                            .font(theme.appFont(11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    TextField("Why should this drug be added?", text: $reason, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                        .padding(14)
                        .background(Color.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: reason) { _, newValue in
                            if newValue.count > 300 { reason = String(newValue.prefix(300)) }
                        }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(theme.appFont(13))
                        .foregroundStyle(.red)
                }

                Button {
                    submit()
                } label: {
                    ZStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Submit Request")
                                .font(theme.appFont(17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(drugName.trimmingCharacters(in: .whitespaces).isEmpty ? Color(.systemGray3) : Color(.label))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(drugName.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
            .padding(24)
        }
    }

    private var confirmationView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Request Submitted!")
                .font(theme.appFont(22, weight: .bold))

            Text("Thanks for the suggestion. We review all requests and add the most-requested drugs regularly.")
                .font(theme.appFont(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Done") { dismiss() }
                .font(theme.appFont(17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(.label))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
    }

    private func submit() {
        let name = drugName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            await SupabaseManager.ensureAnonymousSession()
            guard let uid = await SupabaseManager.currentUserId() else {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Could not authenticate. Please try again."
                }
                return
            }

            let row = SupabaseManager.DrugSubmissionRow(
                user_id: uid,
                drug_name: name,
                reason: reason.trimmingCharacters(in: .whitespaces).isEmpty ? nil : reason.trimmingCharacters(in: .whitespaces),
                created_at: Date()
            )

            do {
                try await SupabaseManager.insertDrugSubmission(row)
                await MainActor.run {
                    isSubmitting = false
                    submitted = true
                }
            } catch {
                SentryReporting.captureSupabaseError(
                    error,
                    operation: "drug_submissions.insert",
                    userId: uid
                )
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Submission failed. Please try again."
                }
            }
        }
    }
}
