import AuthenticationServices
import SwiftUI

/// First-launch sign-in surface.
///
/// Shown by `RootView` whenever `AuthStore` has settled with no user. The
/// only way out is a successful provider sign-in; once that lands, the
/// auth listener flips `currentUserId` and RootView swaps to the timeline.
///
/// Apple's HIG mandates that "Sign in with Apple" is offered when any
/// other social provider is — we offer Google too, and Apple sits on top
/// at equal prominence. The Google flow uses Supabase's built-in
/// `signInWithOAuth(provider:redirectTo:)` which wraps
/// `ASWebAuthenticationSession` end-to-end.
struct OnboardingScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce: AppleSignInNonce?
    @State private var inFlight = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            DailyCadenceLogo(layout: .oneWord, markSize: 72)
                .padding(.bottom, Spacing.s5)

            Text("A quieter way to log your day.")
                .font(.DS.body)
                .foregroundStyle(Color.DS.fg2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.s6)

            Spacer()

            SignInIllustration()
                .padding(.bottom, Spacing.s4)

            VStack(spacing: Spacing.s3) {
                appleButton
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                googleButton

                if let errorMessage {
                    Text(errorMessage)
                        .font(.DS.small)
                        .foregroundStyle(Color.DS.workout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.s2)
                }

                Text("By continuing you agree to our terms.")
                    .font(.DS.caption)
                    .foregroundStyle(Color.DS.fg2)
                    .padding(.top, Spacing.s2)
            }
            .padding(.horizontal, Spacing.s5)
            .padding(.bottom, Spacing.s7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.DS.bg1)
    }

    /// Apple's HIG: `.black` on light backgrounds, `.white` on dark.
    /// `SignInWithAppleButton` doesn't auto-adapt to color scheme — we
    /// pick the style explicitly so the button always reads correctly
    /// against `Color.DS.bg1` (which is cream in light, near-black in
    /// dark).
    @ViewBuilder
    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            // Generate the nonce pair just before Apple displays the
            // sheet. Holding it in `@State` is fine because the request
            // and completion run back-to-back on the main actor; no
            // concurrent `make()` calls.
            let fresh = AppleSignInNonce.make()
            nonce = fresh
            request.requestedScopes = [.fullName, .email]
            request.nonce = fresh.hashed
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .disabled(inFlight)
    }

    /// Google brand guidelines: white background + dark text + multi-
    /// color G on light surfaces; near-black background (#1F1F1F) +
    /// white text + same multi-color G on dark surfaces. The `G` logo
    /// is the official 4-color mark bundled as a vector asset
    /// (`Assets.xcassets/GoogleG.imageset`) so it stays sharp at any
    /// scale and the brand colors don't shift.
    private var googleButton: some View {
        let isDark = colorScheme == .dark
        let bg: Color = isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : .white
        let fg: Color = isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.11)
        let borderColor: Color = isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
        return Button {
            Task { await runGoogleSignIn() }
        } label: {
            HStack(spacing: 10) {
                Image("GoogleG")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text("Continue with Google")
                    .font(.system(size: 19, weight: .medium))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 50)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .disabled(inFlight)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8),
                let raw = nonce?.raw
            else {
                errorMessage = "Apple didn't return a usable identity token. Try again."
                return
            }
            Task { await exchange(idToken: token, rawNonce: raw) }
        case .failure(let error):
            // ASAuthorizationError.canceled is user-cancelled — no error UI
            if (error as? ASAuthorizationError)?.code == .canceled {
                errorMessage = nil
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func exchange(idToken: String, rawNonce: String) async {
        inFlight = true
        defer { inFlight = false }
        do {
            try await AuthStore.shared.signInWithApple(
                idToken: idToken,
                rawNonce: rawNonce
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func runGoogleSignIn() async {
        inFlight = true
        defer { inFlight = false }
        do {
            try await AuthStore.shared.signInWithGoogle()
            errorMessage = nil
        } catch {
            // ASWebAuthenticationSessionError.canceledLogin is user
            // dismissing the browser sheet — silent, no error UI.
            if let asError = error as? ASWebAuthenticationSessionError,
               asError.code == .canceledLogin {
                errorMessage = nil
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("Light") {
    OnboardingScreen()
}

#Preview("Dark") {
    OnboardingScreen().preferredColorScheme(.dark)
}
