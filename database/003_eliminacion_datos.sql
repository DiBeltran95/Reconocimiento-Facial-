-- ═════════════════════════════════════════════════════════════════════════════
-- 003 · Eliminación con borrado real: versión que incluye Control de Personal
--
-- Redefine los procedimientos de inventario/005 para anonimizar también la
-- ficha de asistencia (nombre, documento, cargo) y apagar los kioscos de una
-- empresa eliminada. Las marcaciones se conservan, sin persona identificable.
--
-- Las FOTOS del rostro son archivos del servidor de Presente, no filas: las
-- borra ese backend al eliminar, y bin/limpiar_fotos.php (tarea diaria) las
-- de fichas anonimizadas desde Ventario. Esas fichas quedan con un documento
-- «ELIM<id>» que las identifica.
-- ═════════════════════════════════════════════════════════════════════════════

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

DROP PROCEDURE IF EXISTS sp_anonimizar_usuario;
DROP PROCEDURE IF EXISTS sp_anonimizar_empresa;

DELIMITER $$

CREATE PROCEDURE sp_anonimizar_usuario(IN p_usuario BIGINT UNSIGNED)
BEGIN
  UPDATE usuarios
     SET nombre             = 'Cuenta eliminada',
         email              = CONCAT('eliminado-', uuid, '@eliminado.invalid'),
         documento          = NULL,
         telefono           = NULL,
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

  -- UPDATE directo y no SELECT … INTO: sin filas, un SELECT INTO lanza
  -- NOT FOUND, que cortaría el cursor de sp_anonimizar_empresa al llamarla.
  UPDATE asis_empleados
     SET nombre = 'Persona eliminada', documento = CONCAT('ELIM', id), cargo = NULL, activo = 0
   WHERE usuario_id = p_usuario;
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

  -- También quienes solo marcaban asistencia (sin cuenta).
  UPDATE asis_empleados
     SET nombre = 'Persona eliminada', documento = CONCAT('ELIM', id), cargo = NULL, activo = 0
   WHERE empresa_id = p_empresa;
  UPDATE asis_dispositivos d JOIN sedes s ON s.id = d.sede_id
     SET d.activo = 0
   WHERE s.empresa_id = p_empresa;
END$$

DELIMITER ;
