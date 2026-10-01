-- Datos sintéticos de G8 con los volúmenes del informe:
--   pasajero 100.000 · boleto 200.000 · tarifa 50 · vuelo_programado 50.000 · vuelo_operado 50.000
--   reserva_pnr 100.000 · equipaje 100.000 · movimiento_equipaje 300.000
--   region 3 · aeropuerto 42 · hub 10
-- Es determinista (usa un hash MD5 en lugar de RAND()): siempre genera exactamente los mismos datos.
--
-- Reglas de coherencia:
--   * Ningún evento de un boleto es anterior a su emisión, y los USADO viajaron antes de hoy (2026-09-30).
--   * tarifa_base es el precio de la tarifa del boleto, y la tarifa corresponde a su clase (Y, J, F).
--   * Los vuelos aterrizan después de despegar, y todos los vuelos operados ya ocurrieron.
--   * Solo los boletos USADO tienen equipaje, y la maleta es del pasajero del boleto.
--   * Cada maleta tiene 3 eventos en orden cronológico; el registro es antes del embarque.
--   * El PNR de cada movimiento es la reserva del mismo pasajero.

SET @hoy := DATE('2026-09-30');
SET @aeropuertos := 'CLT,PHL,JFK,LGA,DCA,MIA,BOS,EWR,BWI,IAD,PIT,RDU,ATL,MCO,DFW,ORD,MSP,DTW,CLE,STL,MCI,MSY,IAH,AUS,SAT,MEM,BNA,MDW,PHX,LAX,SFO,SAN,LAS,SEA,PDX,SLC,DEN,ABQ,TUS,SJC,SNA,OAK';

-- Número pseudoaleatorio de 32 bits a partir de un texto. MD5 da valores independientes entre sí
-- (con CRC32, que es lineal, los valores de una misma fila quedaban relacionados).
CREATE FUNCTION aux_hash(texto VARCHAR(100)) RETURNS BIGINT UNSIGNED DETERMINISTIC NO SQL
    RETURN CAST(CONV(LEFT(MD5(texto), 8), 16, 10) AS UNSIGNED);

-- Números auxiliares del 1 al 1.000.000
CREATE TABLE aux_digitos (v INT PRIMARY KEY);
INSERT INTO aux_digitos VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9);
CREATE TABLE aux_numeros (n INT PRIMARY KEY);
INSERT INTO aux_numeros
SELECT 1 + a.v + 10 * b.v + 100 * c.v + 1000 * d.v + 10000 * e.v + 100000 * f.v
FROM aux_digitos a, aux_digitos b, aux_digitos c, aux_digitos d, aux_digitos e, aux_digitos f;

-- ---------------------------------------------------------------- Tablas comunes
INSERT INTO region VALUES ('ESTE'), ('CENTRAL'), ('OESTE');

INSERT INTO aeropuerto (codigo_aeropuerto, region)
SELECT SUBSTRING(@aeropuertos, 4 * (n - 1) + 1, 3),
       CASE WHEN n <= 14 THEN 'ESTE' WHEN n <= 28 THEN 'CENTRAL' ELSE 'OESTE' END
FROM aux_numeros
WHERE n <= 42;

INSERT INTO hub VALUES
  ('CLT', 'ESTE'), ('PHL', 'ESTE'), ('JFK', 'ESTE'), ('LGA', 'ESTE'), ('DCA', 'ESTE'), ('MIA', 'ESTE'),
  ('DFW', 'CENTRAL'), ('ORD', 'CENTRAL'), ('PHX', 'OESTE'), ('LAX', 'OESTE');

-- ---------------------------------------------------------------- Pasajeros y tarifas
INSERT INTO pasajero (id)
SELECT n FROM aux_numeros WHERE n <= 100000;

-- Tarifas 1-30: clase Y (100 a 600) · 31-42: clase J (800 a 2.500) · 43-50: clase F (2.500 a 6.000)
INSERT INTO tarifa (id, precio)
SELECT n,
       CASE WHEN n <= 30 THEN ROUND(100 + (aux_hash(CONCAT('tar:', n)) % 50001) / 100, 2)
            WHEN n <= 42 THEN ROUND(800 + (aux_hash(CONCAT('tar:', n)) % 170001) / 100, 2)
            ELSE ROUND(2500 + (aux_hash(CONCAT('tar:', n)) % 350001) / 100, 2) END
FROM aux_numeros
WHERE n <= 50;

-- ---------------------------------------------------------------- Boletos
-- Emitidos entre el 01/10/2025 y el 25/09/2026; el viaje es de 1 a 60 días después de la emisión.
INSERT INTO boleto (id_boleto, id_pasajero, numero_boleto, fecha_emision, tarifa_base,
                    clase_servicio, estado, timestamp_evento_boleto, id_tarifa)
SELECT b.id_boleto,
       b.id_pasajero,
       CONCAT('001', LPAD(1200000000 + b.id_boleto * 37 + aux_hash(CONCAT('nb:', b.id_boleto)) % 37, 10, '0')),
       b.fecha_emision,
       t.precio,
       b.clase,
       b.estado,
       CASE b.estado
            WHEN 'USADO'   THEN TIMESTAMP(b.fecha_viaje) + INTERVAL b.minuto_viaje MINUTE
            WHEN 'EMITIDO' THEN TIMESTAMP(b.fecha_emision) + INTERVAL b.minuto_emision MINUTE
            ELSE TIMESTAMP(b.fecha_emision + INTERVAL (b.r_cambio % b.max_dias_cambio) DAY) + INTERVAL b.minuto_emision MINUTE
       END,
       b.id_tarifa
FROM (
    SELECT y.*,
           y.fecha_emision + INTERVAL y.dias_hasta_viaje DAY AS fecha_viaje,
           CASE WHEN y.fecha_emision + INTERVAL y.dias_hasta_viaje DAY < @hoy
                THEN CASE WHEN y.r_estado < 85 THEN 'USADO' WHEN y.r_estado < 95 THEN 'CANCELADO' ELSE 'REEMBOLSADO' END
                ELSE CASE WHEN y.r_estado < 90 THEN 'EMITIDO' ELSE 'CANCELADO' END
           END AS estado,
           LEAST(y.dias_hasta_viaje, DATEDIFF(@hoy, y.fecha_emision)) AS max_dias_cambio,
           CASE y.clase WHEN 'Y' THEN 1 + y.r_tarifa % 30
                        WHEN 'J' THEN 31 + y.r_tarifa % 12
                        ELSE 43 + y.r_tarifa % 8 END AS id_tarifa
    FROM (
        SELECT n AS id_boleto,
               1 + aux_hash(CONCAT('pas:', n)) % 100000 AS id_pasajero,
               CASE WHEN aux_hash(CONCAT('cls:', n)) % 100 < 75 THEN 'Y'
                    WHEN aux_hash(CONCAT('cls:', n)) % 100 < 95 THEN 'J' ELSE 'F' END AS clase,
               DATE('2025-10-01') + INTERVAL (aux_hash(CONCAT('emi:', n)) % 360) DAY AS fecha_emision,
               1 + aux_hash(CONCAT('via:', n)) % 60 AS dias_hasta_viaje,
               aux_hash(CONCAT('est:', n)) % 100 AS r_estado,
               aux_hash(CONCAT('tar:', n)) AS r_tarifa,
               aux_hash(CONCAT('cam:', n)) AS r_cambio,
               300 + aux_hash(CONCAT('hvi:', n)) % 960 AS minuto_viaje,
               aux_hash(CONCAT('hem:', n)) % 1440 AS minuto_emision
        FROM aux_numeros
        WHERE n <= 200000
    ) y
) b
JOIN tarifa t ON t.id = b.id_tarifa;

-- ---------------------------------------------------------------- Vuelos
-- Salidas entre el 01/10/2025 y el 28/09/2026 (todas ya ocurrieron); duran de 1 a 6 horas.
INSERT INTO vuelo_programado (id_vuelo_programado, fecha_salida, fecha_llegada, retraso_minutos, estado_de_vigencia)
SELECT v.n, v.salida, v.salida + INTERVAL v.duracion MINUTE, v.retraso, 'aterrizado'
FROM (
    SELECT n,
           TIMESTAMP('2025-10-01') + INTERVAL (aux_hash(CONCAT('vsal:', n)) % (363 * 1440)) MINUTE AS salida,
           60 + aux_hash(CONCAT('vdur:', n)) % 301 AS duracion,
           CASE WHEN aux_hash(CONCAT('vret:', n)) % 100 < 70 THEN 0
                WHEN aux_hash(CONCAT('vret:', n)) % 100 < 90 THEN 5 + aux_hash(CONCAT('vre2:', n)) % 56
                ELSE 61 + aux_hash(CONCAT('vre2:', n)) % 180 END AS retraso
    FROM aux_numeros
    WHERE n <= 50000
) v;

-- Unos 800 números de vuelo distintos (AA1000 a AA1799), unas 62 salidas por número
INSERT INTO vuelo_operado (id_vuelo_operado, numero_vuelo, fecha_salida_real, fecha_llegada_real, retraso_minutos, estado)
SELECT id_vuelo_programado,
       CONCAT('AA', 1000 + aux_hash(CONCAT('nvu:', id_vuelo_programado)) % 800),
       fecha_salida + INTERVAL retraso_minutos MINUTE,
       fecha_llegada + INTERVAL retraso_minutos MINUTE,
       retraso_minutos,
       IF(retraso_minutos = 0, 'A_TIEMPO', 'RETRASADO')
FROM vuelo_programado;

-- ---------------------------------------------------------------- Reservas (una por pasajero)
INSERT INTO reserva_pnr (id_reserva_pnr, id_pasajero, itinerario_vuelos, info_contacto,
                         pnr_fecha_de_emision, ente_realizador_de_reserva)
SELECT r.n,
       r.n,
       CONCAT_WS('; ',
           CONCAT('AA', 1000 + aux_hash(CONCAT('pv1:', r.n)) % 800, ' ',
                  SUBSTRING(@aeropuertos, 4 * (r.x1 % 42) + 1, 3), '-',
                  SUBSTRING(@aeropuertos, 4 * ((r.x1 + r.x2) % 42) + 1, 3), ' ',
                  DATE_FORMAT(r.primer_vuelo, '%Y-%m-%d')),
           IF(r.tramos >= 2,
              CONCAT('AA', 1000 + aux_hash(CONCAT('pv2:', r.n)) % 800, ' ',
                     SUBSTRING(@aeropuertos, 4 * ((r.x1 + r.x2) % 42) + 1, 3), '-',
                     SUBSTRING(@aeropuertos, 4 * ((r.x1 + r.x2 + r.x3) % 42) + 1, 3), ' ',
                     DATE_FORMAT(r.primer_vuelo + INTERVAL 1 DAY, '%Y-%m-%d')), NULL),
           IF(r.tramos >= 3,
              CONCAT('AA', 1000 + aux_hash(CONCAT('pv3:', r.n)) % 800, ' ',
                     SUBSTRING(@aeropuertos, 4 * ((r.x1 + r.x2 + r.x3) % 42) + 1, 3), '-',
                     SUBSTRING(@aeropuertos, 4 * ((r.x1 + r.x2 + r.x3 + r.x4) % 42) + 1, 3), ' ',
                     DATE_FORMAT(r.primer_vuelo + INTERVAL 2 DAY, '%Y-%m-%d')), NULL)),
       CONCAT(r.nombre, ' ', r.apellido, '; ', LOWER(r.nombre), '.', LOWER(r.apellido), r.n % 97, '@',
              ELT(1 + aux_hash(CONCAT('dom:', r.n)) % 4, 'gmail.com', 'hotmail.com', 'yahoo.com', 'outlook.com'),
              '; +1-', ELT(1 + aux_hash(CONCAT('tel:', r.n)) % 6, '305', '212', '214', '312', '602', '213'),
              '-555-', LPAD(r.n % 10000, 4, '0')),
       r.emision,
       ELT(1 + aux_hash(CONCAT('ent:', r.n)) % 5, 'WEB', 'APP MOVIL', 'AGENCIA DE VIAJES', 'CALL CENTER', 'MOSTRADOR AEROPUERTO')
FROM (
    SELECT n,
           1 + aux_hash(CONCAT('tra:', n)) % 3 AS tramos,
           aux_hash(CONCAT('a1:', n)) % 42 AS x1,
           1 + aux_hash(CONCAT('a2:', n)) % 41 AS x2,
           1 + aux_hash(CONCAT('a3:', n)) % 41 AS x3,
           1 + aux_hash(CONCAT('a4:', n)) % 41 AS x4,
           ELT(1 + aux_hash(CONCAT('nom:', n)) % 12, 'Sofia', 'Mateo', 'Valentina', 'Santiago', 'Isabella', 'Sebastian',
               'Camila', 'Diego', 'Lucia', 'Daniel', 'Mariana', 'Gabriel') AS nombre,
           ELT(1 + aux_hash(CONCAT('ape:', n)) % 12, 'Diaz', 'Garcia', 'Rodriguez', 'Martinez', 'Lopez', 'Gonzalez',
               'Perez', 'Sanchez', 'Ramirez', 'Torres', 'Flores', 'Rivera') AS apellido,
           TIMESTAMP('2025-09-01') + INTERVAL (aux_hash(CONCAT('pem:', n)) % (390 * 1440)) MINUTE AS emision,
           DATE(TIMESTAMP('2025-09-01') + INTERVAL (aux_hash(CONCAT('pem:', n)) % (390 * 1440)) MINUTE)
             + INTERVAL (1 + aux_hash(CONCAT('pvf:', n)) % 60) DAY AS primer_vuelo
    FROM aux_numeros
    WHERE n <= 100000
) r;

-- ---------------------------------------------------------------- Equipaje
-- Unos 60.000 boletos USADO llevan de 1 a 3 maletas; se toman exactamente 100.000 maletas.
-- Etiqueta de 10 dígitos: 0 + código de AA (001) + serial de 6 dígitos.
CREATE TEMPORARY TABLE tmp_maleta AS
SELECT CONCAT('0001', LPAD(ROW_NUMBER() OVER (ORDER BY x.orden, x.id_boleto, x.k), 6, '0')) AS id_maleta,
       x.id_boleto, x.id_pasajero, x.t_registro, x.peso_kg, x.flujo
FROM (
    SELECT b.id_boleto, b.id_pasajero, k.k,
           aux_hash(CONCAT('ord:', b.id_boleto, ':', k.k)) AS orden,
           b.timestamp_evento_boleto - INTERVAL (60 + aux_hash(CONCAT('chk:', b.id_boleto)) % 61) MINUTE AS t_registro,
           ROUND(5 + (aux_hash(CONCAT('peso:', b.id_boleto, ':', k.k)) % 2701) / 100, 2) AS peso_kg,
           CASE WHEN aux_hash(CONCAT('flujo:', b.id_boleto, ':', k.k)) % 100 < 4
                     AND b.timestamp_evento_boleto < '2026-09-26' THEN 'EXTRAVIADO'
                WHEN aux_hash(CONCAT('flujo:', b.id_boleto, ':', k.k)) % 100 < 7 THEN 'DANADO'
                ELSE 'NORMAL' END AS flujo
    FROM boleto b
    JOIN (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3) k
      ON k.k <= CASE WHEN aux_hash(CONCAT('nmal:', b.id_boleto)) % 100 < 50 THEN 1
                     WHEN aux_hash(CONCAT('nmal:', b.id_boleto)) % 100 < 83 THEN 2
                     ELSE 3 END
    WHERE b.estado = 'USADO'
      AND aux_hash(CONCAT('conmal:', b.id_boleto)) % 100 < 40
    ORDER BY orden, b.id_boleto, k.k
    LIMIT 100000
) x;

INSERT INTO equipaje (id, id_pasajero)
SELECT id_maleta, id_pasajero FROM tmp_maleta;

-- Tres eventos por maleta, en minutos desde el registro (rangos que no se solapan)
CREATE TEMPORARY TABLE tmp_plantilla (
    flujo       VARCHAR(12),
    paso        INT,
    tipo_evento VARCHAR(20),
    min_desde   INT,
    max_desde   INT
);
INSERT INTO tmp_plantilla VALUES
  ('NORMAL',     1, 'REGISTRADO',    0,    0),
  ('NORMAL',     2, 'CARGADO',      40,  100),
  ('NORMAL',     3, 'ENTREGADO',   240,  540),
  ('EXTRAVIADO', 1, 'REGISTRADO',    0,    0),
  ('EXTRAVIADO', 2, 'EXTRAVIADO',  240,  540),
  ('EXTRAVIADO', 3, 'ENTREGADO',  1440, 4320),
  ('DANADO',     1, 'REGISTRADO',    0,    0),
  ('DANADO',     2, 'DANADO',      240,  480),
  ('DANADO',     3, 'ENTREGADO',   490,  560);

INSERT INTO movimiento_equipaje
  (id_movimiento, codigo_etiqueta, tipo_evento, timestamp_evento, peso_kg, id_boleto, id_codigo_pnr)
SELECT ROW_NUMBER() OVER (ORDER BY x.ts, x.id_maleta, x.paso),
       x.id_maleta, x.tipo_evento, x.ts, x.peso_kg, x.id_boleto, x.id_pasajero
FROM (
    SELECT mt.id_maleta, p.paso, p.tipo_evento, mt.peso_kg, mt.id_boleto, mt.id_pasajero,
           mt.t_registro + INTERVAL (p.min_desde
               + aux_hash(CONCAT('min:', mt.id_maleta, ':', p.paso)) % (p.max_desde - p.min_desde + 1)) MINUTE AS ts
    FROM tmp_maleta mt
    JOIN tmp_plantilla p ON p.flujo = mt.flujo
) x;

DROP TEMPORARY TABLE tmp_maleta;
DROP TEMPORARY TABLE tmp_plantilla;
DROP TABLE aux_numeros;
DROP TABLE aux_digitos;
DROP FUNCTION aux_hash;
