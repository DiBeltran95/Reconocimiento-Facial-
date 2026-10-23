-- =============================================================================
--  CONTROL DE PERSONAL (Presente) · Migración 007 — Un solo registro por persona
--
--  Antes los datos de una persona vivían DOS veces: en `usuarios` (nombre,
--  documento, correo, teléfono) y en `asis_empleados` (los mismos), y cada
--  backend copiaba los cambios de uno a otro. Ahora:
--
--   * `empleados` (antes asis_empleados) es la ÚNICA fuente de nombre,
--     documento, correo, teléfono, cargo y sede, para Ventario y Presente.
--     El correo del empleado es con el que inicia sesión (único en toda la
--     plataforma).
--   * `usuarios` es solo la CUENTA de acceso: a qué empleado pertenece
--     (`empleado_id`), contraseña, roles por app, pausa de Ventario y horario.
--     Solo las cuentas técnicas SIN empleado (Operario y superadministrador)
--     guardan su propio nombre y correo (ck_usuarios_persona).
--   * La pausa de Presente es la del empleado (`empleados.en_pausa`): no marca
--     ni entra a Presente. Desaparece `usuarios.pausa_asistencia`.
--   * `v_usuarios` (solo lectura) une cuenta + empleado para mostrar nombres.
--
--  Requiere las migraciones 004–006 de esta carpeta y 006–007 de Inventario.
--  Cada sentencia tolera haberse aplicado ya.
-- =============================================================================

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 0. Lo que depende del esquema viejo se rehace al final
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_asis_emp_cupo_insert;
DROP TRIGGER IF EXISTS trg_asis_emp_cupo_update;
DROP TRIGGER IF EXISTS trg_usuarios_cupo_insert;
DROP TRIGGER IF EXISTS trg_usuarios_cupo_update;
DROP FUNCTION IF EXISTS fn_vinculo_ya_contado;
DROP FUNCTION IF EXISTS fn_cuenta_cuenta_en_asistencia;
DROP VIEW IF EXISTS v_asis_marcaciones;

-- -----------------------------------------------------------------------------
-- 1. asis_empleados → empleados (las FK de marcaciones, turnos y novedades
--    siguen a la tabla)
-- -----------------------------------------------------------------------------
RENAME TABLE IF EXISTS asis_empleados TO empleados;

ALTER TABLE empleados
  MODIFY documento VARCHAR(20) NULL COMMENT 'NULL: aún sin documento (p. ej. el dueño al registrarse)';

ALTER TABLE usuarios
  ADD COLUMN IF NOT EXISTS empleado_id INT UNSIGNED NULL AFTER empresa_id,
  MODIFY nombre VARCHAR(120) NULL COMMENT 'Solo cuentas sin empleado (Operario, superadministrador)',
  MODIFY email VARCHAR(191) NULL COMMENT 'Solo cuentas sin empleado; las demás entran con el correo del empleado';

-- -----------------------------------------------------------------------------
-- 2. Enlazar y mover datos (solo la primera vez: mientras exista la columna
--    vieja empleados.usuario_id). La base de producción se vació antes de
--    esta migración; esto cubre cualquier otra base con datos.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS tmp_m007_mover;

DELIMITER $$

CREATE PROCEDURE tmp_m007_mover()
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = DATABASE() AND table_name = 'empleados' AND column_name = 'usuario_id') THEN
    -- La cuenta apunta a su empleado.
    UPDATE usuarios u JOIN empleados e ON e.usuario_id = u.id
       SET u.empleado_id = e.id
     WHERE u.empleado_id IS NULL;

    -- Las cuentas de una empresa sin ficha (el dueño, gerentes…) reciben la
    -- suya en la sede principal. El Operario es una cuenta técnica: no.
    INSERT INTO empleados (empresa_id, sede_id, documento, nombre, telefono, email)
    SELECT u.empresa_id,
           (SELECT s.id FROM sedes s WHERE s.empresa_id = u.empresa_id AND s.deleted_at IS NULL
             ORDER BY s.es_principal DESC, s.id LIMIT 1),
           u.documento, u.nombre, u.telefono, u.email
      FROM usuarios u
     WHERE u.empresa_id IS NOT NULL AND u.empleado_id IS NULL AND u.es_superadmin = 0
       AND u.deleted_at IS NULL AND (u.rol IS NOT NULL OR u.rol_asistencia <> 'OPERARIO');
    UPDATE usuarios u JOIN empleados e ON e.empresa_id = u.empresa_id AND e.email = u.email AND e.usuario_id IS NULL
       SET u.empleado_id = e.id
     WHERE u.empleado_id IS NULL AND u.es_superadmin = 0 AND u.deleted_at IS NULL
       AND (u.rol IS NOT NULL OR u.rol_asistencia <> 'OPERARIO');

    -- El correo de la cuenta (con el que entraba) pasa al empleado; lo demás
    -- solo si la ficha no lo tenía. La pausa de Presente pasa al empleado.
    UPDATE empleados e JOIN usuarios u ON u.empleado_id = e.id
       SET e.email     = COALESCE(u.email, e.email),
           e.telefono  = COALESCE(e.telefono, u.telefono),
           e.documento = COALESCE(e.documento, u.documento),
           e.en_pausa  = GREATEST(e.en_pausa, u.pausa_asistencia);
    UPDATE usuarios SET nombre = NULL, email = NULL WHERE empleado_id IS NOT NULL;
  END IF;
END$$

DELIMITER ;

CALL tmp_m007_mover();
DROP PROCEDURE IF EXISTS tmp_m007_mover;

-- -----------------------------------------------------------------------------
-- 3. Columnas duplicadas fuera; llaves y reglas nuevas
-- -----------------------------------------------------------------------------
ALTER TABLE empleados
  DROP FOREIGN KEY IF EXISTS fk_asis_emp_usuario;
ALTER TABLE empleados
  DROP INDEX IF EXISTS uk_asis_emp_usuario,
  DROP COLUMN IF EXISTS usuario_id,
  ADD UNIQUE KEY IF NOT EXISTS uk_empleados_email (email);

ALTER TABLE usuarios
  DROP INDEX IF EXISTS uk_usuarios_empresa_documento,
  DROP COLUMN IF EXISTS documento,
  DROP COLUMN IF EXISTS telefono,
  DROP COLUMN IF EXISTS pausa_asistencia,
  ADD UNIQUE KEY IF NOT EXISTS uk_usuarios_empleado (empleado_id),
  ADD CONSTRAINT fk_usuarios_empleado FOREIGN KEY IF NOT EXISTS (empleado_id) REFERENCES empleados (id);

ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS ck_usuarios_persona;
ALTER TABLE usuarios ADD CONSTRAINT ck_usuarios_persona
  CHECK (empleado_id IS NULL OR (nombre IS NULL AND email IS NULL));

-- -----------------------------------------------------------------------------
-- 4. Lectura: cuenta + su empleado. Para MOSTRAR (quién vendió, aprobó,
--    vinculó…) y para iniciar sesión. Nunca se escribe en ella.
--    `pausa_asistencia` se conserva como reflejo de la pausa del empleado.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_usuarios AS
SELECT u.id, u.uuid, u.empresa_id, u.empleado_id,
       COALESCE(e.nombre, u.nombre) AS nombre,
       COALESCE(e.email, u.email)   AS email,
       e.documento, e.telefono, e.cargo,
       e.sede_id                    AS empleado_sede_id,
       e.activo                     AS empleado_activo,
       COALESCE(e.en_pausa, 0)      AS pausa_asistencia,
       u.rol, u.rol_asistencia, u.es_superadmin, u.activo, u.pausa_inventario,
       u.restringir_horario, u.horario, u.acceso_extra_hasta, u.ultimo_acceso,
       u.created_at, u.updated_at, u.deleted_at
  FROM usuarios u
  LEFT JOIN empleados e ON e.id = u.empleado_id;

CREATE OR REPLACE VIEW v_asis_marcaciones AS
SELECT m.id, em.nombre AS empresa, s.nombre AS sede, e.documento, e.nombre AS empleado, m.tipo,
       CAST(m.hora_dispositivo - INTERVAL 5 HOUR AS DATE) AS dia,
       m.hora_dispositivo - INTERVAL 5 HOUR AS hora_local,
       m.hora_servidor - INTERVAL 5 HOUR AS hora_servidor_local,
       TIMESTAMPDIFF(SECOND, m.hora_dispositivo, m.hora_servidor) AS desfase_seg
  FROM asis_marcaciones m
  JOIN empleados e ON e.id = m.empleado_id
  JOIN sedes s ON s.id = m.sede_id
  JOIN empresas em ON em.id = s.empresa_id;

-- -----------------------------------------------------------------------------
-- 5. Personas de cada plan
--    INVENTARIO = cuentas con rol de Ventario sin pausa (como antes).
--    ASISTENCIA = empleados activos sin pausa (el Operario no es persona).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_personas_app;
DROP FUNCTION IF EXISTS fn_personas_empresa;
DROP PROCEDURE IF EXISTS sp_ajustar_cupos;
DROP PROCEDURE IF EXISTS sp_anonimizar_usuario;
DROP PROCEDURE IF EXISTS sp_anonimizar_empresa;
DROP PROCEDURE IF EXISTS sp_registrar_empresa;

DELIMITER $$

CREATE FUNCTION fn_personas_app(p_empresa BIGINT UNSIGNED, p_app VARCHAR(12))
RETURNS INT UNSIGNED
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  IF p_app = 'INVENTARIO' THEN
    RETURN (SELECT COUNT(*) FROM usuarios
             WHERE empresa_id = p_empresa AND activo = 1 AND deleted_at IS NULL
               AND es_superadmin = 0 AND rol IS NOT NULL AND pausa_inventario = 0);
  END IF;
  RETURN (SELECT COUNT(*) FROM empleados WHERE empresa_id = p_empresa AND activo = 1 AND en_pausa = 0);
END$$

-- Vista heredada v_empresa_uso (un plan por empresa): empleados activos más
-- las cuentas técnicas activas.
CREATE FUNCTION fn_personas_empresa(p_empresa BIGINT UNSIGNED)
RETURNS INT UNSIGNED
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  RETURN (SELECT COUNT(*) FROM empleados WHERE empresa_id = p_empresa AND activo = 1)
       + (SELECT COUNT(*) FROM usuarios
           WHERE empresa_id = p_empresa AND empleado_id IS NULL AND activo = 1
             AND deleted_at IS NULL AND es_superadmin = 0);
END$$

-- Si el plan bajó o venció: pausa a los más recientes (nunca al
-- administrador) y deja de usar las sedes elegidas de más (nunca la principal).
CREATE PROCEDURE sp_ajustar_cupos(IN p_empresa BIGINT UNSIGNED, IN p_app VARCHAR(12))
BEGIN
  DECLARE v_limite INT UNSIGNED;
  DECLARE v_exceso INT;
  DECLARE v_admins TEXT;

  SET v_limite = fn_limite_app(p_empresa, p_app, 'personas');
  IF v_limite IS NOT NULL THEN
    SET v_exceso = CAST(fn_uso_app(p_empresa, p_app, 'personas') AS SIGNED) - CAST(v_limite AS SIGNED);
    IF v_exceso > 0 AND p_app = 'INVENTARIO' THEN
      UPDATE usuarios SET pausa_inventario = 1
       WHERE empresa_id = p_empresa AND activo = 1 AND deleted_at IS NULL
         AND rol IS NOT NULL AND rol <> 'ADMIN' AND pausa_inventario = 0
       ORDER BY id DESC
       LIMIT v_exceso;
    ELSEIF v_exceso > 0 THEN
      -- Los administradores se calculan ANTES: el UPDATE no puede leer
      -- usuarios, porque el trigger de empleados la modifica.
      SET v_admins = (SELECT GROUP_CONCAT(empleado_id) FROM usuarios
                       WHERE empresa_id = p_empresa AND empleado_id IS NOT NULL
                         AND (rol = 'ADMIN' OR rol_asistencia = 'ADMIN'));
      UPDATE empleados
         SET en_pausa = 1
       WHERE empresa_id = p_empresa AND activo = 1 AND en_pausa = 0
         AND NOT FIND_IN_SET(id, COALESCE(v_admins, ''))
       ORDER BY id DESC
       LIMIT v_exceso;
    END IF;
  END IF;

  SET v_limite = fn_limite_app(p_empresa, p_app, 'sedes');
  IF v_limite IS NOT NULL THEN
    SET v_exceso = CAST(fn_uso_app(p_empresa, p_app, 'sedes') AS SIGNED) - CAST(v_limite AS SIGNED);
    IF v_exceso > 0 THEN
      DELETE sa FROM sede_aplicativos sa
        JOIN (SELECT sa2.sede_id
                FROM sede_aplicativos sa2
                JOIN sedes s ON s.id = sa2.sede_id
               WHERE s.empresa_id = p_empresa AND sa2.aplicativo = p_app
                 AND s.activo = 1 AND s.deleted_at IS NULL
               ORDER BY s.es_principal ASC, sa2.elegida_en DESC, sa2.sede_id DESC
               LIMIT v_exceso) x ON x.sede_id = sa.sede_id
       WHERE sa.aplicativo = p_app;
    END IF;
  END IF;
END$$

-- Eliminar una cuenta (Ley 1581): sin acceso y sin datos personales. Su
-- empleado queda anonimizado (el historial de ventas y marcaciones se
-- conserva sin nombre).
CREATE PROCEDURE sp_anonimizar_usuario(IN p_usuario BIGINT UNSIGNED)
BEGIN
  -- Primero el id (sin JOIN: el trigger de empleados toca usuarios). Con SET y
  -- no SELECT…INTO: sin fila no lanza NOT FOUND, que cortaría el cursor de
  -- sp_anonimizar_empresa.
  DECLARE v_empleado INT UNSIGNED;
  SET v_empleado = (SELECT empleado_id FROM usuarios WHERE id = p_usuario);
  IF v_empleado IS NOT NULL THEN
    UPDATE empleados
       SET nombre = 'Persona eliminada', documento = CONCAT('ELIM', id),
           cargo = NULL, telefono = NULL, email = NULL, activo = 0
     WHERE id = v_empleado;
  END IF;

  UPDATE usuarios
     SET nombre             = IF(empleado_id IS NULL, 'Cuenta eliminada', NULL),
         email              = IF(empleado_id IS NULL, CONCAT('eliminado-', uuid, '@eliminado.invalid'), NULL),
         password_hash      = '!',
         horario            = NULL,
         restringir_horario = 0,
         acceso_extra_hasta = NULL,
         activo             = 0,
         deleted_at         = COALESCE(deleted_at, UTC_TIMESTAMP(3))
   WHERE id = p_usuario;

  UPDATE refresh_tokens SET revoked_at = UTC_TIMESTAMP(3)
   WHERE usuario_id = p_usuario AND revoked_at IS NULL;
  DELETE FROM codigos_verificacion WHERE usuario_id = p_usuario;
END$$

CREATE PROCEDURE sp_anonimizar_empresa(IN p_empresa BIGINT UNSIGNED)
BEGIN
  DECLARE v_fin TINYINT DEFAULT 0;
  DECLARE v_usuario BIGINT UNSIGNED;
  DECLARE c_usuarios CURSOR FOR SELECT id FROM usuarios WHERE empresa_id = p_empresa;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;

  UPDATE empresas
     SET nombre         = 'Empresa eliminada',
         nit            = NULL,
         telefono       = NULL,
         email_contacto = NULL,
         estado         = 'SUSPENDIDA',
         deleted_at     = COALESCE(deleted_at, UTC_TIMESTAMP(3))
   WHERE id = p_empresa;
  DELETE FROM empresa_configuracion WHERE empresa_id = p_empresa;

  OPEN c_usuarios;
  leer: LOOP
    FETCH c_usuarios INTO v_usuario;
    IF v_fin THEN LEAVE leer; END IF;
    CALL sp_anonimizar_usuario(v_usuario);
  END LOOP;
  CLOSE c_usuarios;

  UPDATE empleados
     SET nombre = 'Persona eliminada', documento = CONCAT('ELIM', id), cargo = NULL,
         telefono = NULL, email = NULL, activo = 0
   WHERE empresa_id = p_empresa;
  UPDATE asis_dispositivos d JOIN sedes s ON s.id = d.sede_id
     SET d.activo = 0
   WHERE s.empresa_id = p_empresa;
END$$

-- Registro de una empresa: las dos apps en Gratis, su sede principal elegida
-- en las dos y el dueño como EMPLEADO (con su correo) + su cuenta ADMIN.
CREATE PROCEDURE sp_registrar_empresa(
  IN p_empresa_uuid    CHAR(36),
  IN p_empresa_nombre  VARCHAR(120),
  IN p_nit             VARCHAR(30),
  IN p_telefono        VARCHAR(30),
  IN p_sede_uuid       CHAR(36),
  IN p_sede_nombre     VARCHAR(120),
  IN p_sede_codigo     VARCHAR(10),
  IN p_usuario_uuid    CHAR(36),
  IN p_usuario_nombre  VARCHAR(120),
  IN p_email           VARCHAR(191),
  IN p_password_hash   VARCHAR(255),
  IN p_aplicativo      VARCHAR(12)
)
BEGIN
  DECLARE v_empresa  BIGINT UNSIGNED;
  DECLARE v_sede     BIGINT UNSIGNED;
  DECLARE v_empleado INT UNSIGNED;
  DECLARE v_usuario  BIGINT UNSIGNED;
  DECLARE v_gratis   SMALLINT UNSIGNED;

  IF p_aplicativo NOT IN ('INVENTARIO','ASISTENCIA') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'APLICATIVO_INVALIDO';
  END IF;
  IF EXISTS (SELECT 1 FROM usuarios WHERE email = p_email)
     OR EXISTS (SELECT 1 FROM empleados WHERE email = p_email) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'EMAIL_EN_USO';
  END IF;
  SET v_gratis = (SELECT id FROM planes WHERE codigo = 'GRATIS');

  INSERT INTO empresas (uuid, nombre, nit, telefono, email_contacto, plan_id, terminos_aceptados_en)
  VALUES (p_empresa_uuid, p_empresa_nombre, NULLIF(p_nit, ''), NULLIF(p_telefono, ''), p_email,
          v_gratis, UTC_TIMESTAMP(3));
  SET v_empresa = LAST_INSERT_ID();

  INSERT INTO empresa_aplicativos (empresa_id, aplicativo) VALUES
    (v_empresa, 'INVENTARIO'), (v_empresa, 'ASISTENCIA');
  INSERT INTO empresa_planes (empresa_id, aplicativo, plan_id) VALUES
    (v_empresa, 'INVENTARIO', v_gratis), (v_empresa, 'ASISTENCIA', v_gratis);

  INSERT INTO empresa_configuracion (empresa_id, clave, valor, tipo, descripcion) VALUES
    (v_empresa, 'nombre_negocio',          p_empresa_nombre,          'STRING',  'Nombre que aparece en el ticket'),
    (v_empresa, 'nit',                     COALESCE(p_nit, ''),       'STRING',  'NIT o identificación fiscal'),
    (v_empresa, 'direccion',               '',                        'STRING',  NULL),
    (v_empresa, 'telefono',                COALESCE(p_telefono, ''),  'STRING',  NULL),
    (v_empresa, 'moneda',                  'COP',                     'STRING',  NULL),
    (v_empresa, 'zona_horaria',            'America/Bogota',          'STRING',  NULL),
    (v_empresa, 'iva_por_defecto',         '19.00',                   'DECIMAL', 'Tasa aplicada a productos nuevos'),
    (v_empresa, 'permitir_stock_negativo', 'true',                    'BOOL',    'Acepta sobreventa offline y genera alerta'),
    (v_empresa, 'permite_credito',         'false',                   'BOOL',    'Habilita el cobro a crédito (fiado)'),
    (v_empresa, 'ticket_pie',              '¡Gracias por su compra!', 'STRING',  NULL),
    (v_empresa, 'offline_grace_days',      '7',                       'INT',     'Días que la app opera sin ver el servidor');

  INSERT INTO metodos_pago (uuid, empresa_id, nombre, tipo, orden, color) VALUES
    (UUID(), v_empresa, 'Efectivo',      'EFECTIVO',      1, '#11794F'),
    (UUID(), v_empresa, 'Tarjeta',       'TARJETA',       2, '#1D4ED8'),
    (UUID(), v_empresa, 'Transferencia', 'TRANSFERENCIA', 3, '#6750A4');

  INSERT INTO sedes (uuid, empresa_id, nombre, codigo, telefono, es_principal)
  VALUES (p_sede_uuid, v_empresa, p_sede_nombre, p_sede_codigo, NULLIF(p_telefono, ''), 1);
  SET v_sede = LAST_INSERT_ID();

  INSERT INTO empleados (empresa_id, sede_id, documento, nombre, cargo, email)
  VALUES (v_empresa, v_sede, NULL, p_usuario_nombre, 'Administrador', p_email);
  SET v_empleado = LAST_INSERT_ID();

  INSERT INTO usuarios (uuid, empresa_id, empleado_id, password_hash, rol, rol_asistencia)
  VALUES (p_usuario_uuid, v_empresa, v_empleado, p_password_hash, 'ADMIN', 'ADMIN');
  SET v_usuario = LAST_INSERT_ID();

  INSERT INTO sede_aplicativos (sede_id, aplicativo, elegida_por) VALUES
    (v_sede, 'INVENTARIO', v_usuario), (v_sede, 'ASISTENCIA', v_usuario);

  SELECT v_empresa AS empresa_id, v_sede AS sede_id, v_usuario AS usuario_id;
END$$

DELIMITER ;

-- -----------------------------------------------------------------------------
-- 6. Triggers
--    · El correo es único en TODA la plataforma: el de un empleado no puede
--      ser el de una cuenta técnica, ni al revés (EMAIL_EN_USO → 409).
--    · Cupo de personas: Ventario cuenta cuentas; Presente, empleados.
--    · Si cambia el nombre o el correo del empleado, su cuenta se marca como
--      modificada para que la app de Ventario la vuelva a bajar.
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_empleados_insert;
DROP TRIGGER IF EXISTS trg_empleados_update;
DROP TRIGGER IF EXISTS trg_empleados_after_update;

DELIMITER $$

CREATE TRIGGER trg_empleados_insert
BEFORE INSERT ON empleados
FOR EACH ROW
BEGIN
  IF NEW.email IS NOT NULL AND EXISTS (SELECT 1 FROM usuarios WHERE email = NEW.email) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'EMAIL_EN_USO';
  END IF;
  IF NEW.activo = 1 AND NEW.en_pausa = 0 THEN
    CALL sp_exigir_cupo_app(NEW.empresa_id, 'ASISTENCIA', 'personas');
  END IF;
END$$

CREATE TRIGGER trg_empleados_update
BEFORE UPDATE ON empleados
FOR EACH ROW
BEGIN
  IF NEW.email IS NOT NULL AND NOT (NEW.email <=> OLD.email)
     AND EXISTS (SELECT 1 FROM usuarios WHERE email = NEW.email) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'EMAIL_EN_USO';
  END IF;
  IF NEW.activo = 1 AND NEW.en_pausa = 0 AND NOT (OLD.activo = 1 AND OLD.en_pausa = 0) THEN
    CALL sp_exigir_cupo_app(NEW.empresa_id, 'ASISTENCIA', 'personas');
  END IF;
END$$

CREATE TRIGGER trg_empleados_after_update
AFTER UPDATE ON empleados
FOR EACH ROW
BEGIN
  IF NOT (NEW.nombre <=> OLD.nombre) OR NOT (NEW.email <=> OLD.email)
     OR NOT (NEW.activo <=> OLD.activo) OR NOT (NEW.en_pausa <=> OLD.en_pausa) THEN
    UPDATE usuarios SET updated_at = UTC_TIMESTAMP(3) WHERE empleado_id = NEW.id;
  END IF;
END$$

CREATE TRIGGER trg_usuarios_cupo_insert
BEFORE INSERT ON usuarios
FOR EACH ROW
BEGIN
  IF NEW.email IS NOT NULL AND EXISTS (SELECT 1 FROM empleados WHERE email = NEW.email) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'EMAIL_EN_USO';
  END IF;
  IF NEW.activo = 1 AND NEW.deleted_at IS NULL AND NEW.es_superadmin = 0
     AND NEW.rol IS NOT NULL AND NEW.pausa_inventario = 0 THEN
    CALL sp_exigir_cupo_app(NEW.empresa_id, 'INVENTARIO', 'personas');
  END IF;
END$$

CREATE TRIGGER trg_usuarios_cupo_update
BEFORE UPDATE ON usuarios
FOR EACH ROW
BEGIN
  IF NEW.email IS NOT NULL AND NOT (NEW.email <=> OLD.email)
     AND EXISTS (SELECT 1 FROM empleados WHERE email = NEW.email) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'EMAIL_EN_USO';
  END IF;
  IF NEW.activo = 1 AND NEW.deleted_at IS NULL AND NEW.es_superadmin = 0
     AND NEW.rol IS NOT NULL AND NEW.pausa_inventario = 0
     AND NOT (OLD.activo = 1 AND OLD.deleted_at IS NULL AND OLD.rol IS NOT NULL AND OLD.pausa_inventario = 0) THEN
    CALL sp_exigir_cupo_app(NEW.empresa_id, 'INVENTARIO', 'personas');
  END IF;
END$$

DELIMITER ;
