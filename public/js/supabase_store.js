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
  if (params.context === 'produtos' || params.listaGeral || params.grupo || params.linha) {
    return supabaseListProducts(params);
  }
  const { data, error } = await supabaseClient.rpc('search_products', {
    term: params.termo || params.q || '',
    region: params.regiao || 'SP',
    only_available: params.disponiveis === true,
    limit_count: Number(params.limite || 40)
  });
  if (error) throw error;
  return data || [];
}

async function supabaseListProductFilters() {
  const { data, error } = await supabaseClient
    .from('products')
    .select('grupo, categoria')
    .limit(10000);
  if (error) throw error;
  const rows = data || [];
  return {
    grupos: uniqueSorted(rows.map((row) => row.grupo)),
    linhas: uniqueSorted(rows.map((row) => row.categoria))
  };
}

async function supabaseListProducts(params = {}) {
  const region = params.regiao || 'SP';
  const limit = Math.min(Math.max(Number(params.limite || 1000), 1), 5000);
  let query = supabaseClient
    .from('products')
    .select('codigo, descricao, marca, aplicacao, ano, estoque, estoque_quantidade, preco_sp, preco_pr, grupo, categoria, montadora, detalhes, oem, similar')
    .order('codigo', { ascending: true })
    .limit(limit);

  const term = String(params.termo || params.q || '').trim();
  if (term) {
    const pattern = `%${escapePostgrestFilter(term)}%`;
    query = query.or([
      `codigo.ilike.${pattern}`,
      `descricao.ilike.${pattern}`,
      `marca.ilike.${pattern}`,
      `aplicacao.ilike.${pattern}`,
      `grupo.ilike.${pattern}`,
      `categoria.ilike.${pattern}`,
      `montadora.ilike.${pattern}`,
      `oem.ilike.${pattern}`,
      `similar.ilike.${pattern}`
    ].join(','));
  }
  if (params.grupo) query = query.eq('grupo', params.grupo);
  if (params.linha) query = query.eq('categoria', params.linha);
  if (params.disponiveis === true) query = query.gt('estoque_quantidade', 0);

  const { data, error } = await query;
  if (error) throw error;
  return (data || []).map((product) => Object.assign({}, product, {
    linha: product.categoria,
    preco: region === 'PR' ? product.preco_pr : product.preco_sp
  }));
}

function uniqueSorted(values) {
  return Array.from(new Set((values || []).map((value) => String(value || '').trim()).filter(Boolean)))
    .sort((a, b) => a.localeCompare(b, 'pt-BR'));
}

function escapePostgrestFilter(value) {
  return String(value || '').replace(/[(),]/g, ' ');
}

function onlyDigits(value) {
  return String(value || '').replace(/\D/g, '');
}

async function supabaseCreateOrder(payload) {
  const { data, error } = await supabaseClient.rpc('create_order', { payload });
  if (error) throw error;
  return data || {};
}

async function supabaseCreateQuotation(payload) {
  const { data, error } = await supabaseClient.rpc('create_quotation', { payload });
  if (error) throw error;
  return data || {};
}

async function supabaseListOrdersReport(filters = {}) {
  let query = supabaseClient
    .from('orders')
    .select('id, numero_pedido, data_hora, created_at, regiao, vendedor, codigo_sap_cliente, cliente, cnpj, telefone, endereco, prazo, transportadora, transportadora_cnpj, transportadora_endereco, observacao, subtotal, desconto_total, total, status, order_items(id, item, codigo, descricao, marca, aplicacao, quantidade, preco_unitario, desconto_percentual, preco_final_unitario, total_item)')
    .order('created_at', { ascending: false })
    .limit(300);
  if (filters.from) query = query.gte('created_at', filters.from);
  if (filters.to) query = query.lt('created_at', filters.to);
  if (filters.status) query = query.eq('status', filters.status);
  if (filters.termo) {
    const term = `%${escapePostgrestFilter(filters.termo)}%`;
    query = query.or(`numero_pedido.ilike.${term},codigo_sap_cliente.ilike.${term},cliente.ilike.${term},cnpj.ilike.${term},vendedor.ilike.${term}`);
  }
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

async function supabaseListQuotationsReport(filters = {}) {
  let query = supabaseClient
    .from('quotations')
    .select('id, numero_cotacao, data_hora, created_at, regiao, vendedor, codigo_sap_cliente, cliente, cnpj, telefone, endereco, prazo, transportadora, transportadora_cnpj, transportadora_endereco, observacao, subtotal, desconto_total, total, status, quotation_items(id, item, codigo, descricao, marca, aplicacao, quantidade, preco_unitario, desconto_percentual, preco_final_unitario, total_item)')
    .order('created_at', { ascending: false })
    .limit(300);
  if (filters.from) query = query.gte('created_at', filters.from);
  if (filters.to) query = query.lt('created_at', filters.to);
  if (filters.status) query = query.eq('status', filters.status);
  if (filters.termo) {
    const term = `%${escapePostgrestFilter(filters.termo)}%`;
    query = query.or(`numero_cotacao.ilike.${term},codigo_sap_cliente.ilike.${term},cliente.ilike.${term},cnpj.ilike.${term},vendedor.ilike.${term}`);
  }
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

async function supabaseUpdateOrderReport(payload = {}) {
  const { data, error } = await supabaseClient.rpc('update_order_items', {
    payload: sanitizeDocumentItemsUpdate(payload)
  });
  if (error) throw error;
  return data || {};
}

async function supabaseUpdateQuotationReport(payload = {}) {
  const { data, error } = await supabaseClient.rpc('update_quotation_items', {
    payload: sanitizeDocumentItemsUpdate(payload)
  });
  if (error) throw error;
  return data || {};
}

function sanitizeDocumentItemsUpdate(payload = {}) {
  if (!payload.id) throw new Error('Registro nao informado.');
  const items = Array.isArray(payload.items) ? payload.items : [];
  if (!items.length) throw new Error('Informe ao menos um item.');
  return {
    id: payload.id,
    items: items.map((item) => ({
      codigo: String(item.codigo || '').trim(),
      quantidade: Math.max(1, Number(item.quantidade || 1)),
      desconto_percentual: Math.max(0, Number(item.desconto_percentual || 0))
    })).filter((item) => item.codigo)
  };
}

async function supabaseListBusinessClients(filters = {}) {
  let query = supabaseClient
    .from('clients')
    .select('id, codigo_sap_cliente, nome, nome_fantasia, cnpj, telefone, email, endereco, cidade, estado, ativo, observacoes, created_at, updated_at')
    .order('nome', { ascending: true })
    .limit(300);
  if (filters.ativos === true) query = query.eq('ativo', true);
  if (filters.termo) {
    const term = `%${escapePostgrestFilter(filters.termo)}%`;
    query = query.or(`codigo_sap_cliente.ilike.${term},nome.ilike.${term},nome_fantasia.ilike.${term},cnpj.ilike.${term},cidade.ilike.${term}`);
  }
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

async function supabaseSaveBusinessClient(payload = {}) {
  const client = {
    codigo_sap_cliente: String(payload.codigo_sap_cliente || '').trim() || null,
    nome: String(payload.nome || '').trim(),
    nome_fantasia: String(payload.nome_fantasia || '').trim() || null,
    cnpj: onlyDigits(payload.cnpj || '') || null,
    telefone: String(payload.telefone || '').trim() || null,
    email: String(payload.email || '').trim() || null,
    endereco: String(payload.endereco || '').trim() || null,
    cidade: String(payload.cidade || '').trim() || null,
    estado: String(payload.estado || '').trim().toUpperCase() || null,
    ativo: payload.ativo !== false,
    observacoes: String(payload.observacoes || '').trim() || null
  };
  if (!client.nome) throw new Error('Informe a razao social/nome do cliente.');
  if (client.email && !isValidEmail(client.email)) throw new Error('Informe um email valido para o cliente.');
  const record = payload.id ? Object.assign({ id: payload.id }, client) : client;
  const { data, error } = await supabaseClient
    .from('clients')
    .upsert(record, { onConflict: 'id' })
    .select('id, codigo_sap_cliente, nome, nome_fantasia, cnpj, telefone, email, endereco, cidade, estado, ativo, observacoes')
    .single();
  if (error) throw error;
  await supabaseLog('SALVAR_CLIENTE', 'clients', data.id, client);
  return data;
}

async function supabaseSaveBusinessClientFromCadastro(cadastro = {}) {
  const codigo = String(cadastro.codigo_sap_cliente || '').trim();
  const cnpj = onlyDigits(cadastro.cnpj || '');
  let existing = null;
  if (codigo) existing = await supabaseFindBusinessClient('codigo_sap_cliente', codigo);
  if (!existing && cnpj) existing = await supabaseFindBusinessClient('cnpj', cnpj);
  return supabaseSaveBusinessClient({
    id: existing && existing.id,
    codigo_sap_cliente: codigo,
    nome: cadastro.razao_social || cadastro.nome_fantasia || '',
    nome_fantasia: cadastro.nome_fantasia || '',
    cnpj,
    telefone: cadastro.whatsapp || cadastro.telefone || '',
    email: cadastro.email_compras || '',
    endereco: formatCadastroClientAddress(cadastro),
    cidade: cadastro.cidade || '',
    estado: cadastro.estado || '',
    ativo: true,
    observacoes: [
      cadastro.protocolo ? `Origem portal: ${cadastro.protocolo}` : '',
      cadastro.observacoes || ''
    ].filter(Boolean).join('\n')
  });
}

async function supabaseFindBusinessClient(field, value) {
  const { data, error } = await supabaseClient
    .from('clients')
    .select('id')
    .eq(field, value)
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data || null;
}

function formatCadastroClientAddress(cadastro) {
  return [
    [cadastro.endereco, cadastro.numero].filter(Boolean).join(', '),
    cadastro.bairro,
    cadastro.complemento,
    [cadastro.cidade, cadastro.estado].filter(Boolean).join('/')
  ].filter(Boolean).join(' - ');
}

async function supabaseListBusinessCarriers(filters = {}) {
  let query = supabaseClient
    .from('carriers')
    .select('id, cnpj, nome, telefone, email, endereco, cidade, estado, ativo, observacoes, created_at')
    .order('nome', { ascending: true })
    .limit(300);
  if (filters.ativos === true) query = query.eq('ativo', true);
  if (filters.termo) {
    const term = `%${escapePostgrestFilter(filters.termo)}%`;
    query = query.or(`nome.ilike.${term},cnpj.ilike.${term},cidade.ilike.${term}`);
  }
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

async function supabaseSaveBusinessCarrier(payload = {}) {
  const carrier = {
    nome: String(payload.nome || '').trim(),
    cnpj: onlyDigits(payload.cnpj || '') || null,
    telefone: String(payload.telefone || '').trim() || null,
    email: String(payload.email || '').trim() || null,
    endereco: String(payload.endereco || '').trim() || null,
    cidade: String(payload.cidade || '').trim() || null,
    estado: String(payload.estado || '').trim().toUpperCase() || null,
    ativo: payload.ativo !== false,
    observacoes: String(payload.observacoes || '').trim() || null
  };
  if (!carrier.nome) throw new Error('Informe o nome da transportadora.');
  if (carrier.email && !isValidEmail(carrier.email)) throw new Error('Informe um email valido para a transportadora.');
  const record = payload.id ? Object.assign({ id: payload.id }, carrier) : carrier;
  const { data, error } = await supabaseClient
    .from('carriers')
    .upsert(record, { onConflict: 'id' })
    .select('id, cnpj, nome, telefone, email, endereco, cidade, estado, ativo, observacoes')
    .single();
  if (error) throw error;
  await supabaseLog('SALVAR_TRANSPORTADORA', 'carriers', data.id, carrier);
  return data;
}

async function supabaseSearchOrderClients(term = '') {
  const [clients, cadastros] = await Promise.all([
    supabaseListBusinessClients({ termo: term, ativos: true }),
    supabaseSearchCadastrosClientesForOrder(term)
  ]);
  const rows = clients.map((client) => ({
    origem: 'cliente',
    id: client.id,
    codigo_sap_cliente: client.codigo_sap_cliente,
    razao_social: client.nome,
    nome_fantasia: client.nome_fantasia,
    cnpj: client.cnpj,
    telefone: client.telefone,
    email_compras: client.email,
    endereco: client.endereco,
    cidade: client.cidade,
    estado: client.estado,
    status: client.ativo ? 'Ativo' : 'Inativo'
  }));
  const portalRows = cadastros.map((row) => Object.assign({ origem: 'portal' }, row));
  return rows.concat(portalRows).slice(0, 60);
}

async function supabaseSearchOrderCarriers(term = '') {
  return supabaseListBusinessCarriers({ termo: term, ativos: true });
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

async function supabaseListCadastrosClientes(filters = {}) {
  let query = supabaseClient
    .from('cadastros_clientes')
    .select('id, protocolo, status, codigo_sap_cliente, cnpj, razao_social, nome_fantasia, ie, telefone, whatsapp, email_compras, cidade, estado, endereco, numero, bairro, complemento, segmento, transportadora, prazo_desejado, vendedor, situacao_cadastral, cnae, possui_regime_especial, descricao_regime, observacoes, observacoes_internas, created_at')
    .order('created_at', { ascending: false })
    .limit(150);
  if (filters.status) query = query.eq('status', filters.status);
  if (filters.termo) {
    const term = `%${escapePostgrestFilter(filters.termo)}%`;
    query = query.or(`protocolo.ilike.${term},codigo_sap_cliente.ilike.${term},cnpj.ilike.${term},razao_social.ilike.${term},nome_fantasia.ilike.${term},cidade.ilike.${term}`);
  }
  const { data, error } = await query;
  if (error) throw error;
  return data || [];
}

async function supabaseGetPortalCadastroSettings() {
  const { data, error } = await supabaseClient
    .from('settings')
    .select('value')
    .eq('key', 'portal_cadastros')
    .maybeSingle();
  if (error) throw error;
  return Object.assign({ email_principal: '' }, data && data.value ? data.value : {});
}

async function supabaseSavePortalCadastroSettings(payload = {}) {
  const email = String(payload.email_principal || '').trim();
  if (!isValidEmail(email)) throw new Error('Informe um email principal valido.');
  const value = {
    email_principal: email,
    updated_at: new Date().toISOString()
  };
  const { data, error } = await supabaseClient
    .from('settings')
    .upsert({ key: 'portal_cadastros', value }, { onConflict: 'key' })
    .select('key, value')
    .single();
  if (error) throw error;
  await supabaseLog('ATUALIZAR_CONFIG_PORTAL_CADASTROS', 'settings', 'portal_cadastros', value);
  return data.value || value;
}

async function supabaseGetCadastrosPortalReport(filters = {}) {
  const statuses = cadastroPortalStatuses();
  const totalPromise = buildCadastrosPortalQuery('id', { count: 'exact', head: true }, filters);
  const statusPromises = statuses.map((status) => buildCadastrosPortalQuery('id', { count: 'exact', head: true }, filters).eq('status', status));
  const recentPromise = buildCadastrosPortalQuery(
    'id, protocolo, status, codigo_sap_cliente, cnpj, razao_social, nome_fantasia, telefone, whatsapp, email_compras, cidade, estado, endereco, numero, bairro, complemento, observacoes, vendedor, created_at',
    {},
    filters
  )
    .order('created_at', { ascending: false })
    .limit(200);

  const [settingsResult, totalResult, recentResult, ...statusResults] = await Promise.all([
    supabaseGetPortalCadastroSettings(),
    totalPromise,
    recentPromise,
    ...statusPromises
  ]);

  const firstError = [totalResult, recentResult, ...statusResults].find((result) => result.error);
  if (firstError) throw firstError.error;

  return {
    settings: settingsResult,
    total: totalResult.count || 0,
    byStatus: statuses.map((status, index) => ({ status, count: statusResults[index].count || 0 })),
    recent: recentResult.data || []
  };
}

function buildCadastrosPortalQuery(select, options, filters) {
  let query = supabaseClient
    .from('cadastros_clientes')
    .select(select, options);
  if (filters.status) query = query.eq('status', filters.status);
  if (filters.from) query = query.gte('created_at', filters.from);
  if (filters.to) query = query.lt('created_at', filters.to);
  return query;
}

function cadastroPortalStatuses() {
  return ['Novo', 'Em analise', 'Pendente', 'Aprovado', 'Reprovado', 'Finalizado SAP'];
}

function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || '').trim());
}

async function supabaseUpdateCadastroCliente(payload) {
  const updates = {
    status: payload.status,
    codigo_sap_cliente: String(payload.codigo_sap_cliente || '').trim() || null,
    observacoes_internas: payload.observacoes_internas || null
  };
  const { data, error } = await supabaseClient
    .from('cadastros_clientes')
    .update(updates)
    .eq('id', payload.id)
    .select('id, protocolo, status, codigo_sap_cliente, observacoes_internas')
    .single();
  if (error) throw error;
  await supabaseLog('ATUALIZAR_CADASTRO_CLIENTE', 'cadastros_clientes', payload.id, updates);
  return data;
}

async function supabaseSearchCadastrosClientesForOrder(term = '') {
  const search = String(term || '').trim();
  let query = supabaseClient
    .from('cadastros_clientes')
    .select('id, protocolo, status, codigo_sap_cliente, cnpj, razao_social, nome_fantasia, telefone, whatsapp, email_compras, cidade, estado, endereco, numero, bairro, complemento, transportadora, prazo_desejado, vendedor, created_at')
    .in('status', ['Aprovado', 'Finalizado SAP'])
    .order('created_at', { ascending: false })
    .limit(30);

  if (search) {
    const pattern = `%${escapePostgrestFilter(search)}%`;
    query = query.or([
      `protocolo.ilike.${pattern}`,
      `codigo_sap_cliente.ilike.${pattern}`,
      `cnpj.ilike.${pattern}`,
      `razao_social.ilike.${pattern}`,
      `nome_fantasia.ilike.${pattern}`,
      `cidade.ilike.${pattern}`
    ].join(','));
  }

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
  const mapped = plan.productsUnique.map(filterProductFields);
  if (!mapped.length) throw new Error('Nenhum produto valido encontrado para importar.');

  const session = getStoredSession() || {};
  let batch = null;
  try {
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
        .upsert(chunks[index], { onConflict: 'codigo', defaultToNull: false });
      if (error) throw error;
      if (typeof payload.onProgress === 'function') {
        payload.onProgress({
          done: Math.min((index + 1) * 300, mapped.length),
          total: mapped.length,
          batch: index + 1,
          batches: chunks.length
        });
      }
    }

    batch = {
      usuario: session.usuario || null,
      tipo: plan.tipo,
      total_recebido: plan.totalRows,
      novos,
      atualizados,
      sem_alteracao: plan.duplicates,
      erros: plan.invalidRows.length,
      status: 'APLICADO'
    };
    await supabaseClient.from('import_batches').insert(batch);
    await supabaseLog('IMPORTAR_PRODUTOS', 'products', plan.tipo, {
      data_hora: new Date().toISOString(),
      usuario: session.usuario || null,
      nome_arquivo: payload.fileName || null,
      linhas_validas: plan.validRows,
      produtos_unicos: plan.uniqueRows,
      codigos_duplicados: plan.duplicateCodes,
      campos_atualizados: plan.fieldsUpdated,
      status: 'sucesso',
      resumo: batch
    });
    return { summary: batch, preview: plan.preview };
  } catch (error) {
    await supabaseLog('ERRO_IMPORTAR_PRODUTOS', 'products', plan.tipo, {
      data_hora: new Date().toISOString(),
      usuario: session.usuario || null,
      nome_arquivo: payload.fileName || null,
      total_linhas: plan.totalRows,
      linhas_validas: plan.validRows,
      produtos_unicos: plan.uniqueRows,
      duplicados: plan.duplicates,
      invalidos: plan.invalidRows.length,
      status: 'erro',
      mensagem_erro: error.message
    });
    throw error;
  }
}

async function supabasePreviewImportProducts(payload) {
  const tipo = normalizeImportType(payload.tipo);
  const table = parseDelimitedTable(payload.texto || '');
  const rows = applyImportMapping(table.rows, payload.mapping);
  if (!rows.length) throw new Error('Cole ou selecione um CSV/TSV com cabecalho.');

  const invalidRows = [];
  const products = [];

  rows.forEach((row, index) => {
    const product = filterProductFields(mapImportProduct(row, tipo));
    if (!product.codigo) {
      invalidRows.push({ linha: index + 2, motivo: 'Codigo ausente' });
      return;
    }
    if (tipo === 'PRECO_SP' && product.preco_sp == null) {
      invalidRows.push({ linha: index + 2, motivo: 'Preco SP ausente ou invalido' });
      return;
    }
    if (tipo === 'PRECO_PR' && product.preco_pr == null) {
      invalidRows.push({ linha: index + 2, motivo: 'Preco PR ausente ou invalido' });
      return;
    }
    products.push(product);
  });

  if (!products.length) throw new Error('Nenhum produto valido encontrado na importacao.');

  const consolidated = consolidateImportProducts(products);
  const productsUnique = consolidated.productsUnique;
  const codes = productsUnique.map((product) => product.codigo);
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
    fieldsUpdated: getImportUpdatedFields(tipo),
    totalRows: rows.length,
    validRows: products.length,
    uniqueRows: productsUnique.length,
    invalidRows,
    duplicateCodes: consolidated.duplicateCodes,
    duplicates: consolidated.duplicateCodes.length,
    existingCount,
    newCount: Math.max(productsUnique.length - existingCount, 0),
    preview: productsUnique.slice(0, 8),
    products,
    productsUnique
  };
}

function getImportColumnPlan(text, tipo) {
  const normalizedType = normalizeImportType(tipo);
  const table = parseDelimitedTable(text || '');
  return {
    headers: table.headers,
    sampleRows: table.rows.slice(0, 3),
    mapping: Object.fromEntries(table.headers.map((header) => [header, suggestImportField(header, normalizedType)]))
  };
}

function getImportAutoAnalysis(text, currentType) {
  const firstPlan = getImportColumnPlan(text, currentType);
  const suggestedType = inferImportTypeFromMapping(firstPlan.mapping, currentType);
  if (suggestedType === currentType || normalizeImportType(suggestedType) === normalizeImportType(currentType)) {
    return Object.assign({ suggestedType }, firstPlan);
  }
  return Object.assign({ suggestedType }, getImportColumnPlan(text, suggestedType));
}

function inferImportTypeFromMapping(mapping, currentType) {
  const fields = Object.values(mapping || {}).filter(Boolean);
  const has = (field) => fields.includes(field);
  const descriptiveCount = ['descricao', 'marca', 'aplicacao', 'ano', 'ipi', 'preco_sem_imposto', 'grupo', 'categoria', 'montadora', 'oem', 'similar']
    .filter(has).length;
  const hasOnlyStock = has('estoque') && descriptiveCount === 0 && !has('preco_sp') && !has('preco_pr') && !has('preco_referencia');
  if (has('preco_sp') && descriptiveCount === 0) return 'PRECO_SP';
  if (has('preco_pr') && descriptiveCount === 0) return 'PRECO_PR';
  if (hasOnlyStock) return 'PORTAL_ESTOQUE';
  if (descriptiveCount >= 2 || has('preco_sem_imposto') || has('preco_referencia')) return 'CRISTIANO';
  return currentType || 'CRISTIANO';
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

const allowedProductFields = [
  'codigo',
  'descricao',
  'marca',
  'aplicacao',
  'ano',
  'ipi',
  'preco_sem_imposto',
  'estoque',
  'estoque_quantidade',
  'preco_sp',
  'preco_pr',
  'status_estoque',
  'status_cadastro',
  'url_imagem',
  'grupo',
  'categoria',
  'montadora',
  'detalhes',
  'oem',
  'similar'
];

function normalizeImportType(tipo) {
  if (tipo === 'CRISTIANO') return 'CADASTRO_COMPLETO';
  return tipo || 'CATALOGO_PESQUISA';
}

function filterProductFields(product) {
  const clean = {};
  allowedProductFields.forEach((field) => {
    if (!Object.prototype.hasOwnProperty.call(product, field)) return;
    const value = product[field];
    if (value === '' || value == null) return;
    clean[field] = value;
  });
  return clean;
}

function mergeImportProduct(previous, incoming) {
  const merged = Object.assign({}, previous);
  Object.entries(incoming).forEach(([field, value]) => {
    if (field === 'codigo') {
      merged.codigo = value;
      return;
    }
    if (value === '' || value == null) return;
    merged[field] = value;
  });
  return merged;
}

function consolidateImportProducts(products) {
  const byCode = new Map();
  const duplicateCodes = new Set();
  products.forEach((product) => {
    if (byCode.has(product.codigo)) {
      duplicateCodes.add(product.codigo);
      byCode.set(product.codigo, mergeImportProduct(byCode.get(product.codigo), product));
      return;
    }
    byCode.set(product.codigo, product);
  });
  return {
    productsUnique: Array.from(byCode.values()).map(filterProductFields),
    duplicateCodes: Array.from(duplicateCodes)
  };
}

function getImportUpdatedFields(tipo) {
  if (tipo === 'PORTAL_ESTOQUE') return ['codigo', 'estoque', 'estoque_quantidade', 'status_estoque'];
  if (tipo === 'PRECO_SP') return ['codigo', 'preco_sp'];
  if (tipo === 'PRECO_PR') return ['codigo', 'preco_pr'];
  if (tipo === 'CATALOGO_PESQUISA') {
    return ['codigo', 'descricao', 'marca', 'aplicacao', 'ano', 'grupo', 'categoria', 'montadora', 'detalhes', 'oem', 'similar'];
  }
  return [
    'codigo',
    'descricao',
    'marca',
    'aplicacao',
    'ano',
    'ipi',
    'preco_sem_imposto',
    'estoque',
    'estoque_quantidade',
    'status_estoque',
    'status_cadastro',
    'url_imagem',
    'grupo',
    'categoria',
    'montadora',
    'detalhes',
    'oem',
    'similar'
  ];
}

function parseDelimitedTable(text) {
  const source = String(text || '').trim();
  if (!source) return { headers: [], rows: [] };
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
  const originalHeaders = rows.shift() || [];
  const headers = originalHeaders.map(normalizeHeader);
  return {
    headers: originalHeaders.map((header) => String(header || '').trim()),
    rows: rows.map((cells) => {
    const item = {};
    headers.forEach((header, index) => {
      if (header) item[header] = String(cells[index] || '').trim();
    });
    return item;
    })
  };
}

function parseDelimitedText(text) {
  return parseDelimitedTable(text).rows;
}

function applyImportMapping(rows, mapping) {
  if (!mapping || !Object.values(mapping).some(Boolean)) return rows;
  return rows.map((row) => {
    const mapped = {};
    Object.entries(mapping).forEach(([header, field]) => {
      if (!field) return;
      const sourceKey = normalizeHeader(header);
      if (Object.prototype.hasOwnProperty.call(row, sourceKey)) mapped[field] = row[sourceKey];
    });
    return mapped;
  });
}

function suggestImportField(header, tipo) {
  const key = normalizeHeader(header);
  const exact = {
    codigoips: 'codigo',
    codigo: 'codigo',
    cod: 'codigo',
    codproduto: 'codigo',
    codigoproduto: 'codigo',
    codigofabricante: 'codigo',
    sku: 'codigo',
    descricao: 'descricao',
    descr: 'descricao',
    descricaoproduto: 'descricao',
    marca: 'marca',
    aplicacao: 'aplicacao',
    aplica: 'aplicacao',
    veiculo: 'aplicacao',
    veiculos: 'aplicacao',
    veiculoaplicacao: 'aplicacao',
    veiculosaplicacao: 'aplicacao',
    ano: 'ano',
    ipi: 'ipi',
    precosimp: 'preco_sem_imposto',
    precosemimposto: 'preco_sem_imposto',
    precosemimp: 'preco_sem_imposto',
    estoque: 'estoque',
    dispgeral: 'estoque',
    dispvenda: 'estoque',
    quantidade: 'estoque',
    qtd: 'estoque',
    qtde: 'estoque',
    grupo: 'grupo',
    linha: 'categoria',
    linhas: 'categoria',
    categoria: 'categoria',
    montadora: 'montadora',
    oem: 'oem',
    similar: 'similar',
    similares: 'similar'
  };
  if (exact[key]) return exact[key];
  if (['precocimp', 'precocomimposto', 'valor', 'prunitci', 'totalcimp', 'praposdesc'].includes(key)) {
    if (tipo === 'PRECO_SP') return 'preco_sp';
    if (tipo === 'PRECO_PR') return 'preco_pr';
    return 'preco_referencia';
  }
  if (key.includes('precosp')) return 'preco_sp';
  if (key.includes('precopr')) return 'preco_pr';
  if (key.includes('preco') && key.includes('imp')) {
    if (tipo === 'PRECO_SP') return 'preco_sp';
    if (tipo === 'PRECO_PR') return 'preco_pr';
    return 'preco_referencia';
  }
  return '';
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
    if (Object.prototype.hasOwnProperty.call(row, alias) && row[alias] !== '') return row[alias];
    if (Object.prototype.hasOwnProperty.call(row, key) && row[key] !== '') return row[key];
  }
  return '';
}

function importNumber(value) {
  let text = String(value || '').trim();
  if (!text) return null;
  text = text.replace(/[^\d,.-]/g, '');
  if (text.includes(',') && text.includes('.')) text = text.replace(/\./g, '').replace(',', '.');
  else if (text.includes(',')) text = text.replace(',', '.');
  const parsed = Number(text);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeProductCode(value) {
  let text = String(value || '').trim();
  if (!text) return '';
  text = text.replace(/\s+/g, '');
  if (/^\d+\.0+$/.test(text)) return text.replace(/\.0+$/, '');
  if (/^\d+(?:[.,]\d+)?e\+\d+$/i.test(text)) {
    const parsed = Number(text.replace(',', '.'));
    if (Number.isFinite(parsed)) return parsed.toLocaleString('en-US', { useGrouping: false, maximumFractionDigits: 0 });
  }
  return text;
}

function mapImportProduct(row, tipo) {
  const importType = normalizeImportType(tipo);
  const codigo = normalizeProductCode(pickImport(row, ['codigo', 'codigo ips', 'cod', 'cod.', 'sku']));
  const estoque = pickImport(row, ['estoque', 'disp geral', 'disp. geral', 'disp venda', 'disp. venda', 'qtde']);
  const precoSemImposto = importNumber(pickImport(row, [
    'preco s/imp', 'preco s imp', 'preco sem imposto', 'preco_sem_imposto', 'pr.unit.', 'pr unit'
  ]));
  const base = { codigo };
  const descriptive = {
    descricao: pickImport(row, ['descricao', 'descr']),
    marca: pickImport(row, ['marca']),
    aplicacao: pickImport(row, ['aplicacao']),
    ano: pickImport(row, ['ano']),
    ipi: importNumber(pickImport(row, ['ipi'])),
    preco_sem_imposto: precoSemImposto,
    status_cadastro: pickImport(row, ['status cadastro', 'status_cadastro']),
    url_imagem: pickImport(row, ['url imagem', 'url_imagem', 'imagem']),
    grupo: pickImport(row, ['grupo']),
    categoria: pickImport(row, ['categoria', 'linha']),
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
  const price = importNumber(pickImport(row, [
    'preco_sp', 'preco_pr', 'preco_referencia', 'preco c/imp', 'preco c imp', 'preco com imposto', 'preco', 'valor',
    'prunitci', 'pr.unit.(c/i)', 'pr unit c/i', 'total c imp', 'total c/ imp',
    'pr apos desc', 'pr.apos desc'
  ]));

  if (importType === 'PORTAL_ESTOQUE') {
    Object.assign(base, stock);
  } else if (importType === 'PRECO_PR') {
    if (price != null) base.preco_pr = price;
  } else if (importType === 'PRECO_SP') {
    if (price != null) base.preco_sp = price;
  } else if (importType === 'CATALOGO_PESQUISA') {
    Object.assign(base, descriptive);
  } else {
    Object.assign(base, descriptive, stock);
    const precoSp = importNumber(pickImport(row, ['preco_sp', 'preco sp', 'preco c/imp sp', 'preco c imp sp']));
    const precoPr = importNumber(pickImport(row, ['preco_pr', 'preco pr', 'preco c/imp pr', 'preco c imp pr']));
    if (precoSp != null) base.preco_sp = precoSp;
    if (precoPr != null) base.preco_pr = precoPr;
  }

  return Object.fromEntries(Object.entries(base).filter(([, value]) => value !== ''));
}

function chunkArray(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
