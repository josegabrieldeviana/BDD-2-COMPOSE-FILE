# G8 · Aeropuerto y Equipaje (MySQL 8.0)

Base de datos del Avance 1 de Bases de Datos II (G8): el esquema corregido, con datos coherentes y los volúmenes del informe (300.000 movimientos de equipaje, 200.000 boletos, etc.).

## Lo que necesitan

- **Docker Desktop** abierto, con el motor encendido (el ícono de la ballena en verde).
- **Git**.
- Un cliente SQL: DataGrip, MySQL Workbench o la consola de `mysql` del contenedor.

## Levantar la base completa

**1. Clonar el repo y pasarse a la rama `luis`**

```bash
git clone https://github.com/josegabrieldeviana/BDD-2-COMPOSE-FILE.git
cd BDD-2-COMPOSE-FILE
git checkout luis
```

Si ya tenían el repo clonado, basta con `git fetch` y `git checkout luis`.

**2. Borrar la base anterior** (si nunca la levantaron, este paso no hace nada)

```bash
docker compose down -v
```

El `-v` es importante: MySQL solo ejecuta los scripts de carga cuando la base se crea desde cero. Si queda el volumen viejo, van a seguir viendo la base vieja.

**3. Levantarla**

```bash
docker compose up -d --build
```

La primera vez descarga la imagen de MySQL 8.0 (unos 250 MB).

**4. Esperar a que termine la carga** (entre 1 y 3 minutos)

```bash
docker logs -f mysql-local
```

Está lista cuando aparece `MySQL init process done` y después una línea con `ready for connections` y `port: 3306`. Salgan del log con Ctrl+C; el contenedor sigue corriendo.

**5. Comprobar que cargó todo**

```bash
docker exec mysql-local mysql -uroot -p0000 G8 -e "SELECT COUNT(*) FROM movimiento_equipaje;"
```

Tiene que dar `300000`. El aviso de "Using a password on the command line" es normal.

## Conectarse

| Campo | Valor |
|---|---|
| Host | `localhost` |
| Puerto | `3307` |
| Usuario | `root` |
| Contraseña | `0000` |
| Base | `G8` |

- **DataGrip:** si "Test Connection" dice *Public Key Retrieval is not allowed*, en la pestaña Advanced pongan `allowPublicKeyRetrieval = true` y `useSSL = false`.
- **MySQL Workbench:** para el plan gráfico, ejecuten la consulta y abran **Execution Plan** en la pestaña de resultados.

## Qué se carga

| Script | Contenido |
|---|---|
| `docker-entrypoint-initdb.d/01_esquema.sql` | Las 15 tablas con las correcciones de integridad: FK de `movimiento_equipaje.codigo_etiqueta` a `equipaje`, `tarifa.precio` con céntimos, zonas del pase de abordaje como regiones, `check_in` apuntando a `pasajero`, sin la columna circular de `asignacion_puerta`, y NOT NULL y CHECK donde corresponde. |
| `docker-entrypoint-initdb.d/02_datos.sql` | Datos sintéticos. Es determinista: a todos les genera exactamente los mismos datos. |
| `docker-entrypoint-initdb.d/03_indices.sql` | Los 6 índices del informe (4 B-tree y 2 FULLTEXT) más `idx_mov_evento_fecha`, que es el de la consulta de optimización. |

| Tabla | Filas |
|---|---|
| movimiento_equipaje | 300.000 |
| boleto | 200.000 |
| pasajero, reserva_pnr, equipaje | 100.000 cada una |
| vuelo_programado, vuelo_operado | 50.000 cada una |
| tarifa | 50 |
| aeropuerto / hub / region | 42 / 10 / 3 |

`check_in`, `pase_abordaje`, `asignacion_puerta` y `segmento_boleto` quedan vacías por ahora.

**Reglas de coherencia que cumplen los datos** (la primera parte de las mediciones las verifica, y todas dan 0):

- Ningún evento de un boleto es anterior a su emisión, y los boletos USADO ya viajaron.
- `tarifa_base` es el precio de la tarifa del boleto, y la tarifa corresponde a su clase (Y, J, F).
- Los vuelos aterrizan después de despegar, y todos los vuelos operados ya ocurrieron.
- Solo los boletos USADO tienen equipaje, y cada maleta es del pasajero del boleto.
- Cada maleta tiene 3 eventos en orden cronológico: registro, carga o incidencia, y entrega.
- El PNR de cada movimiento es la reserva del mismo pasajero.

## Correr las mediciones del informe

`mediciones/consultas_informe.sql` tiene todas las consultas del informe:
- volúmenes y chequeos de coherencia;
- `information_schema.tables` (punto 2.2.1);
- `SHOW INDEX`;
- EXPLAIN y EXPLAIN ANALYZE con y sin cada índice;
- `innodb_index_stats` para el orden y la altura de los B-tree;
- la consulta de optimización del punto 4.

```bash
docker cp mediciones/consultas_informe.sql mysql-local:/tmp/consultas.sql
docker exec mysql-local sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -t G8 < /tmp/consultas.sql'
```

Sirve igual en PowerShell, Git Bash, Mac o Linux. `mediciones/resultados.txt` tiene la salida de una corrida.

Los tiempos cambian un poco entre corridas y entre computadoras. Para el informe, corran cada EXPLAIN ANALYZE 3 veces y usen la mediana. La primera corrida suele salir más lenta porque los datos todavía no están en memoria.

## Problemas comunes

| Problema | Solución |
|---|---|
| `Access denied for user 'root'` | Quedó un volumen creado con la versión anterior del compose, que guardaba la contraseña como `0` porque YAML leía `0000` como número. Corran `docker compose down -v` y vuelvan a levantarla. |
| El puerto 3307 está ocupado | En `docker-compose.yml` cambien `"3307:3306"` por otro puerto, por ejemplo `"3310:3306"`, y conéctense a ese. |
| Faltan datos o la carga se cortó | `docker compose down -v` y `docker compose up -d --build`. |
| `failed to connect to the docker API` | Docker Desktop no está abierto, o su motor todavía está arrancando. |
| Docker Desktop no arranca y su log (`%LOCALAPPDATA%\Docker\log\host\com.docker.backend.exe.log`) dice `dockerInference` o `engine.sock`: *The file cannot be accessed by the system* | Quedaron sockets de una sesión anterior que Windows no puede borrar. Cierren Docker Desktop y renombren las carpetas `%LOCALAPPDATA%\Docker\run` y `%LOCALAPPDATA%\docker-secrets-engine`, por ejemplo agregándoles `_viejo`. Después ábranlo de nuevo. **No usen "Reset to factory defaults"**: borra todas sus imágenes y contenedores. |

## Otros archivos

`G8_completo.sql`, en la raíz, es el respaldo anterior (5.000 boletos y sin movimientos). Ya no se carga; queda solo como referencia.
