-- =====================================================================
-- G8 · Avance 4 · Data Mart Aeropuerto y Equipaje (PostgreSQL 16, base g8_datamart)
-- Esquema de constelación: 2 tablas de hechos que comparten dimensiones conformadas.
-- Reglas de la Prepa 8.2:
--   · las dimensiones solo tienen atributos descriptivos, ninguna clave foránea;
--   · todas las FK están en las tablas de hechos;
--   · las SK las genera Pentaho (Add sequence) porque las claves del OLTP tienen
--     significado (código IATA, número de vuelo, nombre de región, código de estado).
-- La SK 0 de dim_vuelo y dim_estado_inspeccion es el "miembro desconocido";
-- la inserta el job (j00_cargar_datamart.kjb) antes de cada carga.
-- =====================================================================
DROP TABLE IF EXISTS fact_incidencias_equipaje, fact_equipaje_procesado, dim_tiempo, dim_region,
  dim_aeropuerto, dim_vuelo, dim_estado_inspeccion, dim_tipo_equipaje CASCADE;

-- ---------- Dimensiones ----------
CREATE TABLE dim_tiempo (
    sk_tiempo         INT PRIMARY KEY,
    fecha_completa    DATE        NOT NULL UNIQUE,
    anio              INT         NOT NULL,
    trimestre         INT         NOT NULL,
    mes               INT         NOT NULL,
    nombre_mes        VARCHAR(12) NOT NULL,
    dia_mes           INT         NOT NULL,
    dia_semana        VARCHAR(10) NOT NULL,
    es_fin_de_semana  BOOLEAN     NOT NULL
);

CREATE TABLE dim_region (
    sk_region       INT PRIMARY KEY,
    nombre_region   VARCHAR(10) NOT NULL UNIQUE,
    pais_principal  VARCHAR(50) NOT NULL
);

CREATE TABLE dim_aeropuerto (
    sk_aeropuerto      INT PRIMARY KEY,
    codigo_iata        CHAR(3)      NOT NULL UNIQUE,
    nombre_aeropuerto  VARCHAR(100) NOT NULL,
    ciudad             VARCHAR(50)  NOT NULL,
    estado             CHAR(2)      NOT NULL,
    es_hub             BOOLEAN      NOT NULL
);

CREATE TABLE dim_vuelo (
    sk_vuelo          INT PRIMARY KEY,
    numero_vuelo      CHAR(6)     NOT NULL UNIQUE,
    codigo_aerolinea  CHAR(2)     NOT NULL,
    aerolinea         VARCHAR(50) NOT NULL
);

CREATE TABLE dim_estado_inspeccion (
    sk_estado_inspeccion   INT PRIMARY KEY,
    codigo_estado          VARCHAR(30)  NOT NULL UNIQUE,
    descripcion_estado     VARCHAR(100) NOT NULL,
    es_apta_embarque       BOOLEAN      NOT NULL,
    requiere_intervencion  BOOLEAN      NOT NULL
);

CREATE TABLE dim_tipo_equipaje (
    sk_tipo_equipaje   INT PRIMARY KEY,
    categoria          VARCHAR(30) NOT NULL,
    prioridad_entrega  VARCHAR(20) NOT NULL,
    UNIQUE (categoria, prioridad_entrega)
);

-- ---------- Hecho principal: una fila por maleta (su recorrido check-in -> entrega) ----------
CREATE TABLE fact_equipaje_procesado (
    sk_fact_procesado        BIGINT PRIMARY KEY,
    sk_tiempo                INT NOT NULL REFERENCES dim_tiempo(sk_tiempo),
    sk_aeropuerto_origen     INT NOT NULL REFERENCES dim_aeropuerto(sk_aeropuerto),
    sk_aeropuerto_conexion   INT NOT NULL REFERENCES dim_aeropuerto(sk_aeropuerto),
    sk_aeropuerto_destino    INT NOT NULL REFERENCES dim_aeropuerto(sk_aeropuerto),
    sk_region_origen         INT NOT NULL REFERENCES dim_region(sk_region),
    sk_region_destino        INT NOT NULL REFERENCES dim_region(sk_region),
    sk_vuelo                 INT NOT NULL REFERENCES dim_vuelo(sk_vuelo),
    sk_estado_inspeccion     INT NOT NULL REFERENCES dim_estado_inspeccion(sk_estado_inspeccion),
    sk_tipo_equipaje         INT NOT NULL REFERENCES dim_tipo_equipaje(sk_tipo_equipaje),
    tag_rfid_bag             CHAR(10)     NOT NULL,   -- dimensión degenerada (trazabilidad)
    id_pasajero              BIGINT       NOT NULL,   -- dimensión degenerada (peso por pasajero)
    peso_kg                  NUMERIC(5,2) NOT NULL,
    tiempo_transito_bhs_min  NUMERIC(6,2),            -- solo maletas con telemetría en MongoDB
    tiempo_entrega_min       NUMERIC(6,2),            -- solo maletas con telemetría en MongoDB
    fue_entregado_a_tiempo   SMALLINT,                -- 1 si la entrega tomó 20 min o menos
    es_conexion              SMALLINT     NOT NULL,
    transferencia_exitosa    SMALLINT                 -- 1 sin desvío en la conexión (MongoDB)
);

-- ---------- Hecho de incidencias: una fila por inspección de seguridad (MongoDB) ----------
CREATE TABLE fact_incidencias_equipaje (
    sk_fact_incidencia        BIGINT PRIMARY KEY,
    sk_tiempo                 INT NOT NULL REFERENCES dim_tiempo(sk_tiempo),
    sk_aeropuerto_incidencia  INT NOT NULL REFERENCES dim_aeropuerto(sk_aeropuerto),
    sk_aeropuerto_origen      INT NOT NULL REFERENCES dim_aeropuerto(sk_aeropuerto),
    sk_aeropuerto_destino     INT NOT NULL REFERENCES dim_aeropuerto(sk_aeropuerto),
    sk_region_incidencia      INT NOT NULL REFERENCES dim_region(sk_region),
    sk_vuelo                  INT NOT NULL REFERENCES dim_vuelo(sk_vuelo),
    sk_estado_inspeccion      INT NOT NULL REFERENCES dim_estado_inspeccion(sk_estado_inspeccion),
    tag_rfid_bag              CHAR(10)    NOT NULL,
    tipo_incidencia           VARCHAR(60) NOT NULL,
    ocurrio_en_conexion       SMALLINT    NOT NULL,
    requiere_apertura_manual  SMALLINT    NOT NULL,
    fue_retenido              SMALLINT    NOT NULL,
    tiempo_resolucion_min     NUMERIC(6,2),           -- minutos retenida (solo retenidas)
    monto_compensacion_usd    NUMERIC(10,2)           -- compensación notificada al pasajero
);
