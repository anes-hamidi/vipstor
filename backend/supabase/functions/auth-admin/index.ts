import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * auth-admin — account lifecycle + staff PIN sign-in.
 *
 * Deploy with JWT verification disabled:
 *   supabase functions deploy auth-admin --no-verify-jwt
 *
 * The function only uses the service role after validating the caller for
 * staff actions. Moderators authenticate with phone + password and keep a
 * normal Supabase session. Ordinary staff authenticate with a PIN only: the
 * function verifies the PIN server-side, rotates the hidden Auth password and
 * returns a real Supabase session so RLS/data access keeps working.
 *
 * Public actions are deliberately limited to customer self-registration,
 * recovery-code password reset, the PIN staff directory and PIN sign-in.
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ??
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
  "";

const AUTH_EMAIL_DOMAIN = "vip.algomend.app";
const STAFF_ROLES = ["moderator", "manager", "cashier", "driver"] as const;
const PIN_STAFF_ROLES = ["manager", "cashier", "driver"] as const;
const RECOVERY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

/**
 * Separate anonymous client used only to exchange the rotated password for a
 * Supabase session. Keeping this away from `admin` prevents sign-in from
 * replacing the service-role authorization used by later admin operations in
 * the same isolate.
 */
function createSessionClient() {
  return createClient(SUPABASE_URL, ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class ApiError extends Error {
  status: number;
  code: string;

  constructor(status: number, message: string, code = "error") {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorResponse(error: unknown): Response {
  if (error instanceof ApiError) {
    return json(
      { success: false, error: error.message, code: error.code },
      error.status,
    );
  }
  console.error("auth-admin unexpected error", error);
  return json(
    {
      success: false,
      error: "حدث خطأ غير متوقع. حاول مرة أخرى.",
      code: "internal_error",
    },
    500,
  );
}

function messageOf(error: unknown): string {
  if (!error) return "";
  if (typeof error === "string") return error;
  if (typeof error === "object" && "message" in error) {
    return String((error as { message?: unknown }).message ?? "");
  }
  return String(error);
}

function normalizePhone(input: unknown): { e164: string; local: string } {
  let value = String(input ?? "").trim().replace(/[^0-9+]/g, "");
  if (!value) throw new ApiError(400, "رقم الهاتف مطلوب", "invalid_phone");

  if (value.startsWith("00")) value = `+${value.slice(2)}`;
  let digits = value.replace(/[^0-9]/g, "");

  if (value.startsWith("+213")) {
    digits = value.slice(1);
  } else if (digits.startsWith("213")) {
    // already international
  } else if (/^0[5-7][0-9]{8}$/.test(digits)) {
    digits = `213${digits.slice(1)}`;
  } else {
    throw new ApiError(400, "رقم الهاتف غير صالح", "invalid_phone");
  }

  if (!/^213[5-7][0-9]{8}$/.test(digits)) {
    throw new ApiError(400, "رقم الهاتف غير صالح", "invalid_phone");
  }

  return { e164: `+${digits}`, local: `0${digits.slice(3)}` };
}

function authEmailForPhone(localPhone: string): string {
  return `${
    localPhone.replace(/[^0-9]/g, "").replace(/^0/, "213")
  }@${AUTH_EMAIL_DOMAIN}`;
}

function validateName(input: unknown): string {
  const name = String(input ?? "").trim();
  if (name.length < 2 || name.length > 100) {
    throw new ApiError(400, "الاسم يجب أن يكون بين 2 و100 حرف", "invalid_name");
  }
  return name;
}

function validatePassword(input: unknown): string {
  const password = String(input ?? "");
  if (password.length < 8) {
    throw new ApiError(
      400,
      "كلمة المرور يجب أن تكون 8 أحرف على الأقل",
      "weak_password",
    );
  }
  if (new TextEncoder().encode(password).length > 72) {
    throw new ApiError(
      400,
      "كلمة المرور طويلة جداً (72 بايت كحد أقصى)",
      "weak_password",
    );
  }
  return password;
}

function validatePin(input: unknown, required = true): string | null {
  const pin = String(input ?? "").trim();
  if (!pin && !required) return null;
  if (!/^[0-9]{4,8}$/.test(pin)) {
    throw new ApiError(
      400,
      "رمز PIN يجب أن يكون من 4 إلى 8 أرقام",
      "invalid_pin",
    );
  }
  return pin;
}

function validateRole(input: unknown): string {
  const role = String(input ?? "").trim();
  if (!STAFF_ROLES.includes(role as (typeof STAFF_ROLES)[number])) {
    throw new ApiError(400, "دور الموظف غير صالح", "invalid_role");
  }
  return role;
}

function isPinStaffRole(role: unknown): boolean {
  return PIN_STAFF_ROLES.includes(
    String(role ?? "") as (typeof PIN_STAFF_ROLES)[number],
  );
}

/**
 * Random, never-disclosed password used only to obtain a Supabase session for
 * a PIN-authenticated staff member. It is rotated on every PIN sign-in, so no
 * lasting password credential is exposed to staff or moderators.
 */
function generateInternalPassword(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const random = Array.from(
    bytes,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  // Prefix guarantees upper/lower/digit/symbol for projects with a strict
  // password policy while the 256-bit random suffix carries the entropy.
  return `Aa1!${random}`;
}

function validateLanguage(input: unknown): string {
  const language = String(input ?? "ar").trim();
  if (language !== "ar" && language !== "fr") {
    throw new ApiError(400, "اللغة غير صالحة", "invalid_language");
  }
  return language;
}

function generateRecoveryCode(): string {
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  let code = "";
  for (const byte of bytes) {
    code += RECOVERY_ALPHABET[byte % RECOVERY_ALPHABET.length];
  }
  return `${code.slice(0, 4)}-${code.slice(4, 8)}-${code.slice(8, 12)}`;
}

function normalizeRecoveryCode(input: unknown): string {
  return String(input ?? "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
}

function clientIp(req: Request): string {
  return (
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      req.headers.get("cf-connecting-ip") ??
      req.headers.get("x-real-ip") ??
      "unknown"
  );
}

async function enforceRateLimit(
  req: Request,
  bucket: string,
  max: number,
  windowSeconds: number,
  lockSeconds: number,
): Promise<void> {
  const key = `${bucket}:${clientIp(req)}`;
  const { data, error } = await admin.rpc("rpc_auth_rate_limit", {
    p_bucket: key,
    p_max: max,
    p_window_seconds: windowSeconds,
    p_lock_seconds: lockSeconds,
  });
  if (error) {
    throw new ApiError(
      503,
      "تعذر التحقق من حد المحاولات. حاول لاحقاً.",
      "rate_limit_unavailable",
    );
  }
  if (!data?.allowed) {
    const retry = Number(data?.retry_after ?? lockSeconds);
    throw new ApiError(
      429,
      `محاولات كثيرة. حاول بعد ${Math.max(1, Math.ceil(retry / 60))} دقيقة.`,
      "rate_limited",
    );
  }
}

function bearerToken(req: Request): string {
  const header = req.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  return match?.[1]?.trim() ?? "";
}

async function requireModerator(req: Request): Promise<{
  token: string;
  authUserId: string;
  actorId: string;
}> {
  const token = bearerToken(req);
  if (!token) {
    throw new ApiError(401, "يجب تسجيل الدخول", "unauthorized");
  }

  const {
    data: { user },
    error: authError,
  } = await admin.auth.getUser(token);
  if (authError || !user) {
    throw new ApiError(401, "جلسة غير صالحة", "unauthorized");
  }

  const { data: actor, error } = await admin
    .from("users")
    .select("id, role, active, deleted_at")
    .eq("auth_user_id", user.id)
    .maybeSingle();

  if (
    error ||
    !actor ||
    actor.role !== "moderator" ||
    actor.active !== true ||
    actor.deleted_at
  ) {
    throw new ApiError(403, "هذه العملية متاحة للمشرف فقط", "forbidden");
  }

  return { token, authUserId: user.id, actorId: actor.id };
}

async function verifyModeratorPin(
  authUserId: string,
  pin: string,
): Promise<void> {
  const { data, error } = await admin.rpc("rpc_auth_verify_moderator_pin", {
    p_auth_user_id: authUserId,
    p_pin: pin,
  });
  if (error) {
    throw new ApiError(
      503,
      "تعذر التحقق من رمز PIN. حاول لاحقاً.",
      "pin_check_failed",
    );
  }
  if (!data?.valid) {
    throw new ApiError(
      403,
      String(data?.message ?? "رمز PIN غير صحيح"),
      "invalid_pin",
    );
  }
}

async function ensureLivePhoneAvailable(
  localPhone: string,
  e164: string,
  exceptUserId?: string,
): Promise<void> {
  let query = admin
    .from("users")
    .select("id")
    .in("phone", [localPhone, e164])
    .is("deleted_at", null)
    .limit(1);
  if (exceptUserId) query = query.neq("id", exceptUserId);

  const { data, error } = await query;
  if (error) {
    throw new ApiError(
      503,
      "تعذر التحقق من رقم الهاتف. حاول لاحقاً.",
      "phone_check_failed",
    );
  }
  if (data && data.length > 0) {
    throw new ApiError(409, "رقم الهاتف مسجل بالفعل", "phone_exists");
  }
}

async function callUserRpc(
  token: string,
  fn: string,
  params: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(params),
  });

  const text = await response.text();
  let payload: unknown = null;
  try {
    payload = text ? JSON.parse(text) : null;
  } catch {
    payload = text;
  }

  if (!response.ok) {
    const detail =
      payload && typeof payload === "object" && "message" in payload
        ? String((payload as { message?: unknown }).message ?? "")
        : "";
    throw new ApiError(
      response.status === 403 ? 403 : 400,
      detail || "تعذر حفظ بيانات الموظف",
      "profile_update_failed",
    );
  }

  if (!payload || typeof payload !== "object") {
    throw new ApiError(
      502,
      "استجابة غير صالحة من قاعدة البيانات",
      "profile_update_failed",
    );
  }
  return payload as Record<string, unknown>;
}

function mapAuthCreateError(error: unknown): string {
  const message = messageOf(error);
  if (/already|registered|exists|duplicate/i.test(message)) {
    return "رقم الهاتف مسجل بالفعل";
  }
  if (/password/i.test(message)) {
    return "كلمة المرور غير مقبولة. اختر كلمة مرور أقوى.";
  }
  if (/email/i.test(message)) {
    return "تعذر إنشاء الحساب بسبب بيانات الدخول. حاول لاحقاً.";
  }
  return "تعذر إنشاء الحساب. تحقق من البيانات وحاول مجدداً.";
}

/**
 * Best-effort cleanup when Auth creation succeeded but the public-profile
 * finalize RPC failed. Soft-delete the trigger-provisioned row so the phone is
 * reusable, but keep auth_user_id attached: if deleting the Auth identity also
 * fails, the deleted-row guard in rpc_bootstrap_my_account still blocks it.
 */
async function cleanupProvisionedUser(authUserId: string): Promise<void> {
  const { error: profileError } = await admin
    .from("users")
    .update({
      active: false,
      deleted_at: new Date().toISOString(),
      pin_code: null,
      must_change_pin: false,
    })
    .eq("auth_user_id", authUserId);
  if (profileError) {
    console.error("failed to clean up provisioned public user", profileError);
  }

  const { error: authError } = await admin.auth.admin.deleteUser(authUserId);
  if (authError) {
    console.error("failed to clean up provisioned auth user", authError);
  }
}

async function customerRegister(req: Request, body: Record<string, unknown>) {
  const name = validateName(body.name);
  const phone = normalizePhone(body.phone);
  const password = validatePassword(body.password);
  const recoveryCode = generateRecoveryCode();
  const recoveryCodeStored = normalizeRecoveryCode(recoveryCode);

  await enforceRateLimit(req, "customer_register", 20, 3600, 3600);
  await ensureLivePhoneAvailable(phone.local, phone.e164);

  const { data: created, error: createError } = await admin.auth.admin
    .createUser({
      email: authEmailForPhone(phone.local),
      password,
      email_confirm: true,
      user_metadata: {
        name,
        full_name: name,
        phone: phone.local,
      },
      app_metadata: { role: "customer" },
    });

  if (createError || !created.user) {
    throw new ApiError(
      409,
      mapAuthCreateError(createError),
      "auth_create_failed",
    );
  }

  const { data: finalized, error: finalizeError } = await admin.rpc(
    "rpc_auth_customer_register_finalize",
    {
      p_auth_user_id: created.user.id,
      p_phone: phone.local,
      p_name: name,
      p_recovery_code: recoveryCodeStored,
    },
  );

  if (finalizeError) {
    await cleanupProvisionedUser(created.user.id);
    throw new ApiError(
      409,
      messageOf(finalizeError).includes("already exists")
        ? "رقم الهاتف مسجل بالفعل"
        : "تعذر إنشاء الحساب. تحقق من البيانات وحاول مجدداً.",
      "registration_failed",
    );
  }

  return json({
    success: true,
    phone: phone.local,
    user_id: finalized?.user_id,
    recovery_code: recoveryCode,
  });
}

async function customerResetPassword(
  req: Request,
  body: Record<string, unknown>,
) {
  const phone = normalizePhone(body.phone);
  const password = validatePassword(body.new_password);
  const recoveryCode = normalizeRecoveryCode(body.recovery_code);
  if (recoveryCode.length < 8) {
    throw new ApiError(
      400,
      "رقم الهاتف أو رمز الاستعادة غير صحيح",
      "invalid_recovery_code",
    );
  }

  await enforceRateLimit(req, "customer_reset", 12, 3600, 3600);
  await enforceRateLimit(
    req,
    `customer_reset_phone:${phone.local}`,
    5,
    900,
    900,
  );

  const { data: verified, error: verifyError } = await admin.rpc(
    "rpc_auth_customer_recovery_verify",
    {
      p_phone: phone.local,
      p_recovery_code: recoveryCode,
    },
  );

  if (verifyError) {
    throw new ApiError(
      503,
      "تعذر التحقق من رمز الاستعادة. حاول لاحقاً.",
      "recovery_check_failed",
    );
  }
  if (verified?.status !== "success") {
    throw new ApiError(
      verified?.code === "locked" ? 429 : 400,
      String(verified?.error ?? "رقم الهاتف أو رمز الاستعادة غير صحيح"),
      String(verified?.code ?? "invalid_recovery_code"),
    );
  }

  const newRecoveryCode = generateRecoveryCode();
  const newRecoveryCodeStored = normalizeRecoveryCode(newRecoveryCode);

  const { error: passwordError } = await admin.auth.admin.updateUserById(
    String(verified.auth_user_id),
    { password },
  );
  if (passwordError) {
    throw new ApiError(
      502,
      "تعذر تحديث كلمة المرور. حاول لاحقاً.",
      "password_update_failed",
    );
  }

  const { error: rotateError } = await admin.rpc(
    "rpc_auth_customer_recovery_rotate",
    {
      p_auth_user_id: String(verified.auth_user_id),
      p_user_id: String(verified.user_id),
      p_new_recovery_code: newRecoveryCodeStored,
    },
  );
  if (rotateError) {
    console.error("failed to rotate recovery code", rotateError);
    return json({
      success: true,
      warning:
        "تم تغيير كلمة المرور، لكن تعذر إنشاء رمز استعادة جديد. استخدم رمزك السابق.",
      recovery_code: null,
    });
  }

  return json({
    success: true,
    recovery_code: newRecoveryCode,
  });
}

/**
 * Public PIN-terminal directory. Only active cashiers, managers and drivers
 * are listed. Phone numbers are intentionally omitted: the terminal only needs
 * a display name and role, and this endpoint is unauthenticated.
 */
async function staffDirectory(req: Request) {
  await enforceRateLimit(req, "staff_directory", 120, 60, 60);

  const { data, error } = await admin
    .from("users")
    .select("id, name, role, language, must_change_pin")
    .in("role", [...PIN_STAFF_ROLES])
    .eq("active", true)
    .is("deleted_at", null)
    .order("name");

  if (error) {
    console.error("failed to load staff directory", error);
    throw new ApiError(
      503,
      "تعذر تحميل قائمة الموظفين. تحقق من الاتصال وحاول لاحقاً.",
      "directory_failed",
    );
  }

  return json({ success: true, staff: data ?? [] });
}

/**
 * PIN-only staff sign-in.
 *
 * 1. Verify the PIN through the service-role-only internal RPC, which keeps the
 *    existing bcrypt comparison and escalating lockout rules.
 * 2. Rotate the hidden Supabase Auth password to a random secret.
 * 3. Sign in with that secret and return the resulting session tokens.
 *
 * The app installs those tokens with `auth.setSession`, so the staff member
 * gets a normal Supabase JWT and every RLS policy continues to work. Moderators
 * are rejected here and must use phone + password.
 */
async function staffPinLogin(req: Request, body: Record<string, unknown>) {
  const userId = String(body.user_id ?? "").trim();
  const pin = validatePin(body.pin);
  if (!userId) {
    throw new ApiError(400, "اختر الموظف أولاً", "invalid_user");
  }

  await enforceRateLimit(req, "staff_pin_login", 30, 300, 300);

  const { data: user, error: userError } = await admin
    .from("users")
    .select(
      "id, name, phone, role, active, language, must_change_pin, auth_user_id, deleted_at",
    )
    .eq("id", userId)
    .maybeSingle();

  if (userError) {
    console.error("failed to read PIN login user", userError);
    throw new ApiError(
      503,
      "تعذر قراءة بيانات الحساب. حاول لاحقاً.",
      "account_read_failed",
    );
  }
  if (!user || user.deleted_at || user.active !== true) {
    throw new ApiError(
      403,
      "هذا الحساب غير متاح. راجع الإدارة.",
      "account_unavailable",
    );
  }
  if (!isPinStaffRole(user.role)) {
    throw new ApiError(
      403,
      "دخول المشرف يتطلب رقم الهاتف وكلمة المرور.",
      "moderator_password_required",
    );
  }
  if (!user.auth_user_id) {
    throw new ApiError(
      409,
      "الحساب غير مرتبط ببيانات دخول. اطلب من الإدارة إعادة إنشائه.",
      "auth_missing",
    );
  }

  await enforceRateLimit(
    req,
    `staff_pin_login_user:${user.id}`,
    8,
    300,
    300,
  );

  const { data: verified, error: verifyError } = await admin.rpc(
    "internal_verify_user_pin",
    {
      p_user_id: user.id,
      p_pin: pin,
    },
  );

  if (verifyError) {
    console.error("failed to verify staff PIN", verifyError);
    throw new ApiError(
      503,
      "تعذر التحقق من رمز PIN. حاول لاحقاً.",
      "pin_check_failed",
    );
  }
  if (!verified?.valid) {
    const locked = verified?.locked === true;
    throw new ApiError(
      locked ? 429 : 400,
      String(verified?.message ?? "رمز PIN غير صحيح"),
      locked ? "pin_locked" : "invalid_pin",
    );
  }

  const internalPassword = generateInternalPassword();
  const { error: rotateError } = await admin.auth.admin.updateUserById(
    String(user.auth_user_id),
    { password: internalPassword },
  );
  if (rotateError) {
    console.error("failed to rotate staff auth password", rotateError);
    throw new ApiError(
      502,
      "تعذر بدء جلسة الدخول. حاول لاحقاً.",
      "session_prepare_failed",
    );
  }

  const sessionClient = createSessionClient();
  const phone = String(user.phone ?? "");
  let signIn = await sessionClient.auth.signInWithPassword({
    email: authEmailForPhone(phone),
    password: internalPassword,
  });

  // Legacy phone-auth identities may not have the synthetic email. Keep the
  // password-only fallback without ever sending an SMS.
  if (signIn.error) {
    try {
      const normalizedPhone = normalizePhone(phone);
      signIn = await sessionClient.auth.signInWithPassword({
        phone: normalizedPhone.e164,
        password: internalPassword,
      });
    } catch {
      // Keep the original/synthetic-email error for the response below.
    }
  }

  const session = signIn.data.session;
  if (signIn.error || !session) {
    console.error("failed to create staff session", signIn.error);
    throw new ApiError(
      502,
      "تعذر بدء جلسة الدخول. حاول لاحقاً.",
      "session_create_failed",
    );
  }

  return json({
    success: true,
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_in: session.expires_in,
    token_type: session.token_type,
    user: {
      id: user.id,
      name: user.name,
      role: user.role,
      language: user.language,
      must_change_pin: user.must_change_pin === true,
    },
  });
}

async function staffCreate(req: Request, body: Record<string, unknown>) {
  const caller = await requireModerator(req);
  const pin = validatePin(body.admin_pin);
  await verifyModeratorPin(caller.authUserId, pin!);

  const name = validateName(body.name);
  const phone = normalizePhone(body.phone);
  const role = validateRole(body.role);
  // Only moderators use a password. PIN staff get a random internal Auth
  // password that is never known to the client and is rotated on every PIN
  // sign-in. A caller therefore cannot create a staff account with a known
  // password.
  const password = role === "moderator"
    ? validatePassword(body.password)
    : generateInternalPassword();
  const initialPin = validatePin(body.initial_pin);
  const language = validateLanguage(body.language);

  await enforceRateLimit(
    req,
    `staff_create:${caller.actorId}`,
    30,
    3600,
    3600,
  );
  await ensureLivePhoneAvailable(phone.local, phone.e164);

  const { data: created, error: createError } = await admin.auth.admin
    .createUser({
      email: authEmailForPhone(phone.local),
      password,
      email_confirm: true,
      user_metadata: {
        name,
        full_name: name,
        phone: phone.local,
      },
      app_metadata: { role },
    });

  if (createError || !created.user) {
    throw new ApiError(
      409,
      mapAuthCreateError(createError),
      "auth_create_failed",
    );
  }

  const { data: finalized, error: finalizeError } = await admin.rpc(
    "rpc_auth_staff_create_finalize",
    {
      p_actor_id: caller.actorId,
      p_auth_user_id: created.user.id,
      p_name: name,
      p_phone: phone.local,
      p_role: role,
      p_initial_pin: initialPin,
      p_language: language,
    },
  );

  if (finalizeError) {
    await cleanupProvisionedUser(created.user.id);
    const message = messageOf(finalizeError);
    throw new ApiError(
      /already exists/i.test(message) ? 409 : 400,
      /already exists/i.test(message)
        ? "رقم الهاتف مسجل بالفعل"
        : "تعذر إنشاء حساب الموظف. تحقق من البيانات.",
      "staff_create_failed",
    );
  }

  return json({
    success: true,
    user_id: finalized?.user_id,
    phone: phone.local,
    role,
  });
}

async function staffUpdate(req: Request, body: Record<string, unknown>) {
  const caller = await requireModerator(req);
  const pin = validatePin(body.admin_pin);
  await verifyModeratorPin(caller.authUserId, pin!);

  const targetUserId = String(body.target_user_id ?? "").trim();
  if (!targetUserId) {
    throw new ApiError(400, "معرّف الموظف مطلوب", "invalid_target");
  }

  const { data: target, error: targetError } = await admin
    .from("users")
    .select(
      "id, phone, name, role, active, language, auth_user_id, deleted_at",
    )
    .eq("id", targetUserId)
    .maybeSingle();

  if (targetError) {
    throw new ApiError(
      503,
      "تعذر قراءة بيانات الموظف",
      "target_read_failed",
    );
  }
  if (!target || target.deleted_at) {
    throw new ApiError(404, "حساب الموظف غير موجود", "not_found");
  }
  if (target.role === "customer") {
    throw new ApiError(403, "هذا الحساب ليس حساب موظف", "not_staff");
  }
  if (!target.auth_user_id) {
    throw new ApiError(
      409,
      "الحساب غير مرتبط ببيانات دخول. أعد إنشاءه.",
      "auth_missing",
    );
  }

  const name = validateName(body.name);
  const phone = normalizePhone(body.phone);
  const role = validateRole(body.role);
  const language = validateLanguage(body.language);
  const active = body.active;
  if (typeof active !== "boolean") {
    throw new ApiError(400, "حالة الحساب غير صالحة", "invalid_active");
  }
  const newPin = validatePin(body.new_pin, false);
  const rawPassword = String(body.new_password ?? "");
  let newPassword: string | null = null;

  if (role === "moderator") {
    newPassword = rawPassword.length > 0
      ? validatePassword(rawPassword)
      : null;
    if (target.role !== "moderator" && !newPassword) {
      throw new ApiError(
        400,
        "عند ترقية موظف إلى مشرف، عيّن كلمة مرور دخول جديدة.",
        "password_required",
      );
    }
  } else if (target.role === "moderator") {
    // Demoting a moderator to a PIN-only role retires the password they used
    // to sign in. The replacement is random and never returned.
    newPassword = generateInternalPassword();
  }

  const phoneChanged = target.phone !== phone.local;
  const roleChanged = target.role !== role;
  if (phoneChanged) {
    await ensureLivePhoneAvailable(phone.local, phone.e164, targetUserId);
  }

  // Keep all public.users business rules (last moderator, PIN, audit) in the
  // existing SECURITY DEFINER RPC, invoked with the caller's own JWT.
  const profile = await callUserRpc(caller.token, "rpc_save_user_profile", {
    p_caller_id: caller.actorId,
    p_caller_pin: pin,
    p_target_user_id: targetUserId,
    p_name: name,
    p_phone: phoneChanged ? phone.local : target.phone,
    p_language: language,
    p_role: role,
    p_active: active,
    p_new_pin: newPin,
  });

  if (profile.status !== "success") {
    throw new ApiError(
      400,
      String(profile.message ?? "تعذر حفظ بيانات الموظف"),
      "profile_update_failed",
    );
  }

  if (phoneChanged || newPassword || roleChanged) {
    const { data: authData, error: authReadError } = await admin.auth.admin
      .getUserById(target.auth_user_id);
    if (authReadError || !authData?.user) {
      throw new ApiError(
        502,
        "تم حفظ الملف، لكن تعذر قراءة بيانات الدخول. حاول مجدداً.",
        "auth_sync_failed",
      );
    }

    const attributes: Record<string, unknown> = {
      user_metadata: {
        ...(authData.user.user_metadata ?? {}),
        name,
        full_name: name,
        phone: phone.local,
      },
      app_metadata: {
        ...(authData.user.app_metadata ?? {}),
        role,
      },
    };
    if (phoneChanged) {
      attributes.email = authEmailForPhone(phone.local);
      attributes.email_confirm = true;
    }
    if (newPassword) attributes.password = newPassword;

    const { error: authUpdateError } = await admin.auth.admin.updateUserById(
      target.auth_user_id,
      attributes,
    );
    if (authUpdateError) {
      throw new ApiError(
        502,
        phoneChanged
          ? "تم حفظ الملف، لكن تعذر تحديث بيانات الدخول/الهاتف. حاول مجدداً."
          : newPassword
          ? "تم حفظ الملف، لكن تعذر تحديث كلمة المرور. حاول مجدداً."
          : "تم حفظ الملف، لكن تعذر تحديث صلاحية الدخول. حاول مجدداً.",
        "auth_sync_failed",
      );
    }
  }

  return json({
    success: true,
    user_id: targetUserId,
    phone: phone.local,
    role,
    active,
  });
}

async function staffDelete(req: Request, body: Record<string, unknown>) {
  const caller = await requireModerator(req);
  const pin = validatePin(body.admin_pin);
  await verifyModeratorPin(caller.authUserId, pin!);

  const targetUserId = String(body.target_user_id ?? "").trim();
  if (!targetUserId) {
    throw new ApiError(400, "معرّف الموظف مطلوب", "invalid_target");
  }

  const { data: prepared, error: prepareError } = await admin.rpc(
    "rpc_auth_staff_delete_prepare",
    {
      p_actor_id: caller.actorId,
      p_target_user_id: targetUserId,
    },
  );

  if (prepareError) {
    const message = messageOf(prepareError);
    throw new ApiError(
      /last active moderator|own account/i.test(message) ? 403 : 400,
      /last active moderator/i.test(message)
        ? "لا يمكن حذف آخر مشرف عام نشط"
        : /own account/i.test(message)
        ? "لا يمكنك حذف حسابك الحالي"
        : "تعذر حذف حساب الموظف",
      "staff_delete_failed",
    );
  }
  if (prepared?.status !== "success") {
    throw new ApiError(
      400,
      String(prepared?.message ?? "تعذر حذف حساب الموظف"),
      "staff_delete_failed",
    );
  }

  let authDeleted = true;
  let warning: string | null = null;
  if (prepared.auth_user_id) {
    const { error: authDeleteError } = await admin.auth.admin.deleteUser(
      String(prepared.auth_user_id),
    );
    if (authDeleteError) {
      // A previous attempt may already have removed the Auth identity; treat
      // "not found" as success so the moderator does not see a false warning.
      if (/not\s*found|does not exist/i.test(messageOf(authDeleteError))) {
        authDeleted = true;
      } else {
        authDeleted = false;
        warning =
          "تم تعطيل الحساب وحذفه من قائمة الموظفين، لكن تعذر حذف هوية الدخول. راجع مسؤول النظام لتنظيفها.";
        console.error("failed to delete auth user", authDeleteError);
      }
    }
  }

  return json({
    success: true,
    user_id: prepared.user_id,
    auth_deleted: authDeleted,
    warning,
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(
      {
        success: false,
        error: "method not allowed",
        code: "method_not_allowed",
      },
      405,
    );
  }

  try {
    const body = (await req.json().catch(() => ({}))) as Record<
      string,
      unknown
    >;
    const action = String(body.action ?? "").trim();

    switch (action) {
      case "customer_register":
        return await customerRegister(req, body);
      case "customer_reset_password":
        return await customerResetPassword(req, body);
      case "staff_directory":
        return await staffDirectory(req);
      case "staff_pin_login":
        return await staffPinLogin(req, body);
      case "staff_create":
        return await staffCreate(req, body);
      case "staff_update":
        return await staffUpdate(req, body);
      case "staff_delete":
        return await staffDelete(req, body);
      default:
        throw new ApiError(400, "إجراء غير معروف", "unknown_action");
    }
  } catch (error) {
    return errorResponse(error);
  }
});
