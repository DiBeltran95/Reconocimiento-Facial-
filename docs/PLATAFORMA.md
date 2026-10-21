# Plataforma multiempresa · contrato compartido

Dos apps, una base, una cuenta por persona:

| App | Backend | Base de la API |
|---|---|---|
| Inventario POS | Node 22 + Express (`inventario/backend`) | `/api/v1` |
| Control de Personal | PHP 8 (`CONTROL PERSONAL/backend`) | `/api` |

Este documento es la **fuente de verdad** de lo que comparten. Si cambias algo aquí, cámbialo en los
dos backends y en las dos apps (este archivo existe igual en los dos repositorios).

---

## 1. Modelo

```
planes ──< empresas ──< sedes ──< (ventas, stock, traslados, cierres, dispositivos, marcaciones…)
              │ ├──< usuarios  (una cuenta por persona, un rol por app)
              │ ├──< empresa_aplicativos (INVENTARIO / ASISTENCIA habilitadas)
              │ ├──< empresa_configuracion
              │ └──< catálogo (categorías, proveedores, productos, códigos, medios de pago)
              └──< asis_empleados (personas que marcan; opcionalmente ligadas a una cuenta)
```

Migraciones (en este orden, con `npm run db:migrate` y `DB_MIGRACIONES_EXTRA` apuntando a la carpeta
`database` de Control de Personal):

1. `inventario/database/migrations/004_plataforma.sql`
2. `CONTROL PERSONAL/database/002_plataforma.sql`

Cada archivo corre una sola vez (`schema_migraciones`). Si la base ya tenía un negocio, todo pasa a
una **empresa fundadora** (plan ILIMITADO, las dos apps habilitadas, `prefijo_web = 'WEB'`).

## 2. Cuentas y roles

Una fila de `usuarios` por persona. El correo es único en toda la plataforma y es con lo que se
entra a las dos apps.

| Columna | Valores | `NULL` significa |
|---|---|---|
| `rol` (Inventario) | `ADMIN` · `GERENTE` · `AUXILIAR_INVENTARIO` · `VENDEDOR` | no entra a Inventario |
| `rol_asistencia` | `ADMIN` · `GERENTE` · `OPERADOR` | no entra a Control de Personal |
| `activo` | 1 / 0 | — (inactivar saca de las dos apps) |
| `es_superadmin` | 1 = equipo de la plataforma (sin empresa, solo panel) | — |

Reglas (idénticas en `domain/alcance.js · validarSedesDeRol` y `UsuariosControlador::validarCombinacion`):

- Al menos un rol.
- `ADMIN` es el dueño en las **dos** apps: si lo es en una, en la otra es `ADMIN` o `NULL`. No lleva sedes (ve todas).
- `VENDEDOR` y `AUXILIAR_INVENTARIO`: exactamente una sede.
- `GERENTE` (en cualquiera de las dos): al menos una sede. Son las **mismas** sedes (`usuario_sedes`) en las dos apps.
- `OPERADOR` (kioscos): no exige sedes; atiende cualquier sede de la empresa.
- Un gerente administra solo vendedores/auxiliares (Inventario) de sus sedes y empleados (Control de Personal) de sus sedes. Nunca a otro gerente ni al administrador, en ninguna de las dos apps.

Para entrar a una app se exige, en este orden (cada uno con su código de error):

| Código | Cuándo |
|---|---|
| `CUENTA_DESACTIVADA` | `usuarios.activo = 0` |
| `EMPRESA_INEXISTENTE` | la empresa fue eliminada |
| `EMPRESA_SUSPENDIDA` | `empresas.estado = 'SUSPENDIDA'` |
| `APP_NO_HABILITADA` | la empresa no tiene la app en `empresa_aplicativos` |
| `SIN_ACCESO_APP` | la persona no tiene rol en esa app |

## 3. Planes y límites

Los impone **la base** (triggers), no el código: ningún backend puede saltárselos.

| Recurso | Cuenta |
|---|---|
| `sedes` | sedes activas |
| `personas` | cuentas activas + empleados de asistencia activos **sin** cuenta |
| `productos` | productos activos |

Plan `GRATIS` (con el que nace toda empresa): **1 sede, 3 personas, 3 productos**. Un plan vencido
(`plan_vence` pasado) opera con los límites de GRATIS sin perder datos.

Al pasarse, la base lanza `SIGNAL 45000 'LIMITE_PLAN:<recurso>'`. Los backends responden **409**:

```jsonc
// Inventario (Node)
{ "error": { "codigo": "LIMITE_PLAN", "mensaje": "Tu plan no admite más productos",
             "detalles": { "recurso": "productos" }, "permanente": true } }
// Control de Personal (PHP)
{ "error": "Tu plan no admite más personas en el equipo", "codigo": "LIMITE_PLAN", "recurso": "personas" }
```

Las apps avisan **antes** de abrir el formulario con el plan que reciben (`GET /cuenta/empresa`, la
bajada de `/sync/pull` en Inventario, `GET /auth/yo` en Control de Personal):

```jsonc
"plan": {
  "codigo": "GRATIS", "nombre": "Gratis", "vence": null, "vencido": false,
  "sedes":     { "usados": 1, "maximo": 1, "lleno": true },
  "personas":  { "usados": 2, "maximo": 3, "lleno": false },
  "productos": { "usados": 3, "maximo": 3, "lleno": true }   // maximo null = sin límite
}
```

Los planes **no se cobran dentro de las apps** (política de Google Play). Los asigna el
superadministrador en `/plataforma/` (panel web del backend PHP) después del pago. Las apps muestran
el plan y sus límites con un texto neutro, sin botones ni enlaces de pago.

## 4. Endpoints de cuenta (mismo contrato en los dos backends)

| Método y ruta | Acceso | Cuerpo / respuesta |
|---|---|---|
| `POST /cuenta/registro` | público, con límite de intentos | ver abajo · responde la sesión iniciada (201) |
| `GET /cuenta/empresa` | autenticado | `{ empresa, plan, aplicativos }` |
| `PUT /cuenta/empresa` | ADMIN | `{ nombre?, nit?, telefono? }` |
| `POST /cuenta/recuperar` | público | `{ email }` → siempre `{ enviado: true, vigencia_minutos: 15 }` |
| `POST /cuenta/restablecer` | público | `{ email, codigo: "123456", password }` |
| `DELETE /cuenta` | autenticado | `{ password, confirmacion? }` · el ADMIN elimina la empresa (escribe su nombre en `confirmacion`); los demás, su cuenta |

Registro:

```json
{
  "empresa": { "nombre": "Tienda La 14", "nit": "900123456-7", "telefono": "3001234567" },
  "sede":    { "nombre": "Sede principal", "codigo": "PRI" },
  "usuario": { "nombre": "Ana Gómez", "email": "ana@tienda.com", "password": "********" },
  "acepta_terminos": true
}
```

Lo ejecuta `CALL sp_registrar_empresa(…)` en los dos backends: empresa en GRATIS, la app desde la
que se registró habilitada, configuración y medios de pago iniciales, sede principal y el dueño con
`rol = 'ADMIN'` y `rol_asistencia = 'ADMIN'`. El código de sede, si no se envía, se sugiere del
nombre («Sede Norte» → «NOR»).

Recuperar la contraseña: código de 6 dígitos por correo, vence en 15 minutos, 5 intentos, solo vale
el último pedido. Restablecerla cierra todas las sesiones de Inventario.

## 5. Aislamiento

- Todo lo que cuelga de una sede se filtra por las sedes del alcance, que **siempre** son de la
  empresa (también las del ADMIN: no existe un «pase libre»).
- Catálogo, sedes, cuentas y configuración se filtran por `empresa_id`, también al buscar por UUID,
  código, SKU o documento.
- `npm run lint:tenant` (Inventario) falla si una consulta busca por uno de esos campos sin acotar
  por empresa.
- El kiosco (Control de Personal) solo baja empleados activos de su sede y solo acepta marcaciones
  de empleados de su empresa.

## 6. Sesiones en las apps

- Inventario guarda una huella del alcance (`empresa|rol|sedes`). Si el teléfono pasa a otra
  empresa, borra lo descargado de la anterior antes de bajar lo nuevo (nunca lo que falta por subir).
- Una cuenta sin rol en Inventario baja a los teléfonos de Inventario como **inactiva**, para que no
  pueda entrar sin red.
