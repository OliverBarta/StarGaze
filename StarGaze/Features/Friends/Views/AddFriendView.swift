//
//  AddFriendView.swift
//  StarGaze
//

import SwiftUI

struct AddFriendView: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @FocusState private var isUsernameFocused: Bool

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.done)
                        .focused($isUsernameFocused)
                        .onSubmit(add)
                } footer: {
                    Text("Enter your friend's StarGaze username.")
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(trimmedUsername.isEmpty)
                }
            }
            .onAppear {
                isUsernameFocused = true
            }
        }
    }

    private func add() {
        guard !trimmedUsername.isEmpty else { return }
        onAdd(trimmedUsername)
        dismiss()
    }
}

#Preview("Add friend sheet") {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            AddFriendView { _ in }
                .presentationDetents([.medium])
        }
}
