-- =====================================================================
-- G8 · Avance 4 · Staging central relacional en PostgreSQL 16 (base g8_staging)
-- Es el esquema de las Unidades 1 y 2 (G8_completo-2.sql de la rama main)
-- traducido de MySQL 8.0 a PostgreSQL 16, igual que la migración del Avance 2:
--   ENUM  -> VARCHAR + CHECK      DECIMAL -> NUMERIC      resto sin cambios
-- Es la fuente OLTP del ETL; no se modifica nada de su contenido.
-- =====================================================================
DROP TABLE IF EXISTS segmento_boleto, movimiento_equipaje, equipaje, reserva_pnr, boleto,
  pase_abordaje, asignacion_puerta, vuelo_operado, vuelo_programado, check_in, tarifa,
  pasajero, hub, aeropuerto, region CASCADE;

CREATE TABLE region (
    nombre_region VARCHAR(10) PRIMARY KEY,
    CONSTRAINT chk_region_valida CHECK (nombre_region IN ('ESTE', 'CENTRAL', 'OESTE'))
);
CREATE TABLE aeropuerto (
    codigo_aeropuerto CHAR(3) PRIMARY KEY,
    region VARCHAR(10) REFERENCES region(nombre_region)
);
CREATE TABLE hub (
    codigo_base_operaciones CHAR(3) PRIMARY KEY REFERENCES aeropuerto(codigo_aeropuerto),
    region VARCHAR(10) REFERENCES region(nombre_region)
);
CREATE TABLE pasajero ( id BIGINT PRIMARY KEY );
CREATE TABLE tarifa ( id BIGINT PRIMARY KEY, precio NUMERIC );
CREATE TABLE check_in ( id_check_in BIGINT PRIMARY KEY, confirmacion_identidad BIGINT );
CREATE TABLE vuelo_programado (
    id_vuelo_programado BIGINT PRIMARY KEY,
    fecha_salida TIMESTAMP,
    fecha_llegada TIMESTAMP,
    retraso_minutos INTEGER,
    estado_de_vigencia VARCHAR(12) DEFAULT 'programado'
        CHECK (estado_de_vigencia IN ('programado','retrasado','abordado','en_vuelo','aterrizado','cancelado'))
);
CREATE TABLE vuelo_operado (
    id_vuelo_operado BIGINT PRIMARY KEY REFERENCES vuelo_programado(id_vuelo_programado),
    numero_vuelo CHAR(6),
    fecha_salida_real TIMESTAMP,
    fecha_llegada_real TIMESTAMP,
    retraso_minutos INTEGER,
    estado VARCHAR(20)
);
CREATE TABLE asignacion_puerta (
    id_asignacion BIGINT PRIMARY KEY,
    vuelo_asociado BIGINT REFERENCES vuelo_programado(id_vuelo_programado),
    id_pase_abordaje BIGINT
);
CREATE TABLE pase_abordaje (
    id_pase_abordaje BIGINT PRIMARY KEY,
    id_asignacion_puerta BIGINT REFERENCES asignacion_puerta(id_asignacion),
    fecha_emision TIMESTAMP,
    numero_asiento VARCHAR(4),
    zona_abordaje CHAR(1),
    zona_aterrizaje CHAR(1)
);
CREATE TABLE boleto (
    id_boleto BIGINT PRIMARY KEY,
    id_pasajero BIGINT REFERENCES pasajero(id),
    numero_boleto CHAR(13),
    fecha_emision DATE,
    tarifa_base NUMERIC(10,2),
    clase_servicio CHAR(1),
    estado VARCHAR(20),
    timestamp_evento_boleto TIMESTAMP,
    id_tarifa BIGINT REFERENCES tarifa(id)
);
CREATE TABLE reserva_pnr (
    id_reserva_pnr BIGINT PRIMARY KEY,
    id_pasajero BIGINT REFERENCES pasajero(id),
    itinerario_vuelos TEXT,
    info_contacto TEXT,
    pnr_fecha_de_emision TIMESTAMP,
    ente_realizador_de_reserva VARCHAR(255)
);
CREATE TABLE equipaje (
    id CHAR(10) PRIMARY KEY,
    id_pasajero BIGINT REFERENCES pasajero(id)
);
CREATE TABLE movimiento_equipaje (
    id_movimiento BIGINT PRIMARY KEY,
    codigo_etiqueta CHAR(10),
    tipo_evento VARCHAR(20),
    timestamp_evento TIMESTAMP,
    peso_kg NUMERIC(5,2),
    id_boleto BIGINT REFERENCES boleto(id_boleto),
    id_codigo_pnr BIGINT REFERENCES reserva_pnr(id_reserva_pnr)
);
CREATE TABLE segmento_boleto (
    id_segmento_de_boleto INTEGER PRIMARY KEY,
    check_in_id BIGINT REFERENCES check_in(id_check_in),
    boleto_id BIGINT REFERENCES boleto(id_boleto),
    id_pase_abordaje BIGINT REFERENCES pase_abordaje(id_pase_abordaje)
);
-- Índices de apoyo para los joins del ETL (equivalentes a los del Avance 1)
CREATE INDEX idx_mov_etiqueta ON movimiento_equipaje(codigo_etiqueta);
CREATE INDEX idx_seg_boleto   ON segmento_boleto(boleto_id);
