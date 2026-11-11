-- =====================================================================
-- 00_reset.sql  -  Elimina SOLO los objetos de la actividad (esquema campana).
-- El modelo original (esquema public) no se toca.
-- =====================================================================
DROP SCHEMA IF EXISTS campana CASCADE;
