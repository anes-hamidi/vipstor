import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * auth-admin — password-only account lifecycle.
 *
 * Deploy with JWT verification disabled:
 *   supabase functions deploy auth-admin --no-verify-jwt
 *
 * The function only uses the service role after validating the caller for
 * staff actions. Public actions are deliberately limited to customer
 * self-registration and recovery-code password reset.
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ??
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
  "";

const AUTH_EMAIL_DOMAIN = "vip.algomend.app";
const STAFF_ROLES = ["moderator", "manager", "cashier", "driver"] as const;
const RECOVERY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

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

async function staffCreate(req: Request, body: Record<string, unknown>) {
  const caller = await requireModerator(req);
  const pin = validatePin(body.admin_pin);
  await verifyModeratorPin(caller.authUserId, pin!);

  const name = validateName(body.name);
  const phone = normalizePhone(body.phone);
  const role = validateRole(body.role);
  const password = validatePassword(body.password);
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
  const newPassword = rawPassword.length > 0
    ? validatePassword(rawPassword)
    : null;

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
