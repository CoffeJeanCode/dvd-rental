-- =====================================================================
-- 04_procedimientos.sql  -  Procedimiento principal y procedimientos de ciclo
-- ---------------------------------------------------------------------
--  P1 sp_preparar_campana   : procedimiento principal (lote de preparación)
--  P2 sp_habilitar_campana  : PREPARACION -> HABILITADA
--  P3 sp_cerrar_campana     : -> CERRADA (cancela pendientes vía trigger)
--  P4 sp_registrar_baja     : retira la autorización de un canal (cancela pendientes vía trigger)
-- =====================================================================
SET client_encoding = 'UTF8';

-- P1 ------------------------------------------------------------------
-- Control transaccional: el procedimiento NO hace COMMIT ni captura excepciones.
-- Se ejecuta completo dentro de la transacción del CALL; ante cualquier error
-- (validación o fallo técnico) PostgreSQL revierte TODO el lote: lote, decisiones,
-- mensajes y auditoría. No quedan registros parciales.
CREATE OR REPLACE PROCEDURE campana.sp_preparar_campana(
    IN    p_codigo        text,
    IN    p_customer_ids  integer[],
    IN    p_canales       text[]  DEFAULT ARRAY['EMAIL','WHATSAPP'],
    IN    p_actor         text    DEFAULT NULL,
    INOUT p_lote_id       bigint  DEFAULT NULL,
    INOUT p_resumen       jsonb   DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    k          campana.campana%ROWTYPE;
    v_ids      integer[];
    v_canales  text[];
    v_actor    text := coalesce(nullif(btrim(p_actor), ''), session_user::text);
    v_lote     bigint;
    v_cli      integer;
    v_canal    text;
    s          record;
    ch         record;
    m          record;
    v_msg      bigint;
    v_est_prev text;
    v_res      text;
    v_mot      text;
    v_det      text;
    n_seg      integer := 0;
    n_nuevos   integer := 0;
    n_previos  integer := 0;
    n_dec      integer := 0;
    n_exc      integer := 0;
BEGIN
    -- 1) Validación de entradas (lanza excepción y no registra nada)
    v_ids     := campana.fn_normalizar_lista(p_customer_ids);
    v_canales := campana.fn_normalizar_canales(p_canales);
    IF p_codigo IS NULL OR btrim(p_codigo) = '' THEN
        RAISE EXCEPTION 'El código de campaña es obligatorio';
    END IF;

    PERFORM set_config('campana.actor', v_actor, true);   -- actor para auditoría (local a la transacción)

    -- 2) Campaña: bloqueo compartido -> un cierre concurrente espera a que el lote termine
    SELECT * INTO k FROM campana.campana WHERE codigo = p_codigo FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La campaña % no existe', p_codigo;
    END IF;
    IF k.estado <> 'HABILITADA' THEN
        RAISE EXCEPTION 'La campaña % está en estado %; solo se preparan destinatarios en campañas HABILITADAS', k.codigo, k.estado;
    END IF;
    IF current_date >= k.vig_hasta THEN
        RAISE EXCEPTION 'La vigencia de la campaña % terminó el %', k.codigo, k.vig_hasta - 1;
    END IF;

    -- 3) Bloqueo compartido de los contactos del lote: una revocación o cambio de destino
    --    concurrente espera al final del lote y entonces cancela lo que se haya preparado.
    PERFORM 1 FROM campana.contacto_canal
     WHERE customer_id = ANY (v_ids)
     ORDER BY customer_id, canal
       FOR SHARE;

    -- 4) Lote
    INSERT INTO campana.lote (campana_id, actor, ids_recibidos, canales_solicitados,
                              n_ids_recibidos, n_clientes_distintos)
    VALUES (k.campana_id, v_actor, p_customer_ids, v_canales,
            cardinality(p_customer_ids), cardinality(v_ids))
    RETURNING lote_id INTO v_lote;

    -- 5) Una decisión por cliente distinto y canal distinto solicitado
    FOREACH v_cli IN ARRAY v_ids LOOP
        SELECT * INTO s FROM campana.fn_evaluar_segmento(k.campana_id, v_cli);
        IF s.en_segmento THEN
            n_seg := n_seg + 1;
        END IF;

        FOREACH v_canal IN ARRAY v_canales LOOP
            v_msg := NULL;
            IF NOT s.en_segmento THEN
                v_res := 'EXCLUIDO';  v_mot := s.motivo;  v_det := s.detalle;
            ELSE
                SELECT * INTO ch FROM campana.fn_evaluar_canal(v_cli, v_canal);
                IF NOT ch.apto THEN
                    v_res := 'EXCLUIDO';  v_mot := ch.motivo;  v_det := ch.detalle;
                ELSE
                    SELECT * INTO m FROM campana.fn_construir_mensaje(k.campana_id, v_cli, v_canal, ch.es_prueba);

                    -- Idempotencia + concurrencia: la restricción única decide; si otra sesión
                    -- está insertando la misma clave, esta sentencia espera su COMMIT/ROLLBACK.
                    INSERT INTO campana.mensaje (campana_id, customer_id, canal, destino, asunto, cuerpo, es_prueba, lote_id)
                    VALUES (k.campana_id, v_cli, v_canal, ch.destino, m.asunto, m.cuerpo, ch.es_prueba, v_lote)
                    ON CONFLICT ON CONSTRAINT uq_mensaje_campana_cliente_canal DO NOTHING
                    RETURNING mensaje_id INTO v_msg;

                    IF v_msg IS NOT NULL THEN
                        n_nuevos := n_nuevos + 1;
                        v_res := 'INCLUIDO';  v_mot := 'PREPARADO_NUEVO';  v_det := s.detalle || '. ' || ch.detalle;
                    ELSE
                        SELECT mensaje_id, estado INTO v_msg, v_est_prev
                          FROM campana.mensaje
                         WHERE campana_id = k.campana_id AND customer_id = v_cli AND canal = v_canal;
                        IF v_est_prev = 'PENDIENTE' THEN
                            n_previos := n_previos + 1;
                            v_res := 'INCLUIDO';  v_mot := 'YA_PREPARADO';
                            v_det := format('Mensaje %s ya preparado previamente; no se duplica', v_msg);
                        ELSE
                            v_res := 'EXCLUIDO';  v_mot := 'MENSAJE_CANCELADO_PREVIO';
                            v_det := format('Mensaje %s cancelado; no se reactiva en la misma campaña y canal', v_msg);
                        END IF;
                    END IF;
                END IF;
            END IF;

            INSERT INTO campana.decision (lote_id, campana_id, customer_id, canal, resultado, motivo,
                                          detalle, alquileres_aprobados, mensaje_id)
            VALUES (v_lote, k.campana_id, v_cli, v_canal, v_res, v_mot, v_det, s.alquileres, v_msg);
            n_dec := n_dec + 1;
            IF v_res = 'EXCLUIDO' THEN n_exc := n_exc + 1; END IF;
        END LOOP;
    END LOOP;

    -- 6) Resumen
    UPDATE campana.lote
       SET n_clientes_segmento = n_seg, n_mensajes_nuevos = n_nuevos, n_mensajes_ya_preparados = n_previos,
           n_decisiones = n_dec, n_exclusiones = n_exc, estado = 'COMPLETADO'
     WHERE lote_id = v_lote;

    p_lote_id := v_lote;
    p_resumen := jsonb_build_object(
        'lote_id', v_lote, 'campana', k.codigo, 'actor', v_actor,
        'ids_recibidos', cardinality(p_customer_ids), 'clientes_distintos', cardinality(v_ids),
        'canales', v_canales, 'clientes_segmento', n_seg, 'mensajes_nuevos', n_nuevos,
        'mensajes_ya_preparados', n_previos, 'decisiones', n_dec, 'exclusiones', n_exc);
    RAISE NOTICE 'Lote % completado: %', v_lote, p_resumen;
END $$;

-- P2 ------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE campana.sp_habilitar_campana(p_codigo text, p_actor text DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('campana.actor', coalesce(nullif(btrim(p_actor), ''), session_user::text), true);
    UPDATE campana.campana SET estado = 'HABILITADA' WHERE codigo = p_codigo;
    IF NOT FOUND THEN RAISE EXCEPTION 'La campaña % no existe', p_codigo; END IF;
END $$;

-- P3 ------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE campana.sp_cerrar_campana(p_codigo text, p_actor text DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('campana.actor', coalesce(nullif(btrim(p_actor), ''), session_user::text), true);
    UPDATE campana.campana SET estado = 'CERRADA' WHERE codigo = p_codigo;
    IF NOT FOUND THEN RAISE EXCEPTION 'La campaña % no existe', p_codigo; END IF;
END $$;

-- P4 ------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE campana.sp_registrar_baja(p_customer_id integer, p_canal text, p_actor text DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('campana.actor', coalesce(nullif(btrim(p_actor), ''), session_user::text), true);
    UPDATE campana.contacto_canal
       SET autorizado = false
     WHERE customer_id = p_customer_id AND canal = upper(btrim(p_canal));
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe contacto % para el cliente %', upper(p_canal), p_customer_id;
    END IF;
END $$;
