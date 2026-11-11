-- =====================================================================
-- Campaña de Halloween en DVD Rental
-- 01_esquema.sql  -  Objetos adicionales (tablas, restricciones, catálogo)
-- ---------------------------------------------------------------------
-- Principio de diseño: NO se modifica ninguna tabla ni dato del esquema
-- public (modelo original DVD Rental). Todo lo nuevo vive en el esquema
-- "campana" y solo REFERENCIA (FK) a public.customer y public.category.
-- =====================================================================
SET client_encoding = 'UTF8';
CREATE SCHEMA IF NOT EXISTS campana;
COMMENT ON SCHEMA campana IS 'Objetos de la campaña de marketing de Halloween (actividad PL/pgSQL). No altera el modelo original.';

-- ---------------------------------------------------------------------
-- 1. Campaña: parámetros y ciclo de vida PREPARACION -> HABILITADA -> CERRADA
-- ---------------------------------------------------------------------
CREATE TABLE campana.campana (
    campana_id      serial       PRIMARY KEY,
    codigo          varchar(40)  NOT NULL UNIQUE,
    nombre          varchar(120) NOT NULL,
    estado          varchar(12)  NOT NULL DEFAULT 'PREPARACION'
                    CHECK (estado IN ('PREPARACION','HABILITADA','CERRADA')),
    -- Periodo histórico de alquileres analizado: intervalo semiabierto [hist_desde, hist_hasta)
    hist_desde      timestamp    NOT NULL,
    hist_hasta      timestamp    NOT NULL,
    -- Vigencia promocional (independiente del periodo histórico): [vig_desde, vig_hasta)
    vig_desde       date         NOT NULL,
    vig_hasta       date         NOT NULL,
    -- Mínimo de alquileres de categorías aprobadas (configurable, nunca < 1)
    min_alquileres  integer      NOT NULL DEFAULT 1 CHECK (min_alquileres >= 1),
    creada_en       timestamptz  NOT NULL DEFAULT now(),
    creada_por      text         NOT NULL DEFAULT current_user,
    habilitada_en   timestamptz,
    habilitada_por  text,
    cerrada_en      timestamptz,
    cerrada_por     text,
    CONSTRAINT ck_campana_hist CHECK (hist_desde < hist_hasta),
    CONSTRAINT ck_campana_vig  CHECK (vig_desde  < vig_hasta)
);
COMMENT ON COLUMN campana.campana.hist_desde IS 'Inicio INCLUIDO del periodo histórico de alquileres (rental.rental_date >= hist_desde)';
COMMENT ON COLUMN campana.campana.hist_hasta IS 'Fin EXCLUIDO del periodo histórico de alquileres (rental.rental_date < hist_hasta)';
COMMENT ON COLUMN campana.campana.vig_desde  IS 'Primer día INCLUIDO de la vigencia promocional';
COMMENT ON COLUMN campana.campana.vig_hasta  IS 'Primer día EXCLUIDO de la vigencia promocional (fin de vigencia = vig_hasta - 1)';

-- ---------------------------------------------------------------------
-- 2. Ofertas de la campaña (los títulos promocionales NO se buscan en public.film)
-- ---------------------------------------------------------------------
CREATE TABLE campana.campana_oferta (
    campana_id  integer      NOT NULL REFERENCES campana.campana(campana_id),
    orden       smallint     NOT NULL CHECK (orden > 0),
    titulo      varchar(120) NOT NULL CHECK (btrim(titulo) <> ''),
    PRIMARY KEY (campana_id, orden),
    UNIQUE (campana_id, titulo)
);

-- ---------------------------------------------------------------------
-- 3. Categorías aprobadas (terror + relacionadas, explícitas y justificadas)
-- ---------------------------------------------------------------------
CREATE TABLE campana.campana_categoria (
    campana_id    integer     NOT NULL REFERENCES campana.campana(campana_id),
    category_id   integer     NOT NULL REFERENCES public.category(category_id),
    rol           varchar(12) NOT NULL CHECK (rol IN ('PRINCIPAL','RELACIONADA')),
    justificacion text        NOT NULL CHECK (length(btrim(justificacion)) >= 10),
    PRIMARY KEY (campana_id, category_id)
);

-- ---------------------------------------------------------------------
-- 4. Contacto y autorización por canal (independiente de customer.email)
--    Tener un correo o teléfono NO acredita consentimiento ni verificación.
-- ---------------------------------------------------------------------
CREATE TABLE campana.contacto_canal (
    customer_id            integer      NOT NULL REFERENCES public.customer(customer_id),
    canal                  varchar(10)  NOT NULL CHECK (canal IN ('EMAIL','WHATSAPP')),
    destino                varchar(150),
    autorizado             boolean      NOT NULL DEFAULT false,
    autorizado_en          timestamptz,
    fuente_autorizacion    text,
    verificado             boolean      NOT NULL DEFAULT false,
    verificado_en          timestamptz,
    evidencia_verificacion text,
    es_prueba              boolean      NOT NULL DEFAULT true,
    actualizado_en         timestamptz  NOT NULL DEFAULT now(),
    actualizado_por        text         NOT NULL DEFAULT current_user,
    PRIMARY KEY (customer_id, canal),
    -- Una autorización registrada exige fecha y fuente; una verificación exige fecha y evidencia
    CONSTRAINT ck_contacto_autorizacion CHECK (NOT autorizado OR (autorizado_en IS NOT NULL AND fuente_autorizacion IS NOT NULL)),
    CONSTRAINT ck_contacto_verificacion CHECK (NOT verificado OR (verificado_en IS NOT NULL AND evidencia_verificacion IS NOT NULL))
);
COMMENT ON COLUMN campana.contacto_canal.es_prueba IS 'TRUE = dato ficticio de prueba. Nunca representa permiso para un envío real.';

-- ---------------------------------------------------------------------
-- 5. Catálogo de motivos de decisión (inclusión / exclusión)
-- ---------------------------------------------------------------------
CREATE TABLE campana.motivo (
    codigo      varchar(30) PRIMARY KEY,
    resultado   varchar(8)  NOT NULL CHECK (resultado IN ('INCLUIDO','EXCLUIDO')),
    nivel       varchar(8)  NOT NULL CHECK (nivel IN ('CLIENTE','CANAL')),
    descripcion text        NOT NULL,
    UNIQUE (codigo, resultado)
);
INSERT INTO campana.motivo (codigo, resultado, nivel, descripcion) VALUES
 ('CLIENTE_INEXISTENTE',      'EXCLUIDO','CLIENTE','El customer_id no existe en public.customer'),
 ('CLIENTE_INACTIVO',         'EXCLUIDO','CLIENTE','El cliente no está activo (customer.active <> 1 o activebool = false)'),
 ('HISTORIAL_INSUFICIENTE',   'EXCLUIDO','CLIENTE','Alquileres de categorías aprobadas en el periodo histórico por debajo del mínimo'),
 ('SIN_CONTACTO',             'EXCLUIDO','CANAL',  'No existe destino registrado para el canal'),
 ('SIN_AUTORIZACION',         'EXCLUIDO','CANAL',  'El cliente no tiene autorización (consentimiento) registrada para el canal'),
 ('DESTINO_INVALIDO',         'EXCLUIDO','CANAL',  'El destino registrado no tiene un formato válido para el canal'),
 ('DESTINO_NO_VERIFICADO',    'EXCLUIDO','CANAL',  'El destino no tiene verificación registrada'),
 ('MENSAJE_CANCELADO_PREVIO', 'EXCLUIDO','CANAL',  'Ya existe un mensaje CANCELADO para esta campaña, cliente y canal; no se reactiva automáticamente'),
 ('PREPARADO_NUEVO',          'INCLUIDO','CANAL',  'Cliente del segmento con canal autorizado y verificado: se preparó un mensaje nuevo'),
 ('YA_PREPARADO',             'INCLUIDO','CANAL',  'Cliente del segmento con canal apto: el mensaje ya estaba preparado (no se duplica)');

-- ---------------------------------------------------------------------
-- 6. Mensajes preparados (lista de despacho). Máximo 1 por campaña-cliente-canal.
-- ---------------------------------------------------------------------
CREATE TABLE campana.lote (
    lote_id                  bigserial    PRIMARY KEY,
    campana_id               integer      NOT NULL REFERENCES campana.campana(campana_id),
    ejecutado_en             timestamptz  NOT NULL DEFAULT clock_timestamp(),
    actor                    text         NOT NULL,
    usuario_bd               text         NOT NULL DEFAULT session_user,
    sesion_pid               integer      NOT NULL DEFAULT pg_backend_pid(),
    ids_recibidos            integer[]    NOT NULL,
    canales_solicitados      text[]       NOT NULL,
    n_ids_recibidos          integer,
    n_clientes_distintos     integer,
    n_clientes_segmento      integer,
    n_mensajes_nuevos        integer,
    n_mensajes_ya_preparados integer,
    n_decisiones             integer,
    n_exclusiones            integer,
    estado                   varchar(12)  NOT NULL DEFAULT 'EN_PROCESO' CHECK (estado IN ('EN_PROCESO','COMPLETADO'))
);

CREATE TABLE campana.mensaje (
    mensaje_id          bigserial    PRIMARY KEY,
    campana_id          integer      NOT NULL REFERENCES campana.campana(campana_id),
    customer_id         integer      NOT NULL REFERENCES public.customer(customer_id),
    canal               varchar(10)  NOT NULL CHECK (canal IN ('EMAIL','WHATSAPP')),
    destino             varchar(150) NOT NULL,
    asunto              text,
    cuerpo              text         NOT NULL,
    estado              varchar(10)  NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE','CANCELADO')),
    es_prueba           boolean      NOT NULL,
    lote_id             bigint       REFERENCES campana.lote(lote_id),
    creado_en           timestamptz  NOT NULL DEFAULT clock_timestamp(),
    creado_por          text         NOT NULL DEFAULT current_user,
    motivo_cancelacion  text,
    cancelado_en        timestamptz,
    cancelado_por       text,
    -- Regla 9: como máximo un mensaje por campaña, cliente y canal (también bajo concurrencia)
    CONSTRAINT uq_mensaje_campana_cliente_canal UNIQUE (campana_id, customer_id, canal),
    CONSTRAINT ck_mensaje_cancelacion CHECK ((estado = 'CANCELADO') = (cancelado_en IS NOT NULL))
);
CREATE INDEX ix_mensaje_cliente_canal ON campana.mensaje (customer_id, canal) WHERE estado = 'PENDIENTE';

-- ---------------------------------------------------------------------
-- 7. Decisiones: una por lote, cliente distinto y canal distinto solicitado
-- ---------------------------------------------------------------------
CREATE TABLE campana.decision (
    decision_id          bigserial    PRIMARY KEY,
    lote_id              bigint       NOT NULL REFERENCES campana.lote(lote_id),
    campana_id           integer      NOT NULL REFERENCES campana.campana(campana_id),
    customer_id          integer      NOT NULL,          -- sin FK: debe registrar ids inexistentes
    canal                varchar(10)  NOT NULL CHECK (canal IN ('EMAIL','WHATSAPP')),
    resultado            varchar(8)   NOT NULL,
    motivo               varchar(30)  NOT NULL,
    detalle              text,
    alquileres_aprobados integer,
    mensaje_id           bigint       REFERENCES campana.mensaje(mensaje_id),
    registrado_en        timestamptz  NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_decision_lote_cliente_canal UNIQUE (lote_id, customer_id, canal),
    -- El resultado debe ser coherente con el motivo (FK compuesta al catálogo)
    CONSTRAINT fk_decision_motivo FOREIGN KEY (motivo, resultado) REFERENCES campana.motivo (codigo, resultado)
);
CREATE INDEX ix_decision_cliente ON campana.decision (customer_id, canal);

-- ---------------------------------------------------------------------
-- 8. Auditoría (solo inserción)
-- ---------------------------------------------------------------------
CREATE TABLE campana.auditoria (
    auditoria_id  bigserial   PRIMARY KEY,
    ocurrido_en   timestamptz NOT NULL DEFAULT clock_timestamp(),
    actor         text        NOT NULL,
    usuario_bd    text        NOT NULL DEFAULT session_user,
    tabla         text        NOT NULL,
    operacion     text        NOT NULL,
    clave         text        NOT NULL,
    evento        text        NOT NULL,
    antes         jsonb,
    despues       jsonb
);
CREATE INDEX ix_auditoria_tabla_clave ON campana.auditoria (tabla, clave);
