import SwiftUI
import AuthenticationServices

struct SignInScreen: View {
    @Environment(AccountStore.self) private var account

    @State private var creating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAPSY")
                        .font(Typeface.headline(34))
                        .tracking(0.5)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Routes that start where you are.")
                        .font(Typeface.body(15))
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 12) {
                    MonoLabel(creating ? "Create account" : "Sign in", color: Palette.primary)

                    if creating {
                        field("Name", text: $name, focus: .name)
                            .textContentType(.name)
                    }
                    field("Email", text: $email, focus: .email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    secureField

                    if let error = account.errorMessage {
                        Text(error)
                            .font(Typeface.body(13))
                            .foregroundStyle(Palette.destructive)
                    }
                    if let notice = account.notice {
                        Text(notice)
                            .font(Typeface.body(13))
                            .foregroundStyle(Palette.primary)
                    }

                    Button(action: submit) {
                        Text(account.busy ? "Please wait..." : (creating ? "Create account" : "Sign in"))
                    }
                    .buttonStyle(LapsyButtonStyle(kind: .primary))
                    .disabled(account.busy || email.isEmpty || password.isEmpty)

                    HStack {
                        Button(creating ? "I already have an account" : "Create an account") {
                            creating.toggle()
                            account.errorMessage = nil
                            account.notice = nil
                        }
                        Spacer()
                        if !creating {
                            Button("Forgot password?") {
                                Task { await account.sendPasswordReset(email: email) }
                            }
                        }
                    }
                    .font(Typeface.label(11))
                    .foregroundStyle(Palette.textSecondary)
                }
                .card()

                HStack(spacing: 10) {
                    Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)
                    MonoLabel("or", size: 10)
                    Rectangle().fill(Palette.hairline).frame(height: Metrics.hairline)
                }

                VStack(spacing: 10) {
                    SignInWithAppleButton(.continue) { request in
                        account.prepareApple(request)
                    } onCompletion: { result in
                        Task { await account.finishApple(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))

                    Button {
                        Task { await account.signInWithGoogle() }
                    } label: {
                        Text("Continue with Google")
                    }
                    .buttonStyle(LapsyButtonStyle(kind: .outlined))
                    .disabled(account.busy)
                }

                Text("By continuing you agree to the Terms and Privacy Policy.")
                    .font(Typeface.body(11))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(Metrics.gutter)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.neutral.ignoresSafeArea())
    }

    private func submit() {
        focus = nil
        Task {
            if creating {
                await account.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password,
                                     name: name.trimmingCharacters(in: .whitespaces))
            } else {
                await account.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, focus target: Field) -> some View {
        TextField("", text: text, prompt: Text(label).foregroundStyle(Palette.textMuted))
            .focused($focus, equals: target)
            .font(Typeface.body(16))
            .foregroundStyle(Palette.textPrimary)
            .padding(12)
            .background(Palette.well)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(focus == target ? Palette.primary : Palette.hairline, lineWidth: Metrics.hairline))
    }

    private var secureField: some View {
        SecureField("", text: $password, prompt: Text("Password").foregroundStyle(Palette.textMuted))
            .focused($focus, equals: .password)
            .textContentType(creating ? .newPassword : .password)
            .font(Typeface.body(16))
            .foregroundStyle(Palette.textPrimary)
            .padding(12)
            .background(Palette.well)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(RoundedRectangle(cornerRadius: Metrics.corner)
                .strokeBorder(focus == .password ? Palette.primary : Palette.hairline, lineWidth: Metrics.hairline))
            .submitLabel(.go)
            .onSubmit(submit)
    }
}
