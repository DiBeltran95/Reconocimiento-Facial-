-- =============================================================================
--  CONTROL DE PERSONAL (Presente) · Migración 006 — Novedades de los empleados
--
--  Permisos, incapacidades, citas médicas, calamidades, vacaciones y licencias.
--  Las registra el empleado (por ahora, por WhatsApp con el bot de la empresa)
--  y las aprueba o rechaza el gerente o talento humano. Una novedad aprobada
--  justifica la ausencia en los reportes de asistencia.
--
--  Fechas y horas en hora LOCAL de la empresa (no UTC): un permiso «del 3 de
--  noviembre de 8:00 a 12:00» es eso, en la zona de la empresa.
--
--  El soporte (foto de la incapacidad, PDF…) se guarda aquí mismo, en su
--  propia tabla, para que cualquier app de la plataforma pueda mostrarlo. Es
--  un dato de salud (sensible, Ley 1581): solo lo ven talento humano y el
--  administrador.
--
--  Cada sentencia tolera haberse aplicado ya.
-- =============================================================================

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS asis_novedades (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  empresa_id         BIGINT UNSIGNED NOT NULL,
  empleado_id        INT UNSIGNED    NOT NULL,
  tipo               ENUM('PERMISO','INCAPACIDAD','CITA_MEDICA','CALAMIDAD','VACACIONES','LICENCIA','OTRO') NOT NULL,
  fecha_desde        DATE            NOT NULL,
  fecha_hasta        DATE            NOT NULL,
  -- Con horas: un permiso parcial dentro de fecha_desde (fecha_hasta = fecha_desde).
  hora_desde         TIME            NULL,
  hora_hasta         TIME            NULL,
  motivo             VARCHAR(500)    NULL,
  estado             ENUM('PENDIENTE','APROBADA','RECHAZADA','ANULADA') NOT NULL DEFAULT 'PENDIENTE',
  canal              ENUM('WHATSAPP','APP','PANEL') NOT NULL DEFAULT 'WHATSAPP',
  telefono_origen    VARCHAR(30)     NULL,
  resuelto_por       BIGINT UNSIGNED NULL,
  resuelto_en        DATETIME        NULL,
  comentario         VARCHAR(500)    NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_asis_nov_empresa_estado (empresa_id, estado, fecha_desde),
  KEY ix_asis_nov_empleado (empleado_id, fecha_desde),
  CONSTRAINT fk_asis_nov_empresa  FOREIGN KEY (empresa_id)  REFERENCES empresas (id),
  CONSTRAINT fk_asis_nov_empleado FOREIGN KEY (empleado_id) REFERENCES asis_empleados (id),
  CONSTRAINT fk_asis_nov_resuelto FOREIGN KEY (resuelto_por) REFERENCES usuarios (id),
  CONSTRAINT ck_asis_nov_fechas CHECK (fecha_hasta >= fecha_desde),
  CONSTRAINT ck_asis_nov_horas CHECK (
    (hora_desde IS NULL AND hora_hasta IS NULL)
    OR (hora_desde IS NOT NULL AND hora_hasta IS NOT NULL AND hora_hasta > hora_desde AND fecha_hasta = fecha_desde)
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Presente: permisos, incapacidades y demás novedades de los empleados';

CREATE TABLE IF NOT EXISTS asis_novedad_soportes (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  novedad_id   BIGINT UNSIGNED NOT NULL,
  nombre       VARCHAR(160)    NOT NULL,
  mime         VARCHAR(100)    NOT NULL,
  tamano       INT UNSIGNED    NOT NULL,
  contenido    MEDIUMBLOB      NOT NULL,
  created_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_asis_nov_sop_novedad (novedad_id),
  CONSTRAINT fk_asis_nov_sop_novedad FOREIGN KEY (novedad_id) REFERENCES asis_novedades (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Presente: soportes de las novedades (dato sensible: solo talento humano y administrador)';
