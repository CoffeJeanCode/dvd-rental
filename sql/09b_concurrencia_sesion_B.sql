-- =====================================================================
-- 09b_concurrencia_sesion_B.sql  -  SESIÓN B (simultánea con A)
-- B pide 15,14,13,13 (se solapa con A en 13 y 14). Al intentar insertar
-- el mensaje de 13 queda BLOQUEADA por la restricción única hasta que A
-- confirme; entonces ON CONFLICT DO NOTHING la marca como YA_PREPARADO.
-- =====================================================================
\set VERBOSITY terse
\pset footer off
SELECT pg_sleep(2);
SELECT 'B' AS sesion, pg_backend_pid() AS pid, clock_timestamp() AS inicio;
\timing on
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[15,14,13,13], p_actor => 'sesion.B');
\timing off
SELECT 'B: fin' AS paso, clock_timestamp() AS t;
