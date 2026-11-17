# -*- coding: utf-8 -*-
"""
G8 · Avance 4 · Generador de los documentos nuevos de MongoDB (v2)

Lee salida/muestra_maletas.tsv (3.000 maletas reales del modelo relacional,
ver 01_muestra_maletas.sql) y escribe un archivo EJSON por colección en
salida/. No se conecta a ninguna base: solo produce archivos.

Qué cambia frente a los datos del Avance 3
  · Cada maleta de la muestra tiene inspección, telemetría y notificación
    (antes las tres colecciones no compartían ninguna maleta).
  · El aeropuerto de cada documento está en la ruta de la maleta y la fecha
    cae entre su check-in (T) y su entrega (T + 180 min) en SQL.
  · Hay varias lecturas de telemetría por maleta (origen, conexión, destino),
    así que se pueden calcular tiempos.
  · Los resultados varían (retenciones, desvíos en conexión, demoras) y hay
    campos opcionales, o sea, diversidad estructural.
  · Se respetan los nombres de colección, los _id y los validadores vigentes.

Los datos son sintéticos y deterministas: misma muestra -> mismos documentos.
"""
import csv
import datetime as dt
import hashlib
import io
import json
import math
import os
import random
from collections import Counter, defaultdict

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, "salida")
SEMILLA = "G8-avance4-v2"

HUBS = {"CLT", "PHL", "JFK", "LGA", "DCA", "MIA", "DFW", "ORD", "PHX", "LAX"}
AEROPUERTOS = {
    "ESTE": ["CLT", "PHL", "JFK", "LGA", "DCA", "MIA", "BOS", "EWR", "BWI", "IAD", "PIT", "RDU", "ATL", "MCO"],
    "CENTRAL": ["DFW", "ORD", "MSP", "DTW", "CLE", "STL", "MCI", "MSY", "IAH", "AUS", "SAT", "MEM", "BNA", "MDW"],
    "OESTE": ["PHX", "LAX", "SFO", "SAN", "LAS", "SEA", "PDX", "SLC", "DEN", "ABQ", "TUS", "SJC", "SNA", "OAK"],
}
TODOS = [a for lista in AEROPUERTOS.values() for a in lista]


def factor(aeropuerto):
    """Factor fijo por aeropuerto entre 0,6 y 1,8: unos operan mejor que otros."""
    h = int(hashlib.md5(("f-" + aeropuerto).encode()).hexdigest()[:8], 16)
    return 0.6 + (h % 1000) / 1000 * 1.2


def iso(t):
    return {"$date": t.strftime("%Y-%m-%dT%H:%M:%S") + "Z"}


def limitar(x, lo, hi):
    return max(lo, min(hi, x))


TERMINALES = ["T1", "T2", "T3", "TA", "TB", "TC", "TD"]
DEPARTAMENTOS = ["Seguridad de Equipaje Facturado", "Inspección Secundaria", "Unidad Canina K9"]
ARTICULOS = [
    ("Electrónicos", "Batería externa Powerbank", True),
    ("Electrónicos", "Computadora portátil", True),
    ("Líquidos", "Envase de más de 100 ml", False),
    ("Líquidos", "Perfume en envase sellado", True),
    ("Herramientas", "Destornillador de 20 cm", False),
    ("Deportivos", "Bate de béisbol", True),
    ("Inflamables", "Encendedor de gas", False),
    ("Inflamables", "Aerosol de pintura", False),
    ("Alimentos", "Productos cárnicos sin declarar", False),
    ("Medicamentos", "Medicamento con receta", True),
]
MOTIVOS_RETENCION = ["Artículo prohibido", "Imagen de rayos X no concluyente", "Alerta de trazas químicas", "Documentación incompleta"]
OBSERVACIONES = ["Se reacomodó el contenido tras la revisión", "Candado TSA reemplazado", "Líquidos reempacados en bolsa sellada", "Etiqueta de equipaje reimpresa"]
MENSAJES = {
    "EQUIPAJE_EN_CARRUSEL": ("¡Tu equipaje ha llegado!", "Su maleta ya está en el carrusel {n}."),
    "EQUIPAJE_EN_CONEXION": ("Tu equipaje sigue contigo", "Su maleta fue transferida a su vuelo de conexión."),
    "EQUIPAJE_DEMORADO": ("Tu equipaje viene con demora", "Su maleta presentó una demora y llegará más tarde de lo previsto."),
    "EQUIPAJE_RETENIDO": ("Revisión de seguridad", "Su maleta fue retenida para una revisión adicional de seguridad."),
}
MENSAJES_EN = {
    "EQUIPAJE_EN_CARRUSEL": ("Your bag has arrived!", "Your bag is now on carousel {n}."),
    "EQUIPAJE_EN_CONEXION": ("Your bag is on its way", "Your bag was transferred to your connecting flight."),
    "EQUIPAJE_DEMORADO": ("Your bag is delayed", "Your bag was delayed and will arrive later than expected."),
    "EQUIPAJE_RETENIDO": ("Security screening", "Your bag was held for additional security screening."),
}
ASPECTOS = ["cinta_despejada", "personal_amable", "espera_larga", "maleta_maltratada", "senalizacion_clara", "entrega_rapida"]
COMENTARIOS_BUENOS = ["El equipaje llegó muy rápido al carrusel.", "Todo en orden, la maleta llegó intacta.", "Buen servicio en la entrega de equipaje."]
COMENTARIOS_MALOS = ["Esperé demasiado por la maleta.", "La maleta llegó golpeada.", "Mi equipaje no llegó con el resto del vuelo.", "Nadie informaba dónde estaba el equipaje."]
EQUIPOS = ["Brazo Clasificador", "Carrusel de Entrega", "Cinta Transportadora Principal", "Escáner Rayos X 3D"]
FABRICANTES = ["Siemens Logistics", "Vanderlande", "BEUMER Group", "Daifuku", "Smiths Detection"]
REPUESTOS = [("Rodamiento industrial", 120.0), ("Banda reforzada", 450.0), ("Motor eléctrico 5 HP", 980.0),
             ("Sensor óptico", 85.5), ("Tarjeta de control", 640.0), ("Rodillo de arrastre", 210.0)]


def metricas(rng):
    m = {}
    if rng.random() < 0.90:
        m["temperatura_c"] = round(rng.uniform(14, 34), 1)
    if rng.random() < 0.80:
        m["nivel_bateria_pct"] = rng.randint(15, 100)
    if rng.random() < 0.95:
        m["intensidad_senal_dbm"] = rng.randint(-95, -35)
    return m


def lectura(rng, n, etiqueta, aeropuerto, t, punto, alertas):
    ubic = {"terminal": rng.choice(TERMINALES), "cinta": "C-%02d" % rng.randint(1, 24)}
    if rng.random() < 0.60:
        ubic["nivel_zona"] = {"FACTURACION": "Nivel-1", "CLASIFICACION": "Subsuelo-A",
                              "TRANSFERENCIA": "Subsuelo-B", "CARRUSEL": "Llegadas"}[punto]
    ruido = [a for a, p in (("ESCANEADO_DUPLICADO", 0.04), ("LECTURA_RAPIDA", 0.04)) if rng.random() < p]
    return {"_id": "TEL-%04d" % n, "codigo_etiqueta": etiqueta, "codigo_aeropuerto": aeropuerto,
            "timestamp": iso(t), "punto_control": punto, "ubicacion_escaner": ubic,
            "metricas_sensor": metricas(rng), "alertas_detectadas": alertas + ruido}


def generar():
    with io.open(os.path.join(SALIDA, "muestra_maletas.tsv"), encoding="utf-8") as f:
        maletas = list(csv.DictReader(f, delimiter="\t"))

    tel, insp, noti, res = [], [], [], []
    stats = []                      # una fila por maleta para el resumen

    for m in maletas:
        rng = random.Random(SEMILLA + "-" + m["etiqueta"])
        T = dt.datetime.strptime(m["ts_checkin"], "%Y-%m-%d %H:%M:%S")
        entregado = T + dt.timedelta(minutes=180)
        minutos = lambda x: T + dt.timedelta(seconds=round(x * 60))
        ori, con, des = m["ori"], m["con"], m["des"]
        verano = 1.35 if T.month in (6, 7, 8) else 1.0

        # ---- inspección de seguridad -------------------------------------------------
        p_ret = min(0.05 * factor(ori) * verano, 0.35)
        u = rng.random()
        resultado = "RETENIDO" if u < p_ret else "APROBADO_CON_OBSERVACION" if u < p_ret + 0.15 else "APROBADO"
        apertura = rng.random() < {"RETENIDO": 0.85, "APROBADO_CON_OBSERVACION": 0.40, "APROBADO": 0.03}[resultado]
        min_retenida = rng.randint(12, 45) if resultado == "RETENIDO" else 0

        # tránsito por el sistema de equipaje en origen: del check-in a la última lectura
        transito = limitar(rng.gauss(28, 8), 8, 55)
        if apertura:
            transito += rng.uniform(15, 25)
        if resultado == "RETENIDO":
            transito += rng.uniform(5, 12)
        transito = min(transito, 86)          # la maleta figura "cargado" a T + 90 en SQL

        en_conexion = rng.random() < 0.12     # algunas inspecciones ocurren en el aeropuerto de conexión
        t_insp = minutos(rng.uniform(100, 124)) if en_conexion else minutos(transito * rng.uniform(0.3, 0.8))
        d = {"_id": "INSP-%04d" % len(insp), "codigo_etiqueta": m["etiqueta"],
             "codigo_aeropuerto": con if en_conexion else ori,
             "agente_responsable": {"id_agente": "TSA-%04d" % rng.randint(1000, 9999),
                                    "departamento": rng.choice(DEPARTAMENTOS)},
             "resultado_inspeccion": resultado, "requiere_apertura_manual": apertura}
        if apertura:
            arts = rng.sample(ARTICULOS, rng.randint(1, 3))
            if resultado == "RETENIDO" and all(a[2] for a in arts):
                arts[0] = rng.choice([a for a in ARTICULOS if not a[2]])
            d["articulos_inspeccionados"] = [{"categoria": c, "descripcion": s, "permitido": p} for c, s, p in arts]
        if resultado == "APROBADO_CON_OBSERVACION":
            d["observaciones"] = rng.choice(OBSERVACIONES)
        if resultado == "RETENIDO":
            d["retencion"] = {"motivo": rng.choice(MOTIVOS_RETENCION), "minutos_retenida": min_retenida}
        d["timestamp"] = iso(t_insp)
        insp.append(d)

        # ---- transferencia en el aeropuerto de conexión ------------------------------
        entre_regiones = m["region_ori"] != m["region_con"] or m["region_con"] != m["region_des"]
        p_fallo = 0.04 * factor(con) * (1.8 if entre_regiones else 1.0) * (1.0 if con in HUBS else 1.6)
        p_fallo = min(p_fallo + (0.10 if apertura else 0.0), 0.60)
        desvio = rng.random() < p_fallo
        t_con = rng.uniform(120, 138) if desvio else rng.uniform(105, 135)

        # ---- espera en el carrusel de destino: de la lectura de llegada a la entrega ---
        espera = limitar(rng.gauss(13, 4) * math.sqrt(factor(des)), 4, 24)
        if desvio:
            espera += rng.uniform(8, 13)
        espera = min(espera, 38)

        # ---- telemetría: una lectura por punto de control ----------------------------
        peso = float(m["peso_checkin"])
        if rng.random() < 0.10:
            tel.append(lectura(rng, len(tel), m["etiqueta"], ori, minutos(transito * rng.uniform(0.15, 0.5)), "CLASIFICACION", []))
        tel.append(lectura(rng, len(tel), m["etiqueta"], ori, minutos(transito), "FACTURACION",
                           ["ALERTA_PESO"] if peso > 23 else []))
        tel.append(lectura(rng, len(tel), m["etiqueta"], con, minutos(t_con), "TRANSFERENCIA",
                           ["DESVIACION_LIGERA"] if desvio else []))
        tel.append(lectura(rng, len(tel), m["etiqueta"], des, minutos(180 - espera), "CARRUSEL", []))

        # ---- notificación al dueño de la maleta --------------------------------------
        if resultado == "RETENIDO":
            tipo, t_not = "EQUIPAJE_RETENIDO", t_insp + dt.timedelta(minutes=rng.randint(2, 6))
        elif desvio or espera > 20:
            tipo, t_not = "EQUIPAJE_DEMORADO", minutos(t_con + rng.uniform(2, 8)) if desvio else minutos(180 - espera + 20)
        elif rng.random() < 0.65:
            tipo, t_not = "EQUIPAJE_EN_CARRUSEL", minutos(180 - espera + 1)
        else:
            tipo, t_not = "EQUIPAJE_EN_CONEXION", minutos(t_con + 1)
        idioma = "ES" if rng.random() < 0.6 else "EN"
        titulo, cuerpo = (MENSAJES if idioma == "ES" else MENSAJES_EN)[tipo]
        leido = rng.random() < 0.75
        estado = {"enviado": rng.random() < 0.97, "leido": leido}
        if leido:
            estado["timestamp_lectura"] = iso(t_not + dt.timedelta(minutes=rng.randint(1, 40)))
        d = {"_id": "NOT-%04d" % len(noti), "id_pasajero": int(m["pasajero_maleta"]), "codigo_etiqueta": m["etiqueta"],
             "canal": rng.choice(["APP_PUSH", "SMS", "EMAIL"]), "tipo_evento": tipo, "timestamp_envio": iso(t_not),
             "contenido_mensaje": {"titulo": titulo, "cuerpo": cuerpo.format(n=rng.randint(1, 12)), "idioma": idioma},
             "estado_envio": estado}
        compensacion = 0.0
        if tipo == "EQUIPAJE_DEMORADO" and desvio and rng.random() < 0.60:
            compensacion = float(rng.choice([25, 50, 75, 100, 150]))
            d["compensacion"] = {"monto_usd": compensacion, "tipo": rng.choice(["BONO", "MILLAS"])}
        noti.append(d)

        # ---- reseña del pasajero del boleto sobre ese vuelo (4 de cada 10 maletas) ---
        if rng.random() < 0.40:
            estado_maleta = rng.choices(["INTACTO", "RAYADO", "GOLPEADO", "DANADO"], [70, 17, 9, 4])[0]
            nota = 5 - (espera > 15) - (espera > 22) - desvio - (estado_maleta in ("GOLPEADO", "DANADO"))
            nota = int(limitar(nota + rng.choice([-1, 0, 0, 0, 1]), 1, 5))
            d = {"_id": "RES-%04d" % len(res), "id_pasajero": int(m["pasajero_boleto"]),
                 "numero_vuelo": m["numero_vuelo"], "calificacion_general": nota}
            if rng.random() < 0.85:
                d["evaluacion_equipaje"] = {"tiempo_espera_minutos": int(round(espera)), "estado_maleta": estado_maleta,
                                            "atencion_personal": rng.choice(["EXCELENTE", "BUENA", "BUENA", "REGULAR", "MALA"])}
            if rng.random() < 0.70:
                d["etiquetas_aspectos"] = rng.sample(ASPECTOS, rng.randint(1, 3))
            if rng.random() < 0.60:
                d["comentario"] = rng.choice(COMENTARIOS_BUENOS if nota >= 4 else COMENTARIOS_MALOS)
            d["fecha_registro"] = iso(entregado + dt.timedelta(minutes=rng.randint(120, 5 * 24 * 60)))
            res.append(d)

        stats.append(dict(resultado=resultado, apertura=apertura, en_conexion=en_conexion, desvio=desvio,
                          hub_con=con in HUBS, entre_regiones=entre_regiones, espera=espera, transito=transito,
                          tipo=tipo, region_des=m["region_des"], compensacion=compensacion, sobrepeso=peso > 23))

    # ---- mantenimiento de infraestructura: todos los aeropuertos, todo el año --------
    mnt = []
    inicio = dt.datetime(2026, 1, 5, 6, 0, 0)
    for a in TODOS:
        rng = random.Random(SEMILLA + "-mnt-" + a)
        for _ in range(14 if a in HUBS else 9):
            tipo = rng.choices(["PREVENTIVO", "CORRECTIVO", "EMERGENCIA"], [50, 30, 20 * factor(a)])[0]
            equipo = {"id_equipo": "EQP-%03d" % rng.randint(100, 999), "tipo": rng.choice(EQUIPOS)}
            if rng.random() < 0.80:
                equipo["fabricante"] = rng.choice(FABRICANTES)
            repuestos = []
            if tipo != "PREVENTIVO" or rng.random() < 0.50:
                for nombre, costo in rng.sample(REPUESTOS, rng.randint(1, 3)):
                    repuestos.append({"nombre_repuesto": nombre, "cantidad": rng.randint(1, 4), "costo_unitario": costo})
            horas = round(rng.uniform(1, 4) * {"PREVENTIVO": 1, "CORRECTIVO": 2, "EMERGENCIA": 3}[tipo], 1)
            costo = round(sum(r["cantidad"] * r["costo_unitario"] for r in repuestos) + horas * 65.0, 2)
            d = {"_id": "MNT-%04d" % len(mnt), "codigo_aeropuerto": a, "equipo": equipo, "tipo_intervencion": tipo,
                 "costo_total_usd": costo, "tecnicos_asignados": ["TEC-%02d" % rng.randint(10, 99) for _ in range(rng.randint(1, 3))]}
            if repuestos:
                d["repuestos_utilizados"] = repuestos
            if rng.random() < 0.70:
                d["duracion_horas"] = horas
            d["fecha_mantenimiento"] = iso(inicio + dt.timedelta(minutes=rng.randint(0, 309 * 24 * 60)))
            mnt.append(d)

    colecciones = {"telemetria_escanner_equipaje": tel, "inspecciones_seguridad_tsa": insp,
                   "notificaciones_pasajero": noti, "resenas_servicio_pasajero": res,
                   "mantenimiento_infraestructura": mnt}
    for nombre, docs in colecciones.items():
        assert len(docs) <= 10000, nombre + ": los _id solo admiten 4 dígitos"
        with io.open(os.path.join(SALIDA, nombre + ".json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(docs, f, ensure_ascii=False, indent=1)
    return colecciones, stats


def resumen(colecciones, stats):
    n = len(stats)
    pct = lambda cond, base=None: "%.1f %%" % (100.0 * sum(1 for s in (base or stats) if cond(s)) / max(1, len(base or stats)))
    prom = lambda campo, base=None: "%.1f" % (sum(s[campo] for s in (base or stats)) / max(1, len(base or stats)))
    L = ["Maletas de la muestra: %d" % n, "", "Documentos por colección:"]
    L += ["  %-32s %5d" % (k, len(v)) for k, v in colecciones.items()]
    L += ["", "Campos opcionales (documentos que los traen):"]
    for nombre, docs in colecciones.items():
        c = Counter(k for d in docs for k in d)
        L.append("  " + nombre + ": " + ", ".join("%s %d" % (k, v) for k, v in sorted(c.items()) if v < len(docs)))
    L += ["", "Inspección: " + ", ".join("%s %d" % kv for kv in Counter(s["resultado"] for s in stats).most_common()),
          "  con apertura manual: " + pct(lambda s: s["apertura"]),
          "  hechas en el aeropuerto de conexión: " + pct(lambda s: s["en_conexion"]),
          "", "Transferencia con desvío: " + pct(lambda s: s["desvio"]),
          "  conexión en hub: " + pct(lambda s: s["desvio"], [s for s in stats if s["hub_con"]]) +
          " · conexión fuera de hub: " + pct(lambda s: s["desvio"], [s for s in stats if not s["hub_con"]]),
          "  ruta dentro de una región: " + pct(lambda s: s["desvio"], [s for s in stats if not s["entre_regiones"]]) +
          " · entre regiones: " + pct(lambda s: s["desvio"], [s for s in stats if s["entre_regiones"]]),
          "  con apertura manual: " + pct(lambda s: s["desvio"], [s for s in stats if s["apertura"]]) +
          " · sin apertura: " + pct(lambda s: s["desvio"], [s for s in stats if not s["apertura"]]),
          "", "Tránsito en origen (min, check-in a última lectura): promedio " + prom("transito"),
          "  con apertura manual: " + prom("transito", [s for s in stats if s["apertura"]]) +
          " · sin apertura: " + prom("transito", [s for s in stats if not s["apertura"]]),
          "", "Espera en carrusel (min, lectura de llegada a entrega): promedio " + prom("espera"),
          "  hasta 20 min: " + pct(lambda s: s["espera"] <= 20),
          "  por región de destino: " + " · ".join(
              "%s %s" % (r, prom("espera", [s for s in stats if s["region_des"] == r])) for r in AEROPUERTOS),
          "  con desvío: " + prom("espera", [s for s in stats if s["desvio"]]) +
          " · sin desvío: " + prom("espera", [s for s in stats if not s["desvio"]]),
          "", "Notificaciones: " + ", ".join("%s %d" % kv for kv in Counter(s["tipo"] for s in stats).most_common()),
          "  con compensación: %d (total USD %.2f)" % (sum(1 for s in stats if s["compensacion"]), sum(s["compensacion"] for s in stats)),
          "", "Maletas con sobrepeso (> 23 kg en el check-in de SQL) -> ALERTA_PESO: " + pct(lambda s: s["sobrepeso"])]
    texto = "\n".join(L)
    with io.open(os.path.join(SALIDA, "resumen_generacion.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(texto + "\n")
    print(texto)


if __name__ == "__main__":
    resumen(*generar())
