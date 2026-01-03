import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var isSignUp = false

    // Sign In
    @State private var emailIn = ""
    @State private var passwordIn = ""

    // Sign Up
    @State private var emailUp = ""
    @State private var passwordUp = ""
    @State private var displayNameUp = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Welcome to Finds")
                    .font(.largeTitle).bold()
                    .padding(.top, 24)

                Picker("", selection: $isSignUp) {
                    Text("Sign In").tag(false)
                    Text("Sign Up").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    if isSignUp {
                        VStack(spacing: 12) {
                            TextField("Email", text: $emailUp)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textFieldStyle(.roundedBorder)

                            SecureField("Password", text: $passwordUp)
                                .textFieldStyle(.roundedBorder)

                            // Display Name REQUIRED
                            TextField("Display Name", text: $displayNameUp)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                let trimmedName = displayNameUp.trimmingCharacters(in: .whitespacesAndNewlines)
                                Task {
                                    await authVM.signUp(email: emailUp,
                                                        password: passwordUp,
                                                        displayName: trimmedName)
                                }
                            } label: {
                                HStack {
                                    if authVM.isLoading {}
                                    Text("Create Account")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(authVM.isLoading
                                      || emailUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || passwordUp.count < 6
                                      || displayNameUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 12) {
                            TextField("Email", text: $emailIn)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textFieldStyle(.roundedBorder)

                            SecureField("Password", text: $passwordIn)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                Task { await authVM.signIn(email: emailIn, password: passwordIn) }
                            } label: {
                                HStack {
                                    if authVM.isLoading {}
                                    Text("Sign In")
                                }
                                .frame(maxWidth: .infinity)
                                
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(authVM.isLoading
                                      || emailIn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || passwordIn.isEmpty)
                        }
                        .padding(.horizontal)
                    }
                }

                if let err = authVM.errorMessage {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
