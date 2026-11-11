-- =====================================================================
-- 09c_concurrencia_monitor.sql  -  Observa la espera de B (tercera sesión, t = 4 s)
-- =====================================================================
\pset footer off
SELECT pg_sleep(4);
SELECT pid, state, wait_event_type, wait_event, left(regexp_replace(query, '\s+', ' ', 'g'), 70) AS consulta
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid()
  AND (query ILIKE '%sp_preparar_campana%' OR query ILIKE '%pg_sleep%')
ORDER BY pid;
