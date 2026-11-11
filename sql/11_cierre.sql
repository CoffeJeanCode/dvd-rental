-- =====================================================================
-- 11_cierre.sql  -  Cierre de campaña: cancela pendientes y no permite reabrir
-- =====================================================================
SET client_encoding = 'UTF8';
\pset footer off
\set VERBOSITY terse

\echo '--- Antes del cierre'
SELECT k.codigo, m.estado, count(*) FROM campana.mensaje m JOIN campana.campana k USING (campana_id)
GROUP BY 1,2 ORDER BY 1,2;

CALL campana.sp_cerrar_campana('HALLOWEEN-2026-FIELES', 'director.marketing');
CALL campana.sp_cerrar_campana('HALLOWEEN-2026', 'director.marketing');

\echo '--- Después del cierre: todos los pendientes cancelados'
SELECT k.codigo, k.estado AS estado_campana, k.cerrada_por, m.estado, m.motivo_cancelacion, count(*)
FROM campana.mensaje m JOIN campana.campana k USING (campana_id)
GROUP BY 1,2,3,4,5 ORDER BY 1,4,5;
SELECT count(*) AS lista_despacho_restante FROM campana.v_despacho;

\echo '--- Intentos posteriores (todos deben fallar)'
UPDATE campana.campana SET estado = 'HABILITADA' WHERE codigo = 'HALLOWEEN-2026';
UPDATE campana.campana SET nombre = 'Otro nombre' WHERE codigo = 'HALLOWEEN-2026';
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[3]);
CALL campana.sp_cerrar_campana('HALLOWEEN-2026');
DELETE FROM campana.campana WHERE codigo = 'HALLOWEEN-2026';

\echo '--- Evidencia de auditoría del cierre'
SELECT auditoria_id, to_char(ocurrido_en, 'YYYY-MM-DD HH24:MI:SS') AS ocurrido_en, actor, tabla, clave, evento, motivo_cancelacion
FROM campana.v_auditoria WHERE actor = 'director.marketing' ORDER BY auditoria_id;

\echo '--- El modelo original no fue alterado (conteos de public)'
SELECT (SELECT count(*) FROM public.customer) AS customer, (SELECT count(*) FROM public.rental) AS rental,
       (SELECT count(*) FROM public.film_category) AS film_category, (SELECT count(*) FROM public.category) AS category;
