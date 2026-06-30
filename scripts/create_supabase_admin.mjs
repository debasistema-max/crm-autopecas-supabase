import { Client } from 'pg';

const dbUrl = process.env.SUPABASE_DB_URL;
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_PUBLISHABLE_KEY;
const email = process.env.SUPABASE_ADMIN_EMAIL || 'admin@ipscrm.com';
const password = process.env.SUPABASE_ADMIN_PASSWORD;

if (!dbUrl || !supabaseUrl || !supabaseKey || !password) {
  throw new Error('Informe SUPABASE_DB_URL, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY e SUPABASE_ADMIN_PASSWORD.');
}

const signupResponse = await fetch(`${supabaseUrl}/auth/v1/signup`, {
  method: 'POST',
  headers: {
    apikey: supabaseKey,
    Authorization: `Bearer ${supabaseKey}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    email,
    password,
    data: {
      usuario: 'admin',
      nome: 'Administrador'
    }
  })
});

const signupBody = await signupResponse.json();
const signupMessage = String(signupBody.msg || signupBody.message || signupBody.error_code || '');
if (
  !signupResponse.ok
  && !signupMessage.includes('already')
  && !signupMessage.includes('rate_limit')
  && !signupMessage.includes('rate limit')
) {
  throw new Error(JSON.stringify(signupBody));
}

const client = new Client({
  connectionString: dbUrl,
  ssl: { rejectUnauthorized: false }
});

await client.connect();
try {
  let userId = signupBody.user && signupBody.user.id;
  if (!userId) {
    const existing = await client.query('select id from auth.users where email = $1 order by created_at desc limit 1', [email]);
    userId = existing.rows[0] && existing.rows[0].id;
  }
  if (!userId) throw new Error('Usuario Auth nao encontrado para ' + email);

  await client.query(`
    update auth.users
    set email_confirmed_at = coalesce(email_confirmed_at, now())
    where id = $1
  `, [userId]);

  await client.query(`
    insert into public.profiles (id, legacy_id, usuario, nome, email, perfil, ativo)
    values ($1, 'admin', 'admin', 'Administrador', $2, 'ADMIN', true)
    on conflict (id) do update set
      usuario = excluded.usuario,
      nome = excluded.nome,
      email = excluded.email,
      perfil = excluded.perfil,
      ativo = excluded.ativo
  `, [userId, email]);

  console.log(JSON.stringify({ email, userId, status: 'admin pronto' }, null, 2));
} finally {
  await client.end();
}
