-- =====================================================================
-- 09d_concurrencia_verificacion.sql  -  Resultado tras las dos sesiones
-- =====================================================================
\pset footer off
\echo '--- Lotes de las sesiones A y B'
SELECT lote_id, actor, sesion_pid, ejecutado_en, n_clientes_distintos, n_mensajes_nuevos,
       n_mensajes_ya_preparados, n_decisiones, conciliado
FROM campana.v_resumen_lote WHERE actor IN ('sesion.A','sesion.B') ORDER BY lote_id;
\echo '--- Decisiones de cada sesión'
SELECT d.lote_id, l.actor, d.customer_id, d.canal, d.motivo, d.mensaje_id
FROM campana.decision d JOIN campana.lote l USING (lote_id)
WHERE l.actor IN ('sesion.A','sesion.B') ORDER BY d.lote_id, d.customer_id, d.canal;
\echo '--- Mensajes de 12..15 (uno por cliente y canal, creados por A o B)'
SELECT m.mensaje_id, m.customer_id, m.canal, m.estado, m.creado_por, m.lote_id
FROM campana.mensaje m WHERE m.campana_id = 1 AND m.customer_id BETWEEN 12 AND 15 ORDER BY 2,3;
\echo '--- Duplicados en toda la tabla (debe dar 0 filas)'
SELECT campana_id, customer_id, canal, count(*) FROM campana.mensaje GROUP BY 1,2,3 HAVING count(*) > 1;
