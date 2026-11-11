-- =====================================================================
-- 08_escenarios.sql  -  Demostración de escenarios (ejecutar con ON_ERROR_STOP=0:
-- varios pasos DEBEN fallar y el error es la evidencia esperada).
-- =====================================================================
SET client_encoding = 'UTF8';
\pset footer off
\set VERBOSITY terse

\echo '#####################################################################'
\echo '# E0. FUNCIONES REUTILIZABLES: contratos y resultados'
\echo '#####################################################################'
\echo '--- F1 fn_normalizar_lista: deduplica y ordena'
SELECT campana.fn_normalizar_lista(ARRAY[3,99999,3,1,1]) AS lista_normalizada;
\echo '--- F1 rechaza NULL / vacía / elementos NULL (3 errores esperados)'
SELECT campana.fn_normalizar_lista(NULL);
SELECT campana.fn_normalizar_lista('{}'::integer[]);
SELECT campana.fn_normalizar_lista(ARRAY[3,NULL,4]);
\echo '--- F2 fn_normalizar_canales'
SELECT campana.fn_normalizar_canales(ARRAY[' whatsapp','EMAIL','email']) AS canales;
SELECT campana.fn_normalizar_canales(ARRAY['SMS']);
\echo '--- F5 fn_destino_valido'
SELECT x.canal, x.destino, campana.fn_destino_valido(x.canal, x.destino) AS valido
FROM (VALUES ('EMAIL','ana@correo-prueba.example'), ('EMAIL','susan.wilson@@correo-prueba'),
             ('EMAIL','sin-arroba.example'), ('EMAIL','a..b@correo.example'),
             ('WHATSAPP','+573005550003'), ('WHATSAPP','3005550003'), ('WHATSAPP','+57300ABC')) AS x(canal, destino);
\echo '--- F3/F4 conteo y segmento por cliente (campaña HALLOWEEN-2026)'
SELECT x.id AS customer_id, s.en_segmento, s.motivo, s.alquileres, s.detalle
FROM unnest(ARRAY[1,3,4,16,20,99999]) AS x(id)
CROSS JOIN LATERAL campana.fn_evaluar_segmento(1, x.id) s;
\echo '--- F6 fn_evaluar_canal (canales independientes)'
SELECT x.id AS customer_id, x.canal, e.apto, e.motivo, e.destino
FROM (VALUES (3,'EMAIL'),(3,'WHATSAPP'),(4,'EMAIL'),(4,'WHATSAPP'),(5,'EMAIL'),(7,'EMAIL'),(8,'EMAIL'),(8,'WHATSAPP')) AS x(id, canal)
CROSS JOIN LATERAL campana.fn_evaluar_canal(x.id, x.canal) e;
\echo '--- F7 fn_construir_mensaje (vista previa, no persiste nada)'
SELECT asunto, cuerpo FROM campana.fn_construir_mensaje(1, 3, 'EMAIL', true);
SELECT cuerpo FROM campana.fn_construir_mensaje(1, 3, 'WHATSAPP', true);

\echo '#####################################################################'
\echo '# E1. LOTE PRINCIPAL: ambos canales, un canal, sin contacto, inválido,'
\echo '#     inactivo, historial insuficiente, inexistente, repetidos, Sci-Fi'
\echo '#####################################################################'
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[3,4,5,7,8,16,20,99999,1,3,3,4], p_actor => 'ana.marketing');
SELECT customer_id, cliente, canal, resultado, motivo, alquileres_aprobados AS alq, detalle
FROM campana.v_decisiones WHERE lote_id = (SELECT max(lote_id) FROM campana.lote) ORDER BY customer_id, canal;
\echo '--- Destinatarios preparados del lote'
SELECT mensaje_id, customer_id, cliente, canal, destino, estado, es_prueba
FROM campana.v_destinatarios WHERE lote_id = (SELECT max(lote_id) FROM campana.lote) ORDER BY customer_id, canal;
\echo '--- Resumen del lote (conciliado = true)'
SELECT lote_id, actor, n_ids_recibidos, n_clientes_distintos, n_clientes_segmento, n_mensajes_nuevos,
       n_mensajes_ya_preparados, n_decisiones, n_exclusiones, conciliado
FROM campana.v_resumen_lote WHERE lote_id = (SELECT max(lote_id) FROM campana.lote);

\echo '#####################################################################'
\echo '# E2. EJECUCIÓN REPETIDA: misma lista -> 0 mensajes nuevos, sin duplicados'
\echo '#####################################################################'
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[3,4,5,7,8,16,20,99999,1,3,3,4], p_actor => 'ana.marketing');
SELECT customer_id, canal, resultado, motivo, mensaje_id, detalle
FROM campana.v_decisiones WHERE lote_id = (SELECT max(lote_id) FROM campana.lote) AND resultado = 'INCLUIDO'
ORDER BY customer_id, canal;
SELECT campana_id, customer_id, canal, count(*) AS mensajes
FROM campana.mensaje GROUP BY 1,2,3 HAVING count(*) > 1;   -- 0 filas = sin duplicados

\echo '#####################################################################'
\echo '# E3. VALIDACIÓN DE LA LISTA: rechazos sin registros (4 errores esperados)'
\echo '#####################################################################'
SELECT count(*) AS lotes_antes FROM campana.lote \gset
CALL campana.sp_preparar_campana('HALLOWEEN-2026', NULL);
CALL campana.sp_preparar_campana('HALLOWEEN-2026', '{}'::integer[]);
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[3,NULL]);
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[3], ARRAY['EMAIL','SMS']);
SELECT :lotes_antes AS lotes_antes, count(*) AS lotes_despues FROM campana.lote;
\echo '--- Solicitud de un solo canal: decisiones solo para WHATSAPP'
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[5], ARRAY['whatsapp'], 'ana.marketing');
SELECT customer_id, canal, resultado, motivo FROM campana.v_decisiones
WHERE lote_id = (SELECT max(lote_id) FROM campana.lote);

\echo '#####################################################################'
\echo '# E4. VARIAS CATEGORÍAS COINCIDENTES: un solo conteo por alquiler'
\echo '#     En DVD Rental cada película tiene una sola categoría; para probar la'
\echo '#     regla se agrega TEMPORALMENTE Sci-Fi a una película Horror alquilada'
\echo '#     por el cliente 11, dentro de una transacción que termina en ROLLBACK.'
\echo '#####################################################################'
BEGIN;
SELECT i.film_id AS film_multi FROM public.rental r JOIN public.inventory i USING (inventory_id)
JOIN public.film_category fc USING (film_id) WHERE r.customer_id = 11 AND fc.category_id = 11 LIMIT 1 \gset
INSERT INTO public.film_category (film_id, category_id) VALUES (:film_multi, 14);
SELECT f.film_id, f.title, string_agg(c.name, ', ' ORDER BY c.name) AS categorias
FROM public.film f JOIN public.film_category fc USING (film_id) JOIN public.category c USING (category_id)
WHERE f.film_id = :film_multi GROUP BY 1,2;
\echo '--- Conteo ingenuo con JOIN (multiplica) vs función (no multiplica)'
SELECT count(*) AS conteo_join_ingenuo,
       count(DISTINCT r.rental_id) AS alquileres_distintos,
       campana.fn_contar_alquileres_aprobados(1, 11) AS conteo_funcion
FROM public.rental r JOIN public.inventory i USING (inventory_id)
JOIN public.film_category fc USING (film_id)
JOIN campana.campana_categoria cc ON cc.category_id = fc.category_id AND cc.campana_id = 1
WHERE r.customer_id = 11;
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[11], p_actor => 'ana.marketing');
SELECT customer_id, canal, resultado, motivo, alquileres_aprobados FROM campana.v_decisiones
WHERE lote_id = (SELECT max(lote_id) FROM campana.lote);
ROLLBACK;
SELECT count(*) AS filas_film_category_agregadas_que_persisten
FROM public.film_category WHERE film_id = :film_multi AND category_id = 14;

\echo '#####################################################################'
\echo '# E5. REVOCACIÓN, PÉRDIDA DE VERIFICACIÓN Y CAMBIO DE DESTINO'
\echo '#####################################################################'
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[9,10,11], p_actor => 'ana.marketing');
SELECT mensaje_id, customer_id, canal, destino, estado FROM campana.mensaje WHERE customer_id IN (9,10,11) ORDER BY 2,3;
\echo '--- 9 solicita BAJA por EMAIL (retira autorización) -> solo su EMAIL se cancela'
CALL campana.sp_registrar_baja(9, 'EMAIL', 'soporte.bajas');
\echo '--- 10 cambia su número de WhatsApp -> WhatsApp cancelado; el nuevo destino queda sin verificar'
SELECT set_config('campana.actor', 'soporte.contactos', false);
UPDATE campana.contacto_canal SET destino = '+57 300 555 9910' WHERE customer_id = 10 AND canal = 'WHATSAPP';
\echo '--- 11 pierde la verificación de su correo -> EMAIL cancelado'
UPDATE campana.contacto_canal SET verificado = false WHERE customer_id = 11 AND canal = 'EMAIL';
SELECT set_config('campana.actor', '', false);
SELECT mensaje_id, customer_id, canal, destino, estado, motivo_cancelacion, cancelado_por
FROM campana.mensaje WHERE customer_id IN (9,10,11) ORDER BY 2,3;
SELECT customer_id, canal, destino, autorizado, verificado FROM campana.contacto_canal WHERE customer_id IN (9,10,11) ORDER BY 1,2;
\echo '--- Nueva ejecución: los canales afectados quedan excluidos con su motivo'
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[9,10,11], p_actor => 'ana.marketing');
SELECT customer_id, canal, resultado, motivo, detalle FROM campana.v_decisiones
WHERE lote_id = (SELECT max(lote_id) FROM campana.lote) ORDER BY 1,2;
\echo '--- Se restablecen autorización / verificación -> NO se reactiva (MENSAJE_CANCELADO_PREVIO)'
UPDATE campana.contacto_canal SET autorizado = true, autorizado_en = now(),
       fuente_autorizacion = 'PRUEBA-FICTICIA: nuevo opt-in simulado' WHERE customer_id = 9 AND canal = 'EMAIL';
UPDATE campana.contacto_canal SET verificado = true, verificado_en = now(),
       evidencia_verificacion = 'PRUEBA-FICTICIA: OTP simulado nuevo número' WHERE customer_id = 10 AND canal = 'WHATSAPP';
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[9,10], p_actor => 'ana.marketing');
SELECT customer_id, canal, resultado, motivo, detalle FROM campana.v_decisiones
WHERE lote_id = (SELECT max(lote_id) FROM campana.lote) ORDER BY 1,2;

\echo '#####################################################################'
\echo '# E6. OPERACIONES DIRECTAS rechazadas por triggers / restricciones'
\echo '#     (cada sentencia debe fallar)'
\echo '#####################################################################'
\echo '--- reactivar un mensaje cancelado'
UPDATE campana.mensaje SET estado = 'PENDIENTE' WHERE customer_id = 9 AND canal = 'EMAIL';
\echo '--- alterar el texto de un mensaje'
UPDATE campana.mensaje SET cuerpo = 'Oferta 50% de descuento' WHERE customer_id = 3 AND canal = 'EMAIL';
\echo '--- borrar un mensaje'
DELETE FROM campana.mensaje WHERE customer_id = 3;
\echo '--- insertar directo un mensaje para un cliente sin contacto (7)'
INSERT INTO campana.mensaje (campana_id, customer_id, canal, destino, cuerpo, es_prueba)
VALUES (1, 7, 'EMAIL', 'maria.miller@sakilacustomer.org', 'hola', true);
\echo '--- insertar directo un mensaje para un cliente fuera del segmento (20)'
INSERT INTO campana.mensaje (campana_id, customer_id, canal, destino, cuerpo, es_prueba)
VALUES (1, 20, 'EMAIL', 'sharon.robinson@correo-prueba.example', 'hola', true);
\echo '--- insertar directo un duplicado (3, EMAIL)'
INSERT INTO campana.mensaje (campana_id, customer_id, canal, destino, cuerpo, es_prueba)
VALUES (1, 3, 'EMAIL', 'linda.williams@correo-prueba.example', 'duplicado', true);
\echo '--- cambiar reglas de una campaña HABILITADA'
UPDATE campana.campana SET min_alquileres = 5 WHERE codigo = 'HALLOWEEN-2026';
UPDATE campana.campana SET hist_desde = '2006-01-01' WHERE codigo = 'HALLOWEEN-2026';
\echo '--- cambiar ofertas / categorías de una campaña HABILITADA'
INSERT INTO campana.campana_oferta (campana_id, orden, titulo) VALUES (1, 3, 'Película inventada');
DELETE FROM campana.campana_categoria WHERE campana_id = 1 AND category_id = 14;
\echo '--- volver a PREPARACION'
UPDATE campana.campana SET estado = 'PREPARACION' WHERE codigo = 'HALLOWEEN-2026';
\echo '--- borrar o alterar decisiones / auditoría / lotes'
DELETE FROM campana.decision WHERE customer_id = 99999;
UPDATE campana.auditoria SET actor = 'otro' WHERE auditoria_id = 1;
UPDATE campana.lote SET n_mensajes_nuevos = 0 WHERE lote_id = 1;
TRUNCATE campana.mensaje CASCADE;
\echo '--- mínimo de alquileres inferior a 1 en una campaña nueva'
INSERT INTO campana.campana (codigo, nombre, hist_desde, hist_hasta, vig_desde, vig_hasta, min_alquileres)
VALUES ('X', 'X', '2005-01-01', '2006-01-01', '2026-10-01', '2026-12-01', 0);
\echo '--- categoría distinta de Horror como PRINCIPAL'
BEGIN;
INSERT INTO campana.campana (codigo, nombre, hist_desde, hist_hasta, vig_desde, vig_hasta)
VALUES ('TMP-ACTION', 'Temporal', '2005-01-01', '2006-03-01', '2026-10-01', '2026-12-01');
INSERT INTO campana.campana_categoria (campana_id, category_id, rol, justificacion)
SELECT campana_id, 1, 'PRINCIPAL', 'Acción no equivale a terror' FROM campana.campana WHERE codigo = 'TMP-ACTION';
ROLLBACK;
\echo '--- Verificación: nada cambió'
SELECT estado, count(*) FROM campana.mensaje GROUP BY 1 ORDER BY 1;
SELECT codigo, estado, min_alquileres, hist_desde FROM campana.campana;

\echo '#####################################################################'
\echo '# E7. ERROR TÉCNICO DURANTE EL LOTE -> reversión total'
\echo '#     Se instala un trigger de prueba que simula una falla inesperada al'
\echo '#     registrar la decisión del cliente 19 (después de preparar 17 y 18).'
\echo '#####################################################################'
CREATE FUNCTION campana.tg_prueba_falla() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.customer_id = 19 THEN
        RAISE EXCEPTION 'FALLA TÉCNICA SIMULADA (disco lleno) al registrar cliente %', NEW.customer_id
              USING ERRCODE = '53100';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_prueba_falla BEFORE INSERT ON campana.decision
FOR EACH ROW EXECUTE FUNCTION campana.tg_prueba_falla();

SELECT (SELECT count(*) FROM campana.lote) AS lotes, (SELECT count(*) FROM campana.decision) AS decisiones,
       (SELECT count(*) FROM campana.mensaje) AS mensajes, (SELECT count(*) FROM campana.auditoria) AS auditoria \gset antes_
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[17,18,19], p_actor => 'ana.marketing');
SELECT :antes_lotes AS lotes_antes, (SELECT count(*) FROM campana.lote) AS lotes_despues,
       :antes_decisiones AS decisiones_antes, (SELECT count(*) FROM campana.decision) AS decisiones_despues,
       :antes_mensajes AS mensajes_antes, (SELECT count(*) FROM campana.mensaje) AS mensajes_despues,
       :antes_auditoria AS auditoria_antes, (SELECT count(*) FROM campana.auditoria) AS auditoria_despues;
SELECT count(*) AS mensajes_de_17_18_19 FROM campana.mensaje WHERE customer_id IN (17,18,19);

DROP TRIGGER trg_prueba_falla ON campana.decision;
DROP FUNCTION campana.tg_prueba_falla();
\echo '--- Sin la falla, el mismo lote se completa'
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[17,18,19], p_actor => 'ana.marketing');

\echo '#####################################################################'
\echo '# E8. MÍNIMO CONFIGURABLE: segunda campaña con min_alquileres = 3'
\echo '#####################################################################'
INSERT INTO campana.campana (codigo, nombre, hist_desde, hist_hasta, vig_desde, vig_hasta, min_alquileres)
VALUES ('HALLOWEEN-2026-FIELES', 'Halloween clientes frecuentes', '2005-05-01', '2006-03-01', '2026-10-15', '2026-12-01', 3);
INSERT INTO campana.campana_oferta (campana_id, orden, titulo)
SELECT campana_id, o.orden, o.titulo FROM campana.campana,
       (VALUES (1,'Colony: Zona Cero'), (2,'The Others')) o(orden, titulo) WHERE codigo = 'HALLOWEEN-2026-FIELES';
INSERT INTO campana.campana_categoria (campana_id, category_id, rol, justificacion)
SELECT campana_id, 11, 'PRINCIPAL', 'Categoría de terror del catálogo (Horror)' FROM campana.campana WHERE codigo = 'HALLOWEEN-2026-FIELES';
\echo '--- preparar antes de habilitar: debe fallar'
CALL campana.sp_preparar_campana('HALLOWEEN-2026-FIELES', ARRAY[12]);
CALL campana.sp_habilitar_campana('HALLOWEEN-2026-FIELES', 'marketing.config');
CALL campana.sp_preparar_campana('HALLOWEEN-2026-FIELES', ARRAY[10,12,18], ARRAY['EMAIL'], 'ana.marketing');
SELECT customer_id, canal, resultado, motivo, alquileres_aprobados, detalle FROM campana.v_decisiones
WHERE campana = 'HALLOWEEN-2026-FIELES' ORDER BY 1;
