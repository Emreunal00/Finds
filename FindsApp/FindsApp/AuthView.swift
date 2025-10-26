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
                            TextField("Display Name (optional)", text: $displayNameUp)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                Task { await authVM.signUp(email: emailUp, password: passwordUp, displayName: displayNameUp.isEmpty ? nil : displayNameUp) }
                            } label: {
                                HStack {
                                    if authVM.isLoading { ProgressView().tint(.white) }
                                    Text("Create Account")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(authVM.isLoading || emailUp.isEmpty || passwordUp.count < 6)
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
                                    if authVM.isLoading { ProgressView().tint(.white) }
                                    Text("Sign In")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(authVM.isLoading || emailIn.isEmpty || passwordIn.isEmpty)
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
            .background(LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}

