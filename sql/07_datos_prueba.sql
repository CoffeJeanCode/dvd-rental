-- =====================================================================
-- 07_datos_prueba.sql  -  Datos de contacto FICTICIOS para pruebas
-- ---------------------------------------------------------------------
-- * NO se usan los correos de public.customer (customer.email): tener un correo
--   no acredita consentimiento ni verificación.
-- * Dominios reservados para pruebas (.example / RFC 2606) y números de prueba.
-- * es_prueba = true; fuente/evidencia marcadas "PRUEBA-FICTICIA".
-- * La autorización ficticia NO representa permiso para un envío real.
-- =====================================================================
SET client_encoding = 'UTF8';
SELECT set_config('campana.actor', 'qa.datos_prueba', false);

INSERT INTO campana.contacto_canal
 (customer_id, canal, destino, autorizado, autorizado_en, fuente_autorizacion,
  verificado, verificado_en, evidencia_verificacion, es_prueba)
VALUES
 -- 1 Mary Smith: solo alquila Sci-Fi (categoría RELACIONADA) -> elegible en ambos
 (1,'EMAIL',   'mary.smith@correo-prueba.example', true, '2026-10-01','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-01','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (1,'WHATSAPP','+57 300 555 0001',                 true, '2026-10-01','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-01','PRUEBA-FICTICIA: OTP simulado', true),
 -- 3 Linda Williams: elegible en ambos canales
 (3,'EMAIL',   'linda.williams@correo-prueba.example', true,'2026-10-01','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-01','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (3,'WHATSAPP','+573005550003',                        true,'2026-10-01','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-01','PRUEBA-FICTICIA: OTP simulado', true),
 -- 4 Barbara Jones: autoriza solo EMAIL; WhatsApp registrado SIN autorización
 (4,'EMAIL',   'barbara.jones@correo-prueba.example', true,'2026-10-02','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-02','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (4,'WHATSAPP','+573005550004',                       false,NULL,NULL,                                                 true,'2026-10-02','PRUEBA-FICTICIA: OTP simulado', true),
 -- 5 Elizabeth Brown: solo WhatsApp (sin registro de correo)
 (5,'WHATSAPP','+573005550005', true,'2026-10-02','PRUEBA-FICTICIA: opt-in simulado', true,'2026-10-02','PRUEBA-FICTICIA: OTP simulado', true),
 -- 7 Maria Miller: (sin filas) -> SIN_CONTACTO en ambos canales
 -- 8 Susan Wilson: correo con formato inválido; WhatsApp autorizado pero no verificado
 (8,'EMAIL',   'susan.wilson@@correo-prueba', true,'2026-10-03','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-03','PRUEBA-FICTICIA: verificación manual simulada', true),
 (8,'WHATSAPP','+573005550008',               true,'2026-10-03','PRUEBA-FICTICIA: opt-in simulado',         false,NULL,NULL, true),
 -- 9 Margaret Moore: ambos canales (escenario de revocación)
 (9,'EMAIL',   'margaret.moore@correo-prueba.example', true,'2026-10-03','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-03','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (9,'WHATSAPP','+573005550009',                        true,'2026-10-03','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-03','PRUEBA-FICTICIA: OTP simulado', true),
 -- 10 Dorothy Taylor: ambos canales (escenario de cambio de destino)
 (10,'EMAIL',   'dorothy.taylor@correo-prueba.example', true,'2026-10-03','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-03','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (10,'WHATSAPP','+573005550010',                        true,'2026-10-03','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-03','PRUEBA-FICTICIA: OTP simulado', true),
 -- 11 Lisa Anderson: ambos canales (escenario de varias categorías coincidentes)
 (11,'EMAIL',   'lisa.anderson@correo-prueba.example', true,'2026-10-04','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-04','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (11,'WHATSAPP','+573005550011',                       true,'2026-10-04','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-04','PRUEBA-FICTICIA: OTP simulado', true),
 -- 12..15: ambos canales (escenario de concurrencia y de mínimo configurable)
 (12,'EMAIL','nancy.thomas@correo-prueba.example', true,'2026-10-04','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-04','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (12,'WHATSAPP','+573005550012',                    true,'2026-10-04','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-04','PRUEBA-FICTICIA: OTP simulado', true),
 (13,'EMAIL','karen.jackson@correo-prueba.example', true,'2026-10-04','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-04','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (13,'WHATSAPP','+573005550013',                     true,'2026-10-04','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-04','PRUEBA-FICTICIA: OTP simulado', true),
 (14,'EMAIL','betty.white@correo-prueba.example',   true,'2026-10-04','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-04','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (14,'WHATSAPP','+573005550014',                     true,'2026-10-04','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-04','PRUEBA-FICTICIA: OTP simulado', true),
 (15,'EMAIL','helen.harris@correo-prueba.example',  true,'2026-10-04','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-04','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (15,'WHATSAPP','+573005550015',                     true,'2026-10-04','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-04','PRUEBA-FICTICIA: OTP simulado', true),
 -- 16 Sandra Martin: cliente INACTIVO (active = 0) con contactos válidos
 (16,'EMAIL','sandra.martin@correo-prueba.example', true,'2026-10-05','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-05','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (16,'WHATSAPP','+573005550016',                     true,'2026-10-05','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-05','PRUEBA-FICTICIA: OTP simulado', true),
 -- 17..19: ambos canales (escenario de error técnico y reversión)
 (17,'EMAIL','donna.thompson@correo-prueba.example', true,'2026-10-05','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-05','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (17,'WHATSAPP','+573005550017',                      true,'2026-10-05','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-05','PRUEBA-FICTICIA: OTP simulado', true),
 (18,'EMAIL','carol.garcia@correo-prueba.example',   true,'2026-10-05','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-05','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (18,'WHATSAPP','+573005550018',                      true,'2026-10-05','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-05','PRUEBA-FICTICIA: OTP simulado', true),
 (19,'EMAIL','ruth.martinez@correo-prueba.example',  true,'2026-10-05','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-05','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (19,'WHATSAPP','+573005550019',                      true,'2026-10-05','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-05','PRUEBA-FICTICIA: OTP simulado', true),
 -- 20 Sharon Robinson: activa, con contactos, pero SIN alquileres de categorías aprobadas
 (20,'EMAIL','sharon.robinson@correo-prueba.example', true,'2026-10-05','PRUEBA-FICTICIA: formulario web simulado', true,'2026-10-05','PRUEBA-FICTICIA: enlace de confirmación simulado', true),
 (20,'WHATSAPP','+573005550020',                       true,'2026-10-05','PRUEBA-FICTICIA: opt-in simulado',         true,'2026-10-05','PRUEBA-FICTICIA: OTP simulado', true);

-- Vista de los datos de prueba con el perfil de cada cliente
SELECT cc.customer_id, initcap(c.first_name||' '||c.last_name) AS cliente, c.active,
       cc.canal, cc.destino, cc.autorizado, cc.verificado, cc.es_prueba,
       campana.fn_destino_valido(cc.canal, cc.destino) AS formato_ok
FROM campana.contacto_canal cc JOIN public.customer c USING (customer_id)
ORDER BY cc.customer_id, cc.canal;
