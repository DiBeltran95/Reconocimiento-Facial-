-- =============================================================================
--  CONTROL DE PERSONAL · Reconocimiento facial
--  Migración 001 — tablas nuevas sobre `inventarios_db` (MariaDB 11.4)
--
--  Principios:
--   * NO se modifica ninguna tabla existente. Solo se LEEN `sedes`, `usuarios`,
--     `usuario_sedes` y `configuracion` (zona horaria / nombre del negocio).
--   * Datos mínimos: las fotos del rostro viven en disco del servidor (fuera
--     del webroot) y en los teléfonos; la BD nunca guarda imágenes ni vectores.
--   * Todas las horas se guardan en UTC (igual que el resto del sistema);
--     la zona horaria de presentación se lee de configuracion.zona_horaria.
--   * Prefijo `asis_` para no colisionar con el módulo de inventarios.
--
--  Ejecutar una sola vez (phpMyAdmin → SQL, o: mysql inventarios_db < 001_asistencia.sql)
-- =============================================================================

SET NAMES utf8mb4;

-- -----------------------------------------------------------------------------
-- Empleados: identidad mínima + sede a la que pertenecen.
--   * `updated_at` es el reloj de sincronización: cambia al editar al empleado
--     y también cuando se reemplazan sus fotos (lo toca el backend).
--   * Se desactiva (activo = 0) en lugar de borrar, porque sus marcaciones
--     históricas lo referencian. Al desactivarlo el backend borra sus fotos.
--   * `created_at` evita contar como "ausente" a alguien en días anteriores
--     a su vinculación.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `asis_empleados` (
  `id`         INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  `sede_id`    BIGINT UNSIGNED  NOT NULL,
  `documento`  VARCHAR(20)      CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL,
  `nombre`     VARCHAR(120)     NOT NULL,
  `cargo`      VARCHAR(60)      DEFAULT NULL,
  `activo`     TINYINT(1)       NOT NULL DEFAULT 1,
  `created_at` DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_asis_emp_documento` (`documento`),
  KEY `idx_asis_emp_sede` (`sede_id`, `activo`),
  CONSTRAINT `fk_asis_emp_sede` FOREIGN KEY (`sede_id`) REFERENCES `sedes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Asistencia: empleados (las fotos viven en disco, no aquí)';

-- -----------------------------------------------------------------------------
-- Dispositivos (kioscos): cada teléfono/tablet queda amarrado a UNA sede.
--   * Solo se guarda el SHA-256 del token; el token en claro se muestra una
--     única vez al registrar el dispositivo y queda en el almacenamiento
--     seguro del teléfono.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `asis_dispositivos` (
  `id`          SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sede_id`     BIGINT UNSIGNED   NOT NULL,
  `nombre`      VARCHAR(60)       NOT NULL,
  `token_hash`  CHAR(64)          CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL,
  `ultimo_sync` DATETIME          DEFAULT NULL,
  `activo`      TINYINT(1)        NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_asis_disp_token` (`token_hash`),
  KEY `idx_asis_disp_sede` (`sede_id`),
  CONSTRAINT `fk_asis_disp_sede` FOREIGN KEY (`sede_id`) REFERENCES `sedes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Asistencia: kioscos registrados por sede';

-- -----------------------------------------------------------------------------
-- Marcaciones: lo único que se registra en cada llegada/salida.
--   * hora_dispositivo: cuándo ocurrió (reloj del teléfono, UTC). Es la hora
--     "real" aunque la marcación se haya sincronizado horas después (offline).
--   * hora_servidor: cuándo llegó al servidor (UTC_TIMESTAMP()). Sirve como
--     ancla de confianza para detectar relojes manipulados o desfasados.
--   * La llave única (empleado_id, hora_dispositivo) hace que reenviar una
--     marcación offline sea idempotente: nunca se duplica.
--   ~31 bytes por fila: 1.000 empleados × 2 marcas × 365 días ≈ 23 MB/año.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `asis_marcaciones` (
  `id`               BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  `empleado_id`      INT UNSIGNED     NOT NULL,
  `sede_id`          BIGINT UNSIGNED  NOT NULL,
  `tipo`             ENUM('ENTRADA','SALIDA') NOT NULL,
  `hora_dispositivo` DATETIME         NOT NULL,
  `hora_servidor`    DATETIME         NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_asis_marc_empleado_hora` (`empleado_id`, `hora_dispositivo`),
  KEY `idx_asis_marc_sede_hora` (`sede_id`, `hora_dispositivo`),
  CONSTRAINT `fk_asis_marc_empleado` FOREIGN KEY (`empleado_id`) REFERENCES `asis_empleados` (`id`),
  CONSTRAINT `fk_asis_marc_sede`     FOREIGN KEY (`sede_id`)     REFERENCES `sedes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Asistencia: entradas y salidas (horas en UTC)';

-- -----------------------------------------------------------------------------
-- Usuarios de la app de asistencia (independientes del módulo de inventarios).
--   * GENERAL: vincula y opera kioscos en cualquier sede (solo reconocimiento).
--   * ADMINISTRATIVO: personal, horarios, cumplimiento, reportes y usuarios.
--   Los ADMIN / GERENTE existentes en `usuarios` también entran como
--   administrativos (útil para crear las primeras cuentas). Contraseñas argon2id.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `asis_usuarios` (
  `id`            SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `nombre`        VARCHAR(120)      NOT NULL,
  `usuario`       VARCHAR(60)       CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL,
  `password_hash` VARCHAR(255)      NOT NULL,
  `rol`           ENUM('GENERAL','ADMINISTRATIVO') NOT NULL DEFAULT 'GENERAL',
  `activo`        TINYINT(1)        NOT NULL DEFAULT 1,
  `created_at`    DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_asis_usr_usuario` (`usuario`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Asistencia: cuentas General / Administrativo';

-- -----------------------------------------------------------------------------
-- Turnos (plantillas). Un turno = bloques del día + días de la semana.
--   * bloques: 'HH:MM-HH:MM' separados por coma, p. ej. '08:30-12:00,14:00-18:00'
--   * dias: máscara de bits Lun=1, Mar=2, Mié=4, Jue=8, Vie=16, Sáb=32, Dom=64
--           (63 = lunes a sábado, 31 = lunes a viernes)
--   * tolerancia_min: minutos de gracia antes de considerar tardanza.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `asis_horarios` (
  `id`             SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `nombre`         VARCHAR(60)       NOT NULL,
  `bloques`        VARCHAR(120)      CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL,
  `dias`           TINYINT UNSIGNED  NOT NULL DEFAULT 63,
  `tolerancia_min` TINYINT UNSIGNED  NOT NULL DEFAULT 10,
  `activo`         TINYINT(1)        NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Asistencia: turnos reutilizables';

-- -----------------------------------------------------------------------------
-- Rotación semanal por empleado.
--   * desde: lunes en que empieza la rotación.
--   * secuencia: ids de turnos que se alternan cada semana, p. ej. '3,5'
--     → semana 1: turno 3, semana 2: turno 5, semana 3: turno 3…
--   Un cambio de rotación crea una fila nueva con otro `desde`: el historial
--   queda intacto y los reportes pasados siguen siendo correctos.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `asis_rotaciones` (
  `empleado_id` INT UNSIGNED NOT NULL,
  `desde`       DATE         NOT NULL,
  `secuencia`   VARCHAR(60)  CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL,
  PRIMARY KEY (`empleado_id`, `desde`),
  CONSTRAINT `fk_asis_rot_empleado` FOREIGN KEY (`empleado_id`) REFERENCES `asis_empleados` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Asistencia: rotación semanal de turnos';

-- -----------------------------------------------------------------------------
-- Ajuste de UNA semana puntual (reemplazos, vacaciones, cambios de turno).
--   horario_id NULL = esa semana no tiene turno (descanso / vacaciones).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `asis_semanas` (
  `empleado_id` INT UNSIGNED      NOT NULL,
  `semana`      DATE              NOT NULL,
  `horario_id`  SMALLINT UNSIGNED DEFAULT NULL,
  PRIMARY KEY (`empleado_id`, `semana`),
  KEY `idx_asis_sem_horario` (`horario_id`),
  CONSTRAINT `fk_asis_sem_empleado` FOREIGN KEY (`empleado_id`) REFERENCES `asis_empleados` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_asis_sem_horario`  FOREIGN KEY (`horario_id`)  REFERENCES `asis_horarios` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Asistencia: excepciones semanales a la rotación';

-- -----------------------------------------------------------------------------
-- Vista de apoyo (no almacena nada): marcaciones legibles con la hora local.
-- Útil para consultas manuales desde phpMyAdmin. El backend no la necesita.
--   Ej.: SELECT * FROM v_asis_marcaciones WHERE dia = '2026-10-08' AND sede = 'Sede principal';
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `v_asis_marcaciones` AS
SELECT
  m.id,
  s.nombre                                                      AS sede,
  e.documento,
  e.nombre                                                      AS empleado,
  m.tipo,
  DATE(m.hora_dispositivo - INTERVAL 5 HOUR)                    AS dia,
  (m.hora_dispositivo - INTERVAL 5 HOUR)                        AS hora_local,
  (m.hora_servidor    - INTERVAL 5 HOUR)                        AS hora_servidor_local,
  TIMESTAMPDIFF(SECOND, m.hora_dispositivo, m.hora_servidor)    AS desfase_seg
FROM asis_marcaciones m
JOIN asis_empleados e ON e.id = m.empleado_id
JOIN sedes          s ON s.id = m.sede_id;
-- Nota: la vista usa UTC-5 (America/Bogota, sin horario de verano). El backend
-- sí usa la zona de `configuracion.zona_horaria`, así que los reportes de la
-- app y del panel siempre son correctos aunque cambie la zona.
