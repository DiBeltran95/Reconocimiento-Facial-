/* Control de Personal · Panel administrativo (sin dependencias). */
'use strict';

const API = new URL('../api', location.href).pathname.replace(/\/$/, '');
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

const estado = {
  token: null,
  usuario: null,
  sedes: [],
  sede: null,
  reporte: null,
  filtro: 'TODOS',
  empleados: [],
  empleadoEditado: null,
  turnos: [],
  turnoEditado: null,
  periodo: 'semana',
  usuarioEditado: null,
  rotacionPara: null, // empleado fijo al asignar desde su ficha
};

const PRESENCIA = {
  EN_SEDE: ['En la sede', '--entrada'],
  SALIO: ['Salió', '--salida'],
  SIN_SALIDA: ['Sin salida', '--alerta'],
  AUSENTE: ['Ausente', '--peligro'],
  LIBRE: ['Libre', '--texto-suave'],
};
const CUMPLIMIENTO = {
  CUMPLE: ['Cumple', '--entrada'],
  TARDE: ['Llegó tarde', '--alerta'],
  SIN_LLEGAR: ['Aún no llega', '--alerta'],
  SALIDA_ANTICIPADA: ['Salió antes', '--peligro'],
  SIN_SALIDA: ['Sin salida', '--alerta'],
  INCOMPLETO: ['Incompleto', '--peligro'],
  AUSENTE: ['No asistió', '--peligro'],
  PENDIENTE: ['Pendiente', '--texto-suave'],
  LIBRE: ['Libre', '--texto-suave'],
  EXTRA: ['Fuera de turno', '--salida'],
};
const COLORES_TURNO = ['--primario', '--salida', '--alerta', '--entrada', '--peligro', '--secundario'];
const colorTurno = (id) => `var(${COLORES_TURNO[id % COLORES_TURNO.length]})`;
const DIAS = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const DIAS_LARGOS = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

// ------------------------------------------------------------------ utilidades

function guardarSesion(token) {
  estado.token = token;
  try { token ? sessionStorage.setItem('cp_token', token) : sessionStorage.removeItem('cp_token'); } catch { /* modo privado */ }
}
function sesionGuardada() {
  try { return sessionStorage.getItem('cp_token'); } catch { return null; }
}
function localStorageSeguro(clave, valor) {
  try {
    if (valor === undefined) return localStorage.getItem(clave);
    localStorage.setItem(clave, valor);
  } catch { /* sin almacenamiento */ }
  return null;
}

async function api(ruta, { metodo = 'GET', cuerpo, formulario, crudo = false } = {}) {
  const cabeceras = { Accept: 'application/json' };
  if (estado.token) cabeceras.Authorization = `Bearer ${estado.token}`;
  if (cuerpo !== undefined) cabeceras['Content-Type'] = 'application/json';
  let r;
  try {
    r = await fetch(API + ruta, {
      method: metodo,
      headers: cabeceras,
      body: formulario ?? (cuerpo !== undefined ? JSON.stringify(cuerpo) : undefined),
    });
  } catch {
    throw Object.assign(new Error('Sin conexión con el servidor'), { status: 0 });
  }
  if (r.status === 401 && estado.token) {
    cerrarSesion('Tu sesión venció. Ingresa de nuevo.');
    throw Object.assign(new Error('Sesión vencida'), { status: 401 });
  }
  if (crudo && r.ok) return r;
  if (r.status === 204) return null;
  const datos = await r.json().catch(() => ({}));
  if (!r.ok) throw Object.assign(new Error(datos.error || `Error ${r.status}`), { status: r.status, campo: datos.campo });
  return datos;
}

function el(etiqueta, attrs = {}, ...hijos) {
  const n = document.createElement(etiqueta);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === 'class') n.className = v;
    else if (k === 'style') n.style.cssText = v;
    else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
    else if (k === 'value') n.value = v;
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

const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const hoyIso = () => iso(new Date());
const deIso = (s) => new Date(`${s}T12:00:00`);
const sumarDias = (s, d) => { const f = deIso(s); f.setDate(f.getDate() + d); return iso(f); };
const lunesDe = (s) => { const f = deIso(s); const n = (f.getDay() + 6) % 7; f.setDate(f.getDate() - n); return iso(f); };
const semanaTxt = (lunes) => {
  const a = deIso(lunes);
  const b = deIso(sumarDias(lunes, 6));
  const mes = (d) => d.toLocaleDateString('es-CO', { month: 'short' });
  return a.getMonth() === b.getMonth() ? `${a.getDate()} – ${b.getDate()} ${mes(b)}` : `${a.getDate()} ${mes(a)} – ${b.getDate()} ${mes(b)}`;
};
const horaCorta = (s) => (s ? new Date(s).toLocaleTimeString('es-CO', { hour: 'numeric', minute: '2-digit' }) : '—');
const horaLarga = (s) => new Date(s).toLocaleTimeString('es-CO', { hour: 'numeric', minute: '2-digit', second: '2-digit' });
const duracion = (m) => (m <= 0 ? '—' : m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')} min`);
const iniciales = (n) => n.trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join('').toUpperCase();
const bloquesTxt = (b) => b.split(',').map((x) => x.replace('-', '–')).join(' · ');
const aMin = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
const diasTxt = (m) => (m === 127 ? 'Todos los días' : m === 63 ? 'Lunes a sábado' : m === 31 ? 'Lunes a viernes' : DIAS.filter((_, i) => m & (1 << i)).join(' · '));

const cacheFotos = new Map();
async function urlFoto(empleadoId, foto) {
  const clave = `${empleadoId}/${foto.n}/${foto.v}`;
  if (!cacheFotos.has(clave)) {
    cacheFotos.set(clave, api(`/empleados/${empleadoId}/fotos/${foto.n}?v=${foto.v}`, { crudo: true })
      .then((r) => r.blob()).then((b) => URL.createObjectURL(b)).catch(() => null));
  }
  return cacheFotos.get(clave);
}

function avatar(nombre, empleado) {
  const a = el('div', { class: 'avatar', 'aria-hidden': 'true' }, iniciales(nombre));
  if (empleado?.fotos?.length) {
    urlFoto(empleado.id, empleado.fotos[0]).then((url) => { if (url) a.replaceChildren(el('img', { src: url, alt: '' })); });
  }
  return a;
}

function pildora(texto, colorVar, iconoId) {
  return el('span', { class: `pildora${iconoId ? ' pildora--icono' : ''}`, style: `--c:var(${colorVar})` }, iconoId ? icono(iconoId) : null, texto);
}

function etiquetaTurno(turno) {
  if (!turno) return el('span', { class: 'turno-txt' }, 'Sin turno');
  return el('span', { class: 'turno-txt', title: bloquesTxt(turno.bloques) },
    el('span', { class: 'punto-turno', style: `--c:${colorTurno(turno.id ?? 0)}` }), `${turno.nombre} · ${bloquesTxt(turno.bloques)}`);
}

/** Línea de tiempo 5:00 → 23:00 con los bloques de un turno. */
function barraTurno(bloques, color) {
  const desde = 5 * 60;
  const hasta = 23 * 60;
  const x = (m) => ((Math.min(Math.max(m, desde), hasta) - desde) / (hasta - desde)) * 100;
  const cont = el('div', { class: 'barra-turno', style: `--c:${color}`, role: 'img', 'aria-label': `Horario ${bloquesTxt(bloques)}` },
    el('div', { class: 'barra-turno__pista' }));
  for (const b of bloques.split(',').filter(Boolean)) {
    const [i, f] = b.split('-').map(aMin);
    cont.append(el('div', { class: 'barra-turno__bloque', style: `left:${x(i)}%;width:${x(f) - x(i)}%` }));
  }
  for (const h of [6, 9, 12, 15, 18, 21]) cont.append(el('span', { class: 'barra-turno__marca', style: `left:${x(h * 60)}%` }, h));
  return cont;
}

async function descargar(ruta, nombre) {
  try {
    const r = await api(ruta, { crudo: true });
    const url = URL.createObjectURL(await r.blob());
    const a = el('a', { href: url, download: nombre });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  } catch (e) {
    avisar(e.message, true);
  }
}

function mostrarError(id, mensaje) {
  const n = $(id);
  n.textContent = mensaje || '';
  n.hidden = !mensaje;
}

/** Cierra un diálogo de formulario al pulsar "Cancelar" sin validar. */
function cancelable(form, dlg, alEnviar) {
  form.addEventListener('submit', (ev) => {
    if (ev.submitter?.value === 'cancelar') return;
    ev.preventDefault();
    alEnviar(ev);
  });
  dlg.addEventListener('close', () => { dlg.returnValue = ''; });
}

// ------------------------------------------------------------------ sesión

async function iniciar() {
  aplicarTema(localStorageSeguro('cp_tema') || 'dark');
  try {
    const s = await api('/salud');
    if (s.negocio) {
      $('#login-negocio').textContent = s.negocio;
      $('#app-negocio').textContent = s.negocio;
      document.title = `Asistencia · ${s.negocio}`;
    }
  } catch { /* se mostrará al ingresar */ }

  const token = sesionGuardada();
  if (token) {
    estado.token = token;
    try {
      const yo = await api('/auth/yo');
      await entrarApp(yo.usuario);
      return;
    } catch { guardarSesion(null); }
  }
  mostrarLogin();
}

function mostrarLogin(mensaje) {
  $('#vista-app').hidden = true;
  $('#vista-login').hidden = false;
  mostrarError('#login-error', mensaje);
  $('#form-login [name=usuario]').focus();
}

function cerrarSesion(mensaje) {
  guardarSesion(null);
  estado.usuario = null;
  cacheFotos.forEach((p) => p.then((u) => u && URL.revokeObjectURL(u)));
  cacheFotos.clear();
  mostrarLogin(mensaje);
}

$('#form-login').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const f = ev.currentTarget;
  const boton = $('button[type=submit]', f);
  boton.disabled = true;
  mostrarError('#login-error');
  try {
    const r = await api('/auth/login', { metodo: 'POST', cuerpo: { usuario: f.usuario.value, password: f.password.value } });
    guardarSesion(r.token);
    f.password.value = '';
    await entrarApp(r.usuario);
  } catch (e) {
    mostrarLogin(e.message);
  } finally {
    boton.disabled = false;
  }
});

async function entrarApp(usuario) {
  if (usuario.rol !== 'ADMINISTRATIVO') {
    cerrarSesion('Tu cuenta es General: solo opera kioscos desde la app. El panel requiere una cuenta Administrativa.');
    return;
  }
  estado.usuario = usuario;
  $('#usuario-nombre').textContent = usuario.nombre;
  const { sedes } = await api('/sedes');
  estado.sedes = sedes;
  if (!sedes.length) {
    cerrarSesion('Tu usuario no tiene sedes asignadas.');
    return;
  }
  const guardada = Number(localStorageSeguro('cp_sede'));
  estado.sede = sedes.find((s) => s.id === guardada) || sedes[0];
  $('#sede').replaceChildren(...sedes.map((s) => el('option', { value: s.id, selected: s.id === estado.sede.id }, s.nombre)));
  $('#sede').closest('.selector-sede').hidden = sedes.length < 2;
  $('#vista-login').hidden = true;
  $('#vista-app').hidden = false;
  $('#fecha').value = hoyIso();
  $('#fecha').max = hoyIso();
  await cargarTurnos();
  cambiarVista('asistencia');
}

$('#btn-salir').addEventListener('click', () => cerrarSesion());
$('#sede').addEventListener('change', (ev) => {
  estado.sede = estado.sedes.find((s) => s.id === Number(ev.target.value));
  localStorageSeguro('cp_sede', String(estado.sede.id));
  recargarVista();
});

function aplicarTema(t) {
  document.documentElement.dataset.theme = t;
  localStorageSeguro('cp_tema', t);
}
$('#btn-tema').addEventListener('click', () => aplicarTema(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'));

// ------------------------------------------------------------------ navegación

let vistaActual = 'asistencia';
function cambiarVista(v) {
  vistaActual = v;
  $$('.pestanas [role=tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.vista === v)));
  $$('.vista').forEach((s) => { s.hidden = s.id !== `vista-${v}`; });
  recargarVista();
}
function recargarVista() {
  ({
    asistencia: cargarReporte,
    cumplimiento: cargarCumplimiento,
    personal: cargarPersonal,
    horarios: cargarTurnos,
    usuarios: cargarUsuarios,
    kioscos: cargarKioscos,
  })[vistaActual]();
}
$$('.pestanas [role=tab]').forEach((b) => b.addEventListener('click', () => cambiarVista(b.dataset.vista)));

// ------------------------------------------------------------------ asistencia del día

async function cargarReporte() {
  const fecha = $('#fecha').value || hoyIso();
  $('#fecha-etiqueta').textContent = fecha === hoyIso() ? 'Hoy' : 'Historial';
  $('#dia-siguiente').disabled = fecha >= hoyIso();
  try {
    estado.reporte = await api(`/reportes/dia?sede_id=${estado.sede.id}&fecha=${fecha}`);
    pintarReporte();
  } catch (e) {
    if (e.status !== 401) avisar(e.message, true);
  }
}

function kpi(etiqueta, valor, total, colorVar, iconoId) {
  return el('div', { class: 'kpi', style: `--c:var(${colorVar})` },
    el('p', { class: 'etiqueta kpi__etiqueta' }, icono(iconoId), etiqueta),
    el('p', { class: 'kpi__valor' }, valor),
    el('div', { class: 'kpi__barra' }, el('span', { style: `width:${Math.round((Number(valor) / Math.max(1, total)) * 100)}%` })));
}

function textoCumplimiento(c) {
  const [txt, color] = CUMPLIMIENTO[c.estado] || [c.estado, '--texto-suave'];
  let extra = '';
  if ((c.estado === 'TARDE' || c.estado === 'SIN_LLEGAR') && c.retraso_min > 0) extra = ` · ${duracion(c.retraso_min)}`;
  if (c.estado === 'SALIDA_ANTICIPADA' && c.anticipo_min > 0) extra = ` · ${duracion(c.anticipo_min)}`;
  return [txt + extra, color];
}

function pintarReporte() {
  const r = estado.reporte;
  const s = r.resumen;
  const conTurno = s.con_turno > 0;
  $('#kpis').replaceChildren(...(conTurno
    ? [
      kpi('En la sede', s.en_sede, s.total, '--primario', 'i-entrada'),
      kpi('Cumplen', s.cumplen, s.con_turno, '--entrada', 'i-check'),
      kpi('Llegaron tarde', s.tarde, s.con_turno, '--alerta', 'i-reloj'),
      kpi('Incumplen', s.incumplen, s.con_turno, '--peligro', 'i-alerta'),
    ]
    : [
      kpi('En la sede', s.en_sede, s.total, '--entrada', 'i-entrada'),
      kpi('Salieron', s.presentes - s.en_sede - s.sin_salida, s.total, '--salida', 'i-salir'),
      kpi('Ausentes', s.ausentes, s.total, '--alerta', 'i-rostro-no'),
      kpi('Total', s.total, s.total, '--primario', 'i-personas'),
    ]));

  const filtros = [
    ['TODOS', 'Todos', () => true],
    ['EN_SEDE', 'En la sede', (e) => e.estado === 'EN_SEDE'],
    ...(conTurno ? [
      ['TARDE', 'Tarde', (e) => ['TARDE', 'SIN_LLEGAR'].includes(e.cumplimiento.estado)],
      ['INCUMPLEN', 'Incumplen', (e) => ['SALIDA_ANTICIPADA', 'SIN_SALIDA', 'INCOMPLETO', 'AUSENTE'].includes(e.cumplimiento.estado)],
    ] : []),
    ['AUSENTE', 'Ausentes', (e) => e.estado === 'AUSENTE'],
    ['SALIO', 'Salieron', (e) => e.estado === 'SALIO'],
  ];
  if (!filtros.some(([k]) => k === estado.filtro)) estado.filtro = 'TODOS';
  const activo = filtros.find(([k]) => k === estado.filtro)[2];
  $('#chips-estado').replaceChildren(...filtros.map(([k, txt, fn]) => el('button', {
    class: 'chip', type: 'button', 'aria-pressed': String(estado.filtro === k),
    onclick: () => { estado.filtro = k; pintarReporte(); },
  }, `${txt} (${r.empleados.filter(fn).length})`)));

  const q = $('#buscar-asistencia').value.trim().toLowerCase();
  const filas = r.empleados.filter(activo).filter((e) => !q || e.nombre.toLowerCase().includes(q) || e.documento.toLowerCase().includes(q));
  const ahora = Date.now();
  $('#tabla-asistencia tbody').replaceChildren(...filas.map((e) => {
    const minutos = e.minutos + (e.abierta_desde ? Math.floor((ahora - new Date(e.abierta_desde)) / 60000) : 0);
    const [txt, color] = e.turno ? textoCumplimiento(e.cumplimiento) : PRESENCIA[e.estado];
    const alerta = e.alertas.includes('RELOJ_ADELANTADO');
    return el('tr', { tabindex: '0', onclick: () => detalle(e), onkeydown: (ev) => { if (ev.key === 'Enter') detalle(e); } },
      el('td', {}, el('div', { class: 'persona' }, avatar(e.nombre),
        el('div', {}, el('div', { class: 'persona__nombre' }, e.nombre), el('div', { class: 'persona__sub' }, [e.documento, e.cargo].filter(Boolean).join(' · '))))),
      el('td', { 'data-col': 'Turno' }, etiquetaTurno(e.turno)),
      el('td', { 'data-col': 'Entrada' }, el('span', { class: 'hora' }, horaCorta(e.entrada))),
      el('td', { 'data-col': 'Salida' }, el('span', { class: 'hora' }, horaCorta(e.salida))),
      el('td', { 'data-col': 'Tiempo' }, duracion(minutos)),
      el('td', {}, pildora(txt, color), alerta ? el('span', { title: 'Reloj del kiosco adelantado', style: 'color:var(--peligro);margin-left:6px' }, icono('i-alerta')) : null),
    );
  }));
  const vacio = $('#vacio-asistencia');
  vacio.hidden = filas.length > 0;
  vacio.replaceChildren(el('strong', {}, s.total === 0 ? 'Sin personal en esta sede' : 'Nada que mostrar'),
    s.total === 0 ? 'Agrega empleados en la pestaña Personal.' : 'Ningún empleado coincide con el filtro.');
}

const ESTADO_BLOQUE = {
  OK: ['Cumplido', '--entrada'], TARDE: ['Llegó tarde', '--alerta'], ANTICIPADA: ['Salió antes', '--peligro'],
  TARDE_ANTICIPADA: ['Tarde y salió antes', '--peligro'], FALTA: ['No se presentó', '--peligro'],
  SIN_LLEGAR: ['Aún no llega', '--alerta'], SIN_SALIDA: ['Sin salida', '--alerta'], EN_CURSO: ['En curso', '--primario'],
  PENDIENTE: ['Pendiente', '--texto-suave'],
};

function detalle(e) {
  $('#detalle-nombre').textContent = e.nombre;
  $('#detalle-sub').textContent = [e.documento, e.cargo, PRESENCIA[e.estado][0]].filter(Boolean).join(' · ');
  const turno = $('#detalle-turno');
  turno.replaceChildren();
  if (e.turno) {
    const [txt, color] = textoCumplimiento(e.cumplimiento);
    turno.append(
      el('p', { class: 'etiqueta' }, 'Turno del día'),
      el('p', {}, `${e.turno.nombre} · ${bloquesTxt(e.turno.bloques)} · tolerancia ${e.turno.tolerancia_min} min`),
      pildora(txt, color),
      el('div', { style: 'display:grid;gap:6px;margin:12px 0 20px' }, ...e.cumplimiento.bloques.map((b) => {
        const [t, c] = ESTADO_BLOQUE[b.estado] || [b.estado, '--texto-suave'];
        const extra = [b.llegada && `llegó ${b.llegada}`, b.salida && `salió ${b.salida}`,
          b.retraso_min > 0 && `+${b.retraso_min} min`, b.anticipo_min > 0 && `−${b.anticipo_min} min`].filter(Boolean).join(' · ');
        return el('div', { style: 'display:flex;gap:10px;align-items:center' },
          el('span', { class: 'mono', style: 'width:110px' }, `${b.inicio}–${b.fin}`), pildora(t, c), el('span', { class: 'suave', style: 'font-size:13px' }, extra));
      })));
  }
  const lista = e.marcaciones.length
    ? e.marcaciones.map((m) => {
      const entrada = m.tipo === 'ENTRADA';
      let nota = '';
      if (m.desfase_seg < -120) nota = `Reloj del kiosco adelantado ${Math.ceil(-m.desfase_seg / 60)} min`;
      else if (m.desfase_seg > 600) nota = `Enviada ${duracion(Math.floor(m.desfase_seg / 60))} después (sin conexión)`;
      return el('li', { style: `--c:var(${entrada ? '--entrada' : '--salida'})` },
        el('span', { class: 'punto' }, icono(entrada ? 'i-entrada' : 'i-salir')),
        el('div', {},
          el('p', { class: 'fila' }, el('span', {}, entrada ? 'Entrada' : 'Salida'), el('span', { class: 'hora' }, horaLarga(m.hora))),
          el('p', { class: 'suave' }, `Servidor: ${horaLarga(m.hora_servidor)}`),
          nota ? el('p', { style: `color:var(${m.desfase_seg < 0 ? '--peligro' : '--texto-suave'});font-weight:600;font-size:13px` }, nota) : null));
    })
    : [el('li', { class: 'suave', style: 'display:block' }, 'No registró marcaciones este día.')];
  $('#detalle-lista').replaceChildren(...lista);
  $('#dlg-detalle').showModal();
}
$('#dlg-detalle [data-cerrar]').addEventListener('click', () => $('#dlg-detalle').close());

$('#fecha').addEventListener('change', cargarReporte);
$('#dia-anterior').addEventListener('click', () => { $('#fecha').value = sumarDias($('#fecha').value || hoyIso(), -1); cargarReporte(); });
$('#dia-siguiente').addEventListener('click', () => {
  const s = sumarDias($('#fecha').value || hoyIso(), 1);
  if (s <= hoyIso()) { $('#fecha').value = s; cargarReporte(); }
});
$('#buscar-asistencia').addEventListener('input', () => estado.reporte && pintarReporte());
$('#btn-csv-dia').addEventListener('click', () => {
  const f = $('#fecha').value || hoyIso();
  descargar(`/reportes/dia.csv?sede_id=${estado.sede.id}&fecha=${f}`, `asistencia_${estado.sede.codigo}_${f}.csv`);
});
$('#btn-csv-rango').addEventListener('click', () => {
  const f = $('#form-rango');
  f.hasta.value = hoyIso();
  f.desde.value = sumarDias(hoyIso(), -14);
  f.desde.max = f.hasta.max = hoyIso();
  mostrarError('#rango-error');
  $('#dlg-rango').showModal();
});
cancelable($('#form-rango'), $('#dlg-rango'), async (ev) => {
  const f = ev.currentTarget;
  if (!f.desde.value || !f.hasta.value || f.hasta.value < f.desde.value) {
    mostrarError('#rango-error', 'Revisa las fechas: la final debe ser igual o posterior a la inicial.');
    return;
  }
  await descargar(`/reportes/rango.csv?sede_id=${estado.sede.id}&desde=${f.desde.value}&hasta=${f.hasta.value}`,
    `asistencia_${estado.sede.codigo}_${f.desde.value}_a_${f.hasta.value}.csv`);
  $('#dlg-rango').close();
});

setInterval(() => {
  if (estado.token && vistaActual === 'asistencia' && $('#fecha').value === hoyIso() && !document.hidden) cargarReporte();
}, 60000);

// ------------------------------------------------------------------ cumplimiento

const PERIODOS = {
  semana: ['Esta semana', () => [lunesDe(hoyIso()), hoyIso()]],
  pasada: ['Semana pasada', () => { const l = sumarDias(lunesDe(hoyIso()), -7); return [l, sumarDias(l, 6)]; }],
  quincena: ['Últimos 15 días', () => [sumarDias(hoyIso(), -14), hoyIso()]],
  mes: ['Este mes', () => [`${hoyIso().slice(0, 8)}01`, hoyIso()]],
};

function pintarPeriodos() {
  $('#chips-periodo').replaceChildren(...Object.entries(PERIODOS).map(([k, [txt, rango]]) => el('button', {
    class: 'chip', type: 'button', 'aria-pressed': String(estado.periodo === k),
    onclick: () => {
      estado.periodo = k;
      const [d, h] = rango();
      $('#cump-desde').value = d;
      $('#cump-hasta').value = h;
      cargarCumplimiento();
    },
  }, txt)));
}

async function cargarCumplimiento() {
  if (!$('#cump-desde').value) {
    const [d, h] = PERIODOS[estado.periodo][1]();
    $('#cump-desde').value = d;
    $('#cump-hasta').value = h;
  }
  $('#cump-desde').max = $('#cump-hasta').max = hoyIso();
  pintarPeriodos();
  try {
    const r = await api(`/reportes/cumplimiento?sede_id=${estado.sede.id}&desde=${$('#cump-desde').value}&hasta=${$('#cump-hasta').value}`);
    pintarCumplimiento(r);
  } catch (e) {
    if (e.status !== 401) avisar(e.message, true);
  }
}
['#cump-desde', '#cump-hasta'].forEach((id) => $(id).addEventListener('change', () => { estado.periodo = ''; cargarCumplimiento(); }));
$('#btn-csv-cump').addEventListener('click', () => {
  const d = $('#cump-desde').value;
  const h = $('#cump-hasta').value;
  descargar(`/reportes/cumplimiento.csv?sede_id=${estado.sede.id}&desde=${d}&hasta=${h}`, `cumplimiento_${estado.sede.codigo}_${d}_a_${h}.csv`);
});

const colorPct = (p) => (p == null ? '--texto-suave' : p >= 90 ? '--entrada' : p >= 75 ? '--alerta' : '--peligro');
const colorDia = (e) => (CUMPLIMIENTO[e]?.[1] ?? '--borde');

function pintarCumplimiento(r) {
  const s = r.resumen;
  const p = s.porcentaje;
  $('#cump-resumen').replaceChildren(
    el('div', { class: 'anillo' },
      el('div', { class: 'anillo__envoltura', role: 'img', 'aria-label': `Cumplimiento general ${p ?? 0} %` },
        el('div', { class: 'anillo__circulo', style: `--p:${p ?? 0};--c:var(${colorPct(p)})` }),
        el('span', { class: 'anillo__valor' }, p == null ? '—' : `${p}%`)),
      el('p', { class: 'suave', style: 'margin:8px 0 0;text-align:center;font-size:13px' }, `${s.dias_cumplidos} de ${s.dias_programados} jornadas cumplidas`)),
    kpi('Tardanzas', s.tardanzas, s.dias_programados, '--alerta', 'i-reloj'),
    kpi('Ausencias', s.ausencias, s.dias_programados, '--peligro', 'i-rostro-no'),
    kpi('Salidas antes', s.salidas_anticipadas, s.dias_programados, '--salida', 'i-salir'),
    kpi('Cumplidas', s.dias_cumplidos, s.dias_programados, '--entrada', 'i-check'),
  );
  $('#cump-leyenda').replaceChildren(...[['Cumple', '--entrada'], ['Tarde / sin salida', '--alerta'], ['Falta / salió antes', '--peligro'], ['Libre / pendiente', '--borde']]
    .map(([t, c]) => el('span', {}, el('span', { class: `punto${c === '--borde' ? ' punto--vacio' : ''}`, style: `--c:var(${c})` }), t)));

  const filas = r.empleados.filter((e) => e.dias_programados > 0).sort((a, b) => (a.porcentaje ?? 101) - (b.porcentaje ?? 101));
  $('#tabla-cumplimiento tbody').replaceChildren(...filas.map((e) => el('tr', {},
    el('td', {}, el('div', { class: 'persona' }, avatar(e.nombre),
      el('div', {}, el('div', { class: 'persona__nombre' }, e.nombre), el('div', { class: 'persona__sub' }, [e.documento, e.cargo].filter(Boolean).join(' · '))))),
    el('td', { 'data-col': '%' }, el('span', { class: 'porcentaje', style: `--c:var(${colorPct(e.porcentaje)})` }, e.porcentaje == null ? '—' : `${e.porcentaje}%`)),
    el('td', { 'data-col': 'Días' }, `${e.dias_cumplidos}/${e.dias_programados}`),
    el('td', { 'data-col': 'Tardanzas' }, e.tardanzas ? `${e.tardanzas} · ${duracion(e.minutos_tarde)}` : '—'),
    el('td', { 'data-col': 'Ausencias' }, e.ausencias || '—'),
    el('td', { 'data-col': 'Salidas antes' }, e.salidas_anticipadas ? `${e.salidas_anticipadas} · ${duracion(e.minutos_anticipados)}` : '—'),
    el('td', {}, el('div', { class: 'puntos' }, ...e.dias.map((d) => el('span', {
      class: `punto${!d.estado || d.estado === 'LIBRE' || d.estado === 'PENDIENTE' ? ' punto--vacio' : ''}`,
      style: `--c:var(${colorDia(d.estado)})`,
      title: `${deIso(d.fecha).toLocaleDateString('es-CO', { weekday: 'short', day: 'numeric' })}: ${CUMPLIMIENTO[d.estado]?.[0] ?? '—'}`,
    })))),
  )));
  const vacio = $('#vacio-cumplimiento');
  vacio.hidden = filas.length > 0;
  vacio.replaceChildren(el('strong', {}, 'Nadie tiene horario en este período'), 'Asigna rotaciones en la pestaña Horarios para medir el cumplimiento.');
}

// ------------------------------------------------------------------ personal

async function cargarPersonal() {
  try {
    const { empleados } = await api(`/empleados?sede_id=${estado.sede.id}`);
    estado.empleados = empleados;
    pintarPersonal();
  } catch (e) {
    if (e.status !== 401) avisar(e.message, true);
  }
}

function pintarPersonal() {
  const q = $('#buscar-personal').value.trim().toLowerCase();
  const lista = estado.empleados.filter((e) => !q || [e.nombre, e.documento, e.cargo || ''].some((t) => t.toLowerCase().includes(q)));
  $('#lista-personal').replaceChildren(...lista.map((e) => el('button', { class: 'tarjeta-emp', type: 'button', onclick: () => abrirEmpleado(e) },
    avatar(e.nombre, e),
    el('div', { class: 'tarjeta-emp__info' },
      el('p', { class: 'tarjeta-emp__nombre' }, e.nombre),
      el('p', { class: 'suave' }, [e.documento, e.cargo].filter(Boolean).join(' · ')),
      el('p', {}, etiquetaTurno(e.turno_semana)),
      el('p', { style: 'margin-top:6px' }, e.fotos.length ? pildora('Rostro', '--entrada', 'i-check') : pildora('Sin rostro', '--alerta', 'i-rostro-no'))),
  )));
  const vacio = $('#vacio-personal');
  vacio.hidden = lista.length > 0;
  vacio.replaceChildren(el('strong', {}, estado.empleados.length ? 'Sin resultados' : 'Aún no hay personal'),
    estado.empleados.length ? 'Prueba con otra búsqueda.' : 'Agrega al primer empleado con el botón «Nuevo empleado».');
}
$('#buscar-personal').addEventListener('input', pintarPersonal);
$('#btn-nuevo').addEventListener('click', () => abrirEmpleado(null));

function abrirEmpleado(e) {
  estado.empleadoEditado = e;
  const f = $('#form-empleado');
  f.reset();
  $('#dlg-empleado-titulo').textContent = e ? 'Editar empleado' : 'Nuevo empleado';
  f.sede_id.replaceChildren(...estado.sedes.map((s) => el('option', { value: s.id }, s.nombre)));
  f.documento.value = e?.documento || '';
  f.nombre.value = e?.nombre || '';
  f.cargo.value = e?.cargo || '';
  f.sede_id.value = String(e?.sede_id || estado.sede.id);
  $('#btn-baja').hidden = !e;
  $('#bloque-horario').hidden = !e;
  mostrarError('#empleado-error');
  $('#miniaturas').replaceChildren();
  (e?.fotos || []).forEach(async (foto) => {
    const url = await urlFoto(e.id, foto);
    if (url) $('#miniaturas').append(el('img', { src: url, alt: `Foto ${foto.n} del rostro` }));
  });
  if (e) cargarPlan(e);
  $('#dlg-empleado').showModal();
}

/** Próximas semanas del empleado; cada una se puede cambiar puntualmente. */
async function cargarPlan(e) {
  const cont = $('#plan-empleado');
  cont.replaceChildren(el('p', { class: 'suave' }, 'Cargando horario…'));
  try {
    const plan = await api(`/empleados/${e.id}/horario?semanas=6`);
    const rot = plan.rotacion;
    const nombre = (id) => estado.turnos.find((t) => t.id === id)?.nombre ?? `Turno ${id}`;
    cont.replaceChildren(
      el('p', {}, rot && rot.secuencia.length
        ? `Rota cada semana: ${rot.secuencia.map(nombre).join(' → ')} · desde ${semanaTxt(rot.desde)}`
        : 'Sin horario asignado: no se evalúa su cumplimiento.'),
      el('div', { class: 'plan' }, ...plan.semanas.map((s) => {
        const sel = el('select', { 'aria-label': `Turno de la semana ${semanaTxt(s.semana)}` },
          el('option', { value: '' }, s.ajustada ? 'Volver a la rotación' : 'Según rotación'),
          el('option', { value: '0' }, 'Sin turno (descanso / vacaciones)'),
          ...estado.turnos.filter((t) => t.activo).map((t) => el('option', { value: t.id }, `Solo esta semana: ${t.nombre}`)));
        sel.addEventListener('change', async () => {
          try {
            await api(`/empleados/${e.id}/semana`, {
              metodo: 'PUT',
              cuerpo: sel.value === '' ? { semana: s.semana, quitar: true } : { semana: s.semana, horario_id: sel.value === '0' ? null : Number(sel.value) },
            });
            avisar('Semana actualizada');
            cargarPlan(e);
          } catch (x) { avisar(x.message, true); }
        });
        return el('div', { class: 'plan__fila' },
          el('span', { class: 'mono' }, s.semana === lunesDe(hoyIso()) ? `Esta · ${semanaTxt(s.semana)}` : semanaTxt(s.semana)),
          el('span', {}, s.horario ? etiquetaTurno(s.horario) : el('span', { class: 'turno-txt' }, s.ajustada ? 'Sin turno (ajustada)' : 'Sin turno'),
            s.ajustada ? el('span', { style: 'color:var(--alerta);margin-left:6px', title: 'Semana ajustada' }, '●') : null),
          sel);
      })));
    $('#btn-rotacion-empleado').onclick = () => abrirRotacion(e, rot?.secuencia ?? []);
  } catch (x) {
    cont.replaceChildren(el('p', { class: 'error' }, x.message));
  }
}

cancelable($('#form-empleado'), $('#dlg-empleado'), async (ev) => {
  const f = ev.currentTarget;
  mostrarError('#empleado-error');
  const archivos = [...f.fotos.files];
  if (archivos.length > 3) return mostrarError('#empleado-error', 'Selecciona máximo 3 fotos.');
  if (archivos.length && !f.consentimiento.checked) return mostrarError('#empleado-error', 'Confirma la autorización de datos biométricos para subir fotos.');
  if (!f.documento.value.trim() || !f.nombre.value.trim()) return mostrarError('#empleado-error', 'Documento y nombre son obligatorios.');
  const boton = $('#btn-guardar-empleado');
  boton.disabled = true;
  try {
    const datos = { documento: f.documento.value, nombre: f.nombre.value, cargo: f.cargo.value || null, sede_id: Number(f.sede_id.value) };
    const e = estado.empleadoEditado;
    const r = e ? await api(`/empleados/${e.id}`, { metodo: 'PUT', cuerpo: datos }) : await api('/empleados', { metodo: 'POST', cuerpo: datos });
    if (archivos.length) {
      const fd = new FormData();
      archivos.forEach((a) => fd.append('fotos[]', a));
      await api(`/empleados/${r.empleado.id}/fotos`, { metodo: 'POST', formulario: fd });
    }
    $('#dlg-empleado').close();
    avisar(e ? 'Cambios guardados' : r.reactivado ? 'Empleado reactivado' : 'Empleado creado · asígnale un horario');
    cargarPersonal();
  } catch (x) {
    mostrarError('#empleado-error', x.message);
  } finally {
    boton.disabled = false;
  }
  return null;
});

$('#btn-baja').addEventListener('click', async () => {
  const e = estado.empleadoEditado;
  if (!e || !confirm(`¿Dar de baja a ${e.nombre}? Conserva su historial, pero ya no podrá marcar y sus fotos se eliminan.`)) return;
  try {
    await api(`/empleados/${e.id}`, { metodo: 'DELETE' });
    $('#dlg-empleado').close();
    avisar('Empleado dado de baja');
    cargarPersonal();
  } catch (x) {
    avisar(x.message, true);
  }
});

// ------------------------------------------------------------------ turnos

async function cargarTurnos() {
  try {
    const { horarios } = await api('/horarios');
    estado.turnos = horarios;
    if (vistaActual === 'horarios') pintarTurnos();
  } catch (e) {
    if (e.status !== 401) avisar(e.message, true);
  }
}

function pintarTurnos() {
  $('#lista-turnos').replaceChildren(...estado.turnos.map((t) => el('button', {
    class: 'tarjeta-turno', type: 'button', style: `--c:${colorTurno(t.id)}`, onclick: () => abrirTurno(t),
  },
  el('div', { class: 'tarjeta-turno__cab' }, el('strong', {}, t.nombre), el('span', { class: 'mono', style: `color:${colorTurno(t.id)}` }, duracion(t.minutos_dia))),
  el('span', { class: 'mono' }, bloquesTxt(t.bloques)),
  barraTurno(t.bloques, colorTurno(t.id)),
  el('span', { class: 'suave', style: 'font-size:13px' }, `${diasTxt(t.dias)} · tolerancia ${t.tolerancia_min} min`))));
  const vacio = $('#vacio-turnos');
  vacio.hidden = estado.turnos.length > 0;
  vacio.replaceChildren(el('strong', {}, 'Crea tu primer turno'), 'Ejemplo: «Turno A» de 08:30 a 12:00 y de 14:00 a 18:00, lunes a sábado.');
}

function filaBloque(inicio = '08:00', fin = '12:00') {
  const fila = el('div', { class: 'bloque' },
    el('span', { class: 'num' }),
    el('input', { type: 'time', value: inicio, 'aria-label': 'Desde', required: true, oninput: previaTurno }),
    el('span', {}, '→'),
    el('input', { type: 'time', value: fin, 'aria-label': 'Hasta', required: true, oninput: previaTurno }),
    el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Quitar bloque', onclick: () => { fila.remove(); numerarBloques(); previaTurno(); } }, icono('i-x')));
  return fila;
}
function numerarBloques() {
  $$('#bloques-turno .bloque').forEach((b, i) => { $('.num', b).textContent = i + 1; });
  $('#btn-agregar-bloque').hidden = $$('#bloques-turno .bloque').length >= 4;
}
function bloquesDelFormulario() {
  return $$('#bloques-turno .bloque').map((b) => $$('input', b).map((i) => i.value)).filter(([a, b]) => a && b).map(([a, b]) => `${a}-${b}`)
    .sort().join(',');
}
function previaTurno() {
  $('#vista-turno').replaceChildren(...barraTurno(bloquesDelFormulario() || '', colorTurno(estado.turnoEditado?.id ?? 0)).childNodes);
}

function abrirTurno(t) {
  estado.turnoEditado = t;
  const f = $('#form-turno');
  f.reset();
  $('#dlg-turno-titulo').textContent = t ? 'Editar turno' : 'Nuevo turno';
  f.nombre.value = t?.nombre ?? '';
  f.tolerancia_min.value = t?.tolerancia_min ?? 10;
  $('#bloques-turno').replaceChildren(...(t ? t.bloques.split(',') : ['08:30-12:00', '14:00-18:00']).map((b) => filaBloque(...b.split('-'))));
  numerarBloques();
  const mascara = t?.dias ?? 63;
  $('#dias-turno').replaceChildren(el('legend', {}, 'Días que aplica'), ...DIAS.map((d, i) => el('label', { title: DIAS_LARGOS[i] },
    el('input', { type: 'checkbox', value: i, checked: Boolean(mascara & (1 << i)), 'aria-label': DIAS_LARGOS[i] }), el('span', {}, d))));
  $('#btn-archivar-turno').hidden = !t;
  mostrarError('#turno-error');
  previaTurno();
  $('#dlg-turno').showModal();
}
$('#btn-nuevo-turno').addEventListener('click', () => abrirTurno(null));
$('#btn-agregar-bloque').addEventListener('click', () => { $('#bloques-turno').append(filaBloque('14:00', '18:00')); numerarBloques(); previaTurno(); });

cancelable($('#form-turno'), $('#dlg-turno'), async (ev) => {
  const f = ev.currentTarget;
  const dias = $$('#dias-turno input:checked').reduce((m, i) => m | (1 << Number(i.value)), 0);
  const bloques = bloquesDelFormulario();
  if (!f.nombre.value.trim()) return mostrarError('#turno-error', 'Ponle un nombre al turno.');
  if (!bloques) return mostrarError('#turno-error', 'Agrega al menos un bloque.');
  if (!dias) return mostrarError('#turno-error', 'Selecciona al menos un día.');
  try {
    const cuerpo = { nombre: f.nombre.value, bloques, dias, tolerancia_min: Number(f.tolerancia_min.value || 0) };
    const t = estado.turnoEditado;
    await api(t ? `/horarios/${t.id}` : '/horarios', { metodo: t ? 'PUT' : 'POST', cuerpo });
    $('#dlg-turno').close();
    avisar(t ? 'Turno actualizado' : 'Turno creado');
    await cargarTurnos();
    pintarTurnos();
  } catch (x) {
    mostrarError('#turno-error', x.message);
  }
  return null;
});

$('#btn-archivar-turno').addEventListener('click', async () => {
  const t = estado.turnoEditado;
  if (!t || !confirm(`¿Archivar «${t.nombre}»? Quienes lo tengan en su rotación lo conservan; no aparecerá en nuevas asignaciones.`)) return;
  try {
    await api(`/horarios/${t.id}`, { metodo: 'DELETE' });
    $('#dlg-turno').close();
    await cargarTurnos();
    pintarTurnos();
  } catch (x) { avisar(x.message, true); }
});

// ------------------------------------------------------------------ rotación

function filaSecuencia(id) {
  const li = el('li', {},
    el('span', { class: 'num' }),
    el('select', { 'aria-label': 'Turno de esta semana', onchange: previaRotacion },
      ...estado.turnos.filter((t) => t.activo).map((t) => el('option', { value: t.id, selected: t.id === id }, `${t.nombre} · ${bloquesTxt(t.bloques)}`))),
    el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Subir', onclick: () => { li.previousElementSibling?.before(li); numerarSecuencia(); } }, icono('i-arriba')),
    el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Bajar', onclick: () => { li.nextElementSibling?.after(li); numerarSecuencia(); } }, icono('i-abajo')),
    el('button', { class: 'btn-icono', type: 'button', 'aria-label': 'Quitar', onclick: () => { li.remove(); numerarSecuencia(); } }, icono('i-x')));
  return li;
}
function numerarSecuencia() {
  $$('#secuencia li').forEach((li, i) => { $('.num', li).textContent = `S${i + 1}`; });
  $('#btn-agregar-semana').hidden = $$('#secuencia li').length >= 8;
  previaRotacion();
}
const secuenciaActual = () => $$('#secuencia select').map((s) => Number(s.value));

function previaRotacion() {
  const f = $('#form-rotacion');
  const desde = f.desde.value ? lunesDe(f.desde.value) : lunesDe(hoyIso());
  $('#rotacion-semana').textContent = `Empieza la semana del ${semanaTxt(desde)} (lunes)`;
  const sec = secuenciaActual();
  $('#rotacion-previa').replaceChildren(...(sec.length ? [el('p', { class: 'etiqueta' }, 'Así quedarán las próximas semanas'),
    ...Array.from({ length: 6 }, (_, i) => {
      const t = estado.turnos.find((x) => x.id === sec[i % sec.length]);
      return el('div', {}, el('span', { class: 'mono' }, semanaTxt(sumarDias(desde, 7 * i))), etiquetaTurno(t));
    })] : []));
}

async function abrirRotacion(empleado = null, secuencia = []) {
  if (!estado.turnos.filter((t) => t.activo).length) {
    avisar('Primero crea al menos un turno', true);
    return;
  }
  estado.rotacionPara = empleado;
  const f = $('#form-rotacion');
  f.reset();
  f.desde.value = lunesDe(hoyIso());
  $('#dlg-rotacion-titulo').textContent = empleado ? `Rotación de ${empleado.nombre}` : 'Asignar rotación';
  $('#secuencia').replaceChildren(...(secuencia.length ? secuencia : [estado.turnos.find((t) => t.activo).id]).map(filaSecuencia));
  numerarSecuencia();
  mostrarError('#rotacion-error');
  $('#bloque-personal-rotacion').hidden = Boolean(empleado);
  if (!empleado) {
    if (!estado.empleados.length) {
      try { estado.empleados = (await api(`/empleados?sede_id=${estado.sede.id}`)).empleados; } catch { /* se informa abajo */ }
    }
    $('#rot-todos').checked = false;
    $('#rotacion-personal').replaceChildren(...estado.empleados.map((e) => el('label', { class: 'check' },
      el('input', { type: 'checkbox', value: e.id }),
      el('span', {}, e.nombre, el('span', { class: 'suave' }, ` · ${e.turno_semana ? `esta semana: ${e.turno_semana.nombre}` : 'sin horario'}`)))));
  }
  $('#btn-guardar-rotacion').textContent = empleado ? 'Guardar rotación' : 'Asignar';
  $('#dlg-rotacion').showModal();
}
$('#btn-asignar').addEventListener('click', () => abrirRotacion());
$('#btn-agregar-semana').addEventListener('click', () => { $('#secuencia').append(filaSecuencia(estado.turnos.find((t) => t.activo)?.id)); numerarSecuencia(); });
$('#form-rotacion').desde.addEventListener('change', previaRotacion);
$('#rot-todos').addEventListener('change', (ev) => $$('#rotacion-personal input').forEach((i) => { i.checked = ev.target.checked; }));

cancelable($('#form-rotacion'), $('#dlg-rotacion'), async (ev) => {
  const f = ev.currentTarget;
  const secuencia = secuenciaActual();
  const empleados = estado.rotacionPara ? [estado.rotacionPara.id] : $$('#rotacion-personal input:checked').map((i) => Number(i.value));
  if (!secuencia.length) return mostrarError('#rotacion-error', 'Agrega al menos un turno a la secuencia.');
  if (!empleados.length) return mostrarError('#rotacion-error', 'Selecciona al menos un empleado.');
  try {
    await api('/horarios/asignar', { metodo: 'POST', cuerpo: { empleados, secuencia, desde: lunesDe(f.desde.value || hoyIso()) } });
    $('#dlg-rotacion').close();
    avisar(empleados.length > 1 ? `Rotación asignada a ${empleados.length} personas` : 'Rotación guardada');
    if (estado.rotacionPara && $('#dlg-empleado').open) cargarPlan(estado.rotacionPara);
    estado.empleados = [];
    if (vistaActual === 'personal') cargarPersonal();
  } catch (x) {
    mostrarError('#rotacion-error', x.message);
  }
  return null;
});

// ------------------------------------------------------------------ usuarios

async function cargarUsuarios() {
  try {
    const { usuarios } = await api('/usuarios');
    $('#lista-usuarios').replaceChildren(...(usuarios.length ? usuarios.map((u) => el('div', { class: 'kiosco' },
      avatar(u.nombre),
      el('div', { class: 'kiosco__info' },
        el('p', { style: 'font-weight:700' }, u.nombre),
        el('p', { class: 'suave' }, `@${u.usuario}${u.activo ? '' : ' · inactivo'}`)),
      u.rol === 'ADMINISTRATIVO' ? pildora('Administrativo', '--primario', 'i-escudo') : pildora('General', '--salida', 'i-movil'),
      el('button', { class: 'btn btn--fantasma', type: 'button', onclick: () => abrirUsuario(u) }, 'Editar'),
    )) : [el('div', { class: 'vacio' }, el('strong', {}, 'Aún no hay cuentas propias'), 'Crea una cuenta General para operar los kioscos de las sedes.')]));
  } catch (e) {
    if (e.status !== 401) avisar(e.message, true);
  }
}

function abrirUsuario(u) {
  estado.usuarioEditado = u;
  const f = $('#form-usuario');
  f.reset();
  $('#dlg-usuario-titulo').textContent = u ? 'Editar usuario' : 'Nuevo usuario';
  f.nombre.value = u?.nombre ?? '';
  f.usuario.value = u?.usuario ?? '';
  f.usuario.disabled = Boolean(u);
  $$('input[name=rol]', f).forEach((r) => { r.checked = r.value === (u?.rol ?? 'GENERAL'); });
  $('#etq-clave').textContent = u ? 'Nueva contraseña (opcional)' : 'Contraseña';
  $('#fila-activo').hidden = !u;
  f.activo.checked = u?.activo ?? true;
  mostrarError('#usuario-error');
  $('#dlg-usuario').showModal();
}
$('#btn-nuevo-usuario').addEventListener('click', () => abrirUsuario(null));

cancelable($('#form-usuario'), $('#dlg-usuario'), async (ev) => {
  const f = ev.currentTarget;
  const u = estado.usuarioEditado;
  const cuerpo = { nombre: f.nombre.value, rol: $('input[name=rol]:checked', f).value };
  if (!u) cuerpo.usuario = f.usuario.value;
  if (f.password.value) cuerpo.password = f.password.value;
  if (u) cuerpo.activo = f.activo.checked;
  if (!u && f.password.value.length < 8) return mostrarError('#usuario-error', 'La contraseña debe tener al menos 8 caracteres.');
  try {
    await api(u ? `/usuarios/${u.id}` : '/usuarios', { metodo: u ? 'PUT' : 'POST', cuerpo });
    $('#dlg-usuario').close();
    avisar(u ? 'Cambios guardados' : 'Usuario creado');
    cargarUsuarios();
  } catch (x) {
    mostrarError('#usuario-error', x.message);
  }
  return null;
});

// ------------------------------------------------------------------ kioscos

async function cargarKioscos() {
  try {
    const { dispositivos } = await api('/dispositivos');
    $('#lista-kioscos').replaceChildren(...(dispositivos.length ? dispositivos.map((d) => {
      const min = d.ultimo_sync ? (Date.now() - new Date(d.ultimo_sync)) / 60000 : Infinity;
      const salud = min < 15 ? ['En línea', '--entrada'] : min < 24 * 60 ? ['Inactivo', '--alerta'] : ['Sin señal', '--peligro'];
      return el('div', { class: 'kiosco' },
        el('div', { class: 'kiosco__icono' }, icono('i-movil')),
        el('div', { class: 'kiosco__info' },
          el('p', { style: 'font-weight:700' }, d.nombre),
          el('p', { class: 'suave' }, `${d.sede} · última conexión: ${d.ultimo_sync ? new Date(d.ultimo_sync).toLocaleString('es-CO') : 'nunca'}`)),
        pildora(salud[0], salud[1]),
        el('button', { class: 'btn btn--peligro', type: 'button', onclick: () => revocar(d) }, 'Desvincular'));
    }) : [el('div', { class: 'vacio' }, el('strong', {}, 'No hay kioscos vinculados'), 'Instala la app en un teléfono y vincúlalo a la sede.')]));
  } catch (e) {
    if (e.status !== 401) avisar(e.message, true);
  }
}

async function revocar(d) {
  if (!confirm(`¿Desvincular «${d.nombre}»? El teléfono dejará de poder registrar marcaciones.`)) return;
  try {
    await api(`/dispositivos/${d.id}`, { metodo: 'DELETE' });
    avisar('Kiosco desvinculado');
    cargarKioscos();
  } catch (e) {
    avisar(e.message, true);
  }
}

iniciar();
