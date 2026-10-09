# Control de Personal · Reconocimiento facial

Control de ingreso y salida del personal por sede. El empleado llega, mira el
teléfono (kiosco) y queda registrado. El reconocimiento facial corre **en el
teléfono**; el servidor PHP solo guarda identidades, fotos y las marcaciones.

```
┌──────────────── Teléfono / tablet (Flutter) ─────────────────┐        ┌────── Servidor (PHP 8.1+) ──────┐
│ Cámara → ML Kit (detección + malla) → alineación ArcFace     │  HTTPS │ API REST ligera (sin framework)  │
│ → MobileFaceNet (TFLite, en isolate) → vector 128/192        │◄──────►│ Fotos en disco PRIVADO           │
│ → comparación local (coseno) → prueba de vida (parpadeo)     │  ETag  │ MariaDB: solo identidad, turnos  │
│ SQLite local: empleados, rostros, cola offline de marcas     │  304   │ y marcaciones (≈31 bytes c/u)    │
└──────────────────────────────────────────────────────────────┘        └──────────────────────────────────┘
```

## Estructura

| Carpeta | Contenido |
|---|---|
| `database/001_asistencia.sql` | Migración: 7 tablas `asis_*` + 1 vista. **No modifica ninguna tabla existente.** |
| `backend/` | API PHP + panel web administrativo (`/panel/`). |
| `app/` | App Flutter (kiosco + panel de operador + panel administrativo). |

## 1. Base de datos

Ejecuta `database/001_asistencia.sql` una sola vez sobre `inventarios_db` (phpMyAdmin → SQL).

| Tabla | Para qué | Tamaño |
|---|---|---|
| `asis_empleados` | Documento, nombre, cargo, sede, activo | ~100 B por persona |
| `asis_marcaciones` | Empleado, sede, tipo, **hora del dispositivo** y **hora del servidor** (UTC) | ~31 B por marca (≈23 MB/año con 1.000 personas) |
| `asis_dispositivos` | Kioscos por sede (solo el SHA-256 del token) | mínimo |
| `asis_usuarios` | Cuentas **General** y **Administrativo** | mínimo |
| `asis_horarios` | Turnos: bloques (`08:30-12:00,14:00-18:00`), días, tolerancia | mínimo |
| `asis_rotaciones` | Rotación semanal por empleado (`desde` + secuencia `A,B`) | 1 fila por cambio |
| `asis_semanas` | Ajuste de UNA semana (reemplazo, vacaciones) | solo excepciones |

De las tablas existentes solo se **leen** `sedes`, `usuarios`, `usuario_sedes` y
`configuracion` (zona horaria y nombre del negocio). Las fotos **nunca** van a la BD.

## 2. Backend (alwaysdata u otro hosting PHP)

Requisitos: PHP 8.1+ con `pdo_mysql` (y recomendado `gd`, `exif`, `sodium`). Sin Composer.

1. Sube la carpeta `backend/` completa.
2. Apunta el *document root* del sitio a `backend/public` (en alwaysdata: Web → Sitios → Raíz).
   Si no puedes, los `.htaccess` incluidos bloquean `src/`, `config/`, `bin/` y `storage/`.
3. Copia `config/config.example.php` como `config/config.php` y completa la conexión
   y un `jwt_secret` aleatorio: `php -r "echo bin2hex(random_bytes(32));"`
4. Da permiso de escritura a `storage/` (fotos y control de intentos de acceso).
5. Usa **HTTPS** (la app rechaza HTTP plano).
6. Primera cuenta: entra con un usuario **ADMIN/GERENTE** del sistema de inventarios
   (funciona como Administrativo) o créala por consola:
   ```bash
   php bin/crear_usuario.php admin "Nombre Apellido" ADMINISTRATIVO
   ```

Panel web: `https://tu-dominio/panel/` (solo cuentas Administrativas).

### API

| Método y ruta | Quién | Para qué |
|---|---|---|
| `GET /api/salud` | público | Hora del servidor (los kioscos miden el desfase de su reloj) |
| `POST /api/auth/login` | público | `{usuario, password}` → JWT (12 h) |
| `GET /api/sedes` · `POST /api/dispositivos` | General / Administrativo | Vincular un kiosco a una sede |
| `GET/POST/PUT/DELETE /api/empleados…` | Administrativo | Personal y fotos del rostro |
| `GET/POST/PUT/DELETE /api/horarios…` · `POST /api/horarios/asignar` | Administrativo | Turnos y rotación masiva |
| `GET /api/empleados/{id}/horario` · `PUT …/rotacion` · `PUT …/semana` | Administrativo | Plan semanal de una persona |
| `GET /api/reportes/dia` (`.csv`) · `/rango.csv` · `/cumplimiento` (`.csv`) | Administrativo | Reportes y exportación para nómina |
| `GET/POST/PUT /api/usuarios` | Administrativo | Cuentas |
| `GET /api/kiosco/empleados` · `POST /api/kiosco/marcaciones` · `GET /api/kiosco/marcaciones/hoy` | Kiosco (`X-Dispositivo`) | Sincronización y registro |

## 3. App Flutter

Requisitos: Flutter 3.47+, Android 7.0+ (minSdk 24) o iOS 15.5+, cámara frontal.

### Modelo de reconocimiento (obligatorio)
Copia un **MobileFaceNet en TensorFlow Lite** como `app/assets/modelos/mobilefacenet.tflite`
(entrada float32 `[1,112,112,3]` o `[2,112,112,3]`, salida 128 o 192). Un archivo de uso
común es el `mobilefacenet.tflite` del proyecto de código abierto *FaceRecognitionAuth*
(GitHub: `MCarlomagno/FaceRecognitionAuth`, carpeta `assets`). Revisa su licencia antes
de usarlo comercialmente. La app adapta tamaño de entrada y salida automáticamente.

### Compilar
```bash
cd app
flutter pub get
flutter build apk --release
```
En Windows, si Gradle falla con *"Unable to establish loopback connection"*, define
una carpeta temporal corta para Java antes de compilar:
`set JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\tmp`

Opcional: copia los `.ttf` de Plus Jakarta Sans, Space Grotesk y JetBrains Mono en
`app/assets/fuentes/` para que la tipografía funcione sin internet desde el primer arranque.

### Compilar en GitHub Actions e instalar en el teléfono
El workflow [`compilar-app.yml`](.github/workflows/compilar-app.yml) corre con cada
cambio de `app/` en `main` (o a mano: **Actions → Compilar app → Run workflow**):
análisis y pruebas → **.ipa** (iPhone) y **.apk** (Android) → publica ambos en el
Release **`ultima`** del repositorio, listo para descargar desde el teléfono.

**Modelo facial en la compilación** (elige una):
- Súbelo al repo en `app/assets/modelos/mobilefacenet.tflite` (si su licencia lo permite: el repo y el Release son públicos), o
- crea el secreto `MODELO_TFLITE_URL` (Settings → Secrets and variables → Actions) con la URL de descarga directa, o
- pega la URL en el campo *modelo_url* al ejecutar el workflow a mano.

**Android:** descarga `ControlPersonal-Android.apk` del Release en el teléfono e instálalo
(permite "instalar apps desconocidas" para el navegador).

**iPhone sin cuenta de desarrollador (gratis):** Apple no permite instalar un `.ipa`
sin firma, así que se firma con tu Apple ID al instalarlo:
1. En un PC con Windows o Mac instala **Sideloadly** (o usa **AltStore**).
2. Descarga `ControlPersonal-iOS-sin-firmar.ipa` del Release, conecta el iPhone por cable
   y arrástralo a Sideloadly; ingresa tu Apple ID.
3. En el iPhone: **Ajustes → Privacidad y seguridad → Modo de desarrollador** (actívalo y
   reinicia) y **Ajustes → General → VPN y gestión de dispositivos** → confía en tu Apple ID.
4. Con un Apple ID gratuito la firma dura **7 días**: vuelve a instalar (o deja que AltStore
   la renueve sola).

**iPhone con Apple Developer Program (firma directa, 1 año):** agrega estos secretos y el
workflow genera `ControlPersonal-iOS.ipa` ya firmado (se instala con Apple Configurator,
Xcode o un enlace de distribución ad hoc):

| Secreto | Valor |
|---|---|
| `IOS_P12_BASE64` | Certificado *Apple Distribution* (o *Development*) exportado como `.p12`, en base64 |
| `IOS_P12_PASSWORD` | Contraseña de ese `.p12` |
| `IOS_PROVISION_BASE64` | Perfil `.mobileprovision` (Ad Hoc con los UDID de los iPhone), en base64 |

Para obtener el base64 en Windows: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("cert.p12"))`
(PowerShell) o en Mac: `base64 -i cert.p12 | pbcopy`. El identificador de la app se toma del
perfil automáticamente.

> En repositorios privados los minutos de macOS cuentan 10× del plan gratuito de Actions.

### Uso
1. **Configurar el kiosco** (una vez): URL del servidor → usuario **General** o
   **Administrativo** → sede y nombre del kiosco.
2. **Kiosco**: el empleado mira la cámara; el HUD lo encuadra, pide un parpadeo
   (prueba de vida) y lo identifica. Se sugiere **Entrada** o **Salida** según su
   última marcación y se confirma sola en 4 s. Al registrar le dice si llegó a tiempo.
   Funciona **sin internet**: las marcas quedan en cola y se envían solas.
3. **Ícono de escudo** (arriba a la derecha):
   - **General** → panel de operador: estado, sincronización, marcaciones de hoy, cambiar de sede.
   - **Administrativo** → Asistencia (día y cumplimiento), Personal (alta, registro
     facial guiado de 3 tomas, horario), Horarios (turnos y rotaciones), Ajustes
     (usuarios, kioscos, exigencia del reconocimiento, tema).

## 4. Horarios con rotación semanal

1. Crea los turnos, p. ej. **Turno A** `08:30–12:00` y `14:00–18:00`, **Turno B**
   `10:30–14:00` y `16:00–21:00`, días y tolerancia.
2. **Asignar rotación**: orden `Turno A → Turno B`, semana de inicio y personas.
   Cada lunes pasan solos al siguiente turno (A, B, A, B…). Puedes rotar hasta 8 turnos.
3. Para **una sola semana** distinta (reemplazo, vacaciones) toca esa semana en la
   ficha del empleado; la rotación sigue igual después.

### Reglas de cumplimiento
Las marcaciones se emparejan en tramos (entrada → salida) y se comparan con cada bloque:

| Estado | Cuándo |
|---|---|
| Cumple | Llegó y salió dentro de la tolerancia en todos sus bloques |
| Llegó tarde | Llegada > inicio + tolerancia (se informan los minutos) |
| Salió antes | Salida < fin − tolerancia |
| Incompleto | Faltó a algún bloque del día |
| No asistió | Tenía turno y no marcó |
| Sin salida | Entró y no marcó salida (días pasados) |
| Libre / Fuera de turno | No tenía turno ese día (si marcó: fuera de turno) |

Si alguien marca solo al llegar y al irse en jornada partida, el tramo cubre ambos
bloques y cuenta como cumplido (no se exige marcar el almuerzo).

## 5. Seguridad y privacidad (Ley 1581 de 2012)
- Los datos biométricos son **sensibles**: la app exige confirmar la **autorización
  expresa** del empleado antes de registrar su rostro. Guarda la autorización firmada.
- Las fotos están en una carpeta **no pública** y solo se entregan con token a kioscos
  de la misma sede o a administrativos. Al dar de baja a alguien se **borran** sus fotos
  (su historial se conserva).
- Contraseñas argon2id; tokens de kiosco guardados como SHA-256; sesiones JWT que se
  revalidan en cada petición; bloqueo de 15 min tras 8 intentos fallidos.
- Cada marcación guarda la hora del teléfono y la del servidor: si un kiosco tiene el
  reloj adelantado, el reporte lo marca.

## 6. Pruebas
```bash
cd app
flutter analyze
flutter test                                  # lógica de visión, puntualidad, horarios
flutter test test_capturas --update-goldens   # capturas de las pantallas en test_capturas/goldens
```
El backend se probó de punta a punta contra MariaDB 11.4 con el esquema real
(52 comprobaciones: roles, rotación, cumplimiento, idempotencia, fotos y seguridad).

## Limitaciones conocidas
- Turnos que cruzan la medianoche (p. ej. 22:00–06:00) no están soportados todavía.
- Los festivos no se descuentan automáticamente (usa el ajuste semanal "Sin turno").
- La prueba de vida por parpadeo frena fotos impresas, no videos de alta calidad.
- El kiosco funciona en orientación vertical.
