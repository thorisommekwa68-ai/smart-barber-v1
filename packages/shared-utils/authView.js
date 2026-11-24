const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (character) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
})[character]);

export function renderAuthView(mode, message = "", { allowRegistration = true } = {}) {
  const isRegister = mode === "register";
  const isRecovery = mode === "recover";
  const isPasswordUpdate = mode === "update-password";
  const title = isRegister ? "Create your account"
    : isRecovery ? "Reset your password"
      : isPasswordUpdate ? "Choose a new password"
        : "Welcome back";
  const submit = isRegister ? "Create account"
    : isRecovery ? "Send reset link"
      : isPasswordUpdate ? "Update password"
        : "Sign in";
  return `<section class="panel canva-panel" style="max-width:480px;margin:48px auto">
    <div class="eyebrow">SMART BARBER / SECURE ACCOUNT</div>
    <h1 class="page-title">${title}</h1>
    <p class="muted">${isRegister ? "Create an account to save favourites and manage your appointments."
      : isRecovery ? "Enter your email and we’ll send a secure password reset link."
        : isPasswordUpdate ? "Your password must be at least 8 characters."
          : "Sign in to manage your account and appointments."}</p>
    ${message ? `<div class="notice canva-banner" role="status">${escapeHtml(message)}</div>` : ""}
    <form data-auth-form="${mode}">
      <div style="display:grid;grid-template-columns:1fr;gap:14px;margin:20px 0">
        ${isRegister ? `<label class="field full">Name<input class="input canva-input" name="displayName" autocomplete="name" required maxlength="100"></label>` : ""}
        ${!isPasswordUpdate ? `<label class="field full">Email<input class="input canva-input" name="email" type="email" autocomplete="email" required></label>` : ""}
        ${!isRecovery ? `<label class="field full">${isPasswordUpdate ? "New password" : "Password"}<input class="input canva-input" name="password" type="password" autocomplete="${isRegister ? "new-password" : "current-password"}" minlength="8" required></label>` : ""}
      </div>
      <p class="muted" data-auth-error role="alert"></p>
      <div class="modal-actions">
        <button class="btn canva-button" type="submit">${submit}</button>
      </div>
    </form>
    <div style="display:flex;gap:14px;flex-wrap:wrap;margin-top:18px">
      ${!isPasswordUpdate && (allowRegistration || isRegister) ? `<button class="text-btn canva-button" type="button" data-auth-mode="${isRegister ? "login" : "register"}">${isRegister ? "Already have an account? Sign in" : "Create an account"}</button>` : ""}
      ${mode === "login" ? `<button class="text-btn canva-button" type="button" data-auth-mode="recover">Forgot password?</button>` : ""}
      ${isRecovery || isRegister ? `<button class="text-btn canva-button" type="button" data-auth-mode="login">Back to sign in</button>` : ""}
    </div>
  </section>`;
}

export async function submitAuthForm(form, auth) {
  const values = Object.fromEntries(new FormData(form));
  if (form.dataset.authForm === "register") {
    const result = await auth.register(values);
    if (result.error) throw result.error;
    return result.data.session
      ? { session: result.data.session, message: "Account created successfully." }
      : { session: null, message: "Check your email to verify your account, then sign in." };
  }
  if (form.dataset.authForm === "login") {
    const result = await auth.login(values);
    if (result.error) throw result.error;
    if (!result.data.session) throw new Error("Sign-in did not return an active session.");
    return { session: result.data.session, message: "Signed in successfully." };
  }
  if (form.dataset.authForm === "recover") {
    const result = await auth.recoverPassword(values.email);
    if (result.error) throw result.error;
    return { session: null, message: "If an account exists for that email, a password reset link has been sent." };
  }
  if (form.dataset.authForm === "update-password") {
    const result = await auth.updatePassword(values.password);
    if (result.error) throw result.error;
    return { session: result.data.session, message: "Password updated successfully." };
  }
  throw new Error("Unsupported authentication action.");
}
