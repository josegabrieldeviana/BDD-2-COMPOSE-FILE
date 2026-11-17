-- =====================================================================
-- G8 · Avance 4 · Cruce de las claves de MongoDB contra G8_main
-- Se ejecuta después de las tablas temporales que genera
-- cruce_exportar_claves.js (misma sesión). Solo lectura sobre G8_main.
-- =====================================================================

-- Vista de trabajo: una fila por maleta con su ruta, sus fechas y su vuelo
CREATE TEMPORARY TABLE tmp_maleta AS
SELECT m.codigo_etiqueta etiqueta, e.id_pasajero,
       SUBSTRING(r.itinerario_vuelos, 1, 3) ori, SUBSTRING(r.itinerario_vuelos, 5, 3) con,
       SUBSTRING(r.itinerario_vuelos, 13, 3) des,
       m.timestamp_evento ts_checkin, m.timestamp_evento + INTERVAL 180 MINUTE ts_entregado,
       vo.numero_vuelo
FROM movimiento_equipaje m
JOIN equipaje e ON e.id = m.codigo_etiqueta
JOIN reserva_pnr r ON r.id_reserva_pnr = m.id_codigo_pnr
LEFT JOIN segmento_boleto s ON s.boleto_id = m.id_boleto
LEFT JOIN pase_abordaje pa ON pa.id_pase_abordaje = s.id_pase_abordaje
LEFT JOIN asignacion_puerta ap ON ap.id_asignacion = pa.id_asignacion_puerta
LEFT JOIN vuelo_operado vo ON vo.id_vuelo_operado = ap.vuelo_asociado
WHERE m.tipo_evento = 'check_in';
ALTER TABLE tmp_maleta ADD PRIMARY KEY (etiqueta);

SELECT 'A etiquetas de MongoDB que existen en equipaje' AS cruce;
SELECT 'inspecciones' col, COUNT(*) docs, SUM(e.id IS NOT NULL) existe_en_sql FROM tmp_insp t LEFT JOIN equipaje e ON e.id = t.etiqueta UNION ALL
SELECT 'telemetria', COUNT(*), SUM(e.id IS NOT NULL) FROM tmp_tel t LEFT JOIN equipaje e ON e.id = t.etiqueta UNION ALL
SELECT 'notificaciones', COUNT(*), SUM(e.id IS NOT NULL) FROM tmp_not t LEFT JOIN equipaje e ON e.id = t.etiqueta;

SELECT 'B aeropuertos de MongoDB: catalogo, region y si son hub' AS cruce;
SELECT x.aeropuerto, a.region, (h.codigo_base_operaciones IS NOT NULL) es_hub,
       SUM(x.col = 'insp') inspecciones, SUM(x.col = 'tel') telemetria, SUM(x.col = 'mnt') mantenimiento
FROM (SELECT 'insp' col, aeropuerto FROM tmp_insp UNION ALL SELECT 'tel', aeropuerto FROM tmp_tel UNION ALL SELECT 'mnt', aeropuerto FROM tmp_mnt) x
LEFT JOIN aeropuerto a ON a.codigo_aeropuerto = x.aeropuerto
LEFT JOIN hub h ON h.codigo_base_operaciones = x.aeropuerto
GROUP BY x.aeropuerto, a.region, es_hub ORDER BY a.region, x.aeropuerto;

SELECT 'C inspeccion: el aeropuerto del documento frente a la ruta de la maleta' AS cruce;
SELECT CASE WHEN t.aeropuerto = m.ori THEN '1 origen' WHEN t.aeropuerto = m.con THEN '2 conexion'
            WHEN t.aeropuerto = m.des THEN '3 destino' ELSE '4 fuera de la ruta' END donde, COUNT(*) inspecciones
FROM tmp_insp t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta GROUP BY donde ORDER BY donde;

SELECT 'D telemetria: el aeropuerto del documento frente a la ruta de la maleta' AS cruce;
SELECT CASE WHEN t.aeropuerto = m.ori THEN '1 origen' WHEN t.aeropuerto = m.con THEN '2 conexion'
            WHEN t.aeropuerto = m.des THEN '3 destino' ELSE '4 fuera de la ruta' END donde, COUNT(*) lecturas
FROM tmp_tel t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta GROUP BY donde ORDER BY donde;

SELECT 'E fecha del documento frente a los eventos de la maleta en SQL' AS cruce;
-- (tres consultas separadas: MySQL no deja usar dos veces una tabla temporal en la misma consulta)
SELECT 'inspecciones' col, SUM(t.ts BETWEEN m.ts_checkin AND m.ts_entregado) dentro_de_la_ventana,
       SUM(t.ts < m.ts_checkin) antes_del_checkin, SUM(t.ts > m.ts_entregado) despues_de_entregada,
       ROUND(AVG(ABS(TIMESTAMPDIFF(HOUR, m.ts_checkin, t.ts))) / 24, 1) desfase_promedio_dias
FROM tmp_insp t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta;
SELECT 'telemetria' col, SUM(t.ts BETWEEN m.ts_checkin AND m.ts_entregado) dentro_de_la_ventana,
       SUM(t.ts < m.ts_checkin) antes_del_checkin, SUM(t.ts > m.ts_entregado) despues_de_entregada,
       ROUND(AVG(ABS(TIMESTAMPDIFF(HOUR, m.ts_checkin, t.ts))) / 24, 1) desfase_promedio_dias
FROM tmp_tel t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta;
SELECT 'notificaciones (lectura)' col, SUM(t.ts_lectura BETWEEN m.ts_checkin AND m.ts_entregado) dentro_de_la_ventana,
       SUM(t.ts_lectura < m.ts_checkin) antes_del_checkin, SUM(t.ts_lectura > m.ts_entregado) despues_de_entregada,
       ROUND(AVG(ABS(TIMESTAMPDIFF(HOUR, m.ts_checkin, t.ts_lectura))) / 24, 1) desfase_promedio_dias
FROM tmp_not t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta;

SELECT 'F maletas inspeccionadas: cuantas tienen vuelo en SQL' AS cruce;
SELECT COUNT(*) inspecciones, SUM(m.numero_vuelo IS NOT NULL) con_vuelo, SUM(m.numero_vuelo IS NULL) sin_vuelo
FROM tmp_insp t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta;

SELECT 'G notificaciones: el pasajero del documento es el dueno de la maleta' AS cruce;
SELECT COUNT(*) notificaciones, SUM(t.id_pasajero = m.id_pasajero) coincide FROM tmp_not t JOIN tmp_maleta m ON m.etiqueta = t.etiqueta;

SELECT 'H resenas: vuelo y pasajero existen, y el par pasajero-vuelo es real' AS cruce;
SELECT COUNT(*) resenas,
       SUM(EXISTS (SELECT 1 FROM vuelo_operado v WHERE v.numero_vuelo = t.numero_vuelo)) vuelo_existe,
       SUM(EXISTS (SELECT 1 FROM pasajero p WHERE p.id = t.id_pasajero)) pasajero_existe,
       SUM(EXISTS (SELECT 1 FROM boleto b JOIN segmento_boleto s ON s.boleto_id = b.id_boleto
                   JOIN pase_abordaje pa ON pa.id_pase_abordaje = s.id_pase_abordaje
                   JOIN asignacion_puerta ap ON ap.id_asignacion = pa.id_asignacion_puerta
                   JOIN vuelo_operado v ON v.id_vuelo_operado = ap.vuelo_asociado
                   WHERE b.id_pasajero = t.id_pasajero AND v.numero_vuelo = t.numero_vuelo)) par_real_por_boleto,
       SUM(EXISTS (SELECT 1 FROM tmp_maleta m WHERE m.id_pasajero = t.id_pasajero)) pasajero_tiene_maleta,
       MIN(t.espera) espera_min, MAX(t.espera) espera_max, ROUND(AVG(t.espera), 1) espera_prom
FROM tmp_res t;

SELECT 'I cobertura: maletas de SQL con algun documento en MongoDB' AS cruce;
CREATE TEMPORARY TABLE tmp_union AS
SELECT etiqueta, 'insp' col FROM tmp_insp;
INSERT INTO tmp_union SELECT etiqueta, 'tel' FROM tmp_tel;
INSERT INTO tmp_union SELECT etiqueta, 'not' FROM tmp_not;
SELECT (SELECT COUNT(*) FROM tmp_maleta) maletas_sql, COUNT(DISTINCT CASE WHEN col = 'insp' THEN etiqueta END) con_inspeccion,
       COUNT(DISTINCT CASE WHEN col = 'tel' THEN etiqueta END) con_telemetria,
       COUNT(DISTINCT CASE WHEN col = 'not' THEN etiqueta END) con_notificacion,
       COUNT(DISTINCT etiqueta) con_alguno
FROM tmp_union;
