# Publicar Presente y Ventario en Google Play

Guía de lo que falta para subir las dos apps. Las apps ya traen:

- **Nombres:** Presente y Ventario.
- **Identificadores definitivos:** `com.krenovapp.presente` y `com.krenovapp.ventario`.
- **Ícono de Presente:** normal, adaptable y el de 512 px para Play.
- **Firma de publicación:** se lee de `android/key.properties`.
- **Eliminación de cuenta dentro de la app:** Ajustes → Mi empresa.
- **Páginas públicas que exige Play:**
  - Política de privacidad: <https://agendaservi.com/privacidad/>
  - Eliminar la cuenta: <https://agendaservi.com/eliminar-cuenta/>

  Existen en cuanto se sube el backend PHP actualizado (paso 1).

---

## 1. Servidores (antes de publicar)

### Ventario: backend Node (inventarios.alwaysdata.net)

1. Sube de nuevo `src/modules/cuenta/index.js`, que ahora borra los datos de verdad al eliminar una cuenta.
2. En las variables de entorno del sitio, agrega o cambia:
   ```
   NODE_ENV=production
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=465
   SMTP_SEGURO=true
   SMTP_USER=krenovapp@gmail.com
   SMTP_PASSWORD=<contraseña de aplicación de Gmail, SIN espacios>
   CORREO_REMITENTE=Ventario <krenovapp@gmail.com>
   ```
   - `NODE_ENV=production` deja de mostrar detalles internos en los errores. Hoy el servidor está en `development` y expone rutas y consultas SQL en cada error.
   - Con `NODE_ENV=production`, el servidor exige que `JWT_ACCESS_SECRET` y `JWT_REFRESH_SECRET` sean distintos y sin valores de ejemplo. Los de tu `.env` local ya cumplen.
3. Reinicia el sitio.

### Presente: backend PHP (agendaservi.com)

1. Sube de nuevo estos archivos:
   - `src/Servicios/Correo.php` (envío por SMTP de Gmail)
   - `src/Controladores/CuentaControlador.php`
   - `bin/limpiar_fotos.php`
   - `public/privacidad/`
   - `public/eliminar-cuenta/`
   - `public/legal.css`
2. En `config/config.php`, en el servidor:
   ```php
   'nombre_plataforma' => 'Krenovapp',
   'correo' => [
       'habilitado' => true,
       'remitente'  => 'Presente <krenovapp@gmail.com>',
       'smtp' => [
           'host'    => 'smtp.gmail.com',
           'puerto'  => 465,
           'usuario' => 'krenovapp@gmail.com',
           'clave'   => '<contraseña de aplicación de Gmail>',
       ],
   ],
   ```
3. Crea la cuenta de **superadministrador**. Es la única que entra a <https://agendaservi.com/plataforma/> para habilitar apps y asignar planes. Por SSH, desde la carpeta del backend:
   ```
   php bin/crear_superadmin.php <correo> "Krenovapp"
   ```
   Usa un correo que no sea el de una cuenta de empresa. La contraseña se pide por teclado.
4. Crea una **tarea programada diaria** en alwaysdata (Avanzado → Tareas programadas):
   ```
   php /home/<cuenta>/www/control/bin/limpiar_fotos.php
   ```
   Borra las fotos del rostro de quien elimine su cuenta desde Ventario.

### La base de datos

Ya está migrada (21-10-2026). Respaldos previos en `PERSONAL\RESPALDOS\`.

Reiniciar los servidores **no** migra la base. Las migraciones futuras se aplican desde `inventario/backend`:

```
DB_MIGRACIONES_EXTRA="../../CONTROL PERSONAL/database" node scripts/migrate.mjs
```

Aplica solo los archivos nuevos: cada uno queda anotado en `schema_migraciones`.

### Prueba rápida

- Entra a Ventario con `di.beltran@udla.edu.co`.
- Entra a Presente (administración) con `dibeltran`: la cuenta de asistencia migrada; acepta el usuario viejo además de correos.
- Prueba «¿Olvidaste tu contraseña?» con un correo real para confirmar que llega el código.

---

## 2. Llave de firma (una por app, una sola vez)

En una terminal, para cada app:

```
keytool -genkey -v -keystore C:\Users\DiBeltran\llaves\presente.jks -keyalg RSA -keysize 2048 -validity 10000 -alias presente
keytool -genkey -v -keystore C:\Users\DiBeltran\llaves\ventario.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ventario
```

Luego crea `android/key.properties` en cada app:

- `SAS\CONTROL PERSONAL\app\android\key.properties`
- `SAS\inventario\mobile\android\key.properties`

```
storePassword=<la contraseña que elegiste>
keyPassword=<la misma, salvo que hayas puesto otra>
keyAlias=presente
storeFile=C:\\Users\\DiBeltran\\llaves\\presente.jks
```

Para Ventario, usa `ventario` en `keyAlias` y la ruta de `ventario.jks` en `storeFile`.

- **Guarda copia de los `.jks` y sus contraseñas** fuera del PC: en un gestor de contraseñas y en una memoria USB.
- **No los subas a git:** `.gitignore` ya los excluye.
- Con Play App Signing, Google guarda la llave final. Si pierdes esta, se puede reemplazar desde Play Console, pero toma días.

## 3. Compilar

```
flutter build appbundle --release
```

El paquete queda en `build/app/outputs/bundle/release/app-release.aab`.

- Si no hay `key.properties`, se firma con la llave de depuración y **Play lo rechaza**.
- En este PC, Gradle necesita la variable `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\t`.
- Para cada nueva versión, sube el número en `pubspec.yaml`: `version: 1.0.1+2`. El número después del `+` debe crecer siempre.

---

## 4. Play Console (cuenta personal)

> **Cuenta personal = prueba cerrada obligatoria.** Antes de pedir acceso a producción, cada app debe estar en prueba cerrada con **al menos 12 testers inscritos durante 14 días seguidos**. Invítalos por correo (lista de testers) y pídeles que instalen la app y la usen. Empieza esto cuanto antes: es lo que más tiempo toma.

Para cada app:

1. **Crear app.** Usa los datos de abajo y acepta las declaraciones.
   - Nombre: Presente o Ventario.
   - Idioma: Español (Latinoamérica).
   - Tipo: App.
   - Precio: Gratis.
2. **Ficha de Play Store.**
   - Descripción corta (máximo 80 caracteres) y descripción completa.
   - Ícono 512×512:
     - Presente: `SAS\CONTROL PERSONAL\docs\play\icono_play_512.png`.
     - Ventario: hay que diseñarlo.
   - Gráfico de funciones de 1024×500.
   - Al menos 2 capturas de teléfono. Presente tiene capturas en `docs\capturas\`.
3. **Contenido de la app**
   - **Política de privacidad:** `https://agendaservi.com/privacidad/`
   - **Acceso a la app:** requiere iniciar sesión. Da a Google una cuenta de prueba que funcione: crea una empresa de demostración desde la app y escribe su correo y contraseña ahí. Sin esto, rechazan la revisión.
   - **Anuncios:** no.
   - **Clasificación de contenido:** cuestionario, categoría «Utilidades / Productividad».
   - **Público objetivo:** 18 años o más.
   - **Seguridad de los datos:** ver la sección 5.
   - **Eliminación de la cuenta:** `https://agendaservi.com/eliminar-cuenta/`
   - **App gubernamental / funciones financieras / salud:** no.
4. **Prueba cerrada.** Sube el `.aab`, agrega la lista de testers y publica en esa pista. Pasados los 14 días con 12 o más testers, solicita el acceso a producción.

---

## 5. Seguridad de los datos (formulario de Play)

En las dos apps, las respuestas generales son estas:

- ¿Recopila o comparte datos? **Sí recopila, no comparte.**
- ¿Cifrado en tránsito? **Sí** (HTTPS).
- ¿Se puede pedir que se borren los datos? **Sí**: dentro de la app y en la URL de eliminación.

### Presente

| Tipo de dato | Recopilado | Obligatorio | Propósito |
|---|---|---|---|
| Información personal → Nombre | Sí | Sí | Funcionalidad de la app, administración de la cuenta |
| Información personal → Correo electrónico | Sí | Sí | Administración de la cuenta |
| Información personal → IDs de usuario (documento) | Sí | Sí | Funcionalidad de la app |
| Fotos y videos → Fotos (rostro) | Sí | Sí, para marcar con el rostro | Funcionalidad de la app |
| Actividad en la app → Otras acciones (marcaciones de entrada y salida) | Sí | Sí | Funcionalidad de la app |
| IDs del dispositivo u otros | Sí | Sí | Funcionalidad de la app, seguridad |

Presente usa reconocimiento facial. En la descripción de la ficha di claramente que las fotos del rostro se usan solo para marcar asistencia y que se registra la autorización de cada persona (Ley 1581).

### Ventario

| Tipo de dato | Recopilado | Obligatorio | Propósito |
|---|---|---|---|
| Información personal → Nombre | Sí | Sí | Funcionalidad, administración de la cuenta |
| Información personal → Correo electrónico | Sí | Sí | Administración de la cuenta |
| Información personal → Teléfono | Sí | No | Funcionalidad |
| Información financiera → Historial de compras (ventas del negocio) | Sí | Sí | Funcionalidad de la app |
| Fotos y videos → Fotos (de productos) | Sí | No | Funcionalidad de la app |
| IDs del dispositivo u otros | Sí | Sí | Funcionalidad de la app, seguridad |

---

## 6. Celulares que ya tienen las apps instaladas por APK

El identificador cambió, así que la versión de Play se instala **al lado** de la vieja; no la reemplaza.

- En cada celular, instala la de Play y desinstala la vieja.
- **En Ventario**, sube primero las ventas pendientes de la app vieja: Ajustes → Pendientes vacío.
- **En los kioscos de Presente** hay que volver a vincular el dispositivo.
