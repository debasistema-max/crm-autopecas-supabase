async function supabaseLogin(usuario, senha) {
  if (!isSupabaseReady()) throw new Error('Supabase nao configurado.');
  const login = String(usuario || '').trim();
  const email = login.includes('@') ? login : login + '@ipscrm.com';
  const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password: senha });
  if (error) throw error;
  const profile = await supabaseCurrentProfile(data.user.id);
  return supabaseSessionFromProfile(data.user, profile);
}

async function supabaseLogout() {
  if (isSupabaseReady()) await supabaseClient.auth.signOut();
}

async function supabaseValidateSession() {
  if (!isSupabaseReady()) return null;
  const { data, error } = await supabaseClient.auth.getUser();
  if (error || !data.user) return null;
  const profile = await supabaseCurrentProfile(data.user.id);
  return supabaseSessionFromProfile(data.user, profile);
}

async function supabaseCurrentProfile(userId) {
  const { data, error } = await supabaseClient
    .from('profiles')
    .select('id, usuario, nome, email, perfil, ativo')
    .eq('id', userId)
    .single();
  if (error) throw error;
  if (!data || data.ativo === false) throw new Error('Usuario inativo.');
  return data;
}

async function supabaseModules(perfil) {
  const { data, error } = await supabaseClient
    .from('role_permissions')
    .select('modulo')
    .eq('perfil', perfil)
    .eq('permitido', true);
  if (error) throw error;
  return (data || []).map((row) => row.modulo);
}

async function supabaseSessionFromProfile(user, profile) {
  return {
    sessionId: user.id,
    usuario: profile.usuario,
    nome: profile.nome,
    email: profile.email || user.email,
    perfil: profile.perfil,
    modules: await supabaseModules(profile.perfil)
  };
}

async function supabaseGetDashboard() {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const [{ data: orders, error: ordersError }, { count: missingCount, error: missingError }, { count: zeroCount, error: zeroError }] = await Promise.all([
    supabaseClient.from('orders').select('numero_pedido, cliente, vendedor, status, total, created_at').order('created_at', { ascending: false }).limit(8),
    supabaseClient.from('products').select('codigo', { count: 'exact', head: true }).eq('status_cadastro', 'NAO_CADASTRADO'),
    supabaseClient.from('products').select('codigo', { count: 'exact', head: true }).lte('estoque_quantidade', 0)
  ]);
  if (ordersError || missingError || zeroError) throw ordersError || missingError || zeroError;
  const pedidosHoje = (orders || []).filter((order) => new Date(order.created_at) >= today);
  return {
    pedidosHoje: pedidosHoje.length,
    totalHoje: pedidosHoje.reduce((sum, order) => sum + Number(order.total || 0), 0),
    ultimosPedidos: orders || [],
    produtosSemCadastro: missingCount || 0,
    estoqueZerado: zeroCount || 0
  };
}

async function supabaseSearchProducts(params) {
  const { data, error } = await supabaseClient.rpc('search_products', {
    term: params.termo || params.q || '',
    region: params.regiao || 'SP',
    only_available: params.disponiveis === true,
    limit_count: Number(params.limite || 40)
  });
  if (error) throw error;
  return data || [];
}

async function supabaseCreateOrder(payload) {
  const { data, error } = await supabaseClient.rpc('create_order', { payload });
  if (error) throw error;
  return data || {};
}

async function supabaseGetLogs(filters) {
  let query = supabaseClient
    .from('logs')
    .select('data_hora, usuario, acao, entidade, id_entidade')
    .order('data_hora', { ascending: false })
    .limit(100);
  if (filters && filters.usuario) query = query.ilike('usuario', `%${filters.usuario}%`);
  if (filters && filters.acao) query = query.ilike('acao', `%${filters.acao}%`);
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

async function supabaseListUsers() {
  const { data, error } = await supabaseClient
    .from('profiles')
    .select('id, usuario, nome, email, perfil, ativo, ultimo_login')
    .order('nome', { ascending: true });
  if (error) throw error;
  return data || [];
}

async function supabaseSaveUser(payload) {
  const profile = {
    usuario: String(payload.usuario || '').trim(),
    nome: String(payload.nome || '').trim(),
    email: String(payload.email || '').trim(),
    perfil: payload.perfil || 'VENDEDOR',
    ativo: payload.ativo !== false
  };
  if (!profile.usuario || !profile.nome || !profile.email) {
    throw new Error('Usuario, nome e email sao obrigatorios.');
  }

  let userId = payload.id_usuario || payload.id || '';
  if (!userId) {
    if (!payload.senha) throw new Error('Informe uma senha inicial para novo usuario.');
    const previousSession = await supabaseClient.auth.getSession();
    const { data: signupData, error: signupError } = await supabaseClient.auth.signUp({
      email: profile.email,
      password: payload.senha,
      options: { data: { usuario: profile.usuario, nome: profile.nome } }
    });
    if (previousSession.data.session) {
      await supabaseClient.auth.setSession({
        access_token: previousSession.data.session.access_token,
        refresh_token: previousSession.data.session.refresh_token
      });
    }
    if (signupError) throw signupError;
    userId = signupData.user && signupData.user.id;
    if (!userId) throw new Error('Usuario Auth nao foi criado no Supabase.');
  }

  const { data, error } = await supabaseClient
    .from('profiles')
    .upsert(Object.assign({ id: userId }, profile), { onConflict: 'id' })
    .select('id, usuario, nome, email, perfil, ativo, ultimo_login')
    .single();
  if (error) throw error;
  await supabaseLog('SALVAR_USUARIO', 'profiles', userId, profile);
  return data;
}

async function supabaseImportProducts(payload) {
  const plan = await supabasePreviewImportProducts(payload);
  const mapped = plan.products;

  let novos = 0;
  let atualizados = 0;
  const codes = mapped.map((product) => product.codigo);
  for (const chunk of chunkArray(codes, 500)) {
    const { data, error } = await supabaseClient
      .from('products')
      .select('codigo')
      .in('codigo', chunk);
    if (error) throw error;
    const existing = new Set((data || []).map((item) => item.codigo));
    chunk.forEach((code) => {
      if (existing.has(code)) atualizados += 1;
      else novos += 1;
    });
  }

  const chunks = chunkArray(mapped, 300);
  for (let index = 0; index < chunks.length; index += 1) {
    const { error } = await supabaseClient
      .from('products')
      .upsert(chunks[index], { onConflict: 'codigo' });
    if (error) throw error;
    if (typeof payload.onProgress === 'function') {
      payload.onProgress({
        done: Math.min((index + 1) * 300, mapped.length),
        total: mapped.length
      });
    }
  }

  const batch = {
    usuario: (getStoredSession() || {}).usuario || null,
    tipo: plan.tipo,
    total_recebido: plan.totalRows,
    novos,
    atualizados,
    sem_alteracao: plan.duplicates,
    erros: plan.invalidRows.length,
    status: 'APLICADO'
  };
  await supabaseClient.from('import_batches').insert(batch);
  await supabaseLog('IMPORTAR_PRODUTOS', 'products', plan.tipo, batch);
  return { summary: batch, preview: plan.preview };
}

async function supabasePreviewImportProducts(payload) {
  const tipo = payload.tipo || 'CATALOGO_PESQUISA';
  const rows = parseDelimitedText(payload.texto || '');
  if (!rows.length) throw new Error('Cole ou selecione um CSV/TSV com cabecalho.');

  const seen = new Set();
  const duplicateCodes = new Set();
  const invalidRows = [];
  const products = [];

  rows.forEach((row, index) => {
    const product = mapImportProduct(row, tipo);
    if (!product.codigo) {
      invalidRows.push({ linha: index + 2, motivo: 'Codigo ausente' });
      return;
    }
    if (seen.has(product.codigo)) duplicateCodes.add(product.codigo);
    seen.add(product.codigo);
    products.push(product);
  });

  if (!products.length) throw new Error('Nenhum produto valido encontrado na importacao.');

  const codes = products.map((product) => product.codigo);
  let existingCount = 0;
  for (const chunk of chunkArray(codes, 500)) {
    const { data, error } = await supabaseClient
      .from('products')
      .select('codigo')
      .in('codigo', chunk);
    if (error) throw error;
    existingCount += (data || []).length;
  }

  return {
    tipo,
    totalRows: rows.length,
    validRows: products.length,
    invalidRows,
    duplicates: duplicateCodes.size,
    existingCount,
    newCount: Math.max(products.length - existingCount, 0),
    preview: products.slice(0, 8),
    products
  };
}

async function supabaseLog(acao, entidade, idEntidade, dadosNovos) {
  const session = getStoredSession() || {};
  await supabaseClient.from('logs').insert({
    usuario: session.usuario || null,
    acao,
    entidade,
    id_entidade: idEntidade == null ? null : String(idEntidade),
    dados_novos: dadosNovos || null
  });
}

function parseDelimitedText(text) {
  const source = String(text || '').trim();
  if (!source) return [];
  const delimiter = source.includes('\t') ? '\t' : detectCsvDelimiter(source);
  const rows = [];
  let row = [];
  let value = '';
  let quoted = false;
  for (let i = 0; i < source.length; i += 1) {
    const char = source[i];
    const next = source[i + 1];
    if (char === '"' && quoted && next === '"') {
      value += '"';
      i += 1;
    } else if (char === '"') {
      quoted = !quoted;
    } else if (char === delimiter && !quoted) {
      row.push(value);
      value = '';
    } else if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && next === '\n') i += 1;
      row.push(value);
      if (row.some((cell) => String(cell).trim())) rows.push(row);
      row = [];
      value = '';
    } else {
      value += char;
    }
  }
  row.push(value);
  if (row.some((cell) => String(cell).trim())) rows.push(row);
  const headers = (rows.shift() || []).map(normalizeHeader);
  return rows.map((cells) => {
    const item = {};
    headers.forEach((header, index) => {
      if (header) item[header] = String(cells[index] || '').trim();
    });
    return item;
  });
}

function detectCsvDelimiter(text) {
  const firstLine = String(text || '').split(/\r?\n/)[0] || '';
  return (firstLine.match(/;/g) || []).length > (firstLine.match(/,/g) || []).length ? ';' : ',';
}

function normalizeHeader(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '');
}

function pickImport(row, aliases) {
  for (const alias of aliases) {
    const key = normalizeHeader(alias);
    if (Object.prototype.hasOwnProperty.call(row, key) && row[key] !== '') return row[key];
  }
  return '';
}

function importNumber(value) {
  let text = String(value || '').trim();
  if (!text) return 0;
  text = text.replace(/[^\d,.-]/g, '');
  if (text.includes(',') && text.includes('.')) text = text.replace(/\./g, '').replace(',', '.');
  else if (text.includes(',')) text = text.replace(',', '.');
  const parsed = Number(text);
  return Number.isFinite(parsed) ? parsed : 0;
}

function normalizeProductCode(value) {
  const text = String(value || '').trim();
  return /^\d+\.0$/.test(text) ? text.slice(0, -2) : text;
}

function mapImportProduct(row, tipo) {
  const codigo = normalizeProductCode(pickImport(row, ['codigo', 'codigo ips', 'cod', 'cod.', 'sku']));
  const estoque = pickImport(row, ['estoque', 'disp geral', 'disp. geral', 'disp venda', 'disp. venda', 'qtde']);
  const base = { codigo };
  const descriptive = {
    descricao: pickImport(row, ['descricao', 'descr']),
    marca: pickImport(row, ['marca']),
    aplicacao: pickImport(row, ['aplicacao']),
    ano: pickImport(row, ['ano']),
    ipi: importNumber(pickImport(row, ['ipi'])),
    status_cadastro: pickImport(row, ['status cadastro', 'status_cadastro']),
    url_imagem: pickImport(row, ['url imagem', 'url_imagem', 'imagem']),
    grupo: pickImport(row, ['grupo']),
    categoria: pickImport(row, ['categoria']),
    montadora: pickImport(row, ['montadora']),
    detalhes: pickImport(row, ['detalhes', 'palavras chave', 'palavras-chave']),
    oem: pickImport(row, ['oem']),
    similar: pickImport(row, ['similar', 'similares'])
  };
  const stock = {
    estoque,
    estoque_quantidade: importNumber(estoque),
    status_estoque: pickImport(row, ['status estoque', 'status_estoque'])
  };
  const price = importNumber(pickImport(row, ['preco', 'valor', 'prunitci', 'pr.unit.(c/i)', 'total c imp', 'total c/ imp', 'pr apos desc', 'pr.apos desc']));

  if (tipo === 'PORTAL_ESTOQUE') {
    Object.assign(base, stock);
  } else if (tipo === 'PRECO_PR') {
    if (price) base.preco_pr = price;
  } else if (tipo === 'PRECO_SP') {
    if (price) base.preco_sp = price;
  } else {
    Object.assign(base, descriptive, stock);
    const precoSp = importNumber(pickImport(row, ['preco sp', 'preco_sp'])) || price;
    const precoPr = importNumber(pickImport(row, ['preco pr', 'preco_pr'])) || price;
    if (precoSp) base.preco_sp = precoSp;
    if (precoPr) base.preco_pr = precoPr;
  }

  return Object.fromEntries(Object.entries(base).filter(([, value]) => value !== ''));
}

function chunkArray(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
