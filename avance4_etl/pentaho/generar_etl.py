# -*- coding: utf-8 -*-
"""
G8 · Avance 4 · Genera los archivos de Pentaho (PDI 10.2) del ETL:
    t01..t08 *.ktr  (una transformación por tabla del datamart)
    j00_cargar_datamart.kjb  (job que las ejecuta en orden)
Se escriben en esta misma carpeta. Después se abren y se ejecutan en Spoon como
cualquier .ktr hecho a mano; este script solo evita armar 80 pasos clic a clic.

Conexiones: PostgreSQL 16 en localhost:5438 (contenedor pg-g8-bi, usuario postgres).
MongoDB Atlas: variable ${G8_MONGO_URI} de kettle.properties (la cadena no va en el .ktr).
"""
import io
import json
import os
from xml.sax.saxutils import escape

AQUI = os.path.dirname(os.path.abspath(__file__))
STG, DM = "pg16_staging_input", "pg16_datamart_output"
MONGO_DB = "aeropuerto_nosql"
FECHA_CORTE = "2026/11/16 23:59:59.000"     # "hoy" del ETL: lo posterior es una entrega futura
DIR = "${Internal.Entry.Current.Directory}"


def e(v):
    return escape(str(v), {'"': "&quot;"})


# ----------------------------------------------------------------- conexiones
def conexion(nombre, base):
    attrs = [("FORCE_IDENTIFIERS_TO_LOWERCASE", "N"), ("FORCE_IDENTIFIERS_TO_UPPERCASE", "N"),
             ("IS_CLUSTERED", "N"), ("PORT_NUMBER", "5438"), ("PRESERVE_RESERVED_WORD_CASE", "Y"),
             ("QUOTE_ALL_FIELDS", "N"), ("SUPPORTS_BOOLEAN_DATA_TYPE", "Y"),
             ("SUPPORTS_TIMESTAMP_DATA_TYPE", "Y"), ("USE_POOLING", "N")]
    a = "".join("<attribute><code>%s</code><attribute>%s</attribute></attribute>" % x for x in attrs)
    return ("<connection><name>%s</name><server>localhost</server><type>POSTGRESQL</type>"
            "<access>Native</access><database>%s</database><port>5438</port><username>postgres</username>"
            "<password>0000</password><servername/><data_tablespace/><index_tablespace/>"
            "<attributes>%s</attributes></connection>") % (nombre, base, a)


# ----------------------------------------------------------------- pasos
def paso(nombre, tipo, cuerpo, x, y):
    return ("<step><name>%s</name><type>%s</type><description/><distribute>Y</distribute>"
            "<custom_distribution/><copies>1</copies><partitioning><method>none</method><schema_name/>"
            "</partitioning>%s<attributes/><cluster_schema/><remotesteps><input></input><output></output>"
            "</remotesteps><GUI><xloc>%d</xloc><yloc>%d</yloc><draw>Y</draw></GUI></step>") % (
        e(nombre), tipo, cuerpo, int(x * 1.7), int(y * 1.4))   # espaciado para que no se monten los nombres


def table_input(n, con, sql, x, y):
    return paso(n, "TableInput", "<connection>%s</connection><sql>%s</sql><limit>0</limit><lookup/>"
                "<execute_each_row>N</execute_each_row><variables_active>N</variables_active>"
                "<lazy_conversion_active>N</lazy_conversion_active>" % (con, e(sql.strip())), x, y)


def table_output(n, tabla, mapeo, x, y):
    campos = "".join("<field><column_name>%s</column_name><stream_name>%s</stream_name></field>" % (c, s)
                     for c, s in mapeo)
    return paso(n, "TableOutput", "<connection>%s</connection><schema>public</schema><table>%s</table>"
                "<commit>1000</commit><truncate>N</truncate><ignore_errors>N</ignore_errors>"
                "<use_batch>Y</use_batch><specify_fields>Y</specify_fields><partitioning_enabled>N"
                "</partitioning_enabled><partitioning_field/><partitioning_daily>N</partitioning_daily>"
                "<partitioning_monthly>Y</partitioning_monthly><tablename_in_field>N</tablename_in_field>"
                "<tablename_field/><tablename_in_table>Y</tablename_in_table><return_keys>N</return_keys>"
                "<return_field/><fields>%s</fields>" % (DM, tabla, campos), x, y)


def secuencia(n, campo, x, y, inicio=1):
    return paso(n, "Sequence", "<valuename>%s</valuename><use_database>N</use_database><connection/>"
                "<schema/><seqname>SEQ_</seqname><use_counter>Y</use_counter><counter_name/>"
                "<start_at>%d</start_at><increment_by>1</increment_by><max_value>999999999</max_value>"
                % (campo, inicio), x, y)


def constante(n, campos, x, y):
    f = "".join("<field><name>%s</name><type>%s</type><format/><currency/><decimal/><group/>"
                "<nullif>%s</nullif><length>-1</length><precision>-1</precision>"
                "<set_empty_string>N</set_empty_string></field>" % (a, t, e(v)) for a, t, v in campos)
    return paso(n, "Constant", "<fields>%s</fields>" % f, x, y)


def select_values(n, x, y, seleccion=(), quitar=(), meta=()):
    s = "".join("<field><name>%s</name><rename>%s</rename><length>-2</length><precision>-2</precision>"
                "</field>" % (a, r if r else a) for a, r in seleccion)
    q = "".join("<remove><name>%s</name></remove>" % a for a in quitar)
    m = "".join("<meta><name>%s</name><rename>%s</rename><type>%s</type><length>-2</length>"
                "<precision>-2</precision><conversion_mask>%s</conversion_mask>"
                "<date_format_lenient>false</date_format_lenient><date_format_locale/>"
                "<date_format_timezone/><lenient_string_to_number>false</lenient_string_to_number>"
                "<encoding/><decimal_symbol/><grouping_symbol/><currency_symbol/><storage_type/></meta>"
                % (a, r, t, e(mask)) for a, r, t, mask in meta)
    return paso(n, "SelectValues", "<fields>%s<select_unspecified>N</select_unspecified>%s%s</fields>"
                % (s, q, m), x, y)


def value_mapper(n, campo, destino, pares, x, y, defecto=""):
    f = "".join("<field><source_value>%s</source_value><target_value>%s</target_value></field>"
                % (e(a), e(b)) for a, b in pares)
    nd = "<non_match_default>%s</non_match_default>" % e(defecto) if defecto else "<non_match_default/>"
    return paso(n, "ValueMapper", "<field_to_use>%s</field_to_use><target_field>%s</target_field>%s"
                "<fields>%s</fields>" % (campo, destino, nd, f), x, y)


def string_cut(n, cortes, x, y):
    f = "".join("<field><in_stream_name>%s</in_stream_name><out_stream_name>%s</out_stream_name>"
                "<cut_from>%s</cut_from><cut_to>%s</cut_to></field>" % c for c in cortes)
    return paso(n, "StringCut", "<fields>%s</fields>" % f, x, y)


def sort_rows(n, campos, x, y, unicos=False):
    f = "".join("<field><name>%s</name><ascending>Y</ascending><case_sensitive>Y</case_sensitive>"
                "<collator_enabled>N</collator_enabled><collator_strength>0</collator_strength>"
                "<presorted>N</presorted></field>" % c for c in campos)
    return paso(n, "SortRows", "<directory>%%%%java.io.tmpdir%%%%</directory><prefix>out</prefix>"
                "<sort_size>1000000</sort_size><free_memory/><compress>N</compress><compress_variable/>"
                "<unique_rows>%s</unique_rows><fields>%s</fields>" % ("Y" if unicos else "N", f), x, y)


def merge_join(n, tipo, paso1, paso2, claves1, claves2, x, y):
    k1 = "".join("<key>%s</key>" % k for k in claves1)
    k2 = "".join("<key>%s</key>" % k for k in claves2)
    return paso(n, "MergeJoin", "<join_type>%s</join_type><step1>%s</step1><step2>%s</step2>"
                "<keys_1>%s</keys_1><keys_2>%s</keys_2>" % (tipo, e(paso1), e(paso2), k1, k2), x, y)


def calculadora(n, calculos, x, y):
    c = "".join("<calculation><field_name>%s</field_name><calc_type>%s</calc_type><field_a>%s</field_a>"
                "<field_b>%s</field_b><field_c/><value_type>%s</value_type><value_length>%d</value_length>"
                "<value_precision>%d</value_precision><remove>%s</remove><conversion_mask/>"
                "<decimal_symbol/><grouping_symbol/><currency_symbol/></calculation>"
                % (f, t, a, b, vt, ln, pr, "Y" if rm else "N") for f, t, a, b, vt, ln, pr, rm in calculos)
    return paso(n, "Calculator", c, x, y)


def rango(n, entrada, salida, reglas, x, y, defecto=""):
    r = "".join("<rule><lower_bound>%s</lower_bound><upper_bound>%s</upper_bound><value>%s</value></rule>"
                % (lo, hi, e(v)) for lo, hi, v in reglas)
    return paso(n, "NumberRange", "<inputField>%s</inputField><outputField>%s</outputField>"
                "<fallBackValue>%s</fallBackValue><rules>%s</rules>" % (entrada, salida, e(defecto), r), x, y)


def formula(n, formulas, x, y):
    f = "".join("<formula><field_name>%s</field_name><formula_string>%s</formula_string>"
                "<value_type>%s</value_type><value_length>-1</value_length><value_precision>-1"
                "</value_precision><replace_field/></formula>" % (a, e(fs), t) for a, fs, t in formulas)
    return paso(n, "Formula", f, x, y)


def filtro(n, si, no, condicion, x, y):
    return paso(n, "FilterRows", "<send_true_to>%s</send_true_to><send_false_to>%s</send_false_to>"
                "<compare><condition>%s</condition></compare>" % (e(si), e(no), condicion), x, y)


def cond_campos(izq, op, der):
    return "<negated>N</negated><leftvalue>%s</leftvalue><function>%s</function><rightvalue>%s</rightvalue>" % (
        izq, e(op), der)


def cond_fecha(izq, op, texto):
    return ("<negated>N</negated><leftvalue>%s</leftvalue><function>%s</function><rightvalue/>"
            "<value><name>constant</name><type>Date</type><text>%s</text><length>-1</length>"
            "<precision>-1</precision><isnull>N</isnull><mask>yyyy/MM/dd HH:mm:ss.SSS</mask></value>"
            % (izq, e(op), texto))


def salida_texto(n, archivo, x, y, campos=(("tag_rfid_bag", "String", ""), ("ori", "String", ""),
                                          ("con", "String", ""), ("des", "String", ""),
                                          ("ts_checkin", "Date", "yyyy-MM-dd HH:mm:ss"),
                                          ("ts_entregado", "Date", "yyyy-MM-dd HH:mm:ss"))):
    # Los campos se declaran con largo -1: si no, PDI rellena cada texto hasta el largo de la columna.
    f = "".join("<field><name>%s</name><type>%s</type><format>%s</format><currency/><decimal/><group/>"
                "<nullif/><trim_type>none</trim_type><length>-1</length><precision>-1</precision></field>"
                % (a, t, fm) for a, t, fm in campos)
    return paso(n, "TextFileOutput", "<separator>;</separator><enclosure>&quot;</enclosure>"
                "<enclosure_forced>N</enclosure_forced><enclosure_fix_disabled>N</enclosure_fix_disabled>"
                "<header>Y</header><footer>N</footer><format>DOS</format><compression>None</compression>"
                "<encoding>UTF-8</encoding><endedLine/><fileNameInField>N</fileNameInField><fileNameField/>"
                "<create_parent_folder>Y</create_parent_folder><file><name>%s</name><is_command>N"
                "</is_command><servlet_output>N</servlet_output><do_not_open_new_file_init>N"
                "</do_not_open_new_file_init><extention>csv</extention><append>N</append><split>N</split>"
                "<haspartno>N</haspartno><add_date>N</add_date><add_time>N</add_time>"
                "<SpecifyFormat>N</SpecifyFormat><date_time_format/><add_to_result_filenames>N"
                "</add_to_result_filenames><pad>N</pad><fast_dump>N</fast_dump><splitevery>0</splitevery>"
                "</file><fields>%s</fields>" % (e(archivo), f), x, y)


def csv_input(n, archivo, campos, x, y):
    f = "".join("<field><name>%s</name><type>String</type><format/><currency/><decimal/><group/>"
                "<length>-1</length><precision>-1</precision><trim_type>both</trim_type></field>" % c
                for c in campos)
    return paso(n, "CsvInput", "<filename>%s</filename><filename_field/><rownum_field/>"
                "<include_filename>N</include_filename><separator>;</separator><enclosure>&quot;</enclosure>"
                "<header>Y</header><buffer_size>50000</buffer_size><lazy_conversion>N</lazy_conversion>"
                "<add_filename_result>N</add_filename_result><parallel>N</parallel>"
                "<newline_possible>N</newline_possible><encoding>UTF-8</encoding><fields>%s</fields>"
                % (e(archivo), f), x, y)


def db_lookup(n, con, tabla, claves, valores, x, y):
    k = "".join("<key><name>%s</name><field>%s</field><condition>=</condition><name2/></key>" % c
                for c in claves)
    v = "".join("<value><name>%s</name><rename>%s</rename><default>%s</default><type>%s</type></value>" % c
                for c in valores)
    return paso(n, "DBLookup", "<connection>%s</connection><cache>Y</cache><cache_load_all>Y</cache_load_all>"
                "<cache_size>0</cache_size><lookup><schema>public</schema><table>%s</table><orderby/>"
                "<fail_on_multiple>N</fail_on_multiple><eat_row_on_failure>N</eat_row_on_failure>%s%s"
                "</lookup>" % (con, tabla, k, v), x, y)


def mongo_input(n, coleccion, etapas, campos, x, y):
    pipeline = ", ".join(json.dumps(s, ensure_ascii=False) for s in etapas)
    f = "".join("<mongo_field><field_name>%s</field_name><field_path>$.%s</field_path>"
                "<field_type>%s</field_type><indexed_vals/></mongo_field>" % (c, c, t) for c, t in campos)
    return paso(n, "MongoDbInput", "<hostname/><port/><use_all_replica_members>N</use_all_replica_members>"
                "<db_name>%s</db_name><fields_name/><collection>%s</collection>"
                "<json_field_name>json</json_field_name><json_query>%s</json_query><auth_database/>"
                "<auth_user/><auth_password/><auth_mech/><auth_kerberos>N</auth_kerberos><connect_timeout/>"
                "<socket_timeout/><use_ssl_socket_factory>N</use_ssl_socket_factory>"
                "<read_preference>primary</read_preference><output_json>N</output_json>"
                "<query_is_pipeline>Y</query_is_pipeline><execute_for_each_row>N</execute_for_each_row>"
                "<use_connection_string>Y</use_connection_string><use_legacy_options>N</use_legacy_options>"
                "<connection_string>${G8_MONGO_URI}</connection_string><mongo_fields>%s</mongo_fields>"
                % (MONGO_DB, coleccion, e(pipeline), f), x, y)


# ----------------------------------------------------------------- archivos
def transformacion(archivo, nombre, descripcion, pasos, saltos, conexiones=(STG, DM)):
    bases = {STG: "g8_staging", DM: "g8_datamart"}
    con = "".join(conexion(c, bases[c]) for c in conexiones)
    hops = "".join("<hop><from>%s</from><to>%s</to><enabled>Y</enabled></hop>" % (e(a), e(b)) for a, b in saltos)
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<transformation><info><name>%s</name>'
           "<description>%s</description><extended_description/><trans_version/><trans_type>Normal</trans_type>"
           "<directory>/</directory><parameters></parameters></info><notepads></notepads>%s<order>%s</order>"
           "%s<step_error_handling></step_error_handling></transformation>\n") % (
        e(nombre), e(descripcion), con, hops, "".join(pasos))
    with io.open(os.path.join(AQUI, archivo), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(xml)
    print("escrito", archivo, "-", len(pasos), "pasos")


def mapeo(*cols):
    return [(c, c) for c in cols]


# ===================================================================== t01 dim_tiempo
MESES = [(str(i), m) for i, m in enumerate(["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio",
                                             "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"], 1)]
DIAS = [(str(i), d) for i, d in enumerate(["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes",
                                            "Sábado"], 1)]
transformacion(
    "t01_dim_tiempo.ktr", "t01_dim_tiempo", "Dimensión tiempo con grano día, a partir de las fechas de los eventos de equipaje",
    [table_input("Input fechas (movimiento_equipaje)", STG, """
SELECT DISTINCT CAST(timestamp_evento AS DATE) AS fecha_completa
FROM movimiento_equipaje
WHERE timestamp_evento <= TIMESTAMP '2026-11-16 23:59:59'   -- fecha de corte: no hay eventos futuros
ORDER BY fecha_completa""", 60, 120),
     calculadora("Atributos de la fecha", [
         ("anio", "YEAR_OF_DATE", "fecha_completa", "", "Integer", 4, 0, False),
         ("trimestre", "QUARTER_OF_DATE", "fecha_completa", "", "Integer", 1, 0, False),
         ("mes", "MONTH_OF_DATE", "fecha_completa", "", "Integer", 2, 0, False),
         ("dia_mes", "DAY_OF_MONTH", "fecha_completa", "", "Integer", 2, 0, False),
         ("dia_semana_num", "DAY_OF_WEEK", "fecha_completa", "", "Integer", 1, 0, False)], 240, 120),
     value_mapper("Nombre del mes", "mes", "nombre_mes", MESES, 400, 120),
     value_mapper("Nombre del día", "dia_semana_num", "dia_semana", DIAS, 560, 120),
     value_mapper("¿Fin de semana?", "dia_semana_num", "fin_semana_txt", [("1", "true"), ("7", "true")], 720, 120,
                  defecto="false"),
     select_values("Tipos finales", 720, 260, meta=[("fin_semana_txt", "es_fin_de_semana", "Boolean", "")]),
     secuencia("Añadir secuencia (sk_tiempo)", "sk_tiempo", 560, 260),
     table_output("Output dim_tiempo", "dim_tiempo",
                  mapeo("sk_tiempo", "fecha_completa", "anio", "trimestre", "mes", "nombre_mes", "dia_mes",
                        "dia_semana", "es_fin_de_semana"), 400, 260)],
    [("Input fechas (movimiento_equipaje)", "Atributos de la fecha"), ("Atributos de la fecha", "Nombre del mes"),
     ("Nombre del mes", "Nombre del día"), ("Nombre del día", "¿Fin de semana?"), ("¿Fin de semana?", "Tipos finales"),
     ("Tipos finales", "Añadir secuencia (sk_tiempo)"), ("Añadir secuencia (sk_tiempo)", "Output dim_tiempo")])

# ===================================================================== t02 dim_region
transformacion(
    "t02_dim_region.ktr", "t02_dim_region", "Dimensión región (tabla común de la Unidad 1)",
    [table_input("Input region", STG, "SELECT nombre_region FROM region ORDER BY nombre_region", 60, 120),
     constante("Añadir país", [("pais_principal", "String", "Estados Unidos")], 240, 120),
     secuencia("Añadir secuencia (sk_region)", "sk_region", 400, 120),
     table_output("Output dim_region", "dim_region", mapeo("sk_region", "nombre_region", "pais_principal"), 560, 120)],
    [("Input region", "Añadir país"), ("Añadir país", "Añadir secuencia (sk_region)"),
     ("Añadir secuencia (sk_region)", "Output dim_region")])

# ===================================================================== t03 dim_aeropuerto
transformacion(
    "t03_dim_aeropuerto.ktr", "t03_dim_aeropuerto",
    "Dimensión aeropuerto: códigos y hubs del staging + nombre, ciudad y estado del catálogo CSV",
    [table_input("Input aeropuerto + hub", STG, """
SELECT a.codigo_aeropuerto,
       (h.codigo_base_operaciones IS NOT NULL) AS es_hub
FROM aeropuerto a
LEFT JOIN hub h ON h.codigo_base_operaciones = a.codigo_aeropuerto
ORDER BY a.codigo_aeropuerto""", 60, 80),
     csv_input("Input catálogo de aeropuertos (CSV)", DIR + "/catalogo_aeropuertos.csv",
               ["codigo_iata", "nombre_aeropuerto", "ciudad", "estado"], 60, 240),
     sort_rows("Ordenar staging por código", ["codigo_aeropuerto"], 240, 80),
     sort_rows("Ordenar CSV por código", ["codigo_iata"], 240, 240),
     merge_join("Unir staging con catálogo", "INNER", "Ordenar staging por código", "Ordenar CSV por código",
                ["codigo_aeropuerto"], ["codigo_iata"], 420, 160),
     select_values("Seleccionar campos", 580, 160,
                   seleccion=[("codigo_iata", ""), ("nombre_aeropuerto", ""), ("ciudad", ""), ("estado", ""),
                              ("es_hub", "")]),
     secuencia("Añadir secuencia (sk_aeropuerto)", "sk_aeropuerto", 740, 160),
     table_output("Output dim_aeropuerto", "dim_aeropuerto",
                  mapeo("sk_aeropuerto", "codigo_iata", "nombre_aeropuerto", "ciudad", "estado", "es_hub"), 900, 160)],
    [("Input aeropuerto + hub", "Ordenar staging por código"),
     ("Input catálogo de aeropuertos (CSV)", "Ordenar CSV por código"),
     ("Ordenar staging por código", "Unir staging con catálogo"), ("Ordenar CSV por código", "Unir staging con catálogo"),
     ("Unir staging con catálogo", "Seleccionar campos"), ("Seleccionar campos", "Añadir secuencia (sk_aeropuerto)"),
     ("Añadir secuencia (sk_aeropuerto)", "Output dim_aeropuerto")])

# ===================================================================== t04 dim_vuelo
AEROLINEAS = [("AA", "American Airlines"), ("DL", "Delta Air Lines"), ("UA", "United Airlines"),
              ("WN", "Southwest Airlines")]
transformacion(
    "t04_dim_vuelo.ktr", "t04_dim_vuelo", "Dimensión vuelo: un registro por número de vuelo operado",
    [table_input("Input vuelo_operado", STG,
                 "SELECT DISTINCT numero_vuelo FROM vuelo_operado ORDER BY numero_vuelo", 60, 120),
     string_cut("Código de aerolínea", [("numero_vuelo", "codigo_aerolinea", 0, 2)], 240, 120),
     value_mapper("Nombre de la aerolínea", "codigo_aerolinea", "aerolinea", AEROLINEAS, 400, 120),
     secuencia("Añadir secuencia (sk_vuelo)", "sk_vuelo", 560, 120),
     table_output("Output dim_vuelo", "dim_vuelo", mapeo("sk_vuelo", "numero_vuelo", "codigo_aerolinea", "aerolinea"),
                  720, 120)],
    [("Input vuelo_operado", "Código de aerolínea"), ("Código de aerolínea", "Nombre de la aerolínea"),
     ("Nombre de la aerolínea", "Añadir secuencia (sk_vuelo)"), ("Añadir secuencia (sk_vuelo)", "Output dim_vuelo")])

# ===================================================================== t05 dim_estado_inspeccion
transformacion(
    "t05_dim_estado_inspeccion.ktr", "t05_dim_estado_inspeccion",
    "Dimensión estado de inspección: resultados distintos de inspecciones_seguridad_tsa (MongoDB)",
    [mongo_input("Input resultados de inspección (MongoDB)", "inspecciones_seguridad_tsa",
                 [{"$group": {"_id": "$resultado_inspeccion"}},
                  {"$project": {"_id": 0, "codigo_estado": "$_id"}},
                  {"$sort": {"codigo_estado": 1}}],
                 [("codigo_estado", "String")], 60, 120),
     value_mapper("Descripción del estado", "codigo_estado", "descripcion_estado",
                  [("APROBADO", "Aprobado sin observaciones"),
                   ("APROBADO_CON_OBSERVACION", "Aprobado con observaciones de seguridad"),
                   ("RETENIDO", "Retenido para revisión adicional")], 260, 120),
     value_mapper("¿Apta para embarque?", "codigo_estado", "apta_txt", [("RETENIDO", "false")], 420, 120,
                  defecto="true"),
     value_mapper("¿Requiere intervención?", "codigo_estado", "interv_txt", [("APROBADO", "false")], 580, 120,
                  defecto="true"),
     select_values("Tipos finales", 580, 260, meta=[("apta_txt", "es_apta_embarque", "Boolean", ""),
                                                    ("interv_txt", "requiere_intervencion", "Boolean", "")]),
     secuencia("Añadir secuencia (sk_estado_inspeccion)", "sk_estado_inspeccion", 420, 260),
     table_output("Output dim_estado_inspeccion", "dim_estado_inspeccion",
                  mapeo("sk_estado_inspeccion", "codigo_estado", "descripcion_estado", "es_apta_embarque",
                        "requiere_intervencion"), 260, 260)],
    [("Input resultados de inspección (MongoDB)", "Descripción del estado"),
     ("Descripción del estado", "¿Apta para embarque?"), ("¿Apta para embarque?", "¿Requiere intervención?"),
     ("¿Requiere intervención?", "Tipos finales"), ("Tipos finales", "Añadir secuencia (sk_estado_inspeccion)"),
     ("Añadir secuencia (sk_estado_inspeccion)", "Output dim_estado_inspeccion")],
    conexiones=(DM,))

# ===================================================================== t06 dim_tipo_equipaje
REGLAS_PESO = [(-1.0e9, 10.0, "Ligera (menos de 10 kg)"), (10.0, 23.001, "Estándar (10 a 23 kg)"),
               (23.001, 1.0e9, "Sobrepeso (más de 23 kg)")]
PRIORIDAD = [("F", "Prioritaria"), ("J", "Prioritaria"), ("W", "Normal"), ("Y", "Normal")]
transformacion(
    "t06_dim_tipo_equipaje.ktr", "t06_dim_tipo_equipaje",
    "Dimensión tipo de equipaje: categoría por peso del check-in y prioridad por clase del boleto",
    [table_input("Input peso y clase de cada maleta", STG, """
SELECT m.peso_kg, b.clase_servicio
FROM movimiento_equipaje m
JOIN boleto b ON b.id_boleto = m.id_boleto
WHERE m.tipo_evento = 'check_in'""", 60, 120),
     rango("Categoría por peso", "peso_kg", "categoria", REGLAS_PESO, 240, 120),
     value_mapper("Prioridad por clase", "clase_servicio", "prioridad_entrega", PRIORIDAD, 400, 120),
     sort_rows("Combinaciones únicas", ["categoria", "prioridad_entrega"], 560, 120, unicos=True),
     secuencia("Añadir secuencia (sk_tipo_equipaje)", "sk_tipo_equipaje", 720, 120),
     table_output("Output dim_tipo_equipaje", "dim_tipo_equipaje",
                  mapeo("sk_tipo_equipaje", "categoria", "prioridad_entrega"), 880, 120)],
    [("Input peso y clase de cada maleta", "Categoría por peso"), ("Categoría por peso", "Prioridad por clase"),
     ("Prioridad por clase", "Combinaciones únicas"), ("Combinaciones únicas", "Añadir secuencia (sk_tipo_equipaje)"),
     ("Añadir secuencia (sk_tipo_equipaje)", "Output dim_tipo_equipaje")])

# ===================================================================== t07 fact_equipaje_procesado
SQL_MALETAS = """
-- Mega join del staging: una fila por maleta con todas las claves naturales que necesita el hecho
SELECT m.codigo_etiqueta                            AS tag_rfid_bag,
       e.id_pasajero,                                         -- dueño de la maleta
       m.peso_kg,                                             -- peso del check-in (regla de limpieza)
       m.timestamp_evento                           AS ts_checkin,
       en.timestamp_evento                          AS ts_entregado,
       CAST(m.timestamp_evento AS DATE)             AS fecha_checkin,
       SUBSTRING(r.itinerario_vuelos FROM 1 FOR 3)  AS ori,
       SUBSTRING(r.itinerario_vuelos FROM 5 FOR 3)  AS con,
       SUBSTRING(r.itinerario_vuelos FROM 13 FOR 3) AS des,
       ao.region                                    AS region_ori,
       ad.region                                    AS region_des,
       vo.numero_vuelo,
       b.clase_servicio
FROM movimiento_equipaje m
JOIN movimiento_equipaje en ON en.codigo_etiqueta = m.codigo_etiqueta AND en.tipo_evento = 'entregado'
JOIN equipaje e      ON e.id = m.codigo_etiqueta
JOIN boleto b        ON b.id_boleto = m.id_boleto
JOIN reserva_pnr r   ON r.id_reserva_pnr = m.id_codigo_pnr
JOIN aeropuerto ao   ON ao.codigo_aeropuerto = SUBSTRING(r.itinerario_vuelos FROM 1 FOR 3)
JOIN aeropuerto ad   ON ad.codigo_aeropuerto = SUBSTRING(r.itinerario_vuelos FROM 13 FOR 3)
LEFT JOIN segmento_boleto s    ON s.boleto_id = m.id_boleto
LEFT JOIN pase_abordaje pa     ON pa.id_pase_abordaje = s.id_pase_abordaje
LEFT JOIN asignacion_puerta ap ON ap.id_asignacion = pa.id_asignacion_puerta
LEFT JOIN vuelo_operado vo     ON vo.id_vuelo_operado = ap.vuelo_asociado
WHERE m.tipo_evento = 'check_in'
ORDER BY m.codigo_etiqueta"""
FECHA_TXT = "%Y-%m-%d %H:%M:%S"
DT = "yyyy-MM-dd HH:mm:ss"
transformacion(
    "t07_fact_equipaje_procesado.ktr", "t07_fact_equipaje_procesado",
    "Hecho principal: una fila por maleta. Staging (PostgreSQL) + telemetría e inspecciones (MongoDB)",
    [table_input("Input maletas (mega join del staging)", STG, SQL_MALETAS, 40, 60),
     filtro("¿La entrega ya ocurrió?", "¿Origen distinto de destino?", "Descartadas: entrega futura",
            cond_fecha("ts_entregado", "<=", FECHA_CORTE), 200, 60),
     salida_texto("Descartadas: entrega futura", DIR + "/descartes/maletas_entrega_futura", 200, 200),
     filtro("¿Origen distinto de destino?", "Regla es_conexion", "Descartadas: origen igual a destino",
            cond_campos("ori", "<>", "des"), 360, 60),
     salida_texto("Descartadas: origen igual a destino", DIR + "/descartes/maletas_origen_igual_destino", 360, 200),
     formula("Regla es_conexion", [("es_conexion", "IF(OR([ori]=[con];[con]=[des]);0;1)", "Integer")], 520, 60),
     rango("Categoría por peso", "peso_kg", "categoria", REGLAS_PESO, 680, 60),
     value_mapper("Prioridad por clase", "clase_servicio", "prioridad_entrega", PRIORIDAD, 840, 60),
     sort_rows("Ordenar maletas por etiqueta", ["tag_rfid_bag"], 1000, 60),
     mongo_input("Input telemetría por maleta (MongoDB)", "telemetria_escanner_equipaje",
                 [{"$group": {"_id": "$codigo_etiqueta",
                              "t_fact": {"$max": {"$cond": [{"$eq": ["$punto_control", "FACTURACION"]}, "$timestamp", None]}},
                              "t_carr": {"$max": {"$cond": [{"$eq": ["$punto_control", "CARRUSEL"]}, "$timestamp", None]}},
                              "desvio": {"$max": {"$cond": [{"$in": ["DESVIACION_LIGERA",
                                                                     {"$ifNull": ["$alertas_detectadas", []]}]}, 1, 0]}}}},
                  {"$project": {"_id": 0, "tag_mongo": "$_id",
                                "ts_facturacion": {"$dateToString": {"format": FECHA_TXT, "date": "$t_fact"}},
                                "ts_carrusel": {"$dateToString": {"format": FECHA_TXT, "date": "$t_carr"}},
                                "transferencia_exitosa": {"$subtract": [1, "$desvio"]}}},
                  {"$sort": {"tag_mongo": 1}}],
                 [("tag_mongo", "String"), ("ts_facturacion", "String"), ("ts_carrusel", "String"),
                  ("transferencia_exitosa", "Integer")], 40, 320),
     select_values("Texto a fecha (telemetría)", 200, 320,
                   meta=[("ts_facturacion", "ts_facturacion", "Date", DT), ("ts_carrusel", "ts_carrusel", "Date", DT)]),
     sort_rows("Ordenar telemetría por etiqueta", ["tag_mongo"], 360, 320),
     mongo_input("Input inspecciones por maleta (MongoDB)", "inspecciones_seguridad_tsa",
                 [{"$project": {"_id": 0, "tag_insp": "$codigo_etiqueta", "codigo_estado": "$resultado_inspeccion"}},
                  {"$sort": {"tag_insp": 1}}],
                 [("tag_insp", "String"), ("codigo_estado", "String")], 40, 460),
     sort_rows("Ordenar inspecciones por etiqueta", ["tag_insp"], 360, 460),
     merge_join("Unir maletas con telemetría", "LEFT OUTER", "Ordenar maletas por etiqueta",
                "Ordenar telemetría por etiqueta", ["tag_rfid_bag"], ["tag_mongo"], 1000, 320),
     merge_join("Unir con inspecciones", "LEFT OUTER", "Unir maletas con telemetría",
                "Ordenar inspecciones por etiqueta", ["tag_rfid_bag"], ["tag_insp"], 1000, 460),
     calculadora("Tiempos de tránsito y entrega", [
         # los segundos salen como Number: con Integer la división entre 60 sería entera
         ("seg_transito", "DATE_DIFF_SEC", "ts_facturacion", "ts_checkin", "Number", -1, -1, True),
         ("seg_entrega", "DATE_DIFF_SEC", "ts_entregado", "ts_carrusel", "Number", -1, -1, True),
         ("sesenta", "CONSTANT", "60", "", "Number", -1, -1, True),
         ("tiempo_transito_bhs_min", "DIVIDE", "seg_transito", "sesenta", "Number", 6, 2, False),
         ("tiempo_entrega_min", "DIVIDE", "seg_entrega", "sesenta", "Number", 6, 2, False)], 1000, 600),
     rango("¿Entregada a tiempo? (20 min)", "tiempo_entrega_min", "a_tiempo_txt",
           [(-1.0e9, 20.0001, "1"), (20.0001, 1.0e9, "0")], 840, 600),
     db_lookup("Lookup dim_tiempo", DM, "dim_tiempo", [("fecha_checkin", "fecha_completa")],
               [("sk_tiempo", "sk_tiempo", "", "Integer")], 680, 600),
     db_lookup("Lookup aeropuerto origen", DM, "dim_aeropuerto", [("ori", "codigo_iata")],
               [("sk_aeropuerto", "sk_aeropuerto_origen", "", "Integer")], 520, 600),
     db_lookup("Lookup aeropuerto conexión", DM, "dim_aeropuerto", [("con", "codigo_iata")],
               [("sk_aeropuerto", "sk_aeropuerto_conexion", "", "Integer")], 360, 600),
     db_lookup("Lookup aeropuerto destino", DM, "dim_aeropuerto", [("des", "codigo_iata")],
               [("sk_aeropuerto", "sk_aeropuerto_destino", "", "Integer")], 200, 600),
     db_lookup("Lookup región origen", DM, "dim_region", [("region_ori", "nombre_region")],
               [("sk_region", "sk_region_origen", "", "Integer")], 40, 600),
     db_lookup("Lookup región destino", DM, "dim_region", [("region_des", "nombre_region")],
               [("sk_region", "sk_region_destino", "", "Integer")], 40, 740),
     db_lookup("Lookup dim_vuelo", DM, "dim_vuelo", [("numero_vuelo", "numero_vuelo")],
               [("sk_vuelo", "sk_vuelo", "0", "Integer")], 200, 740),
     db_lookup("Lookup estado de inspección", DM, "dim_estado_inspeccion", [("codigo_estado", "codigo_estado")],
               [("sk_estado_inspeccion", "sk_estado_inspeccion", "0", "Integer")], 360, 740),
     db_lookup("Lookup tipo de equipaje", DM, "dim_tipo_equipaje",
               [("categoria", "categoria"), ("prioridad_entrega", "prioridad_entrega")],
               [("sk_tipo_equipaje", "sk_tipo_equipaje", "", "Integer")], 520, 740),
     secuencia("Añadir secuencia (sk_fact_procesado)", "sk_fact_procesado", 680, 740),
     select_values("Tipos finales", 840, 740, meta=[("a_tiempo_txt", "fue_entregado_a_tiempo", "Integer", "")]),
     table_output("Output fact_equipaje_procesado", "fact_equipaje_procesado",
                  mapeo("sk_fact_procesado", "sk_tiempo", "sk_aeropuerto_origen", "sk_aeropuerto_conexion",
                        "sk_aeropuerto_destino", "sk_region_origen", "sk_region_destino", "sk_vuelo",
                        "sk_estado_inspeccion", "sk_tipo_equipaje", "tag_rfid_bag", "id_pasajero", "peso_kg",
                        "tiempo_transito_bhs_min", "tiempo_entrega_min", "fue_entregado_a_tiempo", "es_conexion",
                        "transferencia_exitosa"), 1000, 740)],
    [("Input maletas (mega join del staging)", "¿La entrega ya ocurrió?"),
     ("¿La entrega ya ocurrió?", "¿Origen distinto de destino?"),
     ("¿La entrega ya ocurrió?", "Descartadas: entrega futura"),
     ("¿Origen distinto de destino?", "Regla es_conexion"),
     ("¿Origen distinto de destino?", "Descartadas: origen igual a destino"),
     ("Regla es_conexion", "Categoría por peso"), ("Categoría por peso", "Prioridad por clase"),
     ("Prioridad por clase", "Ordenar maletas por etiqueta"),
     ("Input telemetría por maleta (MongoDB)", "Texto a fecha (telemetría)"),
     ("Texto a fecha (telemetría)", "Ordenar telemetría por etiqueta"),
     ("Input inspecciones por maleta (MongoDB)", "Ordenar inspecciones por etiqueta"),
     ("Ordenar maletas por etiqueta", "Unir maletas con telemetría"),
     ("Ordenar telemetría por etiqueta", "Unir maletas con telemetría"),
     ("Unir maletas con telemetría", "Unir con inspecciones"),
     ("Ordenar inspecciones por etiqueta", "Unir con inspecciones"),
     ("Unir con inspecciones", "Tiempos de tránsito y entrega"),
     ("Tiempos de tránsito y entrega", "¿Entregada a tiempo? (20 min)"),
     ("¿Entregada a tiempo? (20 min)", "Lookup dim_tiempo"),
     ("Lookup dim_tiempo", "Lookup aeropuerto origen"), ("Lookup aeropuerto origen", "Lookup aeropuerto conexión"),
     ("Lookup aeropuerto conexión", "Lookup aeropuerto destino"), ("Lookup aeropuerto destino", "Lookup región origen"),
     ("Lookup región origen", "Lookup región destino"), ("Lookup región destino", "Lookup dim_vuelo"),
     ("Lookup dim_vuelo", "Lookup estado de inspección"), ("Lookup estado de inspección", "Lookup tipo de equipaje"),
     ("Lookup tipo de equipaje", "Añadir secuencia (sk_fact_procesado)"),
     ("Añadir secuencia (sk_fact_procesado)", "Tipos finales"), ("Tipos finales", "Output fact_equipaje_procesado")])

# ===================================================================== t08 fact_incidencias_equipaje
SQL_RUTA = """
-- Ruta y vuelo de cada maleta (staging), para completar las inspecciones de MongoDB
SELECT m.codigo_etiqueta                            AS tag_rfid_bag,
       SUBSTRING(r.itinerario_vuelos FROM 1 FOR 3)  AS ori,
       SUBSTRING(r.itinerario_vuelos FROM 5 FOR 3)  AS con,
       SUBSTRING(r.itinerario_vuelos FROM 13 FOR 3) AS des,
       vo.numero_vuelo
FROM movimiento_equipaje m
JOIN reserva_pnr r ON r.id_reserva_pnr = m.id_codigo_pnr
LEFT JOIN segmento_boleto s    ON s.boleto_id = m.id_boleto
LEFT JOIN pase_abordaje pa     ON pa.id_pase_abordaje = s.id_pase_abordaje
LEFT JOIN asignacion_puerta ap ON ap.id_asignacion = pa.id_asignacion_puerta
LEFT JOIN vuelo_operado vo     ON vo.id_vuelo_operado = ap.vuelo_asociado
WHERE m.tipo_evento = 'check_in'
ORDER BY m.codigo_etiqueta"""
transformacion(
    "t08_fact_incidencias_equipaje.ktr", "t08_fact_incidencias_equipaje",
    "Hecho de incidencias: una fila por inspección de seguridad (MongoDB) cruzada con la ruta de la maleta (staging)",
    [mongo_input("Input inspecciones (MongoDB)", "inspecciones_seguridad_tsa",
                 [{"$project": {"_id": 0, "tag_insp": "$codigo_etiqueta",
                                "aeropuerto_incidencia": "$codigo_aeropuerto",
                                "codigo_estado": "$resultado_inspeccion",
                                "apertura_manual": "$requiere_apertura_manual",
                                "tipo_incidencia": {"$ifNull": ["$retencion.motivo", {"$cond": [
                                    {"$eq": ["$resultado_inspeccion", "APROBADO_CON_OBSERVACION"]},
                                    "Observación de seguridad", "Inspección sin novedad"]}]},
                                "tiempo_resolucion_min": "$retencion.minutos_retenida",
                                "ts_inspeccion": {"$dateToString": {"format": FECHA_TXT, "date": "$timestamp"}}}},
                  {"$sort": {"tag_insp": 1}}],
                 [("tag_insp", "String"), ("aeropuerto_incidencia", "String"), ("codigo_estado", "String"),
                  ("apertura_manual", "Boolean"), ("tipo_incidencia", "String"),
                  ("tiempo_resolucion_min", "Number"), ("ts_inspeccion", "String")], 40, 60),
     sort_rows("Ordenar inspecciones por etiqueta", ["tag_insp"], 220, 60),
     table_input("Input ruta y vuelo de la maleta (staging)", STG, SQL_RUTA, 40, 200),
     sort_rows("Ordenar maletas por etiqueta", ["tag_rfid_bag"], 220, 200),
     mongo_input("Input compensaciones (MongoDB)", "notificaciones_pasajero",
                 [{"$match": {"compensacion.monto_usd": {"$exists": True}}},
                  {"$project": {"_id": 0, "tag_notif": "$codigo_etiqueta",
                                "monto_compensacion_usd": "$compensacion.monto_usd"}},
                  {"$sort": {"tag_notif": 1}}],
                 [("tag_notif", "String"), ("monto_compensacion_usd", "Number")], 40, 340),
     sort_rows("Ordenar compensaciones por etiqueta", ["tag_notif"], 220, 340),
     merge_join("Unir inspección con la maleta", "INNER", "Ordenar inspecciones por etiqueta",
                "Ordenar maletas por etiqueta", ["tag_insp"], ["tag_rfid_bag"], 400, 130),
     merge_join("Unir con compensación", "LEFT OUTER", "Unir inspección con la maleta",
                "Ordenar compensaciones por etiqueta", ["tag_insp"], ["tag_notif"], 400, 270),
     select_values("Tipos de MongoDB", 560, 270,
                   meta=[("ts_inspeccion", "ts_inspeccion", "Date", DT),
                         ("apertura_manual", "requiere_apertura_manual", "Integer", "")]),
     calculadora("Fecha de la inspección", [
         ("fecha_inspeccion", "REMOVE_TIME_FROM_DATE", "ts_inspeccion", "", "Date", -1, -1, False)], 720, 270),
     formula("Regla ocurrio_en_conexion", [("ocurrio_en_conexion", "IF([aeropuerto_incidencia]=[con];1;0)", "Integer")],
             880, 270),
     value_mapper("¿Fue retenida?", "codigo_estado", "retenido_txt", [("RETENIDO", "1")], 1040, 270, defecto="0"),
     db_lookup("Lookup región del aeropuerto (staging)", STG, "aeropuerto",
               [("aeropuerto_incidencia", "codigo_aeropuerto")], [("region", "region_incidencia", "", "String")],
               1040, 410),
     db_lookup("Lookup dim_tiempo", DM, "dim_tiempo", [("fecha_inspeccion", "fecha_completa")],
               [("sk_tiempo", "sk_tiempo", "", "Integer")], 880, 410),
     db_lookup("Lookup aeropuerto de la incidencia", DM, "dim_aeropuerto", [("aeropuerto_incidencia", "codigo_iata")],
               [("sk_aeropuerto", "sk_aeropuerto_incidencia", "", "Integer")], 720, 410),
     db_lookup("Lookup aeropuerto origen", DM, "dim_aeropuerto", [("ori", "codigo_iata")],
               [("sk_aeropuerto", "sk_aeropuerto_origen", "", "Integer")], 560, 410),
     db_lookup("Lookup aeropuerto destino", DM, "dim_aeropuerto", [("des", "codigo_iata")],
               [("sk_aeropuerto", "sk_aeropuerto_destino", "", "Integer")], 400, 410),
     db_lookup("Lookup región de la incidencia", DM, "dim_region", [("region_incidencia", "nombre_region")],
               [("sk_region", "sk_region_incidencia", "", "Integer")], 240, 410),
     db_lookup("Lookup dim_vuelo", DM, "dim_vuelo", [("numero_vuelo", "numero_vuelo")],
               [("sk_vuelo", "sk_vuelo", "0", "Integer")], 80, 410),
     db_lookup("Lookup estado de inspección", DM, "dim_estado_inspeccion", [("codigo_estado", "codigo_estado")],
               [("sk_estado_inspeccion", "sk_estado_inspeccion", "0", "Integer")], 80, 550),
     secuencia("Añadir secuencia (sk_fact_incidencia)", "sk_fact_incidencia", 240, 550),
     select_values("Tipos finales", 400, 550, meta=[("retenido_txt", "fue_retenido", "Integer", "")]),
     table_output("Output fact_incidencias_equipaje", "fact_incidencias_equipaje",
                  mapeo("sk_fact_incidencia", "sk_tiempo", "sk_aeropuerto_incidencia", "sk_aeropuerto_origen",
                        "sk_aeropuerto_destino", "sk_region_incidencia", "sk_vuelo", "sk_estado_inspeccion") +
                  [("tag_rfid_bag", "tag_insp")] +
                  mapeo("tipo_incidencia", "ocurrio_en_conexion", "requiere_apertura_manual", "fue_retenido",
                        "tiempo_resolucion_min", "monto_compensacion_usd"), 560, 550)],
    [("Input inspecciones (MongoDB)", "Ordenar inspecciones por etiqueta"),
     ("Input ruta y vuelo de la maleta (staging)", "Ordenar maletas por etiqueta"),
     ("Input compensaciones (MongoDB)", "Ordenar compensaciones por etiqueta"),
     ("Ordenar inspecciones por etiqueta", "Unir inspección con la maleta"),
     ("Ordenar maletas por etiqueta", "Unir inspección con la maleta"),
     ("Unir inspección con la maleta", "Unir con compensación"),
     ("Ordenar compensaciones por etiqueta", "Unir con compensación"),
     ("Unir con compensación", "Tipos de MongoDB"), ("Tipos de MongoDB", "Fecha de la inspección"),
     ("Fecha de la inspección", "Regla ocurrio_en_conexion"), ("Regla ocurrio_en_conexion", "¿Fue retenida?"),
     ("¿Fue retenida?", "Lookup región del aeropuerto (staging)"),
     ("Lookup región del aeropuerto (staging)", "Lookup dim_tiempo"),
     ("Lookup dim_tiempo", "Lookup aeropuerto de la incidencia"),
     ("Lookup aeropuerto de la incidencia", "Lookup aeropuerto origen"),
     ("Lookup aeropuerto origen", "Lookup aeropuerto destino"),
     ("Lookup aeropuerto destino", "Lookup región de la incidencia"),
     ("Lookup región de la incidencia", "Lookup dim_vuelo"), ("Lookup dim_vuelo", "Lookup estado de inspección"),
     ("Lookup estado de inspección", "Añadir secuencia (sk_fact_incidencia)"),
     ("Añadir secuencia (sk_fact_incidencia)", "Tipos finales"), ("Tipos finales", "Output fact_incidencias_equipaje")])


# ===================================================================== j00 job
def entrada(nombre, tipo, cuerpo, x, y):
    return ("<entry><name>%s</name><description/><type>%s</type>%s<parallel>N</parallel><draw>Y</draw>"
            "<nr>0</nr><xloc>%d</xloc><yloc>%d</yloc></entry>") % (e(nombre), tipo, cuerpo, x, y)


def entrada_trans(nombre, archivo, x, y):
    return entrada(nombre, "TRANS", "<specification_method>filename</specification_method><trans_object_id/>"
                   "<filename>%s/%s</filename><transname/><arg_from_previous>N</arg_from_previous>"
                   "<params_from_previous>N</params_from_previous><exec_per_row>N</exec_per_row>"
                   "<clear_rows>N</clear_rows><clear_files>N</clear_files><set_logfile>N</set_logfile><logfile/>"
                   "<logext/><add_date>N</add_date><add_time>N</add_time><loglevel>Basic</loglevel>"
                   "<cluster>N</cluster><slave_server_name/><set_append_logfile>N</set_append_logfile>"
                   "<wait_until_finished>Y</wait_until_finished><follow_abort_remote>N</follow_abort_remote>"
                   "<create_parent_folder>N</create_parent_folder><logging_remote_work>N</logging_remote_work>"
                   "<parameters><pass_all_parameters>Y</pass_all_parameters></parameters>"
                   % (DIR, archivo), x, y)


with io.open(os.path.join(AQUI, "..", "sql", "03_preparar_carga.sql"), encoding="utf-8") as fh:
    SQL_PREPARAR = fh.read()
PASOS_JOB = [("t01 dim_tiempo", "t01_dim_tiempo.ktr"), ("t02 dim_region", "t02_dim_region.ktr"),
             ("t03 dim_aeropuerto", "t03_dim_aeropuerto.ktr"), ("t04 dim_vuelo", "t04_dim_vuelo.ktr"),
             ("t05 dim_estado_inspeccion", "t05_dim_estado_inspeccion.ktr"),
             ("t06 dim_tipo_equipaje", "t06_dim_tipo_equipaje.ktr"),
             ("t07 fact_equipaje_procesado", "t07_fact_equipaje_procesado.ktr"),
             ("t08 fact_incidencias_equipaje", "t08_fact_incidencias_equipaje.ktr")]
entradas = [entrada("START", "SPECIAL", "<start>Y</start><dummy>N</dummy><repeat>N</repeat><schedulerType>0"
                    "</schedulerType><intervalSeconds>0</intervalSeconds><intervalMinutes>60</intervalMinutes>"
                    "<hour>12</hour><minutes>0</minutes><weekDay>1</weekDay><DayOfMonth>1</DayOfMonth>", 60, 80),
            entrada("Preparar datamart", "SQL",
                    "<sql>%s</sql><useVariableSubstitution>F</useVariableSubstitution><sqlfromfile>F</sqlfromfile>"
                    "<sqlfilename/><sendOneStatement>F</sendOneStatement><connection>%s</connection>"
                    % (e(SQL_PREPARAR), DM), 300, 80)]
coords = [(560, 80), (820, 80), (1080, 80), (1080, 260), (820, 260), (560, 260), (300, 260), (300, 440)]
for (n, a), (x, y) in zip(PASOS_JOB, coords):
    entradas.append(entrada_trans(n, a, x, y))
entradas.append(entrada("Success", "SUCCESS", "", 560, 440))
orden = ["START", "Preparar datamart"] + [n for n, _ in PASOS_JOB] + ["Success"]
hops = "".join("<hop><from>%s</from><to>%s</to><from_nr>0</from_nr><to_nr>0</to_nr><enabled>Y</enabled>"
               "<evaluation>Y</evaluation><unconditional>%s</unconditional></hop>"
               % (e(a), e(b), "Y" if a == "START" else "N") for a, b in zip(orden, orden[1:]))
job = ('<?xml version="1.0" encoding="UTF-8"?>\n<job><name>j00_cargar_datamart</name>'
       "<description>Carga completa del Data Mart G8: prepara las tablas, carga las 6 dimensiones y luego los 2 hechos"
       "</description><extended_description/><job_version/><job_status>0</job_status><directory>/</directory>"
       "<parameters></parameters>%s<slaveservers></slaveservers><entries>%s</entries><hops>%s</hops>"
       "<notepads></notepads></job>\n") % (conexion(DM, "g8_datamart"), "".join(entradas), hops)
with io.open(os.path.join(AQUI, "j00_cargar_datamart.kjb"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write(job)
print("escrito j00_cargar_datamart.kjb -", len(entradas), "entradas")
