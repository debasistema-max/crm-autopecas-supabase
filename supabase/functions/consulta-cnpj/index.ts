import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const cnpj = await readCnpj(req);
    if (cnpj.length !== 14) return json({ ok: false, error: 'CNPJ invalido.' }, 400);

    const data = await fetchCnpjData(cnpj);
    return json({ ok: true, data });
  } catch (error) {
    return json({ ok: false, error: error.message || 'Nao foi possivel consultar o CNPJ.' }, 500);
  }
});

async function readCnpj(req: Request) {
  if (req.method === 'GET') {
    const url = new URL(req.url);
    return onlyDigits(url.searchParams.get('cnpj'));
  }
  if (req.method === 'POST') {
    const body = await req.json().catch(() => ({}));
    return onlyDigits(body.cnpj);
  }
  throw new Error('Metodo nao permitido.');
}

async function fetchCnpjData(cnpj: string) {
  const attempts = [
    {
      url: `https://brasilapi.com.br/api/cnpj/v1/${cnpj}`,
      source: 'brasilapi'
    },
    {
      url: `https://www.receitaws.com.br/v1/cnpj/${cnpj}`,
      source: 'receitaws'
    }
  ];

  let lastError: Error | null = null;
  for (const attempt of attempts) {
    try {
      const response = await fetch(attempt.url, {
        headers: {
          Accept: 'application/json',
          'User-Agent': 'crm-autopecas-supabase'
        }
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const payload = await response.json();
      if (payload.status === 'ERROR') throw new Error(payload.message || 'CNPJ nao encontrado.');
      return normalizeCnpjData(payload, attempt.source);
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
    }
  }

  throw lastError || new Error('Consulta indisponivel.');
}

function normalizeCnpjData(data: Record<string, unknown>, source: string) {
  if (source === 'receitaws') {
    const atividades = Array.isArray(data.atividade_principal) ? data.atividade_principal : [];
    const atividade = (atividades[0] || {}) as Record<string, unknown>;
    return {
      fonte: source,
      razao_social: data.nome,
      nome_fantasia: data.fantasia,
      cnae_fiscal: atividade.code,
      cnae_fiscal_descricao: atividade.text,
      descricao_situacao_cadastral: data.situacao,
      cep: data.cep,
      descricao_tipo_de_logradouro: '',
      logradouro: data.logradouro,
      numero: data.numero,
      complemento: data.complemento,
      bairro: data.bairro,
      municipio: data.municipio,
      uf: data.uf,
      ddd_telefone_1: data.telefone,
      email: data.email,
      raw: data
    };
  }
  return Object.assign({ fonte: source, raw: data }, data);
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
