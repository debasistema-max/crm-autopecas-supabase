const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const profile = { id_usuario: 'fictional-user', usuario: 'lab-user', nome: 'LAB ONLY',
  email: 'lab@example.invalid', perfil: 'VENDEDOR', ativo: true };
const fictionalPassword = ['not', 'a', 'real', 'credential'].join('-');

function storeFixture() {
  const calls = [];
  let stored;
  const client = {
    auth: {
      async getSession() { calls.push('getSession'); return { data: { session: null } }; },
      async signUp(input) { calls.push('signUp'); assert.equal(input.password, fictionalPassword);
        return { data: { user: { id: 'fictional-created-user' } } }; },
      async updateUser() { assert.fail('unexpected password mutation'); }
    },
    from(table) {
      assert.equal(table, 'profiles');
      calls.push('profiles');
      return {
        select() { return { eq() { return { async maybeSingle() { return { data: null }; } }; } }; },
        upsert(value) { stored = value; calls.push('upsert');
          return { select() { return { async single() { return { data: value }; } }; } }; }
      };
    }
  };
  const c = vm.createContext({ supabaseClient: client, console });
  vm.runInContext(fs.readFileSync('public/js/supabase_store.js', 'utf8'), c);
  c.supabaseLog = async (action, table, id, data) => {
    calls.push('audit');
    assert.ok(!Object.hasOwn(data, 'senha'));
    assert.ok(!Object.hasOwn(data, 'password'));
  };
  return { c, calls, stored: () => stored };
}

function uiFixture() {
  const nodes = new Map();
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, { value: '', hidden: false, disabled: false,
      required: false, style: {}, textContent: '', innerHTML: '', scrollIntoView() {}, addEventListener() {} });
    return nodes.get(id);
  };
  const c = vm.createContext({ document: { getElementById: node, querySelectorAll: () => [] },
    supabaseListUsers: async () => [] });
  vm.runInContext(fs.readFileSync('public/js/users.js', 'utf8'), c);
  return { c, node };
}

test('existing user password input is rejected before any query, mutation or audit', async () => {
  for (const key of ['id_usuario', 'id']) {
    const h = storeFixture();
    const payload = { ...profile, id_usuario: undefined, [key]: 'fictional-user', senha: fictionalPassword };
    await assert.rejects(h.c.supabaseSaveUser(payload), error => {
      assert.match(error.message, /senha nao foi alterada/);
      assert.ok(!error.message.includes(fictionalPassword));
      return true;
    });
    assert.deepEqual(h.calls, []);
  }
});

test('editing the profile with a blank password does not mutate Auth credentials', async () => {
  const h = storeFixture();
  const result = await h.c.supabaseSaveUser({ ...profile, senha: '' });
  assert.equal(result.id, profile.id_usuario);
  assert.deepEqual(h.calls, ['profiles', 'profiles', 'profiles', 'upsert', 'audit']);
  assert.ok(!Object.hasOwn(h.stored(), 'senha'));
});

test('new user still requires and sends its initial password only to Auth', async () => {
  const h = storeFixture();
  const result = await h.c.supabaseSaveUser({ ...profile, id_usuario: '', senha: fictionalPassword });
  assert.equal(result.id, 'fictional-created-user');
  assert.ok(h.calls.includes('signUp'));
  assert.ok(!Object.hasOwn(h.stored(), 'senha'));
  const empty = storeFixture();
  await assert.rejects(empty.c.supabaseSaveUser({ ...profile, id_usuario: '', senha: '' }), /senha inicial/);
  assert.ok(!empty.calls.includes('upsert'));
  assert.ok(!empty.calls.includes('signUp'));
});

test('edit form clears and disables password; new form clears all fields and restores required password', () => {
  const h = uiFixture();
  h.node('newUserPassword').value = fictionalPassword;
  h.c.fillUserForm({ id: 'fictional-user', usuario: 'lab-user', nome: 'LAB', email: 'lab@example.invalid', perfil: 'ADMIN', ativo: true });
  assert.equal(h.node('newUserPassword').value, '');
  assert.equal(h.node('newUserPassword').disabled, true);
  assert.equal(h.node('newUserPassword').required, false);
  assert.equal(h.node('newUserPasswordField').hidden, true);
  h.c.clearUserForm();
  for (const id of ['userId', 'newUserLogin', 'newUserName', 'newUserEmail', 'newUserPassword']) {
    assert.equal(h.node(id).value, '');
  }
  assert.equal(h.node('newUserProfile').value, 'VENDEDOR');
  assert.equal(h.node('newUserActive').value, 'true');
  assert.equal(h.node('newUserPassword').disabled, false);
  assert.equal(h.node('newUserPassword').required, true);
  assert.equal(h.node('newUserPasswordField').hidden, false);
});

test('profile save omits stale/autofilled password and keeps an honest success message after refresh', async () => {
  const h = uiFixture();
  h.c.fillUserForm({ id: 'fictional-user', usuario: 'lab-user', nome: 'LAB', email: 'lab@example.invalid', ativo: true });
  h.node('newUserPassword').value = fictionalPassword;
  h.c.supabaseSaveUser = async payload => {
    assert.equal(payload.senha, '');
    assert.equal(payload.id_usuario, 'fictional-user');
  };
  const button = { disabled: false, textContent: 'Salvar usuario' };
  await h.c.saveUserFromForm({ preventDefault() {}, submitter: button });
  assert.equal(h.node('userMessage').textContent, 'Perfil atualizado. A senha nao foi alterada.');
  assert.equal(button.disabled, false);
});

test('failures do not show success and restore the save button', async () => {
  const h = uiFixture();
  h.c.supabaseSaveUser = async () => { throw new Error('Erro ficticio'); };
  const button = { disabled: false, textContent: 'Salvar usuario' };
  await h.c.saveUserFromForm({ preventDefault() {}, submitter: button });
  assert.equal(h.node('userMessage').textContent, 'Erro ficticio');
  assert.equal(button.disabled, false);
});

test('both login and app invalidate the updated store cache; app also invalidates users UI', () => {
  for (const file of ['public/app.html', 'public/index.html']) {
    assert.match(fs.readFileSync(file, 'utf8'), /js\/supabase_store\.js\?v=20261027-security-2/);
  }
  assert.match(fs.readFileSync('public/app.html', 'utf8'), /js\/users\.js\?v=20261027-security-2/);
});
