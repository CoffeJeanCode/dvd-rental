-- =====================================================================
-- 02_funciones.sql  -  Funciones reutilizables
-- ---------------------------------------------------------------------
--  F1 fn_normalizar_lista(int[])                 -> valida y deduplica customer_id
--  F2 fn_normalizar_canales(text[])              -> valida y deduplica canales
--  F3 fn_contar_alquileres_aprobados(camp, cli)  -> conteo sin multiplicación
--  F4 fn_evaluar_segmento(camp, cli)             -> existencia, actividad, historial
--  F5 fn_destino_valido(canal, destino)          -> formato de correo / WhatsApp (E.164)
--  F6 fn_evaluar_canal(cli, canal)               -> contacto, autorización, formato, verificación
--  F7 fn_construir_mensaje(camp, cli, canal)     -> asunto y cuerpo personalizados
--  F8 fn_actor()                                 -> actor responsable para auditoría
-- =====================================================================
SET client_encoding = 'UTF8';

-- F8 ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION campana.fn_actor()
RETURNS text LANGUAGE sql STABLE AS
$$ SELECT coalesce(nullif(current_setting('campana.actor', true), ''), session_user::text) $$;
COMMENT ON FUNCTION campana.fn_actor() IS 'Actor de negocio fijado por el procedimiento (campana.actor) o, en su defecto, el usuario de BD.';

-- F1 ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION campana.fn_normalizar_lista(p_ids integer[])
RETURNS integer[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_ids integer[];
BEGIN
    IF p_ids IS NULL THEN
        RAISE EXCEPTION 'Lista de customer_id obligatoria: se recibió NULL' USING ERRCODE = '22004';
    END IF;
    IF cardinality(p_ids) = 0 THEN
        RAISE EXCEPTION 'Lista de customer_id vacía: debe contener al menos un identificador' USING ERRCODE = '22023';
    END IF;
    IF array_position(p_ids, NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'La lista de customer_id contiene un elemento NULL (posición %)', array_position(p_ids, NULL)
              USING ERRCODE = '22004';
    END IF;
    -- Repetidos se evalúan una sola vez; el orden ascendente fija un orden de bloqueo estable (evita interbloqueos)
    SELECT array_agg(DISTINCT x ORDER BY x) INTO v_ids FROM unnest(p_ids) AS x;
    RETURN v_ids;
END $$;
COMMENT ON FUNCTION campana.fn_normalizar_lista(integer[]) IS
 'Contrato: rechaza NULL, vacía o con elementos NULL (excepción). Devuelve los ids distintos ordenados.';

-- F2 ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION campana.fn_normalizar_canales(p_canales text[])
RETURNS text[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_canales text[];
    v_malo    text;
BEGIN
    IF p_canales IS NULL OR cardinality(p_canales) = 0 THEN
        RAISE EXCEPTION 'Debe solicitarse al menos un canal (EMAIL, WHATSAPP)' USING ERRCODE = '22023';
    END IF;
    IF array_position(p_canales, NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'La lista de canales contiene un elemento NULL' USING ERRCODE = '22004';
    END IF;
    SELECT array_agg(DISTINCT upper(btrim(c)) ORDER BY upper(btrim(c))) INTO v_canales FROM unnest(p_canales) AS c;
    SELECT c INTO v_malo FROM unnest(v_canales) AS c WHERE c NOT IN ('EMAIL','WHATSAPP') LIMIT 1;
    IF v_malo IS NOT NULL THEN
        RAISE EXCEPTION 'Canal no soportado: "%". Canales válidos: EMAIL, WHATSAPP', v_malo USING ERRCODE = '22023';
    END IF;
    RETURN v_canales;
END $$;

-- F3 ------------------------------------------------------------------
-- Relaciones usadas del modelo: rental -> inventory -> film_category -> (campana_categoria)
-- El EXISTS (semi-join) garantiza que un alquiler aporta UNA unidad aunque la película
-- pertenezca a varias categorías aprobadas.
CREATE OR REPLACE FUNCTION campana.fn_contar_alquileres_aprobados(p_campana_id integer, p_customer_id integer)
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT count(*)::integer
    FROM public.rental r
    JOIN campana.campana k ON k.campana_id = p_campana_id
    WHERE r.customer_id = p_customer_id
      AND r.rental_date >= k.hist_desde          -- límite inferior INCLUIDO
      AND r.rental_date <  k.hist_hasta          -- límite superior EXCLUIDO
      AND EXISTS (
            SELECT 1
            FROM public.inventory i
            JOIN public.film_category fc   ON fc.film_id = i.film_id
            JOIN campana.campana_categoria cc ON cc.category_id = fc.category_id
                                             AND cc.campana_id  = p_campana_id
            WHERE i.inventory_id = r.inventory_id)
$$;
COMMENT ON FUNCTION campana.fn_contar_alquileres_aprobados(integer, integer) IS
 'Cuenta alquileres (rental_id) del cliente en [hist_desde, hist_hasta) cuya película tiene al menos una categoría aprobada. Un alquiler = 1 unidad.';

-- F4 ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION campana.fn_evaluar_segmento(p_campana_id integer, p_customer_id integer)
RETURNS TABLE (en_segmento boolean, motivo varchar, alquileres integer, detalle text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    k campana.campana%ROWTYPE;
    c public.customer%ROWTYPE;
    n integer;
BEGIN
    SELECT * INTO k FROM campana.campana WHERE campana_id = p_campana_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Campaña % inexistente', p_campana_id;
    END IF;

    SELECT * INTO c FROM public.customer WHERE customer_id = p_customer_id;
    IF NOT FOUND THEN
        RETURN QUERY SELECT false, 'CLIENTE_INEXISTENTE'::varchar, NULL::integer,
               format('customer_id %s no existe en public.customer', p_customer_id);
        RETURN;
    END IF;

    -- Cliente activo: ambos indicadores del modelo deben estar activos
    IF NOT (c.activebool AND c.active = 1) THEN
        RETURN QUERY SELECT false, 'CLIENTE_INACTIVO'::varchar, NULL::integer,
               format('customer.active=%s, activebool=%s', c.active, c.activebool);
        RETURN;
    END IF;

    n := campana.fn_contar_alquileres_aprobados(p_campana_id, p_customer_id);
    IF n < k.min_alquileres THEN
        RETURN QUERY SELECT false, 'HISTORIAL_INSUFICIENTE'::varchar, n,
               format('%s alquiler(es) de categorías aprobadas en [%s, %s); mínimo requerido %s',
                      n, k.hist_desde, k.hist_hasta, k.min_alquileres);
        RETURN;
    END IF;

    RETURN QUERY SELECT true, NULL::varchar, n,
           format('%s alquiler(es) de categorías aprobadas en [%s, %s); mínimo %s',
                  n, k.hist_desde, k.hist_hasta, k.min_alquileres);
END $$;

-- F5 ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION campana.fn_destino_valido(p_canal text, p_destino text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE upper(p_canal)
        WHEN 'EMAIL' THEN
            p_destino IS NOT NULL
            AND length(p_destino) <= 254
            AND position('..' IN p_destino) = 0
            AND p_destino ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$'
        WHEN 'WHATSAPP' THEN
            -- Formato internacional E.164: + código de país y 8 a 15 dígitos en total
            p_destino IS NOT NULL AND p_destino ~ '^\+[1-9][0-9]{7,14}$'
        ELSE false
    END
$$;

-- F6 ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION campana.fn_evaluar_canal(p_customer_id integer, p_canal text)
RETURNS TABLE (apto boolean, motivo varchar, destino varchar, es_prueba boolean, detalle text)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    r campana.contacto_canal%ROWTYPE;
    v_canal text := upper(btrim(p_canal));
BEGIN
    SELECT * INTO r FROM campana.contacto_canal cc
     WHERE cc.customer_id = p_customer_id AND cc.canal = v_canal;

    IF NOT FOUND OR r.destino IS NULL OR btrim(r.destino) = '' THEN
        RETURN QUERY SELECT false, 'SIN_CONTACTO'::varchar, NULL::varchar, NULL::boolean,
               format('No hay destino registrado para %s', v_canal);
        RETURN;
    END IF;
    IF NOT r.autorizado THEN
        RETURN QUERY SELECT false, 'SIN_AUTORIZACION'::varchar, r.destino, r.es_prueba,
               format('Destino %s registrado sin autorización vigente para %s', r.destino, v_canal);
        RETURN;
    END IF;
    IF NOT campana.fn_destino_valido(v_canal, r.destino) THEN
        RETURN QUERY SELECT false, 'DESTINO_INVALIDO'::varchar, r.destino, r.es_prueba,
               format('El destino "%s" no cumple el formato de %s', r.destino, v_canal);
        RETURN;
    END IF;
    IF NOT r.verificado THEN
        RETURN QUERY SELECT false, 'DESTINO_NO_VERIFICADO'::varchar, r.destino, r.es_prueba,
               format('El destino %s no tiene verificación registrada', r.destino);
        RETURN;
    END IF;

    RETURN QUERY SELECT true, NULL::varchar, r.destino, r.es_prueba,
           format('Autorizado %s (%s); verificado %s (%s)%s',
                  to_char(r.autorizado_en, 'YYYY-MM-DD'), r.fuente_autorizacion,
                  to_char(r.verificado_en, 'YYYY-MM-DD'), r.evidencia_verificacion,
                  CASE WHEN r.es_prueba THEN ' [DATO FICTICIO DE PRUEBA]' ELSE '' END);
END $$;

-- F7 ------------------------------------------------------------------
-- No inventa precios, descuentos ni disponibilidad. Incluye nombre, títulos,
-- identificación de la campaña, vigencia y forma de solicitar la baja.
CREATE OR REPLACE FUNCTION campana.fn_construir_mensaje(p_campana_id integer, p_customer_id integer,
                                                        p_canal text, p_es_prueba boolean DEFAULT true)
RETURNS TABLE (asunto text, cuerpo text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    k        campana.campana%ROWTYPE;
    v_nombre text;
    v_tit    text[];
    v_lista  text;
    v_pref   text := CASE WHEN p_es_prueba THEN '[PRUEBA - DATOS FICTICIOS - NO ENVIAR] ' ELSE '' END;
    v_ref    text;
    v_vig    text;
    v_canal  text := upper(btrim(p_canal));
BEGIN
    SELECT * INTO k FROM campana.campana WHERE campana_id = p_campana_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Campaña % inexistente', p_campana_id; END IF;

    SELECT initcap(btrim(first_name)) || ' ' || initcap(btrim(last_name)) INTO v_nombre
      FROM public.customer WHERE customer_id = p_customer_id;
    IF v_nombre IS NULL THEN RAISE EXCEPTION 'Cliente % inexistente', p_customer_id; END IF;

    SELECT array_agg('«' || o.titulo || '»' ORDER BY o.orden) INTO v_tit
      FROM campana.campana_oferta o WHERE o.campana_id = p_campana_id;
    IF v_tit IS NULL THEN RAISE EXCEPTION 'La campaña % no tiene ofertas', k.codigo; END IF;

    v_lista := CASE WHEN cardinality(v_tit) = 1 THEN v_tit[1]
                    ELSE array_to_string(v_tit[1:cardinality(v_tit) - 1], ', ') || ' y ' || v_tit[cardinality(v_tit)] END;
    v_ref := format('%s/%s/%s', k.codigo, p_customer_id, v_canal);
    v_vig := format('del %s al %s', to_char(k.vig_desde, 'DD/MM/YYYY'), to_char(k.vig_hasta - 1, 'DD/MM/YYYY'));

    IF v_canal = 'EMAIL' THEN
        asunto := v_pref || format('[%s] %s: %s', k.codigo, k.nombre, v_lista);
        cuerpo := v_pref || format(
E'Hola %s:\n\n'
'En DVD Rental preparamos la campaña "%s" (código %s) para clientes que disfrutan del cine de terror '
'y géneros afines. Te invitamos a conocer %s.\n\n'
'Consulta en tu tienda DVD Rental los horarios y condiciones vigentes. Campaña vigente %s.\n\n'
'Si no deseas recibir más mensajes de esta campaña por correo electrónico, responde a este correo con la palabra BAJA.\n'
'Referencia: %s',
            v_nombre, k.nombre, k.codigo, v_lista, v_vig, v_ref);
    ELSIF v_canal = 'WHATSAPP' THEN
        asunto := NULL;
        cuerpo := v_pref || format(
'Hola %s, DVD Rental te invita a la campaña "%s" (%s): %s. '
'Consulta horarios y condiciones en tu tienda. Vigente %s. '
'Responde BAJA para no recibir más mensajes de esta campaña por WhatsApp. Ref: %s',
            v_nombre, k.nombre, k.codigo, v_lista, v_vig, v_ref);
    ELSE
        RAISE EXCEPTION 'Canal no soportado: %', p_canal;
    END IF;
    RETURN NEXT;
END $$;
