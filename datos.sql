-- =====================================================================
-- Datos de prueba para el subsistema G8 (MySQL 8.0)
-- Ejecutar DESPUÉS de crear las tablas. Tarda unos segundos/minutos.
-- Los datos son deterministas: todos los del grupo obtienen los mismos.
-- =====================================================================

-- ---------- Tablas auxiliares (se borran al final) ----------
DROP TABLE IF EXISTS aux_digitos, aux_nums, aux_aeropuertos;
CREATE TABLE aux_digitos (d INT PRIMARY KEY);
INSERT INTO aux_digitos VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

-- Números del 1 al 1.000.000
CREATE TABLE aux_nums (n INT PRIMARY KEY);
INSERT INTO aux_nums
SELECT a.d + b.d*10 + c.d*100 + e.d*1000 + f.d*10000 + g.d*100000 + 1
FROM aux_digitos a, aux_digitos b, aux_digitos c, aux_digitos e, aux_digitos f, aux_digitos g;

-- ---------- region, aeropuerto, hub ----------
INSERT INTO region VALUES ('ESTE'),('CENTRAL'),('OESTE');

INSERT INTO aeropuerto VALUES
('CLT','ESTE'),('PHL','ESTE'),('JFK','ESTE'),('LGA','ESTE'),('DCA','ESTE'),('MIA','ESTE'),('BOS','ESTE'),
('EWR','ESTE'),('BWI','ESTE'),('IAD','ESTE'),('PIT','ESTE'),('RDU','ESTE'),('ATL','ESTE'),('MCO','ESTE'),
('DFW','CENTRAL'),('ORD','CENTRAL'),('MSP','CENTRAL'),('DTW','CENTRAL'),('CLE','CENTRAL'),('STL','CENTRAL'),('MCI','CENTRAL'),
('MSY','CENTRAL'),('IAH','CENTRAL'),('AUS','CENTRAL'),('SAT','CENTRAL'),('MEM','CENTRAL'),('BNA','CENTRAL'),('MDW','CENTRAL'),
('PHX','OESTE'),('LAX','OESTE'),('SFO','OESTE'),('SAN','OESTE'),('LAS','OESTE'),('SEA','OESTE'),('PDX','OESTE'),
('SLC','OESTE'),('DEN','OESTE'),('ABQ','OESTE'),('TUS','OESTE'),('SJC','OESTE'),('SNA','OESTE'),('OAK','OESTE');

INSERT INTO hub VALUES
('CLT','ESTE'),('PHL','ESTE'),('JFK','ESTE'),('LGA','ESTE'),('DCA','ESTE'),('MIA','ESTE'),
('DFW','CENTRAL'),('ORD','CENTRAL'),('PHX','OESTE'),('LAX','OESTE');

-- Lista numerada de aeropuertos (0..41) para armar itinerarios
CREATE TABLE aux_aeropuertos (i INT PRIMARY KEY, codigo CHAR(3));
INSERT INTO aux_aeropuertos
SELECT ROW_NUMBER() OVER (ORDER BY codigo_aeropuerto) - 1, codigo_aeropuerto FROM aeropuerto;

-- ---------- pasajero (100.000) y tarifa (50) ----------
INSERT INTO pasajero SELECT n FROM aux_nums WHERE n <= 100000;

INSERT INTO tarifa
SELECT n, 80 + MOD(CONV(LEFT(MD5(CONCAT('t', n)), 8), 16, 10), 1200) FROM aux_nums WHERE n <= 50;

-- ---------- vuelo_programado (50.000) ----------
INSERT INTO vuelo_programado
SELECT n,
       TIMESTAMP('2026-01-01') + INTERVAL MOD(CONV(LEFT(MD5(CONCAT('vs', n)), 8), 16, 10), 525600) MINUTE,
       TIMESTAMP('2026-01-01') + INTERVAL MOD(CONV(LEFT(MD5(CONCAT('vs', n)), 8), 16, 10), 525600) + 60 + MOD(n, 300) MINUTE,
       MOD(CONV(LEFT(MD5(CONCAT('r', n)), 8), 16, 10), 90),
       ELT(1 + MOD(CONV(LEFT(MD5(CONCAT('e', n)), 8), 16, 10), 6), 'programado','retrasado','abordado','en_vuelo','aterrizado','cancelado')
FROM aux_nums WHERE n <= 50000;

-- ---------- vuelo_operado (50.000, mismo id que el programado) ----------
-- 800 números de vuelo distintos (AA1000..UA1799), cada uno se repite ~62 veces en el año
INSERT INTO vuelo_operado
SELECT vp.id_vuelo_programado,
       CONCAT(ELT(1 + MOD(vp.id_vuelo_programado, 4), 'AA','DL','UA','WN'),
              1000 + MOD(vp.id_vuelo_programado, 800)),
       vp.fecha_salida  + INTERVAL vp.retraso_minutos MINUTE,
       vp.fecha_llegada + INTERVAL vp.retraso_minutos MINUTE,
       vp.retraso_minutos,
       ELT(1 + MOD(vp.id_vuelo_programado, 3), 'completado','en_vuelo','completado')
FROM vuelo_programado vp;

-- ---------- boleto (200.000) ----------
-- numero_boleto: '001' + 10 dígitos, único
INSERT INTO boleto
SELECT n,
       1 + MOD(CONV(LEFT(MD5(CONCAT('p', n)), 8), 16, 10), 100000),
       CONCAT('001', LPAD(n * 9973, 10, '0')),
       DATE('2025-06-01') + INTERVAL MOD(CONV(LEFT(MD5(CONCAT('f', n)), 8), 16, 10), 480) DAY,
       80 + MOD(CONV(LEFT(MD5(CONCAT('tb', n)), 8), 16, 10), 1500) + 0.99,
       ELT(1 + MOD(CONV(LEFT(MD5(CONCAT('c', n)), 8), 16, 10), 10), 'Y','Y','Y','Y','Y','Y','W','W','J','F'),
       ELT(1 + MOD(CONV(LEFT(MD5(CONCAT('s', n)), 8), 16, 10), 10), 'emitido','emitido','emitido','emitido','usado','usado','usado','reembolsado','anulado','cambiado'),
       TIMESTAMP('2025-06-01') + INTERVAL MOD(CONV(LEFT(MD5(CONCAT('ts', n)), 8), 16, 10), 691200) MINUTE,
       1 + MOD(n, 50)
FROM aux_nums WHERE n <= 200000;

-- ---------- reserva_pnr (100.000) ----------
INSERT INTO reserva_pnr
SELECT n,
       1 + MOD(CONV(LEFT(MD5(CONCAT('rp', n)), 8), 16, 10), 100000),
       CONCAT(a1.codigo, '-', a2.codigo, ' ', a2.codigo, '-', a3.codigo),
       CONCAT(ELT(1 + MOD(CONV(LEFT(MD5(CONCAT('nom', n)), 8), 16, 10), 8), 'Maria','Jose','Luis','Ana','Carlos','Laura','Pedro','Sofia'), ' ',
              ELT(1 + MOD(CONV(LEFT(MD5(CONCAT('ape', n)), 8), 16, 10), 8), 'Perez','Gonzalez','Rodriguez','Martinez','Lopez','Garcia','Hernandez','Diaz'),
              ' email usuario', n, '@',
              ELT(1 + MOD(CONV(LEFT(MD5(CONCAT('dom', n)), 8), 16, 10), 4), 'gmail.com','yahoo.com','hotmail.com','outlook.com'),
              ' tel +1', LPAD(MOD(CONV(LEFT(MD5(CONCAT('tel', n)), 8), 16, 10), 1000000000), 10, '5')),
       TIMESTAMP('2025-06-01') + INTERVAL MOD(CONV(LEFT(MD5(CONCAT('pe', n)), 8), 16, 10), 691200) MINUTE,
       ELT(1 + MOD(CONV(LEFT(MD5(CONCAT('en', n)), 8), 16, 10), 4), 'web','app','agencia','call_center')
FROM aux_nums
JOIN aux_aeropuertos a1 ON a1.i = MOD(CONV(LEFT(MD5(CONCAT('o', n)), 8), 16, 10), 42)
JOIN aux_aeropuertos a2 ON a2.i = MOD(CONV(LEFT(MD5(CONCAT('x', n)), 8), 16, 10), 42)
JOIN aux_aeropuertos a3 ON a3.i = MOD(CONV(LEFT(MD5(CONCAT('d', n)), 8), 16, 10), 42)
WHERE n <= 100000;

-- ---------- equipaje (100.000) ----------
INSERT INTO equipaje
SELECT CONCAT('TAG', LPAD(n, 7, '0')), 1 + MOD(CONV(LEFT(MD5(CONCAT('eq', n)), 8), 16, 10), 100000)
FROM aux_nums WHERE n <= 100000;

-- ---------- movimiento_equipaje (300.000: 3 eventos por maleta) ----------
INSERT INTO movimiento_equipaje
SELECT n,
       CONCAT('TAG', LPAD(CEIL(n / 3), 7, '0')),
       ELT(1 + MOD(n - 1, 3), 'check_in', 'cargado', 'entregado'),
       TIMESTAMP('2026-01-01') + INTERVAL MOD(CONV(LEFT(MD5(CONCAT('m', CEIL(n / 3))), 8), 16, 10), 500000) MINUTE
                               + INTERVAL MOD(n - 1, 3) * 90 MINUTE,
       5 + MOD(CONV(LEFT(MD5(CONCAT('kg', n)), 8), 16, 10), 2500) / 100,
       1 + MOD(CONV(LEFT(MD5(CONCAT('mb', CEIL(n / 3))), 8), 16, 10), 200000),
       1 + MOD(CONV(LEFT(MD5(CONCAT('mp', CEIL(n / 3))), 8), 16, 10), 100000)
FROM aux_nums WHERE n <= 300000;

-- ---------- check_in, asignacion_puerta, pase_abordaje, segmento_boleto ----------
INSERT INTO check_in
SELECT n, 1000000 + MOD(CONV(LEFT(MD5(CONCAT('ci', n)), 8), 16, 10), 9000000) FROM aux_nums WHERE n <= 150000;

INSERT INTO asignacion_puerta
SELECT n, n, n FROM aux_nums WHERE n <= 50000;

INSERT INTO pase_abordaje
SELECT n,
       1 + MOD(n - 1, 50000),
       TIMESTAMP('2026-01-01') + INTERVAL MOD(CONV(LEFT(MD5(CONCAT('pa', n)), 8), 16, 10), 525600) MINUTE,
       CONCAT(1 + MOD(n, 35), ELT(1 + MOD(n, 6), 'A','B','C','D','E','F')),
       ELT(1 + MOD(n, 5), '1','2','3','4','5'),
       ELT(1 + MOD(n, 3), 'A','B','C')
FROM aux_nums WHERE n <= 150000;

INSERT INTO segmento_boleto
SELECT n, n, 1 + MOD(n - 1, 200000), n FROM aux_nums WHERE n <= 150000;

-- ---------- Limpieza y estadísticas ----------
DROP TABLE aux_digitos, aux_nums, aux_aeropuertos;

ANALYZE TABLE region, aeropuerto, hub, pasajero, tarifa, check_in, vuelo_programado,
              vuelo_operado, asignacion_puerta, pase_abordaje, boleto, reserva_pnr,
              equipaje, movimiento_equipaje, segmento_boleto;

-- Verificación: filas por tabla
SELECT table_name, table_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY table_name;