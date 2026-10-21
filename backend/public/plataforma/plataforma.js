/* =========================================================================
   Panel de plataforma (superadministrador)
   Empresas: plan, vencimiento, apps habilitadas, suspensión y notas.
   Planes: límites de sedes, personas y productos.
   Los planes se cobran fuera de las apps (política de Google Play): aquí se
   asignan después del pago.
   ========================================================================= */
'use strict';

const API = new URL('../api', location.href).pathname.replace(/\/$/, '');
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

const estado = { token: null, planes: [], empresas: [], empresaEditada: null, planEditado: null };

const NOMBRE_APP = { INVENTARIO: 'Inventario', ASISTENCIA: 'Personal' };
const RECURSOS = [
  ['sedes', 'Sedes'],
  ['personas', 'Personas'],
  ['productos', 'Productos'],
];

// ------------------------------------------------------------------ utilidades

function sesion(token) {
  if (token !== undefined) {
    estado.token = token;
    try { token ? sessionStorage.setItem('pf_token', token) : sessionStorage.removeItem('pf_token'); } catch { /* modo privado */ }
  }
  if (estado.token) return estado.token;
  try { estado.token = sessionStorage.getItem('pf_token'); } catch { /* sin almacenamiento */ }
  return estado.token;
}

async function api(ruta, { metodo = 'GET', cuerpo } = {}) {
  const cabeceras = { Accept: 'application/json' };
  if (sesion()) cabeceras.Authorization = `Bearer ${sesion()}`;
  if (cuerpo !== undefined) cabeceras['Content-Type'] = 'application/json';
  let r;
  try {
    r = await fetch(API + ruta, { method: metodo, headers: cabeceras, body: cuerpo !== undefined ? JSON.stringify(cuerpo) : undefined });
  } catch {
    throw Object.assign(new Error('Sin conexión con el servidor'), { status: 0 });
  }
  const datos = r.status === 204 ? null : await r.json().catch(() => ({}));
  if ((r.status === 401 || r.status === 403) && sesion() && ruta !== '/auth/login') {
    salir('Tu sesión venció o no tiene permiso. Ingresa de nuevo.');
    throw Object.assign(new Error(datos?.error || 'Sesión vencida'), { status: r.status });
  }
  if (!r.ok) throw Object.assign(new Error(datos?.error || `Error ${r.status}`), { status: r.status, campo: datos?.campo });
  return datos;
}

function el(etiqueta, attrs = {}, ...hijos) {
  const n = document.createElement(etiqueta);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === 'class') n.className = v;
    // Por CSSOM y no como atributo: la CSP (sin 'unsafe-inline') bloquea los
    // atributos style, pero no los estilos asignados desde el script.
    else if (k === 'style') n.style.cssText = v;
    else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
    else n.setAttribute(k, v === true ? '' : v);
  }
  for (const h of hijos.flat()) if (h != null && h !== false) n.append(h instanceof Node ? h : document.createTextNode(String(h)));
  return n;
}

function icono(id) {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  const use = document.createElementNS(ns, 'use');
  use.setAttribute('href', `#${id}`);
  svg.append(use);
  return svg;
}

function avisar(mensaje, error = false) {
  const n = el('div', { class: `aviso ${error ? 'aviso--error' : 'aviso--ok'}`, role: error ? 'alert' : 'status' },
    icono(error ? 'i-alerta' : 'i-check'), mensaje);
  $('#avisos').append(n);
  setTimeout(() => n.remove(), 4500);
}

function mostrarError(id, mensaje) {
  const n = $(id);
  n.textContent = mensaje || '';
  n.hidden = !mensaje;
}

/** «Cancelar» cierra el diálogo sin validar; el resto pasa por `alEnviar`. */
function cancelable(form, alEnviar) {
  form.addEventListener('submit', (ev) => {
    if (ev.submitter?.value === 'cancelar') return;
    ev.preventDefault();
    alEnviar(ev);
  });
}

const fechaCorta = (s) => (s ? new Date(s.replace(' ', 'T') + 'Z').toLocaleDateString('es-CO', { day: 'numeric', month: 'short', year: 'numeric' }) : '—');
const limiteTxt = (m) => (m == null ? '∞' : String(m));

function aplicarTema(tema) {
  document.documentElement.dataset.theme = tema;
  try { localStorage.setItem('pf_tema', tema); } catch { /* sin almacenamiento */ }
}

/**
 * Medidor de uso: número y texto («3 de 3 · lleno»), no solo color, para que
 * se entienda también sin distinguir colores y con lector de pantalla.
 */
function medidor(nombre, { usados, maximo }) {
  const pct = maximo == null ? Math.min(100, usados * 4) : Math.min(100, Math.round((usados / Math.max(maximo, 1)) * 100));
  const lleno = maximo != null && usados >= maximo;
  const alto = !lleno && maximo != null && pct >= 80;
  const texto = maximo == null ? `${usados} · sin límite` : `${usados} de ${maximo}${lleno ? ', límite alcanzado' : ''}`;
  return el('div', { class: `medidor${lleno ? ' medidor--lleno' : alto ? ' medidor--alto' : ''}`, role: 'img', 'aria-label': `${nombre}: ${texto}` },
    el('span', { class: 'medidor__nombre' }, nombre),
    el('span', { class: 'medidor__pista' }, el('span', { style: `width:${maximo == null ? 0 : pct}%` })),
    el('span', { class: 'medidor__valor' }, `${usados}/${limiteTxt(maximo)}`));
}

// ------------------------------------------------------------------ sesión

function salir(mensaje) {
  sesion(null);
  $('#vista-app').hidden = true;
  $('#vista-login').hidden = false;
  mostrarError('#login-error', mensaje);
  $('#form-login [name=email]').focus();
}

$('#form-login').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const f = ev.currentTarget;
  const boton = $('button[type=submit]', f);
  mostrarError('#login-error');
  if (!f.email.value.trim() || !f.password.value) return mostrarError('#login-error', 'Escribe tu correo y contraseña.');
  boton.disabled = true;
  try {
    const r = await api('/auth/login', { metodo: 'POST', cuerpo: { email: f.email.value, password: f.password.value } });
    if (!r.superadmin) {
      return mostrarError('#login-error', 'Esta cuenta es de una empresa: entra a su panel o a las apps.');
    }
    sesion(r.token);
    f.password.value = '';
    await entrar();
  } catch (e) {
    mostrarError('#login-error', e.message);
  } finally {
    boton.disabled = false;
  }
  return null;
});

async function entrar() {
  $('#vista-login').hidden = true;
  $('#vista-app').hidden = false;
  await cargarPlanes();
  await Promise.all([cargarResumen(), cargarEmpresas()]);
}

$('#btn-salir').addEventListener('click', () => salir());
$('#btn-tema').addEventListener('click', () => aplicarTema(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'));

$$('.pestanas [role=tab]').forEach((b) => b.addEventListener('click', () => {
  $$('.pestanas [role=tab]').forEach((x) => x.setAttribute('aria-selected', String(x === b)));
  $('#seccion-empresas').hidden = b.dataset.seccion !== 'empresas';
  $('#seccion-planes').hidden = b.dataset.seccion !== 'planes';
}));

// ------------------------------------------------------------------ resumen

async function cargarResumen() {
  const { resumen } = await api('/plataforma/resumen');
  const kpi = (etiqueta, valor, ico, color) => el('div', { class: 'kpi', style: `--c: var(${color})` },
    el('div', { class: 'kpi__etiqueta' }, icono(ico), el('span', { class: 'etiqueta' }, etiqueta)),
    el('p', { class: 'kpi__valor' }, valor));
  $('#kpis').replaceChildren(
    kpi('Empresas', resumen.empresas, 'i-edificio', '--primario'),
    kpi('Nuevas · 30 días', resumen.nuevas_30_dias, 'i-nuevo', '--entrada'),
    kpi('En su límite', resumen.en_limite, 'i-alerta', '--alerta'),
    kpi('Suspendidas', resumen.suspendidas, 'i-pausa', '--peligro'),
  );
}

// ------------------------------------------------------------------ empresas

let temporizadorBusqueda = null;
$('#buscar').addEventListener('input', () => {
  clearTimeout(temporizadorBusqueda);
  temporizadorBusqueda = setTimeout(cargarEmpresas, 300);
});
$('#filtro-estado').addEventListener('change', cargarEmpresas);
$('#filtro-plan').addEventListener('change', cargarEmpresas);

async function cargarEmpresas() {
  const q = new URLSearchParams();
  if ($('#buscar').value.trim()) q.set('buscar', $('#buscar').value.trim());
  if ($('#filtro-estado').value) q.set('estado', $('#filtro-estado').value);
  if ($('#filtro-plan').value) q.set('plan', $('#filtro-plan').value);
  try {
    const { empresas } = await api(`/plataforma/empresas?${q}`);
    estado.empresas = empresas;
    $('#lista-empresas').replaceChildren(...(empresas.length ? empresas.map(filaEmpresa) : [
      el('tr', {}, el('td', { colspan: 5 }, el('div', { class: 'vacio' }, el('strong', {}, 'Sin resultados'), 'Prueba con otro nombre, estado o plan.'))),
    ]));
  } catch (e) {
    if (e.status !== 401) avisar(e.message, true);
  }
}

function filaEmpresa(e) {
  const abrir = () => abrirEmpresa(e);
  return el('tr', { tabindex: 0, onclick: abrir, onkeydown: (ev) => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); abrir(); } } },
    el('td', {},
      el('div', { class: 'empresa__nombre' }, e.nombre),
      el('div', { class: 'empresa__sub' }, [e.email_contacto, e.nit && `NIT ${e.nit}`, `desde ${fechaCorta(e.creada)}`].filter(Boolean).join(' · '))),
    el('td', {},
      el('span', { class: 'pildora', style: `--c: var(${e.plan.codigo === 'GRATIS' ? '--texto-suave' : '--primario'})` }, e.plan.nombre),
      e.plan.vencido && el('div', { class: 'empresa__sub' }, 'Vencido: opera como Gratis'),
      !e.plan.vencido && e.plan.vence && el('div', { class: 'empresa__sub' }, `Vence ${fechaCorta(e.plan.vence)}`)),
    el('td', {}, el('div', { class: 'medidores' }, RECURSOS.map(([k, n]) => medidor(n, e.uso[k])))),
    el('td', {}, el('div', { class: 'chips' }, e.apps.length
      ? e.apps.map((a) => el('span', { class: 'pildora pildora--icono', style: '--c: var(--secundario)' }, NOMBRE_APP[a] ?? a))
      : el('span', { class: 'suave' }, 'Ninguna'))),
    el('td', {}, el('span', { class: 'pildora', style: `--c: var(${e.estado === 'ACTIVA' ? '--entrada' : '--peligro'})` },
      e.estado === 'ACTIVA' ? 'Activa' : 'Suspendida')));
}

function abrirEmpresa(e) {
  estado.empresaEditada = e;
  const f = $('#form-empresa');
  f.reset();
  $('#dlg-empresa-titulo').textContent = e.nombre;
  $('#dlg-empresa-contacto').textContent = [e.email_contacto, e.telefono].filter(Boolean).join(' · ');
  $('#dlg-empresa-uso').replaceChildren(...RECURSOS.map(([k, n]) => medidor(n, e.uso[k])));
  f.plan_id.replaceChildren(...estado.planes.filter((p) => p.activo || p.id === e.plan.id).map((p) =>
    el('option', { value: p.id }, `${p.nombre} · ${limiteTxt(p.max_sedes)} sedes, ${limiteTxt(p.max_personas)} personas, ${limiteTxt(p.max_productos)} productos`)));
  f.plan_id.value = String(e.plan.id);
  f.plan_vence.value = e.plan.vence ?? '';
  f.app_INVENTARIO.checked = e.apps.includes('INVENTARIO');
  f.app_ASISTENCIA.checked = e.apps.includes('ASISTENCIA');
  f.suspendida.checked = e.estado === 'SUSPENDIDA';
  f.notas.value = e.notas ?? '';
  mostrarError('#empresa-error');
  $('#dlg-empresa').showModal();
}

cancelable($('#form-empresa'), async (ev) => {
  const f = ev.currentTarget;
  const e = estado.empresaEditada;
  const suspender = f.suspendida.checked && e.estado !== 'SUSPENDIDA';
  if (suspender && !confirm(`¿Suspender ${e.nombre}? Nadie de esta empresa podrá entrar a las apps hasta que la reactives.`)) return;
  const boton = $('button[type=submit]', f);
  boton.disabled = true;
  try {
    const { empresa } = await api(`/plataforma/empresas/${e.id}`, {
      metodo: 'PUT',
      cuerpo: {
        plan_id: Number(f.plan_id.value),
        plan_vence: f.plan_vence.value || null,
        estado: f.suspendida.checked ? 'SUSPENDIDA' : 'ACTIVA',
        apps: { INVENTARIO: f.app_INVENTARIO.checked, ASISTENCIA: f.app_ASISTENCIA.checked },
        notas: f.notas.value,
      },
    });
    $('#dlg-empresa').close();
    avisar(`${empresa.nombre}: cambios guardados`);
    await Promise.all([cargarResumen(), cargarEmpresas()]);
  } catch (x) {
    mostrarError('#empresa-error', x.message);
  } finally {
    boton.disabled = false;
  }
});

// ------------------------------------------------------------------ planes

async function cargarPlanes() {
  const { planes } = await api('/plataforma/planes');
  estado.planes = planes;
  const filtro = $('#filtro-plan');
  const elegido = filtro.value;
  filtro.replaceChildren(el('option', { value: '' }, 'Todos los planes'), ...planes.map((p) => el('option', { value: p.codigo }, p.nombre)));
  filtro.value = elegido;
  $('#lista-planes').replaceChildren(...planes.map(tarjetaPlan));
}

function tarjetaPlan(p) {
  return el('button', { type: 'button', class: `plan-tarjeta${p.activo ? '' : ' plan-tarjeta--inactivo'}`, onclick: () => abrirPlan(p) },
    el('div', { class: 'plan-tarjeta__cab' },
      el('h3', {}, p.nombre),
      el('span', { class: 'pildora', style: `--c: var(${p.activo ? '--entrada' : '--texto-suave'})` }, p.activo ? `${p.empresas} empresa${p.empresas === 1 ? '' : 's'}` : 'No disponible')),
    p.descripcion && el('p', {}, p.descripcion),
    el('dl', {},
      ...RECURSOS.map(([k, n]) => el('div', {}, el('dt', {}, n), el('dd', {}, limiteTxt(p[`max_${k}`]))))));
}

function abrirPlan(p) {
  estado.planEditado = p;
  const f = $('#form-plan');
  f.reset();
  $('#dlg-plan-titulo').textContent = p ? `Plan ${p.nombre}` : 'Nuevo plan';
  f.codigo.value = p?.codigo ?? '';
  f.codigo.disabled = Boolean(p);
  f.nombre.value = p?.nombre ?? '';
  f.descripcion.value = p?.descripcion ?? '';
  for (const [k] of RECURSOS) f[`max_${k}`].value = p?.[`max_${k}`] ?? '';
  f.orden.value = p?.orden ?? 10;
  $('#fila-plan-activo').hidden = !p;
  f.activo.checked = p?.activo ?? true;
  mostrarError('#plan-error');
  $('#dlg-plan').showModal();
}
$('#btn-nuevo-plan').addEventListener('click', () => abrirPlan(null));

cancelable($('#form-plan'), async (ev) => {
  const f = ev.currentTarget;
  const p = estado.planEditado;
  const cuerpo = {
    nombre: f.nombre.value,
    descripcion: f.descripcion.value,
    max_sedes: f.max_sedes.value || null,
    max_personas: f.max_personas.value || null,
    max_productos: f.max_productos.value || null,
    orden: Number(f.orden.value || 0),
  };
  if (!p) cuerpo.codigo = f.codigo.value;
  else cuerpo.activo = f.activo.checked;
  if (p && p.empresas > 0 && ['sedes', 'personas', 'productos'].some((k) => {
    const nuevo = cuerpo[`max_${k}`] == null ? null : Number(cuerpo[`max_${k}`]);
    return nuevo != null && (p[`max_${k}`] == null || nuevo < p[`max_${k}`]);
  }) && !confirm(`Vas a bajar límites de un plan que usan ${p.empresas} empresa(s). Lo que ya tienen se conserva, pero no podrán crear más por encima del nuevo límite. ¿Continuar?`)) return;
  const boton = $('button[type=submit]', f);
  boton.disabled = true;
  try {
    await api(p ? `/plataforma/planes/${p.id}` : '/plataforma/planes', { metodo: p ? 'PUT' : 'POST', cuerpo });
    $('#dlg-plan').close();
    avisar(p ? 'Plan actualizado' : 'Plan creado');
    await cargarPlanes();
    await cargarEmpresas();
  } catch (x) {
    mostrarError('#plan-error', x.message);
  } finally {
    boton.disabled = false;
  }
});

// ------------------------------------------------------------------ inicio

(async function iniciar() {
  let tema = 'dark';
  try { tema = localStorage.getItem('pf_tema') || 'dark'; } catch { /* sin almacenamiento */ }
  aplicarTema(tema);
  if (sesion()) {
    try {
      await entrar();
      return;
    } catch {
      /* la sesión ya no vale: se pide de nuevo */
    }
  }
  salir();
})();
