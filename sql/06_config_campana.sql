-- =====================================================================
-- 06_config_campana.sql  -  Configuración y habilitación de la campaña
-- =====================================================================
SET client_encoding = 'UTF8';
SELECT set_config('campana.actor', 'marketing.config', false);

-- Periodo histórico: [2005-05-01, 2006-03-01) cubre TODO el historial de rental
--   (min rental_date 2005-05-24, max 2006-02-14). No se descartan años anteriores.
-- Vigencia promocional: [2026-10-15, 2026-12-01) -> del estreno de Colony (15/10/2026)
--   hasta el 30/11/2026, incluyendo el re-estreno de The Others (29/10/2026).
-- Mínimo de alquileres: 1 ("una o más películas" según el enunciado).
INSERT INTO campana.campana (codigo, nombre, hist_desde, hist_hasta, vig_desde, vig_hasta, min_alquileres)
VALUES ('HALLOWEEN-2026', 'Halloween en DVD Rental',
        '2005-05-01 00:00:00', '2006-03-01 00:00:00', DATE '2026-10-15', DATE '2026-12-01', 1);

-- Ofertas de campaña (no se buscan en public.film: son títulos promocionales externos)
INSERT INTO campana.campana_oferta (campana_id, orden, titulo)
SELECT campana_id, o.orden, o.titulo
FROM campana.campana,
     (VALUES (1, 'Colony: Zona Cero'), (2, 'The Others')) AS o(orden, titulo)
WHERE codigo = 'HALLOWEEN-2026';

-- Categorías aprobadas
INSERT INTO campana.campana_categoria (campana_id, category_id, rol, justificacion)
SELECT k.campana_id, c.category_id, x.rol, x.justificacion
FROM campana.campana k
JOIN (VALUES
  ('Horror', 'PRINCIPAL',
   'Categoría de terror del catálogo DVD Rental (category.name = Horror). Ambos títulos promocionales tienen Terror como género principal.'),
  ('Sci-Fi', 'RELACIONADA',
   'Colony: Zona Cero es terror de ciencia ficción (virus de mutación biotecnológica e infectados). El público de Sci-Fi comparte el subgénero de horror científico. Es la única categoría del catálogo con ese vínculo temático directo.')
) AS x(nombre, rol, justificacion) ON true
JOIN public.category c ON c.name = x.nombre
WHERE k.codigo = 'HALLOWEEN-2026';

-- Categorías evaluadas y NO aprobadas (documentadas en el informe):
--   Action   : Colony incluye acción, pero es la categoría de público más amplio; incluirla
--              diluiría el segmento de terror (no equivale a terror).
--   Drama    : The Others tiene carga dramática, pero el drama no implica afinidad con terror.
--   Children/Family/Animation: incompatibles con la clasificación +12 / +15 de los títulos.
--   No existen en el catálogo las categorías Suspenso / Misterio / Thriller.

CALL campana.sp_habilitar_campana('HALLOWEEN-2026', 'marketing.config');

SELECT codigo, nombre, estado, hist_desde, hist_hasta, vig_desde, vig_hasta, min_alquileres, habilitada_por
FROM campana.campana;
SELECT o.orden, o.titulo FROM campana.campana_oferta o ORDER BY o.orden;
SELECT cc.category_id, c.name, cc.rol, cc.justificacion
FROM campana.campana_categoria cc JOIN public.category c USING (category_id) ORDER BY cc.rol, c.name;
