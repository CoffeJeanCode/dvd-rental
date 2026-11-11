-- =====================================================================
-- 09a_concurrencia_sesion_A.sql  -  SESIÓN A
-- Abrir dos consolas psql. Ejecutar este script en la sesión A y, durante
-- la pausa de 6 s, ejecutar 09b en la sesión B (el script B espera 2 s solo).
-- A prepara 12,13,14 y mantiene la transacción abierta (sin COMMIT).
-- =====================================================================
\set VERBOSITY terse
\pset footer off
SELECT 'A' AS sesion, pg_backend_pid() AS pid, clock_timestamp() AS inicio;
BEGIN;
CALL campana.sp_preparar_campana('HALLOWEEN-2026', ARRAY[12,13,14], p_actor => 'sesion.A');
SELECT 'A: lote preparado SIN COMMIT; pausa de 6 s' AS paso, clock_timestamp() AS t;
SELECT pg_sleep(6);
COMMIT;
SELECT 'A: COMMIT' AS paso, clock_timestamp() AS t;
