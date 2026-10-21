-- =============================================================================
--  CONTROL DE PERSONAL · Migración 002 — Plataforma multiempresa
--
--  Requiere la migración 004_plataforma.sql del repositorio de Inventario
--  (empresas, planes, usuarios con rol por app). Se aplica DESPUÉS de ella:
--    cd inventario/backend
--    DB_MIGRACIONES_EXTRA="../../CONTROL PERSONAL/database" npm run db:migrate
--
--  Qué cambia:
--   * Las cuentas dejan de vivir en `asis_usuarios`: todas están en `usuarios`
--     con `rol_asistencia` (ADMIN / GERENTE / OPERADOR). Inactivar a alguien
--     lo saca de las dos apps. `asis_usuarios` queda como respaldo, sin uso.
--   * Un empleado puede quedar LIGADO a una cuenta (usuario_id): un vendedor
--     que además marca asistencia es UNA persona, y cuenta una sola vez en el
--     límite del plan.
--   * Empleados y turnos pasan a ser de una empresa; dispositivos y
--     marcaciones la heredan por su sede.
--   * Se guarda la autorización de datos biométricos (Ley 1581): cuándo y
--     quién la registró.
--
--  Cada sentencia tolera haberse aplicado ya.
-- =============================================================================

SET NAMES utf8mb4;
-- La base hereda su collation a las funciones y procedimientos (sus parámetros
-- VARCHAR). Los hostings la crean con utf8mb4_general_ci y las tablas son
-- utf8mb4_unicode_ci: comparar ambas falla con «Illegal mix of collations».
ALTER DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 1. Empleados: empresa, cuenta ligada y autorización biométrica
-- -----------------------------------------------------------------------------
ALTER TABLE `asis_empleados`
  ADD COLUMN IF NOT EXISTS `empresa_id`        BIGINT UNSIGNED NULL AFTER `id`,
  ADD COLUMN IF NOT EXISTS `usuario_id`        BIGINT UNSIGNED NULL AFTER `sede_id`,
  ADD COLUMN IF NOT EXISTS `consentimiento_en` DATETIME NULL AFTER `activo`,
  ADD COLUMN IF NOT EXISTS `consentimiento_por` BIGINT UNSIGNED NULL AFTER `consentimiento_en`;

UPDATE `asis_empleados` e
  JOIN `sedes` s ON s.id = e.sede_id
   SET e.empresa_id = s.empresa_id
 WHERE e.empresa_id IS NULL;

ALTER TABLE `asis_empleados`
  MODIFY COLUMN `empresa_id` BIGINT UNSIGNED NOT NULL,
  DROP INDEX IF EXISTS `uk_asis_emp_documento`,
  ADD UNIQUE KEY IF NOT EXISTS `uk_asis_emp_empresa_documento` (`empresa_id`, `documento`),
  ADD UNIQUE KEY IF NOT EXISTS `uk_asis_emp_usuario` (`usuario_id`),
  ADD KEY IF NOT EXISTS `idx_asis_emp_empresa` (`empresa_id`, `activo`),
  ADD CONSTRAINT `fk_asis_emp_empresa` FOREIGN KEY IF NOT EXISTS (`empresa_id`) REFERENCES `empresas` (`id`),
  ADD CONSTRAINT `fk_asis_emp_usuario` FOREIGN KEY IF NOT EXISTS (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_asis_emp_consentimiento` FOREIGN KEY IF NOT EXISTS (`consentimiento_por`) REFERENCES `usuarios` (`id`) ON DELETE SET NULL;

-- -----------------------------------------------------------------------------
-- 2. Turnos: de una empresa. Los que existían son de la empresa fundadora.
-- -----------------------------------------------------------------------------
ALTER TABLE `asis_horarios`
  ADD COLUMN IF NOT EXISTS `empresa_id` BIGINT UNSIGNED NULL AFTER `id`;

UPDATE `asis_horarios`
   SET empresa_id = (SELECT id FROM empresas WHERE prefijo_web = 'WEB' LIMIT 1)
 WHERE empresa_id IS NULL;

-- Base nueva sin empresa fundadora: no hay turnos huérfanos que conservar.
DELETE FROM `asis_horarios` WHERE empresa_id IS NULL;

ALTER TABLE `asis_horarios`
  MODIFY COLUMN `empresa_id` BIGINT UNSIGNED NOT NULL,
  ADD KEY IF NOT EXISTS `idx_asis_hor_empresa` (`empresa_id`, `activo`),
  ADD CONSTRAINT `fk_asis_hor_empresa` FOREIGN KEY IF NOT EXISTS (`empresa_id`) REFERENCES `empresas` (`id`);

-- -----------------------------------------------------------------------------
-- 3. Cuentas de asistencia → `usuarios`
--    GENERAL → OPERADOR, ADMINISTRATIVO → ADMIN. El nombre de usuario pasa a
--    la columna email TAL CUAL: así siguen entrando con lo mismo que escriben
--    hoy. Los que no son un correo se listan al final para corregirlos.
--    Si la cuenta ya existe en `usuarios` (mismo correo), solo se le da el rol.
-- -----------------------------------------------------------------------------
UPDATE `usuarios` u
  JOIN `asis_usuarios` a ON a.usuario = u.email
   SET u.rol_asistencia = IF(a.rol = 'ADMINISTRATIVO', 'ADMIN', 'OPERADOR')
 WHERE u.rol_asistencia IS NULL;

INSERT INTO `usuarios` (uuid, empresa_id, nombre, email, password_hash, rol, rol_asistencia, activo, created_at)
SELECT UUID(),
       (SELECT id FROM empresas WHERE prefijo_web = 'WEB' LIMIT 1),
       a.nombre, a.usuario, a.password_hash, NULL,
       IF(a.rol = 'ADMINISTRATIVO', 'ADMIN', 'OPERADOR'),
       a.activo, a.created_at
  FROM `asis_usuarios` a
 WHERE NOT EXISTS (SELECT 1 FROM `usuarios` u WHERE u.email = a.usuario)
   AND EXISTS (SELECT 1 FROM empresas WHERE prefijo_web = 'WEB');

-- -----------------------------------------------------------------------------
-- 4. Personas: cuentas activas + empleados activos SIN cuenta
--    (reemplaza la versión de la migración 004 de Inventario, que solo
--    contaba cuentas).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_personas_empresa;
DELIMITER $$
CREATE FUNCTION fn_personas_empresa(p_empresa BIGINT UNSIGNED)
RETURNS INT UNSIGNED
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  RETURN (SELECT COUNT(*) FROM usuarios
           WHERE empresa_id = p_empresa AND activo = 1
             AND deleted_at IS NULL AND es_superadmin = 0)
       + (SELECT COUNT(*) FROM asis_empleados
           WHERE empresa_id = p_empresa AND activo = 1 AND usuario_id IS NULL);
END$$
DELIMITER ;

-- Crear la cuenta de un empleado que ya contaba no ocupa un cupo nuevo.
-- El backend fija @cupo_vincula_empleado = id del empleado antes del INSERT.
DROP FUNCTION IF EXISTS fn_vinculo_ya_contado;
DELIMITER $$
CREATE FUNCTION fn_vinculo_ya_contado(p_empresa BIGINT UNSIGNED)
RETURNS TINYINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  IF @cupo_vincula_empleado IS NULL THEN
    RETURN 0;
  END IF;
  RETURN EXISTS (SELECT 1 FROM asis_empleados
                  WHERE id = @cupo_vincula_empleado AND empresa_id = p_empresa
                    AND activo = 1 AND usuario_id IS NULL);
END$$
DELIMITER ;

-- Un empleado ocupa cupo cuando está activo y no tiene cuenta (si la tiene,
-- ya cuenta como cuenta).
DROP TRIGGER IF EXISTS trg_asis_emp_cupo_insert;
DELIMITER $$
CREATE TRIGGER trg_asis_emp_cupo_insert
BEFORE INSERT ON asis_empleados
FOR EACH ROW
BEGIN
  IF NEW.activo = 1 AND NEW.usuario_id IS NULL THEN
    CALL sp_exigir_cupo(NEW.empresa_id, 'personas');
  END IF;
END$$
DELIMITER ;

DROP TRIGGER IF EXISTS trg_asis_emp_cupo_update;
DELIMITER $$
CREATE TRIGGER trg_asis_emp_cupo_update
BEFORE UPDATE ON asis_empleados
FOR EACH ROW
BEGIN
  IF NEW.activo = 1 AND NEW.usuario_id IS NULL
     AND NOT (OLD.activo = 1 AND OLD.usuario_id IS NULL) THEN
    CALL sp_exigir_cupo(NEW.empresa_id, 'personas');
  END IF;
END$$
DELIMITER ;

-- -----------------------------------------------------------------------------
-- 5. Vista de apoyo con la empresa (consultas manuales en phpMyAdmin).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `v_asis_marcaciones` AS
SELECT
  m.id,
  em.nombre                                                     AS empresa,
  s.nombre                                                      AS sede,
  e.documento,
  e.nombre                                                      AS empleado,
  m.tipo,
  DATE(m.hora_dispositivo - INTERVAL 5 HOUR)                    AS dia,
  (m.hora_dispositivo - INTERVAL 5 HOUR)                        AS hora_local,
  (m.hora_servidor    - INTERVAL 5 HOUR)                        AS hora_servidor_local,
  TIMESTAMPDIFF(SECOND, m.hora_dispositivo, m.hora_servidor)    AS desfase_seg
FROM asis_marcaciones m
JOIN asis_empleados e  ON e.id = m.empleado_id
JOIN sedes          s  ON s.id = m.sede_id
JOIN empresas       em ON em.id = s.empresa_id;

-- -----------------------------------------------------------------------------
-- Cuentas migradas cuyo «correo» no es un correo: corrígelas desde el panel
-- (siguen funcionando para entrar, pero no podrán recuperar su contraseña).
-- -----------------------------------------------------------------------------
SELECT id, nombre, email AS usuario_a_corregir
  FROM usuarios
 WHERE rol_asistencia IS NOT NULL AND email NOT LIKE '%_@_%._%';
