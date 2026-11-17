# 7. Entorno de Trabajo, Implementación y Carga

> Borrador del punto 3 (sección 7 del informe). Todo lo descrito está construido y ejecutado; las cifras salen de las corridas del 16/11/2026. Donde dice **[Captura]** va una imagen de Spoon (con Windows en modo claro, como pidió la preparadora).

## 7.1. Arquitectura y entorno del flujo en Pentaho Data Integration

### 7.1.1. Configuración del flujo en Spoon y uso de base intermedia de staging

**Entorno**

| Componente | Versión y ubicación |
|---|---|
| Pentaho Data Integration (Spoon) | 10.2.0.0-222 Community Edition, el zip entregado por la preparadora; se abre con `Spoon.bat` |
| Java | OpenJDK 17 (Temurin) |
| Staging relacional (fuente OLTP) | PostgreSQL 16.6, base `g8_staging`, `localhost:5438` |
| Fuente NoSQL | MongoDB Atlas, base `aeropuerto_nosql` (las 5 colecciones de la Unidad 3) |
| Data Mart (destino) | PostgreSQL 16.6, base `g8_datamart`, `localhost:5438`; al G8 le corresponde PostgreSQL por ser grupo par |

**Flujo general**

```
 PostgreSQL g8_staging ─┐
 (15 tablas, U1 y U2)   │      Pentaho Spoon                      PostgreSQL g8_datamart
                        ├──►  8 transformaciones (.ktr)  ──►  6 dimensiones + 2 hechos
 MongoDB Atlas ─────────┤      orquestadas por 1 job (.kjb)       (esquema constelación)
 (5 colecciones, U3)    │                                                 │
 Catálogo CSV ──────────┘                                                 ▼
 (42 aeropuertos)                                                      Metabase
```

**¿Se usó una base intermedia de staging?** Sí, y es la misma que el proyecto ya definía: la base relacional de las Unidades 1 y 2 funciona como *staging central*. Como el G8 trabajó en MySQL 8.0 en la Unidad 1 y migró a PostgreSQL 16 en la Unidad 2, el ETL lee de esa copia en PostgreSQL (`g8_staging`: 15 tablas y 1.400.105 filas, las mismas de la migración del Avance 2). No se creó una tercera base intermedia: las uniones entre fuentes, la limpieza y los cálculos se resuelven dentro de los flujos de Spoon, y el resultado se carga directo en el Data Mart.

**Conexiones definidas en Spoon** **[Captura: ventana Database Connection con "Connection tested successfully"]**

| Nombre de la conexión | Tipo | Base | Uso |
|---|---|---|---|
| `pg16_staging_input` | PostgreSQL (Native JDBC) | `g8_staging` | Table input y lookups contra el staging |
| `pg16_datamart_output` | PostgreSQL (Native JDBC) | `g8_datamart` | Table output y lookups de claves sustitutas |
| MongoDB input | Connection string | `aeropuerto_nosql` | Lectura de colecciones; la cadena es la variable `${G8_MONGO_URI}` de `kettle.properties`, para no dejar la contraseña de Atlas dentro de los `.ktr` entregables |

**Organización de los archivos**

| Archivo | Carga | Fuente principal |
|---|---|---|
| `t01_dim_tiempo.ktr` | dim_tiempo (320 días) | staging |
| `t02_dim_region.ktr` | dim_region (3) | staging |
| `t03_dim_aeropuerto.ktr` | dim_aeropuerto (42) | staging + CSV |
| `t04_dim_vuelo.ktr` | dim_vuelo (800 + desconocido) | staging |
| `t05_dim_estado_inspeccion.ktr` | dim_estado_inspeccion (3 + desconocido) | MongoDB |
| `t06_dim_tipo_equipaje.ktr` | dim_tipo_equipaje (6) | staging |
| `t07_fact_equipaje_procesado.ktr` | hecho principal (90.112 maletas) | staging + MongoDB |
| `t08_fact_incidencias_equipaje.ktr` | hecho de incidencias (3.000 inspecciones) | MongoDB + staging |
| `j00_cargar_datamart.kjb` | job: prepara el datamart y ejecuta t01 a t08 en orden | — |

Se separó una transformación por tabla, como en la prepa, para poder capturar y explicar cada carga por separado. El job las ordena: primero las dimensiones y después los hechos, porque los hechos buscan las claves sustitutas en las dimensiones ya cargadas.

## 7.2. Fase de Extracción (Extract) desde fuentes heterogéneas

### 7.2.1. Conexión y extracción del modelo relacional de origen

La extracción relacional usa el paso **Table input** con la conexión `pg16_staging_input`. Siguiendo la prepa, las dimensiones se extraen con `SELECT DISTINCT ... ORDER BY` para tener un catálogo sin repetidos y ordenado antes de generar la secuencia. Por ejemplo, en `t01_dim_tiempo`:

```sql
SELECT DISTINCT CAST(timestamp_evento AS DATE) AS fecha_completa
FROM movimiento_equipaje
WHERE timestamp_evento <= TIMESTAMP '2026-11-16 23:59:59'
ORDER BY fecha_completa
```

Para el hecho principal, el Table input hace el **"mega join"** del que habló la preparadora. El hecho sale de `movimiento_equipaje`, la tabla del OLTP que tiene las medidas (el peso y las marcas de tiempo de cada evento), y se une con las demás tablas para traer todas las claves naturales que después se convierten en FK:

| Clave que necesita el hecho | Camino en el staging |
|---|---|
| Fecha | `movimiento_equipaje.timestamp_evento` del check-in |
| Aeropuertos de origen, conexión y destino | `movimiento_equipaje.id_codigo_pnr` → `reserva_pnr.itinerario_vuelos` (texto `LAS-LAX LAX-SAN`) |
| Región de origen y de destino | `aeropuerto.region` de cada código |
| Vuelo | `id_boleto` → `segmento_boleto` → `pase_abordaje` → `asignacion_puerta` → `vuelo_operado.numero_vuelo` (LEFT JOIN: el 25 % de los boletos no tiene segmento) |
| Tipo de equipaje | `boleto.clase_servicio` y el peso del check-in |
| Pasajero | `equipaje.id_pasajero` (dueño de la maleta) |

**[Captura: Table input "Input maletas (mega join del staging)" con la consulta y el Preview]**

### 7.2.2. Ingesta desde la fuente NoSQL (MongoDB)

MongoDB tiene paso nativo en Spoon (**MongoDB input**, carpeta *Big Data*), así que no hizo falta un script de exportación. Se configuró con *Connection string*, base `aeropuerto_nosql`, la colección y la opción **"Query is aggregation pipeline"**, con *Output single JSON* desmarcado para que cada campo salga como columna. Se usaron pipelines por dos motivos: resumir en MongoDB los datos que llegan como varios documentos por maleta, y devolver las fechas como texto (`$dateToString`) para que Pentaho no las corra de huso horario al combinarlas con las del staging.

| Paso | Colección | Qué devuelve |
|---|---|---|
| Input resultados de inspección | `inspecciones_seguridad_tsa` | `$group` por `resultado_inspeccion`: los 3 estados distintos (para la dimensión) |
| Input telemetría por maleta | `telemetria_escanner_equipaje` | `$group` por etiqueta: hora de la lectura en facturación y en carrusel, y si hubo `DESVIACION_LIGERA` en la transferencia (3.000 maletas) |
| Input inspecciones por maleta | `inspecciones_seguridad_tsa` | etiqueta y resultado (3.000) |
| Input inspecciones | `inspecciones_seguridad_tsa` | inspección completa con subdocumentos aplanados: `retencion.motivo`, `retencion.minutos_retenida` (3.000) |
| Input compensaciones | `notificaciones_pasajero` | `$match` de las notificaciones con `compensacion.monto_usd` (255) |

Ejemplo del pipeline de telemetría:

```js
{"$group": {"_id": "$codigo_etiqueta",
            "t_fact": {"$max": {"$cond": [{"$eq": ["$punto_control", "FACTURACION"]}, "$timestamp", null]}},
            "t_carr": {"$max": {"$cond": [{"$eq": ["$punto_control", "CARRUSEL"]}, "$timestamp", null]}},
            "desvio": {"$max": {"$cond": [{"$in": ["DESVIACION_LIGERA", {"$ifNull": ["$alertas_detectadas", []]}]}, 1, 0]}}}},
{"$project": {"_id": 0, "tag_mongo": "$_id",
              "ts_facturacion": {"$dateToString": {"format": "%Y-%m-%d %H:%M:%S", "date": "$t_fact"}},
              "ts_carrusel":    {"$dateToString": {"format": "%Y-%m-%d %H:%M:%S", "date": "$t_carr"}},
              "transferencia_exitosa": {"$subtract": [1, "$desvio"]}}},
{"$sort": {"tag_mongo": 1}}
```

La integración SQL + NoSQL se hace por la referencia trazable definida en la Unidad 3: `codigo_etiqueta` en MongoDB es `equipaje.id` en el staging, y `codigo_aeropuerto` es `aeropuerto.codigo_aeropuerto`.

**[Captura: MongoDB input, pestañas Configure connection (Test Connection exitoso), Input options, Query y Fields]**

Además se leyó un tercer origen, `catalogo_aeropuertos.csv` (paso **CSV file input**), con el nombre, la ciudad y el estado de los 42 aeropuertos, datos que no existen en ninguna base del proyecto.

## 7.3. Fase de Transformación (Transform)

### 7.3.1. Conversiones de tipo, estandarización de identificadores y nombres

| Transformación | Paso de Spoon | Dónde |
|---|---|---|
| Fechas de MongoDB (texto) → `Date` con máscara `yyyy-MM-dd HH:mm:ss` | Select values (Meta-data) | t07, t08 |
| `requiere_apertura_manual` (booleano de MongoDB) → entero 0/1 | Select values | t08 |
| Banderas de texto → `Boolean` (`es_fin_de_semana`, `es_apta_embarque`, `requiere_intervencion`) | Value mapper + Select values | t01, t05 |
| Código de aerolínea: primeros 2 caracteres del número de vuelo (`WN1195` → `WN`) | String cut | t04 |
| Nombres legibles: aerolínea (`WN` → Southwest Airlines), mes, día de la semana, descripción del estado | Value mapper | t01, t04, t05 |
| Atributos de fecha: año, trimestre, mes, día del mes y de la semana | Calculator | t01 |
| País constante de las regiones (`Estados Unidos`) | Add constant | t02 |
| Fecha sin hora de la inspección, para buscar en dim_tiempo | Calculator (`REMOVE_TIME_FROM_DATE`) | t08 |
| Claves sustitutas: las claves del OLTP tienen significado (código IATA, número de vuelo, nombre de región, código de estado), por eso se generan con secuencia, como indica la prepa | Add sequence | t01 a t08 |
| Unión de flujos por etiqueta o por código, con ambos flujos ordenados antes | Sort rows + Merge join | t03, t07, t08 |
| Claves naturales → claves sustitutas de cada dimensión | Database lookup (contra el datamart, con caché) | t07, t08 |

**[Captura: Select values (pestaña Meta-data), Value mapper de aerolínea y Merge join con sus claves]**

### 7.3.2. Limpieza y tratamiento de datos inválidos detectados en la auditoría

| Hallazgo (auditoría del punto 2) | Registros | Decisión | Cómo se aplica en Spoon |
|---|---|---|---|
| Entrega con fecha posterior al 16/11/2026 (eventos futuros) | 7.834 maletas | Descartar | Filter rows "¿La entrega ya ocurrió?" → falsas a `descartes/maletas_entrega_futura.csv` |
| Itinerario con origen igual a destino | 2.054 maletas | Descartar | Filter rows "¿Origen distinto de destino?" → `descartes/maletas_origen_igual_destino.csv` |
| Itinerario con origen = conexión o conexión = destino (en realidad, ruta directa) | 4.282 maletas | Corregir: `es_conexion = 0` | Formula `IF(OR([ori]=[con];[con]=[des]);0;1)` |
| El peso de una maleta cambia en cada evento | 100.000 maletas | Corregir: se usa el peso del check-in | Table input (solo el evento `check_in`) |
| Maleta cuyo boleto no tiene segmento de vuelo | 22.421 maletas cargadas | Marcar: `sk_vuelo = 0` ("Sin vuelo asignado") | Database lookup con valor por defecto 0 |
| Maleta sin inspección en MongoDB | 87.112 maletas cargadas | Marcar: `sk_estado_inspeccion = 0` ("Sin inspección registrada") | Database lookup con valor por defecto 0 |
| Datos de MongoDB incoherentes con el staging (aeropuerto fuera de la ruta, fechas fuera de la ventana, colecciones sin maletas en común) | 1.000 documentos | Corregir en el origen: se regeneraron a partir de 3.000 maletas reales del staging | Fuera de Spoon, documentado en la auditoría |

Resultado: de 100.000 maletas del staging llegan 90.112 al hecho principal, y las 9.888 descartadas quedan en los dos CSV de `descartes/` para poder revisarlas.

**[Captura: Filter rows con la condición y las dos salidas, verdadera y falsa]**

### 7.3.3. Reglas de cálculo y enriquecimiento de las métricas de negocio

| Campo del hecho | Regla | Paso |
|---|---|---|
| `tiempo_transito_bhs_min` | lectura en facturación (MongoDB) − check-in (staging), en minutos | Calculator (`DATE_DIFF_SEC` ÷ 60) |
| `tiempo_entrega_min` | evento `entregado` (staging) − lectura en carrusel (MongoDB), en minutos | Calculator |
| `fue_entregado_a_tiempo` | 1 si `tiempo_entrega_min` ≤ 20; 0 si es mayor | Number range |
| `transferencia_exitosa` | 1 si la lectura en el aeropuerto de conexión no tuvo `DESVIACION_LIGERA` | pipeline de MongoDB |
| `es_conexion` | 1 si la ruta tiene tres aeropuertos distintos | Formula |
| `sk_tipo_equipaje` | categoría por peso del check-in (Ligera < 10 kg, Estándar 10–23 kg, Sobrepeso > 23 kg) × prioridad por clase del boleto (F y J Prioritaria; W e Y Normal) | Number range + Value mapper |
| `ocurrio_en_conexion` | 1 si el aeropuerto de la inspección es el de conexión de la maleta | Formula |
| `fue_retenido` | 1 si el resultado es `RETENIDO` | Value mapper |
| `tipo_incidencia` | motivo de la retención, u "Observación de seguridad" o "Inspección sin novedad" | pipeline de MongoDB (`$ifNull` + `$cond`) |
| `tiempo_resolucion_min`, `monto_compensacion_usd` | `retencion.minutos_retenida` y `compensacion.monto_usd` | MongoDB input + Merge join |
| `nombre_aeropuerto`, `ciudad`, `estado` | catálogo CSV unido por código IATA | CSV file input + Merge join |
| `es_hub` | el aeropuerto está en la tabla `hub` | Table input (LEFT JOIN) |

**[Captura: Calculator "Tiempos de tránsito y entrega" y Number range "¿Entregada a tiempo?"]**

## 7.4. Fase de Carga (Load)

### 7.4.1. Inserción en el esquema dimensional en PostgreSQL 16

1. Las tablas del datamart se crearon vacías antes de Pentaho (`sql/02_datamart_ddl.sql`): 6 dimensiones sin claves foráneas y 2 hechos que concentran todas las FK, como indica la prepa.
2. El job empieza con una entrada **SQL** "Preparar datamart". El Table output no puede usar *Truncate table* porque las dimensiones tienen FK desde los hechos (es el error que mostró la preparadora en clase), así que el job vacía las tablas con `TRUNCATE ... CASCADE`, hechos primero, e inserta los miembros desconocidos (SK 0) de dim_vuelo y dim_estado_inspeccion. Así la carga se puede repetir sin duplicar filas.
3. Cada transformación termina en un **Table output** con esquema `public`, *Truncate* desmarcado, *Specify database fields* marcado y el mapeo hecho a mano: a la izquierda la columna del datamart y a la derecha el campo del flujo (por ejemplo `tag_rfid_bag` ← `tag_insp` en t08). Commit cada 1.000 filas, con inserción por lotes.
4. Orden del job: Preparar datamart → t01 → t02 → t03 → t04 → t05 → t06 → t07 → t08 → Success. Cada salto avanza solo si la transformación anterior terminó bien.

| Tabla | Filas cargadas |
|---|---|
| dim_tiempo | 320 |
| dim_region | 3 |
| dim_aeropuerto | 42 |
| dim_vuelo | 801 |
| dim_estado_inspeccion | 4 |
| dim_tipo_equipaje | 6 |
| fact_equipaje_procesado | 90.112 |
| fact_incidencias_equipaje | 3.000 |

El job completo tarda 18 segundos.

**[Captura: job j00 terminado con todas las entradas en verde y la pestaña Logging]**
**[Captura: SELECT en el datamart de cada tabla cargada (Query Tool)]**

## 7.5. Evidencia gráfica y documentos del flujo

### 7.5.1. Capturas comentadas de las transformaciones (.ktr) y del trabajo (.kjb)

Para cada transformación, como en la prepa: (1) el lienzo con todos los pasos en verde después de ejecutar, (2) la configuración del input con su conexión, (3) los pasos de transformación más importantes, (4) el output con el mapeo de campos y (5) un SELECT en el datamart que demuestre la carga.

| Archivo | Qué mostrar |
|---|---|
| t01_dim_tiempo | Table input con DISTINCT y ORDER BY; Calculator; los 3 Value mapper; Add sequence |
| t02_dim_region | Add constant con el país |
| t03_dim_aeropuerto | CSV file input; Sort rows en los dos flujos; Merge join INNER |
| t04_dim_vuelo | String cut y Value mapper de aerolínea |
| t05_dim_estado_inspeccion | MongoDB input con el pipeline `$group` |
| t06_dim_tipo_equipaje | Number range; Sort rows con *Only pass unique rows* |
| t07_fact_equipaje_procesado | mega join; los dos Filter rows con sus descartes; Merge join con MongoDB; Calculator; los 9 Database lookup; Table output |
| t08_fact_incidencias_equipaje | los 2 MongoDB input; Merge join INNER y LEFT OUTER; lookup de región contra el staging |
| j00_cargar_datamart | job completo y log |

**Trazabilidad de un registro (ejemplo):** la maleta `TAG0096232` hace check-in el 02/07/2026 a las 19:10:00 en el staging, con 12,80 kg y la ruta `LAS-LAX LAX-SAN`. En MongoDB se lee en facturación a las 19:39:26 y en el carrusel a las 21:49:31, y su inspección en LAS da `APROBADO`. El staging la entrega a las 22:10:00. En el hecho queda como origen LAS, conexión LAX, destino SAN, vuelo WN1195 (Southwest), 29,43 minutos de tránsito, 20,48 minutos de entrega (`fue_entregado_a_tiempo = 0`) y transferencia exitosa. El detalle está en `resultados_trazabilidad_ejemplo.txt`.
