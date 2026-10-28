import { createClient } from 'npm:@supabase/supabase-js@2.116.0';

function origins() {
  return (Deno.env.get('CRM_ALLOWED_ORIGINS') || 'https://debasistema-max.github.io')
    .split(',').map(value => value.trim()).filter(Boolean);
}
function reply(request: Request, status: number, body: Record<string, unknown>) {
  const origin = request.headers.get('origin') || '';
  return new Response(JSON.stringify(body), { status, headers: {
    'Access-Control-Allow-Origin': origins().includes(origin) ? origin : origins()[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Vary': 'Origin',
    'Cache-Control': 'no-store', 'Content-Type': 'application/json; charset=utf-8',
    'X-Content-Type-Options': 'nosniff'
  } });
}
function safeCode(error: { message?: string; code?: string } | null) {
  const allowed = ['APENAS_ADMIN','DADOS_USUARIO_INVALIDOS','USUARIO_DUPLICADO','EMAIL_DUPLICADO',
    'CRIACAO_USUARIO_EM_ANDAMENTO','SESSAO_ADMIN_INVALIDA'];
  return allowed.includes(error?.message || '') ? error!.message! : 'CRIACAO_USUARIO_FALHOU';
}
function createAdminClient(url: string, secret: string) {
  return createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
}

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return reply(request, 200, {});
  if (request.method !== 'POST') return reply(request, 405, { error: 'METODO_NAO_PERMITIDO' });
  const origin = request.headers.get('origin') || '';
  if (origin && !origins().includes(origin)) return reply(request, 403, { error: 'ORIGEM_NAO_AUTORIZADA' });
  let operationId: string | null = null;
  let admin: ReturnType<typeof createAdminClient> | null = null;
  try {
    const url = Deno.env.get('SUPABASE_URL') || '';
    const anon = Deno.env.get('SUPABASE_ANON_KEY') || '';
    const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    if (!/^https:\/\/(doenvnjzrecrtvwooaai|mtwvxyvpnbgwgltelozw)\.supabase\.co$/.test(url) || !anon || !secret) {
      return reply(request, 503, { error: 'CONFIGURACAO_INDISPONIVEL' });
    }
    const authorization = request.headers.get('authorization') || '';
    if (!/^Bearer \S+$/.test(authorization)) return reply(request, 401, { error: 'AUTENTICACAO_OBRIGATORIA' });
    const caller = createClient(url, anon, { global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false } });
    const { data: identity, error: identityError } = await caller.auth.getUser();
    if (identityError || !identity?.user) return reply(request, 401, { error: 'SESSAO_INVALIDA' });
    const { data: session, error: sessionError } = await caller.rpc('get_app_session_status');
    if (sessionError || session?.active !== true) return reply(request, 401, { error: 'SESSAO_SUBSTITUIDA' });
    const { data: isAdmin, error: permissionError } = await caller.rpc('is_admin');
    if (permissionError || isAdmin !== true) return reply(request, 403, { error: 'APENAS_ADMIN' });
    // Parse credentials only after authenticating and checking the active ADMIN.
    const text = await request.text();
    if (text.length > 4096) return reply(request, 413, { error: 'DADOS_USUARIO_INVALIDOS' });
    let body;
    try { body = JSON.parse(text); } catch { return reply(request, 400, { error: 'DADOS_USUARIO_INVALIDOS' }); }
    if (!body || typeof body !== 'object' || Array.isArray(body) || body.id || body.id_usuario) {
      return reply(request, 400, { error: 'DADOS_USUARIO_INVALIDOS' });
    }
    if (['usuario','nome','email'].some(key => typeof body[key] !== 'string')
      || (body.perfil !== undefined && typeof body.perfil !== 'string')
      || (body.ativo !== undefined && typeof body.ativo !== 'boolean')) {
      return reply(request, 400, { error: 'DADOS_USUARIO_INVALIDOS' });
    }
    const password = typeof body.senha === 'string' ? body.senha : '';
    if (password.length < 8 || password.length > 72) return reply(request, 400, { error: 'SENHA_INICIAL_INVALIDA' });
    const profile = { usuario: String(body.usuario || '').trim().toLowerCase(), nome: String(body.nome || '').trim(),
      email: String(body.email || '').trim().toLowerCase(), perfil: body.perfil || 'VENDEDOR', ativo: body.ativo !== false };
    const prepared = await caller.rpc('prepare_internal_user_provisioning', { profile_data: profile });
    if (prepared.error) return reply(request, 400, { error: safeCode(prepared.error) });
    if (typeof prepared.data !== 'string' || !/^[0-9a-f-]{36}$/i.test(prepared.data)) {
      return reply(request, 503, { error: 'CRIACAO_USUARIO_FALHOU' });
    }
    operationId = prepared.data;
    admin = createAdminClient(url, secret);
    const created = await admin.auth.admin.createUser({ email: profile.email, password, email_confirm: true,
      app_metadata: { account_type: 'internal', provisioning_operation_id: operationId } });
    if (created.error || !created.data?.user?.id) throw new Error('AUTH_CREATE_FAILED');
    const completed = await admin.rpc('complete_internal_user_provisioning', {
      operation_id: operationId, target_user_id: created.data.user.id
    });
    if (completed.error || !completed.data?.id) throw new Error('PROFILE_CREATE_FAILED');
    return reply(request, 200, { profile: completed.data });
  } catch {
    // Never log bodies, passwords, Auth responses or raw provider errors.
    if (operationId && admin) {
      try {
        const cancelled = await admin.rpc('cancel_internal_user_provisioning', { operation_id: operationId });
        if (!cancelled.error && cancelled.data?.status === 'COMMITTED' && cancelled.data.profile?.id) {
          return reply(request, 200, { profile: cancelled.data.profile });
        }
        const cleanupId = cancelled.data?.cleanup_user_id;
        if (!cancelled.error && cancelled.data?.status === 'CANCELLED' && cleanupId) {
          const deleted = await admin.auth.admin.deleteUser(cleanupId);
          if (!deleted.error) {
            const marked = await admin.rpc('finish_internal_user_cleanup', { operation_id: operationId });
            if (!marked.error) return reply(request, 409, { error: 'CRIACAO_USUARIO_FALHOU' });
          }
        }
      } catch { /* Unknown completion: keep the private journal for reconciliation. */ }
      return reply(request, 503, { error: 'CRIACAO_USUARIO_REQUER_CONFERENCIA', operation_id: operationId });
    }
    return reply(request, 500, { error: 'CRIACAO_USUARIO_FALHOU' });
  }
});
