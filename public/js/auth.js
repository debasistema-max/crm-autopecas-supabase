function getStoredSession() {
  try {
    return JSON.parse(sessionStorage.getItem(APP_CONFIG.sessionKey) || 'null');
  } catch (error) {
    return null;
  }
}

function setStoredSession(session) {
  sessionStorage.setItem(APP_CONFIG.sessionKey, JSON.stringify(session));
}

function clearStoredSession() {
  sessionStorage.removeItem(APP_CONFIG.sessionKey);
}

function getSessionId() {
  const stored = getStoredSession();
  return stored && (stored.sessionId || stored.token);
}

async function validateCurrentSession() {
  const sessionId = getSessionId();
  if (!sessionId) return null;
  const supabaseSession = await supabaseValidateSession();
  if (supabaseSession) {
    setStoredSession(supabaseSession);
    return supabaseSession;
  }
  return null;
}

document.addEventListener('DOMContentLoaded', () => {
  const form = document.getElementById('loginForm');
  if (!form) return;

  const message = document.getElementById('loginMessage');
  const button = document.getElementById('loginButton');
  const buttonLabel = document.getElementById('loginButtonLabel');
  const password = document.getElementById('senha');
  const passwordToggle = document.getElementById('passwordToggle');
  let submitting = false;

  function setPasswordVisible(visible) {
    password.type = visible ? 'text' : 'password';
    passwordToggle.textContent = visible ? 'Ocultar' : 'Mostrar';
    passwordToggle.setAttribute('aria-label', visible ? 'Ocultar senha' : 'Mostrar senha');
    passwordToggle.setAttribute('aria-pressed', String(visible));
  }

  function setLoading(loading) {
    button.disabled = loading;
    button.setAttribute('aria-busy', String(loading));
    buttonLabel.textContent = loading ? 'Entrando...' : 'Entrar';
    form.setAttribute('aria-busy', String(loading));
  }

  passwordToggle.addEventListener('click', () => {
    setPasswordVisible(password.type === 'password');
    password.focus();
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (submitting) return;
    submitting = true;
    message.textContent = '';
    message.classList.remove('is-success');
    setPasswordVisible(false);
    setLoading(true);
    let succeeded = false;
    try {
      const usuario = document.getElementById('usuario').value;
      const senha = password.value;
      const data = await supabaseLogin(usuario, senha);
      const session = Object.assign({}, data.session || {}, {
        sessionId: data.sessionId || data.token || (data.session && data.session.token),
        modules: data.modules || []
      });
      setStoredSession(session);
      succeeded = true;
      message.classList.add('is-success');
      message.textContent = 'Acesso autorizado. Abrindo o sistema...';
      buttonLabel.textContent = 'Acesso autorizado';
      window.location.href = 'app.html';
    } catch (error) {
      password.value = '';
      message.textContent = 'Usuario ou senha invalidos.';
      message.focus();
    } finally {
      if (!succeeded) {
        submitting = false;
        setLoading(false);
      }
    }
  });

  window.addEventListener('pageshow', () => {
    setPasswordVisible(false);
  });
});
