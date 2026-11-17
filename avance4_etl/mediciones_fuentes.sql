-- =====================================================================
-- G8 · Avance 4 · Mediciones sobre la fuente relacional (solo lectura)
-- Base: G8_main (los datos de la rama main, los mismos 1.400.105 registros
-- que se migraron a PostgreSQL en el Avance 2).
-- Objetivo: saber qué puede cargar el ETL en cada columna del modelo
-- dimensional y cuántos registros afecta cada anomalía.
-- =====================================================================
USE G8_main;

SELECT '01 filas por tabla' AS medicion;
SELECT 'region' t, COUNT(*) n FROM region UNION ALL
SELECT 'aeropuerto', COUNT(*) FROM aeropuerto UNION ALL
SELECT 'hub', COUNT(*) FROM hub UNION ALL
SELECT 'pasajero', COUNT(*) FROM pasajero UNION ALL
SELECT 'vuelo_programado', COUNT(*) FROM vuelo_programado UNION ALL
SELECT 'vuelo_operado', COUNT(*) FROM vuelo_operado UNION ALL
SELECT 'boleto', COUNT(*) FROM boleto UNION ALL
SELECT 'reserva_pnr', COUNT(*) FROM reserva_pnr UNION ALL
SELECT 'equipaje', COUNT(*) FROM equipaje UNION ALL
SELECT 'movimiento_equipaje', COUNT(*) FROM movimiento_equipaje UNION ALL
SELECT 'segmento_boleto', COUNT(*) FROM segmento_boleto UNION ALL
SELECT 'pase_abordaje', COUNT(*) FROM pase_abordaje UNION ALL
SELECT 'asignacion_puerta', COUNT(*) FROM asignacion_puerta;

SELECT '02 eventos por tipo' AS medicion;
SELECT tipo_evento, COUNT(*) n FROM movimiento_equipaje GROUP BY tipo_evento;

SELECT '03 maletas segun cantidad de eventos y si tienen entregado' AS medicion;
SELECT eventos, con_entregado, COUNT(*) maletas FROM (
  SELECT codigo_etiqueta, COUNT(*) eventos, MAX(tipo_evento = 'entregado') con_entregado
  FROM movimiento_equipaje GROUP BY codigo_etiqueta) x
GROUP BY eventos, con_entregado;

SELECT '04 nulos en movimiento_equipaje' AS medicion;
SELECT SUM(codigo_etiqueta IS NULL) etiqueta_nula, SUM(tipo_evento IS NULL) tipo_nulo,
       SUM(timestamp_evento IS NULL) fecha_nula, SUM(peso_kg IS NULL) peso_nulo,
       SUM(id_boleto IS NULL) boleto_nulo, SUM(id_codigo_pnr IS NULL) pnr_nulo
FROM movimiento_equipaje;

SELECT '05 duplicados etiqueta + tipo de evento, y movimientos sin maleta' AS medicion;
SELECT (SELECT COUNT(*) FROM (SELECT 1 FROM movimiento_equipaje GROUP BY codigo_etiqueta, tipo_evento HAVING COUNT(*) > 1) d) AS pares_duplicados,
       (SELECT COUNT(*) FROM movimiento_equipaje m LEFT JOIN equipaje e ON e.id = m.codigo_etiqueta WHERE e.id IS NULL) AS movimientos_sin_maleta,
       (SELECT COUNT(*) FROM equipaje e LEFT JOIN movimiento_equipaje m ON m.codigo_etiqueta = e.id WHERE m.id_movimiento IS NULL) AS maletas_sin_movimiento;

SELECT '06 minutos entre eventos de la misma maleta' AS medicion;
SELECT TIMESTAMPDIFF(MINUTE, ci.timestamp_evento, ca.timestamp_evento) AS checkin_a_cargado,
       TIMESTAMPDIFF(MINUTE, ca.timestamp_evento, en.timestamp_evento) AS cargado_a_entregado,
       COUNT(*) maletas
FROM movimiento_equipaje ci
JOIN movimiento_equipaje ca ON ca.codigo_etiqueta = ci.codigo_etiqueta AND ca.tipo_evento = 'cargado'
JOIN movimiento_equipaje en ON en.codigo_etiqueta = ci.codigo_etiqueta AND en.tipo_evento = 'entregado'
WHERE ci.tipo_evento = 'check_in'
GROUP BY 1, 2;

SELECT '07 peso: rango y maletas cuyo peso cambia entre eventos' AS medicion;
SELECT MIN(peso_kg) peso_min, MAX(peso_kg) peso_max, ROUND(AVG(peso_kg), 2) peso_prom,
       SUM(peso_kg <= 0) pesos_no_positivos, SUM(peso_kg > 32) pesos_sobre_32kg
FROM movimiento_equipaje;
SELECT pesos_distintos, COUNT(*) maletas, ROUND(AVG(diferencia), 2) dif_promedio_kg, MAX(diferencia) dif_max_kg FROM (
  SELECT codigo_etiqueta, COUNT(DISTINCT peso_kg) pesos_distintos, MAX(peso_kg) - MIN(peso_kg) diferencia
  FROM movimiento_equipaje GROUP BY codigo_etiqueta) x
GROUP BY pesos_distintos;

SELECT '08 rango de fechas y fechas futuras (hoy = 2026-11-16)' AS medicion;
SELECT 'movimiento_equipaje' t, MIN(timestamp_evento) desde, MAX(timestamp_evento) hasta,
       SUM(timestamp_evento > '2026-11-16 23:59:59') futuras, COUNT(*) total FROM movimiento_equipaje
UNION ALL
SELECT 'vuelo_operado', MIN(fecha_salida_real), MAX(fecha_llegada_real),
       SUM(fecha_salida_real > '2026-11-16 23:59:59'), COUNT(*) FROM vuelo_operado;

SELECT '09 formato del itinerario de la reserva' AS medicion;
SELECT SUM(itinerario_vuelos IS NULL) nulos,
       SUM(itinerario_vuelos REGEXP '^[A-Z]{3}-[A-Z]{3} [A-Z]{3}-[A-Z]{3}$') formato_esperado,
       SUM(NOT (itinerario_vuelos REGEXP '^[A-Z]{3}-[A-Z]{3} [A-Z]{3}-[A-Z]{3}$')) otro_formato,
       COUNT(*) total
FROM reserva_pnr;

SELECT '10 itinerarios: anomalias de logica (por reserva)' AS medicion;
SELECT COUNT(*) reservas,
       SUM(con1 <> con2) conexion_no_coincide,
       SUM(ori = con1) origen_igual_conexion,
       SUM(con2 = des) conexion_igual_destino,
       SUM(ori = des) origen_igual_destino,
       SUM(ori = con1 OR con2 = des OR ori = des) con_alguna_anomalia,
       SUM(ori NOT IN (SELECT codigo_aeropuerto FROM aeropuerto) OR des NOT IN (SELECT codigo_aeropuerto FROM aeropuerto)
           OR con1 NOT IN (SELECT codigo_aeropuerto FROM aeropuerto)) codigo_fuera_de_catalogo
FROM (SELECT SUBSTRING(itinerario_vuelos, 1, 3) ori, SUBSTRING(itinerario_vuelos, 5, 3) con1,
             SUBSTRING(itinerario_vuelos, 9, 3) con2, SUBSTRING(itinerario_vuelos, 13, 3) des
      FROM reserva_pnr) x;

SELECT '11 lo mismo, por maleta (via movimiento.id_codigo_pnr)' AS medicion;
SELECT COUNT(*) maletas,
       SUM(ori = con1) origen_igual_conexion,
       SUM(con2 = des) conexion_igual_destino,
       SUM(ori = des) origen_igual_destino,
       SUM(ori = con1 OR con2 = des OR ori = des) con_alguna_anomalia,
       SUM(ro.region <> rd.region) cruza_region_origen_destino,
       SUM(ro.region <> rc.region OR rc.region <> rd.region) conexion_entre_regiones
FROM (SELECT m.codigo_etiqueta,
             SUBSTRING(r.itinerario_vuelos, 1, 3) ori, SUBSTRING(r.itinerario_vuelos, 5, 3) con1,
             SUBSTRING(r.itinerario_vuelos, 9, 3) con2, SUBSTRING(r.itinerario_vuelos, 13, 3) des
      FROM movimiento_equipaje m JOIN reserva_pnr r ON r.id_reserva_pnr = m.id_codigo_pnr
      WHERE m.tipo_evento = 'check_in') x
JOIN aeropuerto ro ON ro.codigo_aeropuerto = x.ori
JOIN aeropuerto rc ON rc.codigo_aeropuerto = x.con1
JOIN aeropuerto rd ON rd.codigo_aeropuerto = x.des;

SELECT '12 maleta -> vuelo: cuantas maletas llegan a un vuelo' AS medicion;
SELECT COUNT(*) maletas,
       SUM(s.boleto_id IS NULL) sin_segmento,
       SUM(s.boleto_id IS NOT NULL AND vo.id_vuelo_operado IS NULL) con_segmento_sin_vuelo,
       SUM(vo.id_vuelo_operado IS NOT NULL) con_vuelo
FROM movimiento_equipaje m
LEFT JOIN segmento_boleto s ON s.boleto_id = m.id_boleto
LEFT JOIN pase_abordaje pa ON pa.id_pase_abordaje = s.id_pase_abordaje
LEFT JOIN asignacion_puerta ap ON ap.id_asignacion = pa.id_asignacion_puerta
LEFT JOIN vuelo_operado vo ON vo.id_vuelo_operado = ap.vuelo_asociado
WHERE m.tipo_evento = 'check_in';

SELECT '13 segmentos por boleto (para saber si la union multiplica filas)' AS medicion;
SELECT segmentos, COUNT(*) boletos FROM (SELECT boleto_id, COUNT(*) segmentos FROM segmento_boleto GROUP BY boleto_id) x GROUP BY segmentos;

SELECT '14 entrega de la maleta frente a la llegada real de su vuelo' AS medicion;
SELECT COUNT(*) maletas_con_vuelo,
       SUM(en.timestamp_evento < vo.fecha_llegada_real) entregada_antes_de_llegar,
       SUM(ci.timestamp_evento > vo.fecha_salida_real) checkin_despues_de_salir,
       SUM(TIMESTAMPDIFF(MINUTE, vo.fecha_llegada_real, en.timestamp_evento) BETWEEN 0 AND 180) entrega_0_a_180_min,
       ROUND(AVG(ABS(TIMESTAMPDIFF(HOUR, vo.fecha_llegada_real, en.timestamp_evento))) / 24, 1) desfase_promedio_dias
FROM movimiento_equipaje ci
JOIN movimiento_equipaje en ON en.codigo_etiqueta = ci.codigo_etiqueta AND en.tipo_evento = 'entregado'
JOIN segmento_boleto s ON s.boleto_id = ci.id_boleto
JOIN pase_abordaje pa ON pa.id_pase_abordaje = s.id_pase_abordaje
JOIN asignacion_puerta ap ON ap.id_asignacion = pa.id_asignacion_puerta
JOIN vuelo_operado vo ON vo.id_vuelo_operado = ap.vuelo_asociado
WHERE ci.tipo_evento = 'check_in';

SELECT '15 coherencia de pasajero entre maleta, boleto y reserva' AS medicion;
SELECT COUNT(*) maletas,
       SUM(e.id_pasajero = b.id_pasajero) maleta_igual_boleto,
       SUM(e.id_pasajero = r.id_pasajero) maleta_igual_reserva,
       SUM(b.id_pasajero = r.id_pasajero) boleto_igual_reserva,
       SUM(e.id_pasajero = b.id_pasajero AND b.id_pasajero = r.id_pasajero) los_tres_iguales
FROM movimiento_equipaje m
JOIN equipaje e ON e.id = m.codigo_etiqueta
JOIN boleto b ON b.id_boleto = m.id_boleto
JOIN reserva_pnr r ON r.id_reserva_pnr = m.id_codigo_pnr
WHERE m.tipo_evento = 'check_in';

SELECT '16 estado del boleto con el que viaja la maleta' AS medicion;
SELECT b.estado, b.clase_servicio, COUNT(*) maletas
FROM movimiento_equipaje m JOIN boleto b ON b.id_boleto = m.id_boleto
WHERE m.tipo_evento = 'check_in'
GROUP BY b.estado, b.clase_servicio WITH ROLLUP;

SELECT '17 vuelos: numeros distintos, aerolinea y estados' AS medicion;
SELECT LEFT(numero_vuelo, 2) aerolinea, COUNT(DISTINCT numero_vuelo) numeros_distintos, COUNT(*) vuelos,
       SUM(numero_vuelo NOT REGEXP '^(AA|DL|UA|WN)[0-9]{4}$') formato_invalido,
       SUM(retraso_minutos < 0) retraso_negativo, SUM(fecha_llegada_real < fecha_salida_real) llegada_antes_de_salida
FROM vuelo_operado GROUP BY LEFT(numero_vuelo, 2);
SELECT vp.estado_de_vigencia programado, vo.estado operado, COUNT(*) vuelos
FROM vuelo_programado vp JOIN vuelo_operado vo ON vo.id_vuelo_operado = vp.id_vuelo_programado
GROUP BY 1, 2 ORDER BY 1, 2;

SELECT '18 maletas por pasajero (para peso promedio por pasajero)' AS medicion;
SELECT maletas_del_pasajero, COUNT(*) pasajeros FROM (SELECT id_pasajero, COUNT(*) maletas_del_pasajero FROM equipaje GROUP BY id_pasajero) x
GROUP BY maletas_del_pasajero ORDER BY 1;
