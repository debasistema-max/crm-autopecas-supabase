const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ ok: false, error: 'Metodo nao permitido.' }, 405);

  try {
    const payload = await req.json();
    const cnpj = onlyDigits(payload.cnpj);
    if (cnpj.length !== 14) return json({ ok: false, error: 'CNPJ invalido.' }, 400);
    if (!payload.razao_social || !payload.email_compras) {
      return json({ ok: false, error: 'Razao social e email de compras sao obrigatorios.' }, 400);
    }
    const anexos = normalizeAttachments(payload.anexos || []);

    const supabase = getSupabaseConfig();
    ensureEmailConfigured();

    const recent = await supabaseFetch(
      supabase,
      `/rest/v1/cadastros_clientes?select=id&cnpj=eq.${encodeURIComponent(cnpj)}&created_at=gte.${encodeURIComponent(new Date(Date.now() - 15 * 60 * 1000).toISOString())}&limit=1`
    );
    if ((recent || []).length) {
      return json({ ok: false, error: 'Ja existe um cadastro recente para este CNPJ.' }, 429);
    }

    const cadastroPayload = Object.assign({}, payload, {
      cnpj,
      origem: 'portal_publico',
      anexos: []
    });

    const rows = await supabaseFetch(
      supabase,
      '/rest/v1/cadastros_clientes?select=protocolo,razao_social,cnpj,cidade,estado,email_compras,vendedor',
      {
        method: 'POST',
        headers: { Prefer: 'return=representation' },
        body: JSON.stringify(cadastroPayload)
      }
    );
    const data = Array.isArray(rows) ? rows[0] : rows;
    if (!data) throw new Error('Cadastro nao retornou protocolo.');

    const attachments = await uploadAttachments(supabase, data.protocolo, anexos);
    if (attachments.length) {
      await supabaseFetch(
        supabase,
        `/rest/v1/cadastros_clientes?protocolo=eq.${encodeURIComponent(data.protocolo)}`,
        {
          method: 'PATCH',
          headers: { Prefer: 'return=minimal' },
          body: JSON.stringify({ anexos: attachments })
        }
      );
    }

    const emailResult = await sendEmails(supabase, data, payload, anexos);
    return json({ ok: true, data: Object.assign({}, data, { anexos: attachments, email: emailResult }) });
  } catch (error) {
    return json({ ok: false, error: error.message || 'Erro ao enviar cadastro.' }, 500);
  }
});

async function sendEmails(
  config: { url: string; key: string },
  row: Record<string, string>,
  payload: Record<string, string>,
  attachments: CadastroAttachment[]
) {
  const from = getEmailFrom();
  const to = await getPortalCadastroEmailTo(config);
  const errors: string[] = [];

  const subject = `Novo cadastro ${row.protocolo} - ${row.razao_social || row.cnpj}`;
  const text = [
    `Protocolo: ${row.protocolo}`,
    `Empresa: ${row.razao_social || ''}`,
    `CNPJ: ${row.cnpj || ''}`,
    `Cidade/UF: ${row.cidade || ''}/${row.estado || ''}`,
    `Contato: ${payload.responsavel_compras || ''}`,
    `Telefone: ${payload.telefone || ''}`,
    `WhatsApp: ${payload.whatsapp || ''}`,
    `Email compras: ${payload.email_compras || ''}`,
    `Vendedor: ${payload.vendedor || ''}`,
    `Situacao cadastral: ${payload.situacao_cadastral || ''}`,
    `CNAE: ${payload.cnae || ''}`,
    `Regime especial: ${payload.possui_regime_especial ? 'Sim' : 'Nao'}`,
    `Descricao regime: ${payload.descricao_regime || ''}`,
    `Anexos recebidos: ${attachments.length}`
  ].join('\n');

  const internalEmail = await sendEmail({
    from,
    to,
    subject,
    text,
    attachments
  });
  if (!internalEmail.ok) {
    console.error('Falha ao enviar email ao financeiro', internalEmail.error);
    errors.push('Falha ao enviar email ao financeiro.');
  }

  const customerRecipients = Array.from(new Set([
    payload.email_compras,
    payload.email_financeiro
  ].filter(Boolean)));

  for (const customerTo of customerRecipients) {
    const customerEmail = await sendEmail({
      from,
      to: customerTo,
      subject: `Recebemos seu cadastro - ${row.protocolo}`,
      text: `Recebemos seu cadastro. Protocolo: ${row.protocolo}. Nossa equipe ira analisar e entrar em contato.`
    });
    if (!customerEmail.ok) {
      console.error('Falha ao enviar email ao cliente', customerEmail.error);
      errors.push(`Falha ao enviar confirmacao para ${customerTo}.`);
    }
  }

  return {
    ok: errors.length === 0,
    errors
  };
}

async function getPortalCadastroEmailTo(config: { url: string; key: string }) {
  const fallback = Deno.env.get('CADASTRO_EMAIL_TO') || 'financeiro@ipsbrasil.com.br';
  try {
    const rows = await supabaseFetch(
      config,
      '/rest/v1/settings?select=value&key=eq.portal_cadastros&limit=1'
    );
    const value = Array.isArray(rows) && rows[0] ? rows[0].value : null;
    const email = String(value?.email_principal || '').trim();
    return email || fallback;
  } catch (error) {
    console.error('Falha ao ler email principal do portal', error.message || error);
    return fallback;
  }
}

function ensureEmailConfigured() {
  if (!isGmailConfigured() && !Deno.env.get('RESEND_API_KEY')) {
    throw new Error('Envio de email nao configurado no Supabase.');
  }
}

type EmailAttachment = {
  name?: string;
  type?: string;
  content?: string;
};

type CadastroAttachment = EmailAttachment & {
  field?: unknown;
  label?: unknown;
  size?: number;
};

type EmailMessage = {
  from: string;
  to: string;
  subject: string;
  text: string;
  attachments?: EmailAttachment[];
};

async function sendEmail(message: EmailMessage) {
  if (isGmailConfigured()) return sendEmailWithGmail(message);
  return sendEmailWithResend(message);
}

async function sendEmailWithGmail(message: EmailMessage) {
  const hostname = Deno.env.get('GMAIL_SMTP_HOST') || 'smtp.gmail.com';
  const port = Number(Deno.env.get('GMAIL_SMTP_PORT') || '465');
  const username = Deno.env.get('GMAIL_SMTP_USER') || '';
  const password = Deno.env.get('GMAIL_SMTP_APP_PASSWORD') || '';
  const conn = await Deno.connectTls({ hostname, port });
  try {
    await readSmtp(conn);
    await smtp(conn, `EHLO ${hostname}`);
    await smtp(conn, 'AUTH LOGIN', 334);
    await smtp(conn, base64(username), 334);
    await smtp(conn, base64(password), 235);
    await smtp(conn, `MAIL FROM:<${extractEmailAddress(message.from)}>`);
    await smtp(conn, `RCPT TO:<${message.to}>`);
    await smtp(conn, 'DATA', 354);
    await smtp(conn, buildMimeMessage(message), 250);
    await smtp(conn, 'QUIT', 221).catch(() => undefined);
    return { ok: true };
  } catch (error) {
    return { ok: false, error: error.message || 'Erro SMTP Gmail.' };
  } finally {
    try {
      conn.close();
    } catch (_error) {
      // Ignora falha ao fechar a conexao SMTP.
    }
  }
}

async function sendEmailWithResend(message: EmailMessage) {
  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) return { ok: false, error: 'RESEND_API_KEY nao configurado.' };
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: message.from,
      to: message.to,
      subject: message.subject,
      text: message.text,
      attachments: (message.attachments || []).map((attachment) => ({
        filename: sanitizeFileName(String(attachment.name || 'documento')),
        content: attachment.content,
        content_type: attachment.type || 'application/octet-stream'
      }))
    })
  });
  if (response.ok) return { ok: true };
  return {
    ok: false,
    error: `${response.status} ${await response.text().catch(() => '')}`.trim()
  };
}

function isGmailConfigured() {
  return Boolean(Deno.env.get('GMAIL_SMTP_USER') && Deno.env.get('GMAIL_SMTP_APP_PASSWORD'));
}

function getEmailFrom() {
  return Deno.env.get('CADASTRO_EMAIL_FROM')
    || Deno.env.get('GMAIL_SMTP_USER')
    || 'Deba Sistema <debasistema@gmail.com>';
}

function getSupabaseConfig() {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('Supabase nao configurado.');
  return { url, key };
}

function normalizeAttachments(input: unknown[]) {
  if (!Array.isArray(input)) throw new Error('Lista de anexos invalida.');
  if (input.length > 5) throw new Error('Envie no maximo 5 arquivos.');
  let totalBytes = 0;
  const attachments: CadastroAttachment[] = [];
  for (const attachment of input as Array<Record<string, unknown>>) {
    const size = Number(attachment.size || 0);
    const type = String(attachment.type || '');
    const content = String(attachment.content || '').replace(/\s/g, '');
    const name = sanitizeFileName(String(attachment.name || 'documento'));
    totalBytes += size;
    if (size > 5 * 1024 * 1024) throw new Error(`Arquivo ${name} ultrapassa 5 MB.`);
    if (totalBytes > 15 * 1024 * 1024) throw new Error('O total dos arquivos nao pode ultrapassar 15 MB.');
    if (!['application/pdf', 'image/jpeg', 'image/png', 'image/webp'].includes(type)) {
      throw new Error(`Arquivo ${name} deve ser PDF, JPG, PNG ou WEBP.`);
    }
    if (!content) {
      throw new Error(`Arquivo ${name} sem conteudo.`);
    }
    attachments.push({
      field: attachment.field,
      label: attachment.label,
      name,
      type,
      size,
      content
    });
  }
  return attachments;
}

async function uploadAttachments(
  config: { url: string; key: string },
  protocolo: string,
  attachments: CadastroAttachment[]
) {
  const uploaded = [];
  for (const attachment of attachments) {
    const fileName = sanitizeFileName(String(attachment.name || 'documento'));
    const storagePath = `${protocolo}/${crypto.randomUUID()}-${fileName}`;
    const bytes = base64ToBytes(String(attachment.content || ''));
    const response = await fetch(`${config.url}/storage/v1/object/cadastros-clientes/${storagePath}`, {
      method: 'PUT',
      headers: {
        apikey: config.key,
        Authorization: `Bearer ${config.key}`,
        'Content-Type': String(attachment.type || 'application/octet-stream'),
        'x-upsert': 'false'
      },
      body: bytes
    });
    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new Error(`Falha ao salvar anexo ${fileName}: ${body || response.status}`);
    }
    uploaded.push({
      field: attachment.field,
      label: attachment.label,
      name: fileName,
      type: attachment.type,
      size: attachment.size,
      bucket: 'cadastros-clientes',
      path: storagePath
    });
  }
  return uploaded;
}

function sanitizeFileName(name: string) {
  return name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120) || 'documento';
}

function base64ToBytes(value: string) {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function supabaseFetch(
  config: { url: string; key: string },
  path: string,
  options: RequestInit = {}
) {
  const response = await fetch(`${config.url}${path}`, {
    ...options,
    headers: Object.assign({
      apikey: config.key,
      Authorization: `Bearer ${config.key}`,
      'Content-Type': 'application/json'
    }, options.headers || {})
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  if (!response.ok) {
    throw new Error(body?.message || body?.error || 'Erro no banco de dados.');
  }
  return body;
}

async function smtp(conn: Deno.TlsConn, command: string, expected = 250) {
  await conn.write(new TextEncoder().encode(command + '\r\n'));
  const response = await readSmtp(conn);
  if (!response.startsWith(String(expected))) {
    throw new Error(`SMTP ${response.trim()}`);
  }
  return response;
}

async function readSmtp(conn: Deno.TlsConn) {
  const decoder = new TextDecoder();
  const buffer = new Uint8Array(4096);
  let text = '';
  while (true) {
    const count = await conn.read(buffer);
    if (count === null) throw new Error('Conexao SMTP encerrada.');
    text += decoder.decode(buffer.subarray(0, count));
    const lines = text.split(/\r?\n/).filter(Boolean);
    const last = lines[lines.length - 1] || '';
    if (/^\d{3} /.test(last)) return text;
  }
}

function buildMimeMessage(message: EmailMessage) {
  const attachments = message.attachments || [];
  if (!attachments.length) {
    return [
      `From: ${message.from}`,
      `To: ${message.to}`,
      `Subject: ${message.subject}`,
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: 8bit',
      '',
      dotStuff(message.text),
      '.'
    ].join('\r\n');
  }

  const boundary = `crm-${crypto.randomUUID()}`;
  const parts = [
    `From: ${message.from}`,
    `To: ${message.to}`,
    `Subject: ${message.subject}`,
    'MIME-Version: 1.0',
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    '',
    `--${boundary}`,
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: 8bit',
    '',
    dotStuff(message.text)
  ];

  for (const attachment of attachments) {
    const fileName = sanitizeFileName(String(attachment.name || 'documento'));
    parts.push(
      `--${boundary}`,
      `Content-Type: ${attachment.type || 'application/octet-stream'}; name="${fileName}"`,
      'Content-Transfer-Encoding: base64',
      `Content-Disposition: attachment; filename="${fileName}"`,
      '',
      wrapBase64(String(attachment.content || ''))
    );
  }

  parts.push(
    `--${boundary}--`,
    '.'
  );

  return parts.join('\r\n');
}

function extractEmailAddress(value: string) {
  const match = value.match(/<([^>]+)>/);
  return (match ? match[1] : value).trim();
}

function base64(value: string) {
  return btoa(value);
}

function wrapBase64(value: string) {
  return value.replace(/\s/g, '').replace(/(.{1,76})/g, '$1\r\n').trim();
}

function dotStuff(value: string) {
  return value.replace(/^\./gm, '..');
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: Object.assign({ 'Content-Type': 'application/json' }, corsHeaders)
  });
}

function onlyDigits(value: unknown) {
  return String(value || '').replace(/\D/g, '');
}
