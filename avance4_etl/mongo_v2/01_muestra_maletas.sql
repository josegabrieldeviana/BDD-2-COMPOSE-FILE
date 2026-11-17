-- =====================================================================
-- G8 · Avance 4 · Muestra de maletas del modelo relacional sobre la que se
-- generan los documentos nuevos de MongoDB (solo lectura sobre G8_main).
--
-- Se eligen maletas "sanas" para que cada documento sea coherente con SQL:
--   · la maleta llega a un vuelo (su boleto tiene segmento),
--   · la ruta tiene tres aeropuertos distintos (origen, conexión, destino),
--   · sus tres eventos ya ocurrieron (entrega hasta el 2026-11-10).
-- La muestra es determinista: ordena por MD5 de la etiqueta y toma 3.000.
-- =====================================================================
USE G8_main;
SELECT m.codigo_etiqueta AS etiqueta,
       e.id_pasajero     AS pasajero_maleta,
       b.id_pasajero     AS pasajero_boleto,
       b.clase_servicio  AS clase,
       SUBSTRING(r.itinerario_vuelos, 1, 3)  AS ori,
       SUBSTRING(r.itinerario_vuelos, 5, 3)  AS con,
       SUBSTRING(r.itinerario_vuelos, 13, 3) AS des,
       ao.region AS region_ori, ac.region AS region_con, ad.region AS region_des,
       DATE_FORMAT(m.timestamp_evento, '%Y-%m-%d %H:%i:%s') AS ts_checkin,
       m.peso_kg AS peso_checkin,
       vo.numero_vuelo
FROM movimiento_equipaje m
JOIN equipaje e      ON e.id = m.codigo_etiqueta
JOIN boleto b        ON b.id_boleto = m.id_boleto
JOIN reserva_pnr r   ON r.id_reserva_pnr = m.id_codigo_pnr
JOIN segmento_boleto s    ON s.boleto_id = m.id_boleto
JOIN pase_abordaje pa     ON pa.id_pase_abordaje = s.id_pase_abordaje
JOIN asignacion_puerta ap ON ap.id_asignacion = pa.id_asignacion_puerta
JOIN vuelo_operado vo     ON vo.id_vuelo_operado = ap.vuelo_asociado
JOIN aeropuerto ao ON ao.codigo_aeropuerto = SUBSTRING(r.itinerario_vuelos, 1, 3)
JOIN aeropuerto ac ON ac.codigo_aeropuerto = SUBSTRING(r.itinerario_vuelos, 5, 3)
JOIN aeropuerto ad ON ad.codigo_aeropuerto = SUBSTRING(r.itinerario_vuelos, 13, 3)
WHERE m.tipo_evento = 'check_in'
  AND SUBSTRING(r.itinerario_vuelos, 1, 3) <> SUBSTRING(r.itinerario_vuelos, 5, 3)
  AND SUBSTRING(r.itinerario_vuelos, 5, 3) <> SUBSTRING(r.itinerario_vuelos, 13, 3)
  AND SUBSTRING(r.itinerario_vuelos, 1, 3) <> SUBSTRING(r.itinerario_vuelos, 13, 3)
  AND m.timestamp_evento + INTERVAL 180 MINUTE <= '2026-11-10 23:59:59'
ORDER BY MD5(m.codigo_etiqueta)
LIMIT 3000;
