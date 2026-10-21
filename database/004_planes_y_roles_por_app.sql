-- =============================================================================
--  CONTROL DE PERSONAL (Presente) · Migración 004 — Planes y roles por app
--
--  Requiere 006_planes_y_roles_por_app.sql del repositorio de Inventario
--  (empresa_planes, sede_aplicativos, pausas, roles por app). Se aplica
--  DESPUÉS de ella. Aquí:
--   * Fichas en pausa por plan (asis_empleados.en_pausa).
--   * Teléfonos de marcación con identidad propia: muchos teléfonos —casi
--     siempre del mismo modelo— entran con la MISMA cuenta Operario, cada uno
--     en su sede. Se distinguen por la instalación (instalacion_uuid) y un
--     código corto visible (codigo), no por el modelo ni por la cuenta.
--   * fn_personas_app y sp_ajustar_cupos cuentan / pausan también las fichas.
--
--  Cada sentencia tolera haberse aplicado ya.
-- =============================================================================

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 1. Fichas en pausa por plan
-- -----------------------------------------------------------------------------
ALTER TABLE `asis_empleados`
  ADD COLUMN IF NOT EXISTS `en_pausa` TINYINT(1) NOT NULL DEFAULT 0 AFTER `activo`;

-- -----------------------------------------------------------------------------
-- 2. Teléfonos de marcación
-- -----------------------------------------------------------------------------
ALTER TABLE `asis_dispositivos`
  ADD COLUMN IF NOT EXISTS `instalacion_uuid` CHAR(36) CHARACTER SET ascii COLLATE ascii_general_ci NULL AFTER `nombre`,
  ADD COLUMN IF NOT EXISTS `codigo` CHAR(4) CHARACTER SET ascii COLLATE ascii_general_ci NULL AFTER `instalacion_uuid`,
  ADD COLUMN IF NOT EXISTS `vinculado_por` BIGINT UNSIGNED NULL AFTER `codigo`,
  ADD COLUMN IF NOT EXISTS `vinculado_en` DATETIME NULL AFTER `vinculado_por`;

-- Código de los teléfonos que ya existían: determinista y único para id < 2^20
-- (7919 es impar: multiplicar por él es biyectivo módulo 2^20).
UPDATE `asis_dispositivos`
   SET `codigo` = UPPER(LPAD(CONV((`id` * 7919) % 1048576, 10, 32), 4, '0'))
 WHERE `codigo` IS NULL;

ALTER TABLE `asis_dispositivos`
  ADD UNIQUE KEY IF NOT EXISTS `uk_asis_disp_instalacion` (`instalacion_uuid`),
  ADD UNIQUE KEY IF NOT EXISTS `uk_asis_disp_codigo` (`codigo`),
  ADD CONSTRAINT `fk_asis_disp_vinculado_por` FOREIGN KEY IF NOT EXISTS (`vinculado_por`)
    REFERENCES `usuarios` (`id`) ON DELETE SET NULL;

-- -----------------------------------------------------------------------------
-- 3. Personas de cada app, con las fichas de asistencia
--    ASISTENCIA = fichas activas sin pausa
--               + cuentas con rol en Presente (no Operario) sin pausa y SIN
--                 ficha activa (con ficha ya cuentan por ella: una vez).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_personas_app;
DROP FUNCTION IF EXISTS fn_vinculo_ya_contado;
DROP FUNCTION IF EXISTS fn_cuenta_cuenta_en_asistencia;
DROP PROCEDURE IF EXISTS sp_ajustar_cupos;

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
  RETURN (SELECT COUNT(*) FROM asis_empleados
           WHERE empresa_id = p_empresa AND activo = 1 AND en_pausa = 0)
       + (SELECT COUNT(*) FROM usuarios u
           WHERE u.empresa_id = p_empresa AND u.activo = 1 AND u.deleted_at IS NULL
             AND u.es_superadmin = 0 AND u.rol_asistencia IS NOT NULL
             AND u.rol_asistencia <> 'OPERARIO' AND u.pausa_asistencia = 0
             AND NOT EXISTS (SELECT 1 FROM asis_empleados e
                              WHERE e.usuario_id = u.id AND e.activo = 1 AND e.en_pausa = 0));
END$$

-- ¿La cuenta ya ocupa cupo en Presente como CUENTA (sin ficha propia)? Si se
-- le crea su ficha, pasa a contar por la ficha: no es una persona nueva.
CREATE FUNCTION fn_cuenta_cuenta_en_asistencia(p_usuario BIGINT UNSIGNED)
RETURNS TINYINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  IF p_usuario IS NULL THEN
    RETURN 0;
  END IF;
  RETURN EXISTS (SELECT 1 FROM usuarios u
                  WHERE u.id = p_usuario AND u.activo = 1 AND u.deleted_at IS NULL
                    AND u.rol_asistencia IS NOT NULL AND u.rol_asistencia <> 'OPERARIO'
                    AND u.pausa_asistencia = 0
                    AND NOT EXISTS (SELECT 1 FROM asis_empleados e
                                     WHERE e.usuario_id = u.id AND e.activo = 1 AND e.en_pausa = 0));
END$$

-- Crear la cuenta de alguien que ya marcaba (ficha activa sin cuenta) no ocupa
-- un cupo nuevo en Presente: el backend fija @cupo_vincula_empleado antes.
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
                    AND activo = 1 AND en_pausa = 0 AND usuario_id IS NULL);
END$$

-- Igual que la versión de Inventario, y en ASISTENCIA pausa primero las fichas
-- más recientes (nunca la del administrador) y después las cuentas.
CREATE PROCEDURE sp_ajustar_cupos(IN p_empresa BIGINT UNSIGNED, IN p_app VARCHAR(12))
BEGIN
  DECLARE v_limite INT UNSIGNED;
  DECLARE v_exceso INT;

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
      UPDATE asis_empleados e
         SET e.en_pausa = 1
       WHERE e.empresa_id = p_empresa AND e.activo = 1 AND e.en_pausa = 0
         AND (e.usuario_id IS NULL
              OR e.usuario_id NOT IN (SELECT id FROM usuarios WHERE rol_asistencia = 'ADMIN'))
       ORDER BY e.id DESC
       LIMIT v_exceso;
      SET v_exceso = CAST(fn_uso_app(p_empresa, p_app, 'personas') AS SIGNED) - CAST(v_limite AS SIGNED);
      IF v_exceso > 0 THEN
        UPDATE usuarios SET pausa_asistencia = 1
         WHERE empresa_id = p_empresa AND activo = 1 AND deleted_at IS NULL
           AND rol_asistencia IS NOT NULL AND rol_asistencia NOT IN ('ADMIN','OPERARIO')
           AND pausa_asistencia = 0
         ORDER BY id DESC
         LIMIT v_exceso;
      END IF;
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

DELIMITER ;

-- -----------------------------------------------------------------------------
-- 4. Una ficha ocupa cupo en Presente al quedar activa y sin pausa, salvo que
--    sea de una cuenta que ya contaba como cuenta (pasa a contar por la ficha).
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_asis_emp_cupo_insert;
DROP TRIGGER IF EXISTS trg_asis_emp_cupo_update;

DELIMITER $$

CREATE TRIGGER trg_asis_emp_cupo_insert
BEFORE INSERT ON asis_empleados
FOR EACH ROW
BEGIN
  IF NEW.activo = 1 AND NEW.en_pausa = 0 AND NOT fn_cuenta_cuenta_en_asistencia(NEW.usuario_id) THEN
    CALL sp_exigir_cupo_app(NEW.empresa_id, 'ASISTENCIA', 'personas');
  END IF;
END$$

CREATE TRIGGER trg_asis_emp_cupo_update
BEFORE UPDATE ON asis_empleados
FOR EACH ROW
BEGIN
  IF NEW.activo = 1 AND NEW.en_pausa = 0 AND NOT (OLD.activo = 1 AND OLD.en_pausa = 0)
     AND NOT fn_cuenta_cuenta_en_asistencia(NEW.usuario_id) THEN
    CALL sp_exigir_cupo_app(NEW.empresa_id, 'ASISTENCIA', 'personas');
  END IF;
END$$

DELIMITER ;
