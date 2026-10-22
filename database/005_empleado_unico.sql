-- =============================================================================
--  CONTROL DE PERSONAL (Presente) · Migración 005 — Un solo registro de empleado
--
--  El empleado se registra una vez (en Presente o en Ventario) y es el mismo en
--  las dos apps. Su ficha guarda también teléfono y correo: con ellos se le
--  crea después una cuenta de acceso (de Presente, de Ventario o de ambas) sin
--  volver a escribir sus datos.
--
--  Cada sentencia tolera haberse aplicado ya.
-- =============================================================================

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE asis_empleados
  ADD COLUMN IF NOT EXISTS telefono VARCHAR(30) NULL AFTER cargo,
  ADD COLUMN IF NOT EXISTS email VARCHAR(191) NULL AFTER telefono;
