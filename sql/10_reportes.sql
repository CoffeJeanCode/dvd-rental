-- =====================================================================
-- 10_reportes.sql  -  Resultados esperados (antes del cierre)
-- =====================================================================
SET client_encoding = 'UTF8';
\pset footer off

\echo '##### 1. DESTINATARIOS PREPARADOS - lista de despacho por canal (HALLOWEEN-2026)'
SELECT canal, customer_id, cliente, destino, es_prueba, mensaje_id
FROM campana.v_despacho WHERE campana = 'HALLOWEEN-2026' ORDER BY canal, customer_id;
SELECT canal, count(*) AS pendientes_de_despacho
FROM campana.v_despacho WHERE campana = 'HALLOWEEN-2026' GROUP BY canal ORDER BY canal;

\echo '##### 1b. Todos los mensajes con estado de preparación'
SELECT mensaje_id, campana, customer_id, cliente, canal, destino, estado, motivo_cancelacion
FROM campana.v_destinatarios ORDER BY campana, customer_id, canal;

\echo '##### 2. DECISIONES - estado consolidado (última decisión) por cliente y canal'
SELECT customer_id, cliente, canal, resultado, motivo, estado_mensaje
FROM campana.v_estado_cliente_canal WHERE campana = 'HALLOWEEN-2026' ORDER BY customer_id, canal;

\echo '##### 2b. Exclusiones por motivo (todas las decisiones registradas)'
SELECT campana, resultado, motivo, count(*) AS decisiones
FROM campana.v_decisiones GROUP BY 1,2,3 ORDER BY 1,2,3;

\echo '##### 3. RESUMEN DE EJECUCIONES (conciliación)'
SELECT lote_id, campana, actor, n_ids_recibidos AS recibidos, n_clientes_distintos AS distintos,
       canales_solicitados AS canales, n_clientes_segmento AS segmento, n_mensajes_nuevos AS nuevos,
       n_mensajes_ya_preparados AS ya_prep, n_decisiones AS decisiones, n_exclusiones AS exclusiones, conciliado
FROM campana.v_resumen_lote ORDER BY lote_id;

\echo '##### 4. AUDITORÍA - creación de mensajes y cambios de estado (fecha y actor)'
SELECT auditoria_id, to_char(ocurrido_en, 'YYYY-MM-DD HH24:MI:SS.MS') AS ocurrido_en, actor, tabla, clave, evento,
       estado_antes, estado_despues, motivo_cancelacion
FROM campana.v_auditoria
WHERE evento LIKE 'MENSAJE_%' OR evento LIKE 'CAMPANA_%' OR evento LIKE 'CONTACTO_%'
ORDER BY auditoria_id;
