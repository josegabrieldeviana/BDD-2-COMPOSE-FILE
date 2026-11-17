-- =====================================================================
-- G8 · Avance 4 · Coherencia de los documentos v2 contra G8_main
-- Se ejecuta en la misma sesión, después de las tablas temporales que
-- genera 04_cruce_exportar.js. Solo lectura sobre G8_main.
-- (MySQL no permite usar dos veces una tabla temporal en la misma consulta;
--  por eso hay tablas intermedias y consultas separadas.)
-- =====================================================================
CREATE TEMPORARY TABLE tmp_maleta AS
SELECT m.codigo_etiqueta etiqueta, e.id_pasajero, m.peso_kg,
       SUBSTRING(r.itinerario_vuelos, 1, 3) ori, SUBSTRING(r.itinerario_vuelos, 5, 3) con,
       SUBSTRING(r.itinerario_vuelos, 13, 3) des,
       m.timestamp_evento ts_checkin, m.timestamp_evento + INTERVAL 90 MINUTE ts_cargado,
       m.timestamp_evento + INTERVAL 180 MINUTE ts_entregado
FROM movimiento_equipaje m
JOIN equipaje e ON e.id = m.codigo_etiqueta
JOIN reserva_pnr r ON r.id_reserva_pnr = m.id_codigo_pnr
WHERE m.tipo_evento = 'check_in';
ALTER TABLE tmp_maleta ADD PRIMARY KEY (etiqueta);

-- Una fila por maleta con sus lecturas de telemetría
CREATE TEMPORARY TABLE tmp_tel_p AS
SELECT etiqueta, COUNT(*) lecturas,
       MAX(CASE WHEN punto = 'FACTURACION'   THEN ts END) t_fact,
       MAX(CASE WHEN punto = 'TRANSFERENCIA' THEN ts END) t_trans,
       MAX(CASE WHEN punto = 'CARRUSEL'      THEN ts END) t_carr,
       MAX(CASE WHEN punto = 'TRANSFERENCIA' THEN desvio END) desvio
FROM tmp_tel GROUP BY etiqueta;
ALTER TABLE tmp_tel_p ADD PRIMARY KEY (etiqueta);

SELECT 'A etiquetas de MongoDB que existen en equipaje' AS cruce;
SELECT 'inspecciones' col, COUNT(*) docs, COUNT(DISTINCT t.etiqueta) maletas, SUM(e.id IS NOT NULL) existe_en_sql FROM tmp_insp t LEFT JOIN equipaje e ON e.id = t.etiqueta;
SELECT 'telemetria' col, COUNT(*) docs, COUNT(DISTINCT t.etiqueta) maletas, SUM(e.id IS NOT NULL) existe_en_sql FROM tmp_tel t LEFT JOIN equipaje e ON e.id = t.etiqueta;
SELECT 'notificaciones' col, COUNT(*) docs, COUNT(DISTINCT t.etiqueta) maletas, SUM(e.id IS NOT NULL) existe_en_sql FROM tmp_not t LEFT JOIN equipaje e ON e.id = t.etiqueta;

SELECT 'B aeropuertos distintos por coleccion y cuantos estan en el catalogo' AS cruce;
SELECT 'inspecciones' col, COUNT(DISTINCT t.aeropuerto) aeropuertos, COUNT(DISTINCT a.codigo_aeropuerto) en_catalogo FROM tmp_insp t LEFT JOIN aeropuerto a ON a.codigo_aeropuerto = t.aeropuerto;
SELECT 'telemetria' col, COUNT(DISTINCT t.aeropuerto) aeropuertos, COUNT(DISTINCT a.codigo_aeropuerto) en_catalogo FROM tmp_tel t LEFT JOIN aeropuerto a ON a.codigo_aeropuerto = t.aeropuerto;
SELECT 'mantenimiento' col, COUNT(DISTINCT t.aeropuerto) aeropuertos, COUNT(DISTINCT a.codigo_aeropuerto) en_catalogo FROM tmp_mnt t LEFT JOIN aeropuerto a ON a.codigo_aeropuerto = t.aeropuerto;

SELECT 'C inspeccion: aeropuerto del documento frente a la ruta de la maleta' AS cruce;
SELECT CASE WHEN t.aeropuerto = m.ori THEN '1 origen' WHEN t.aeropuerto = m.con THEN '2 conexion'
            WHEN t.aeropuerto = m.des THEN '3 destino' ELSE '4 fuera de la ruta' END donde, COUNT(*) inspecciones
FROM tmp_insp t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta GROUP BY donde ORDER BY donde;

SELECT 'D telemetria: punto de control frente a la ruta de la maleta' AS cruce;
SELECT t.punto, SUM(t.aeropuerto = m.ori) en_origen, SUM(t.aeropuerto = m.con) en_conexion, SUM(t.aeropuerto = m.des) en_destino,
       SUM(t.aeropuerto NOT IN (m.ori, m.con, m.des)) fuera_de_la_ruta
FROM tmp_tel t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta GROUP BY t.punto ORDER BY MIN(t.ts - m.ts_checkin);

SELECT 'E fechas de MongoDB dentro de la ventana check-in .. entrega de la maleta' AS cruce;
SELECT 'inspecciones' col, COUNT(*) docs, SUM(t.ts BETWEEN m.ts_checkin AND m.ts_entregado) dentro, MIN(t.ts) desde, MAX(t.ts) hasta FROM tmp_insp t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta;
SELECT 'telemetria' col, COUNT(*) docs, SUM(t.ts BETWEEN m.ts_checkin AND m.ts_entregado) dentro, MIN(t.ts) desde, MAX(t.ts) hasta FROM tmp_tel t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta;
SELECT 'notificaciones (envio)' col, COUNT(*) docs, SUM(t.ts_envio BETWEEN m.ts_checkin AND m.ts_entregado + INTERVAL 30 MINUTE) dentro, MIN(t.ts_envio) desde, MAX(t.ts_envio) hasta FROM tmp_not t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta;

SELECT 'F orden de los hechos: check-in < facturacion < cargado < transferencia < carrusel < entregado' AS cruce;
SELECT COUNT(*) maletas,
       SUM(p.t_fact IS NOT NULL AND p.t_trans IS NOT NULL AND p.t_carr IS NOT NULL) con_las_tres_lecturas,
       SUM(m.ts_checkin < p.t_fact AND p.t_fact < m.ts_cargado AND m.ts_cargado < p.t_trans
           AND p.t_trans < p.t_carr AND p.t_carr < m.ts_entregado) orden_correcto
FROM tmp_tel_p p JOIN tmp_maleta m ON m.etiqueta = p.etiqueta;

SELECT 'G notificaciones: el pasajero del documento es el dueno de la maleta' AS cruce;
SELECT COUNT(*) notificaciones, SUM(t.id_pasajero = m.id_pasajero) coincide FROM tmp_not t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta;

SELECT 'H resenas: el par pasajero-vuelo existe en SQL (por boleto)' AS cruce;
SELECT COUNT(*) resenas,
       SUM(EXISTS (SELECT 1 FROM boleto b JOIN segmento_boleto s ON s.boleto_id = b.id_boleto
                   JOIN pase_abordaje pa ON pa.id_pase_abordaje = s.id_pase_abordaje
                   JOIN asignacion_puerta ap ON ap.id_asignacion = pa.id_asignacion_puerta
                   JOIN vuelo_operado v ON v.id_vuelo_operado = ap.vuelo_asociado
                   WHERE b.id_pasajero = t.id_pasajero AND v.numero_vuelo = t.numero_vuelo)) par_real
FROM tmp_res t;

SELECT 'I maletas con inspeccion, telemetria y notificacion a la vez' AS cruce;
SELECT COUNT(*) maletas_con_telemetria, SUM(i.n IS NOT NULL) con_inspeccion, SUM(n.n IS NOT NULL) con_notificacion,
       SUM(i.n IS NOT NULL AND n.n IS NOT NULL) con_las_tres
FROM tmp_tel_p p
LEFT JOIN (SELECT etiqueta, COUNT(*) n FROM tmp_insp GROUP BY etiqueta) i ON i.etiqueta = p.etiqueta
LEFT JOIN (SELECT etiqueta, COUNT(*) n FROM tmp_not GROUP BY etiqueta) n ON n.etiqueta = p.etiqueta;

SELECT 'J alerta de peso de MongoDB frente al peso del check-in en SQL' AS cruce;
SELECT SUM(m.peso_kg > 23) maletas_sobre_23kg, SUM(t.alerta_peso = 1) con_alerta_peso, SUM((m.peso_kg > 23) = (t.alerta_peso = 1)) coinciden, COUNT(*) lecturas_facturacion
FROM tmp_tel t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta WHERE t.punto = 'FACTURACION';

SELECT 'K adelanto de metricas uniendo SQL y MongoDB, por region de destino' AS cruce;
SELECT a.region region_destino, COUNT(*) maletas,
       ROUND(AVG(TIMESTAMPDIFF(SECOND, m.ts_checkin, p.t_fact)) / 60, 1) transito_origen_min,
       ROUND(AVG(TIMESTAMPDIFF(SECOND, p.t_carr, m.ts_entregado)) / 60, 1) espera_entrega_min,
       ROUND(100 * AVG(TIMESTAMPDIFF(SECOND, p.t_carr, m.ts_entregado) <= 1200), 1) pct_entrega_hasta_20_min,
       ROUND(100 * AVG(p.desvio = 0), 1) pct_transferencia_sin_desvio,
       ROUND(100 * AVG(i.resultado = 'RETENIDO'), 1) pct_retenidas
FROM tmp_tel_p p JOIN tmp_maleta m ON m.etiqueta = p.etiqueta
JOIN aeropuerto a ON a.codigo_aeropuerto = m.des
JOIN tmp_insp i ON i.etiqueta = p.etiqueta
GROUP BY a.region WITH ROLLUP;

SELECT 'L los cinco aeropuertos de conexion con mas desvios y los cinco con menos' AS cruce;
CREATE TEMPORARY TABLE tmp_con AS
SELECT m.con aeropuerto, (h.codigo_base_operaciones IS NOT NULL) es_hub, COUNT(*) maletas, ROUND(100 * AVG(p.desvio = 1), 1) pct_desvio
FROM tmp_tel_p p JOIN tmp_maleta m ON m.etiqueta = p.etiqueta
LEFT JOIN hub h ON h.codigo_base_operaciones = m.con GROUP BY m.con, es_hub;
(SELECT * FROM tmp_con ORDER BY pct_desvio DESC LIMIT 5);
CREATE TEMPORARY TABLE tmp_con2 AS SELECT * FROM tmp_con;
(SELECT * FROM tmp_con2 ORDER BY pct_desvio ASC LIMIT 5);
