#!/usr/bin/env python3
"""Genera una carga masiva y reproducible para Bodegas del Atuel.

Uso:
    python db/seed/generar_datos.py --seed 42 --fecha-ref 2026-11-08
    python db/seed/generar_datos.py --reset --seed 42

Variables de entorno:
    DB_HOST / PGHOST        (default: localhost)
    DB_PORT / PGPORT        (default: 5433)
    DB_USER / PGUSER        (default: postgres)
    DB_PASSWORD / PGPASSWORD (default: postgres)
    DB_NAME / PGDATABASE    (default: bodegas_del_atuel)
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import os
import random
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, time, timedelta
from decimal import ROUND_HALF_UP, Decimal
from time import perf_counter
from typing import Any, Sequence

import psycopg
from faker import Faker
from psycopg import Connection

from cargar_catalogos import (
    cargar_cepas,
    cargar_maridajes,
    leer_csv,
    obtener_config_db,
    preparar_cepas,
    preparar_maridajes,
)

CENTAVOS = Decimal("0.01")
PROGRESO_COMPROBANTES = 25_000
PROGRESO_INSERCION = 50_000
LOCK_TIMEOUT_DEFAULT = 30

logger = logging.getLogger("generar_datos")

TABLAS_GENERADAS = (
    "localidades",
    "encargado_regional",
    "sala_de_ventas",
    "empleado",
    "bodega",
    "empresa_transporte",
    "transportista_de_localidad",
    "finca",
    "parcelas",
    "lote_uva",
    "analisis_calidad",
    "vino",
    "composicion",
    "vino_maridaje",
    "clientes",
    "socio_club",
    "distribuidores",
    "exportadores",
    "permisos",
    "stock_central",
    "stock_sala",
    "ingresos",
    "detalle_ingreso",
    "transferencias",
    "detalle_transferencia",
    "comprobante",
    "detalle_comprobante",
    "auditoria_precio",
)

TABLAS_HASH = TABLAS_GENERADAS + ("cepa", "maridaje")

PK_HASH = {
    "localidades": ("codigo_postal",),
    "encargado_regional": ("codigo_postal_localidad",),
    "sala_de_ventas": ("id_sala",),
    "empleado": ("cuit",),
    "bodega": ("cuit",),
    "empresa_transporte": ("cod_transporte",),
    "transportista_de_localidad": ("codigo_postal", "cod_transporte"),
    "finca": ("id",),
    "parcelas": ("id_finca", "identificador"),
    "lote_uva": ("num_lote",),
    "analisis_calidad": ("identificador",),
    "vino": ("id",),
    "composicion": ("id_cepa", "id_vino"),
    "vino_maridaje": ("cod_vino", "cod_maridaje"),
    "clientes": ("id",),
    "socio_club": ("id",),
    "distribuidores": ("id",),
    "exportadores": ("id",),
    "permisos": ("id",),
    "stock_central": ("codigo_vino",),
    "stock_sala": ("id_sala", "cod_vino"),
    "ingresos": ("id",),
    "detalle_ingreso": ("num_ingreso", "cod_vino"),
    "transferencias": ("num_solicitud",),
    "detalle_transferencia": ("num_transferencia", "cod_vino"),
    "comprobante": ("numero",),
    "detalle_comprobante": ("cod_comprobante", "cod_vino"),
    "auditoria_precio": ("id",),
    "cepa": ("identificador",),
    "maridaje": ("id",),
}

TABLAS_CON_TRIGGERS = (
    "composicion",
    "detalle_comprobante",
    "ingresos",
    "transferencias",
    "detalle_ingreso",
    "detalle_transferencia",
    "vino",
)

SECUENCIAS = (
    ("sala_de_ventas", "id_sala"),
    ("empresa_transporte", "cod_transporte"),
    ("finca", "id"),
    ("lote_uva", "num_lote"),
    ("analisis_calidad", "identificador"),
    ("vino", "id"),
    ("clientes", "id"),
    ("ingresos", "id"),
    ("transferencias", "num_solicitud"),
    ("comprobante", "numero"),
    ("auditoria_precio", "id"),
)

LOCALIDADES_BASE = (
    ("San Rafael", "Mendoza", 5600),
    ("General Alvear", "Mendoza", 5620),
    ("Malargüe", "Mendoza", 5613),
    ("Luján de Cuyo", "Mendoza", 5507),
    ("Maipú", "Mendoza", 5515),
    ("Tupungato", "Mendoza", 5561),
    ("Tunuyán", "Mendoza", 5560),
    ("San Carlos", "Mendoza", 5569),
    ("Lavalle", "Mendoza", 5533),
    ("Rivadavia", "Mendoza", 5577),
    ("Junín", "Mendoza", 5573),
    ("San Martín", "Mendoza", 5570),
    ("Santa Rosa", "Mendoza", 5596),
    ("La Paz", "Mendoza", 5594),
    ("Godoy Cruz", "Mendoza", 5501),
    ("Guaymallén", "Mendoza", 5521),
    ("Las Heras", "Mendoza", 5539),
    ("Capital", "Mendoza", 5500),
    ("Villa Atuel", "Mendoza", 5605),
    ("Bowen", "Mendoza", 5634),
    ("Chacras de Coria", "Mendoza", 5505),
    ("Rodeo del Medio", "Mendoza", 5519),
    ("La Consulta", "Mendoza", 5567),
    ("Vista Flores", "Mendoza", 5565),
    ("Eugenio Bustos", "Mendoza", 5568),
    ("Palmira", "Mendoza", 5584),
    ("San José", "Mendoza", 5586),
    ("Real del Padre", "Mendoza", 5609),
    ("Monte Comán", "Mendoza", 5611),
    ("El Algarrobal", "Mendoza", 5541),
)

BODEGAS_RAZONES = (
    "Bodega Los Andes",
    "Bodegas del Atuel",
    "Viña San Rafael",
    "Bodega Cauce Alto",
    "Bodega Tierra Roja",
    "Bodega Piedra Libre",
    "Bodega Valle Hermoso",
    "Bodega Cumbre Andina",
    "Bodega Río Claro",
    "Bodega Estancia Vieja",
    "Bodega Origen Mendocino",
    "Bodega Pequeña Selección",
)

PAISES_DESTINO = (
    "Brasil",
    "Estados Unidos",
    "Canadá",
    "Reino Unido",
    "España",
    "Alemania",
    "Países Bajos",
    "Japón",
    "China",
    "México",
    "Chile",
    "Uruguay",
)

MARCAS_VINO = (
    "Alma Andina",
    "Cauce",
    "Roca Madre",
    "Valle Alto",
    "Los Andes",
    "Piedra Libre",
    "Atuel",
    "Cuyo",
    "Tierra Roja",
    "Vendimia",
    "Cumbre",
    "Río Claro",
    "Bodega del Sur",
    "Estancia Vieja",
    "Racimo",
    "Terroir",
    "Finca Nueva",
    "Reserva del Plata",
    "Origen",
    "Selección",
)

ADJETIVOS_VINO = (
    "Clásico",
    "Reserva",
    "Gran Reserva",
    "Roble",
    "Selección",
    "Colección",
)

DIAS_CIERRE = (
    "Lunes",
    "Martes",
    "Miércoles",
    "Jueves",
    "Viernes",
    "Sábado",
    "Domingo",
)

SOCIOS_ANTIGUOS = frozenset(range(500, 600))
NO_COMPRA_ANTIGUOS = frozenset(range(15201, 15301))
VINO_MALBEC_RESERVA = 1
SALAS_ACTIVIDAD_RECIENTE = 6


@dataclass(frozen=True)
class VinoDatos:
    id: int
    nombre: str
    volumen: int
    precio: Decimal
    graduacion: Decimal
    tipo: str
    anada: int
    cuit_bodega: str
    cepa_principal: int


def dec2(valor: Any) -> Decimal:
    return Decimal(str(valor)).quantize(CENTAVOS, rounding=ROUND_HALF_UP)


def fecha_ingreso_vino(vino: VinoDatos) -> date:
    return date(vino.anada, 4, 1)


def fecha_transferencia_vino(vino: VinoDatos) -> date:
    return date(vino.anada, 5, 1)


def fecha_venta_vino(vino: VinoDatos) -> date:
    return date(vino.anada, 6, 1)


def vino_disponible_para_transferencia(vino: VinoDatos, fecha: date) -> bool:
    return fecha >= fecha_transferencia_vino(vino)


def vino_disponible_para_venta(vino: VinoDatos, fecha: date) -> bool:
    return fecha >= fecha_venta_vino(vino)


def fecha_aleatoria(rng: random.Random, inicio: date, fin: date) -> date:
    if fin < inicio:
        return inicio
    return inicio + timedelta(days=rng.randint(0, (fin - inicio).days))


def calcular_campanias(fecha_ref: date) -> list[int]:
    campanias: list[int] = []
    for anio in range(fecha_ref.year, fecha_ref.year - 10, -1):
        if date(anio, 4, 30) <= fecha_ref:
            campanias.append(anio)
        if len(campanias) == 5:
            break
    return sorted(campanias)


def insertar_lote(
    conexion: Connection,
    tabla: str,
    columnas: Sequence[str],
    filas: Sequence[Sequence[Any]],
    *,
    tamano_lote: int = 5000,
    overriding: bool = False,
) -> int:
    if not filas:
        return 0

    modo = " OVERRIDING SYSTEM VALUE" if overriding else ""
    marcadores = ", ".join(["%s"] * len(columnas))
    fila_sql = f"({marcadores})"
    sql_base = f"INSERT INTO {tabla} ({', '.join(columnas)}){modo} VALUES "
    tamano_lote = min(tamano_lote, 60_000 // len(columnas))
    total = len(filas)
    informar = total >= PROGRESO_INSERCION
    if informar:
        logger.info("Insertando %s: %d filas...", tabla, total)
    with conexion.cursor() as cursor:
        for inicio in range(0, total, tamano_lote):
            lote = filas[inicio : inicio + tamano_lote]
            sql = sql_base + ", ".join([fila_sql] * len(lote))
            parametros = [valor for fila in lote for valor in fila]
            cursor.execute(sql, parametros)
            if informar:
                logger.info(
                    "  %s: %d/%d filas",
                    tabla,
                    min(inicio + tamano_lote, total),
                    total,
                )

    return total


def hay_datos(conexion: Connection) -> str | None:
    with conexion.cursor() as cursor:
        for tabla in TABLAS_GENERADAS:
            cursor.execute(f"SELECT 1 FROM {tabla} LIMIT 1")
            if cursor.fetchone() is not None:
                return tabla
    return None


def diagnosticar_bloqueos(conexion: Connection) -> None:
    with conexion.cursor() as cursor:
        cursor.execute(
            """
            SELECT a.pid, a.state, a.wait_event_type, a.wait_event,
                   a.xact_start, pg_blocking_pids(a.pid), left(a.query, 200)
            FROM pg_stat_activity a
            WHERE a.datname = current_database()
              AND a.pid <> pg_backend_pid()
              AND (a.state <> 'idle' OR a.xact_start IS NOT NULL)
            ORDER BY a.xact_start NULLS LAST
            """
        )
        sesiones = cursor.fetchall()

    if not sesiones:
        logger.info("No hay otras sesiones activas; el TRUNCATE no debería esperar locks.")
        return

    logger.warning("Hay %d sesión(es) más en la base:", len(sesiones))
    for pid, estado, tipo_espera, espera, xact, bloqueantes, consulta in sesiones:
        logger.warning(
            "  pid=%s estado=%s espera=%s/%s xact=%s bloquea_a=%s query=%s",
            pid,
            estado,
            tipo_espera,
            espera,
            xact,
            bloqueantes,
            consulta,
        )


def configurar_lock_timeout(conexion: Connection) -> None:
    valor = os.getenv("SEED_LOCK_TIMEOUT", str(LOCK_TIMEOUT_DEFAULT))
    try:
        segundos = int(valor)
    except ValueError as exc:
        raise ValueError(f"SEED_LOCK_TIMEOUT inválido: {valor!r}") from exc
    if segundos < 0:
        raise ValueError(f"SEED_LOCK_TIMEOUT inválido: {valor!r}")

    with conexion.cursor() as cursor:
        cursor.execute("SELECT set_config('lock_timeout', %s, true)", (f"{segundos}s",))
    logger.info("lock_timeout configurado en %s s", segundos)


def truncar_tablas_generadas(conexion: Connection) -> None:
    diagnosticar_bloqueos(conexion)
    configurar_lock_timeout(conexion)
    tablas = ", ".join(TABLAS_GENERADAS)
    inicio = perf_counter()
    try:
        with conexion.cursor() as cursor:
            cursor.execute(f"TRUNCATE TABLE {tablas} RESTART IDENTITY CASCADE")
    except psycopg.errors.LockNotAvailable as exc:
        logger.error(
            "El TRUNCATE no pudo tomar los locks dentro del lock_timeout. "
            "Otra corrida o sesión está bloqueando las tablas."
        )
        try:
            with psycopg.connect(**obtener_config_db()) as otra_conexion:
                diagnosticar_bloqueos(otra_conexion)
        except psycopg.Error:
            logger.exception("No se pudo consultar pg_stat_activity tras el timeout")
        raise exc
    logger.info("TRUNCATE completado en %.2f s", perf_counter() - inicio)


def deshabilitar_triggers(conexion: Connection) -> None:
    with conexion.cursor() as cursor:
        for tabla in TABLAS_CON_TRIGGERS:
            cursor.execute(f"ALTER TABLE {tabla} DISABLE TRIGGER USER")


def habilitar_triggers(conexion: Connection) -> None:
    with conexion.cursor() as cursor:
        for tabla in TABLAS_CON_TRIGGERS:
            cursor.execute(f"ALTER TABLE {tabla} ENABLE TRIGGER USER")


def actualizar_secuencias(conexion: Connection) -> None:
    with conexion.cursor() as cursor:
        for tabla, columna in SECUENCIAS:
            cursor.execute(
                f"SELECT setval(pg_get_serial_sequence('{tabla}', '{columna}'), "
                f"(SELECT COALESCE(MAX({columna}), 1) FROM {tabla}))"
            )


def asegurar_catalogos(conexion: Connection) -> None:
    with conexion.cursor() as cursor:
        cursor.execute("SELECT COUNT(*) FROM cepa")
        cepas_actuales = cursor.fetchone()[0]
        cursor.execute("SELECT COUNT(*) FROM maridaje")
        maridajes_actuales = cursor.fetchone()[0]

    if cepas_actuales == 0:
        filas = leer_csv("cepas.csv", ("tipo", "nombre"))
        cepas = preparar_cepas("cepas.csv", filas)
        cargar_cepas(conexion, cepas)

    if maridajes_actuales == 0:
        filas = leer_csv("maridajes.csv", ("nombre", "temperatura"))
        maridajes = preparar_maridajes("maridajes.csv", filas)
        cargar_maridajes(conexion, maridajes)


def leer_catalogos(conexion: Connection) -> tuple[list[dict[str, Any]], list[int]]:
    with conexion.cursor() as cursor:
        cursor.execute(
            "SELECT identificador, tipo, nombre FROM cepa ORDER BY identificador"
        )
        cepas = [
            {"id": fila[0], "tipo": fila[1], "nombre": fila[2]}
            for fila in cursor.fetchall()
        ]
        cursor.execute("SELECT id, nombre FROM maridaje ORDER BY id")
        maridajes = [{"id": fila[0], "nombre": fila[1]} for fila in cursor.fetchall()]
    return cepas, [maridaje["id"] for maridaje in maridajes]


def parsear_argumentos() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Genera datos masivos y reproducibles para Bodegas del Atuel."
    )
    parser.add_argument("--seed", type=int, default=42, help="semilla aleatoria")
    parser.add_argument(
        "--fecha-ref",
        type=date.fromisoformat,
        default=date.today(),
        help="fecha de referencia en formato ISO (default: hoy)",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="vacía las tablas generadas antes de insertar",
    )
    return parser.parse_args()


def main() -> int:
    args = parsear_argumentos()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%H:%M:%S",
    )
    config = obtener_config_db()
    logger.info(
        "Conectando a %s:%s/%s como %s...",
        config["host"],
        config["port"],
        config["dbname"],
        config["user"],
    )

    rng = random.Random(args.seed)
    faker = Faker("es_AR")
    faker.seed_instance(args.seed)
    tiempos: list[tuple[str, float]] = []

    try:
        with psycopg.connect(**config) as conexion:
            logger.info("Conexión establecida")
            with conexion.transaction():
                logger.info("Asegurando catálogos obligatorios...")
                asegurar_catalogos(conexion)
                logger.info("Catálogos listos")
                if args.reset:
                    logger.info("Truncando tablas generadas (--reset)")
                    truncar_tablas_generadas(conexion)
                else:
                    tabla_con_datos = hay_datos(conexion)
                    if tabla_con_datos is not None:
                        raise RuntimeError(
                            f"La tabla {tabla_con_datos} ya tiene datos. "
                            "Usá --reset para regenerar la carga."
                        )

                logger.info("Deshabilitando triggers de usuario...")
                deshabilitar_triggers(conexion)
                try:
                    logger.info("Iniciando generación de datos...")
                    generar_datos(conexion, rng, faker, args.fecha_ref, tiempos)
                finally:
                    logger.info("Habilitando triggers de usuario...")
                    habilitar_triggers(conexion)

                logger.info("Actualizando secuencias...")
                actualizar_secuencias(conexion)

            logger.info("Transacción confirmada. Generando reporte...")
            return imprimir_reporte(conexion, tiempos)
    except (psycopg.Error, RuntimeError, ValueError) as exc:
        logger.error("Error durante la generación: %s", exc)
        return 1


def generar_cuit(
    rng: random.Random,
    usados: set[str],
    prefijos: tuple[str, ...] = ("20", "23", "24", "27"),
) -> str:
    while True:
        cuit = (
            f"{rng.choice(prefijos)}"
            f"{rng.randint(10_000_000, 99_999_999):08d}"
            f"{rng.randint(0, 9)}"
        )
        if cuit not in usados:
            usados.add(cuit)
            return cuit


def generar_localidades(conexion: Connection) -> dict[int, str]:
    localidades = [
        (codigo_postal, nombre, provincia)
        for nombre, provincia, codigo_postal in LOCALIDADES_BASE
    ]
    insertar_lote(
        conexion,
        "localidades",
        ("codigo_postal", "nombre", "provincia"),
        localidades,
    )
    return {codigo_postal: nombre for codigo_postal, nombre, _ in localidades}


def generar_encargados(
    conexion: Connection,
    rng: random.Random,
    faker: Faker,
    localidades: dict[int, str],
) -> None:
    encargados = [
        (faker.name(), codigo_postal) for codigo_postal in sorted(localidades)
    ]
    insertar_lote(
        conexion,
        "encargado_regional",
        ("nombre", "codigo_postal_localidad"),
        encargados,
    )


def generar_salas(
    conexion: Connection,
    rng: random.Random,
    faker: Faker,
    localidades: dict[int, str],
) -> list[tuple[int, int]]:
    obligatorias = {5600, 5620, 5500}
    restantes = sorted(set(localidades) - obligatorias)
    seleccion = set(obligatorias)
    seleccion.update(rng.sample(restantes, 12))
    codigos = sorted(seleccion)

    salas: list[tuple[int, int]] = []
    filas: list[tuple[str, int, str, int]] = []
    for indice, codigo_postal in enumerate(codigos):
        if indice < 2:
            dia_cierre = "Lunes"
        elif indice < 4:
            dia_cierre = "Miércoles"
        else:
            dia_cierre = rng.choice(DIAS_CIERRE)
        calle = faker.street_name()
        numero = rng.randint(10, 5000)
        filas.append((calle, numero, dia_cierre, codigo_postal))
        salas.append((indice + 1, codigo_postal))

    insertar_lote(
        conexion,
        "sala_de_ventas",
        ("id_sala", "calle", "numero", "dia_cierre", "codigo_postal"),
        [
            (id_sala, calle, numero, dia_cierre, codigo_postal)
            for (id_sala, _), (calle, numero, dia_cierre, codigo_postal) in zip(
                salas, filas
            )
        ],
        overriding=True,
    )
    return salas


def generar_empleados(
    conexion: Connection,
    rng: random.Random,
    faker: Faker,
    salas: Sequence[tuple[int, int]],
    fecha_ref: date,
) -> None:
    usados: set[str] = set()
    filas: list[tuple[str, str, date, Decimal, int]] = []
    indice = 0
    for id_sala, _ in salas:
        for _ in range(8):
            if indice < 20:
                dias = rng.randint(6 * 365, 9 * 365)
            elif indice < 40:
                dias = rng.randint(180, 700)
            else:
                dias = rng.randint(0, 5 * 365)
            filas.append(
                (
                    generar_cuit(rng, usados),
                    faker.name(),
                    fecha_ref - timedelta(days=dias),
                    dec2(rng.randint(450_000, 1_500_000)),
                    id_sala,
                )
            )
            indice += 1

    insertar_lote(
        conexion,
        "empleado",
        ("cuit", "nombre", "fecha_ingreso", "salario", "id_sala"),
        filas,
    )


def generar_bodegas(
    conexion: Connection,
    rng: random.Random,
    faker: Faker,
) -> list[dict[str, Any]]:
    usados: set[str] = set()
    bodegas = [
        {
            "cuit": generar_cuit(rng, usados, ("30", "33", "34")),
            "razon_social": razon_social,
            "calle": faker.street_name(),
            "num_calle": rng.randint(10, 4000),
        }
        for razon_social in BODEGAS_RAZONES
    ]
    insertar_lote(
        conexion,
        "bodega",
        ("cuit", "razon_social", "calle", "num_calle"),
        [
            (
                bodega["cuit"],
                bodega["razon_social"],
                bodega["calle"],
                bodega["num_calle"],
            )
            for bodega in bodegas
        ],
    )
    return bodegas


def generar_empresas_transporte(
    conexion: Connection,
    rng: random.Random,
    faker: Faker,
) -> list[dict[str, Any]]:
    usados: set[str] = set()
    empresas = [
        {
            "cod_transporte": indice + 1,
            "razon_social": f"Transporte {faker.last_name()} {indice + 1:02d}",
            "cuit": generar_cuit(rng, usados, ("30", "33", "34")),
            "email": f"contacto{indice + 1:02d}@transportes.com.ar",
            "telefono": f"2604{rng.randint(100000, 999999)}",
            "calle": faker.street_name(),
            "num_calle": rng.randint(10, 4000),
        }
        for indice in range(20)
    ]
    insertar_lote(
        conexion,
        "empresa_transporte",
        (
            "cod_transporte",
            "razon_social",
            "cuit",
            "email",
            "telefono",
            "calle",
            "num_calle",
        ),
        [
            (
                empresa["cod_transporte"],
                empresa["razon_social"],
                empresa["cuit"],
                empresa["email"],
                empresa["telefono"],
                empresa["calle"],
                empresa["num_calle"],
            )
            for empresa in empresas
        ],
        overriding=True,
    )
    return empresas


def generar_coberturas(
    conexion: Connection,
    rng: random.Random,
    localidades: dict[int, str],
    empresas: Sequence[dict[str, Any]],
) -> None:
    codigo_general_alvear = 5620
    sin_general_alvear = sorted(
        codigo for codigo in localidades if codigo != codigo_general_alvear
    )
    coberturas: set[tuple[int, int]] = set()

    for empresa in empresas:
        cod_transporte = empresa["cod_transporte"]
        elegidas = rng.sample(sin_general_alvear, 2)
        coberturas.update((codigo, cod_transporte) for codigo in elegidas)

        if cod_transporte <= 10:
            candidatas = [
                codigo for codigo in sin_general_alvear if codigo not in elegidas
            ]
            coberturas.add((rng.choice(candidatas), cod_transporte))
            coberturas.add((codigo_general_alvear, cod_transporte))

    insertar_lote(
        conexion,
        "transportista_de_localidad",
        ("codigo_postal", "cod_transporte"),
        sorted(coberturas),
    )


def generar_fincas(
    conexion: Connection,
    rng: random.Random,
    faker: Faker,
) -> list[dict[str, Any]]:
    departamentos = [
        (nombre, provincia) for nombre, provincia, _ in LOCALIDADES_BASE[:18]
    ]
    fincas = [
        {
            "id": indice + 1,
            "nombre": f"Finca {departamento} {indice + 1:02d}",
            "superficie": dec2(rng.randint(800, 2500)),
            "departamento": departamento,
            "provincia": provincia,
        }
        for indice, (departamento, provincia) in enumerate(departamentos)
    ]
    insertar_lote(
        conexion,
        "finca",
        ("id", "nombre", "superficie", "departamento", "provincia"),
        [
            (
                finca["id"],
                finca["nombre"],
                finca["superficie"],
                finca["departamento"],
                finca["provincia"],
            )
            for finca in fincas
        ],
        overriding=True,
    )
    return fincas


def generar_parcelas(
    conexion: Connection,
    rng: random.Random,
    fincas: Sequence[dict[str, Any]],
    cepas: Sequence[dict[str, Any]],
    fecha_ref: date,
) -> list[dict[str, Any]]:
    cepas_disponibles = [cepa["id"] for cepa in cepas if cepa["nombre"] != "Semillón"]
    contadores: dict[int, int] = defaultdict(int)
    parcelas: list[dict[str, Any]] = []

    for indice in range(700):
        finca = fincas[indice % len(fincas)]
        id_finca = finca["id"]
        contadores[id_finca] += 1
        parcelas.append(
            {
                "id_finca": id_finca,
                "identificador": contadores[id_finca],
                "superficie": dec2(rng.randint(2, 40)),
                "ano_plantacion": rng.randint(1980, fecha_ref.year - 3),
                "id_cepa": cepas_disponibles[indice % len(cepas_disponibles)],
            }
        )

    insertar_lote(
        conexion,
        "parcelas",
        ("id_finca", "identificador", "superficie", "ano_plantacion", "id_cepa"),
        [
            (
                parcela["id_finca"],
                parcela["identificador"],
                parcela["superficie"],
                parcela["ano_plantacion"],
                parcela["id_cepa"],
            )
            for parcela in parcelas
        ],
    )
    return parcelas


def generar_lotes_y_analisis(
    conexion: Connection,
    rng: random.Random,
    parcelas: Sequence[dict[str, Any]],
    bodegas: Sequence[dict[str, Any]],
    fecha_ref: date,
) -> None:
    campanias = calcular_campanias(fecha_ref)
    lotes: list[tuple[int, date, int, Decimal, str, int, int]] = []
    analisis: list[tuple[int, date, Decimal, Decimal, Decimal, int]] = []
    id_analisis = 1

    for parcela in parcelas:
        for campania in campanias:
            num_lote = len(lotes) + 1
            fin_cosecha = min(date(campania, 4, 30), fecha_ref - timedelta(days=1))
            fecha_cosecha = fecha_aleatoria(rng, date(campania, 2, 1), fin_cosecha)
            kilos = dec2(parcela["superficie"] * rng.randint(5000, 9000))
            bodega = bodegas[(num_lote + campania) % len(bodegas)]
            lotes.append(
                (
                    num_lote,
                    fecha_cosecha,
                    campania,
                    kilos,
                    bodega["cuit"],
                    parcela["id_finca"],
                    parcela["identificador"],
                )
            )

            for _ in range(2):
                inicio_analisis = fecha_cosecha + timedelta(days=1)
                fecha_analisis = fecha_aleatoria(rng, inicio_analisis, fecha_ref)
                analisis.append(
                    (
                        id_analisis,
                        fecha_analisis,
                        dec2(Decimal(rng.randint(1800, 2800)) / 100),
                        dec2(Decimal(rng.randint(300, 420)) / 100),
                        dec2(Decimal(rng.randint(450, 850)) / 100),
                        num_lote,
                    )
                )
                id_analisis += 1

    insertar_lote(
        conexion,
        "lote_uva",
        (
            "num_lote",
            "fecha_cosecha",
            "campania",
            "kilo_cosechado",
            "bodega_entrega",
            "id_finca",
            "id_parcela",
        ),
        lotes,
        overriding=True,
    )
    insertar_lote(
        conexion,
        "analisis_calidad",
        (
            "identificador",
            "fecha",
            "brix",
            "ph",
            "acidez_total",
            "num_lote",
        ),
        analisis,
        overriding=True,
    )


def generar_vinos(
    conexion: Connection,
    rng: random.Random,
    bodegas: Sequence[dict[str, Any]],
    cepas: Sequence[dict[str, Any]],
    maridajes: Sequence[int],
    fecha_ref: date,
) -> tuple[dict[int, VinoDatos], list[int], list[int], int]:
    cepas_utilizables = [cepa for cepa in cepas if cepa["nombre"] != "Semillón"]
    cepas_por_tipo: dict[str, list[dict[str, Any]]] = {
        "tinta": [cepa for cepa in cepas_utilizables if cepa["tipo"] == "tinta"],
        "blanca": [cepa for cepa in cepas_utilizables if cepa["tipo"] == "blanca"],
    }
    cepa_por_nombre = {cepa["nombre"]: cepa for cepa in cepas}
    with conexion.cursor() as cursor:
        cursor.execute("SELECT id, nombre FROM maridaje ORDER BY id")
        maridaje_por_nombre = {
            nombre: identificador for identificador, nombre in cursor
        }

    vinos: dict[int, VinoDatos] = {}
    composiciones: list[tuple[int, int, Decimal]] = []
    vino_maridajes: list[tuple[int, int]] = []
    anada_minima = max(2018, fecha_ref.year - 8)
    anada_maxima = max(anada_minima, (fecha_ref - timedelta(days=6 * 365)).year - 1)

    for id_vino in range(1, 501):
        if id_vino == 1:
            cepa = cepa_por_nombre["Malbec"]
            nombre = "Malbec Reserva"
            volumen = 750
            precio = dec2(12500)
            graduacion = dec2(14)
            anada = 2021
            cuit_bodega = bodegas[0]["cuit"]
        else:
            indice = id_vino - 2
            cepa = cepas_utilizables[indice % len(cepas_utilizables)]
            marca = MARCAS_VINO[indice % len(MARCAS_VINO)]
            adjetivo = ADJETIVOS_VINO[
                (indice // len(MARCAS_VINO)) % len(ADJETIVOS_VINO)
            ]
            nombre = f"{cepa['nombre']} {adjetivo} {marca}"
            volumen = rng.choice((750, 750, 750, 750, 1500, 375))
            if id_vino <= 6:
                cuit_bodega = bodegas[11]["cuit"]
            else:
                cuit_bodega = bodegas[(id_vino - 7) % 11]["cuit"]

            if cepa["tipo"] == "tinta":
                precio = dec2(rng.randint(3500, 25000))
                graduacion = dec2(Decimal(rng.randint(1150, 1550)) / 100)
            else:
                precio = dec2(rng.randint(2800, 18000))
                graduacion = dec2(Decimal(rng.randint(1050, 1400)) / 100)
            anada = rng.randint(anada_minima, anada_maxima)

        vinos[id_vino] = VinoDatos(
            id=id_vino,
            nombre=nombre,
            volumen=volumen,
            precio=precio,
            graduacion=graduacion,
            tipo="tinto" if cepa["tipo"] == "tinta" else "blanco",
            anada=anada,
            cuit_bodega=cuit_bodega,
            cepa_principal=cepa["id"],
        )

        if id_vino == 1:
            composiciones.extend(
                (
                    (cepa_por_nombre["Malbec"]["id"], id_vino, dec2(85)),
                    (cepa_por_nombre["Cabernet Sauvignon"]["id"], id_vino, dec2(15)),
                )
            )
        elif id_vino <= 51:
            composiciones.append((cepa["id"], id_vino, dec2(100)))
        elif id_vino <= 450:
            otras = [
                candidata
                for candidata in cepas_por_tipo[cepa["tipo"]]
                if candidata["id"] != cepa["id"]
            ]
            secundaria = rng.choice(otras)
            porcentaje = rng.randint(55, 90)
            composiciones.extend(
                (
                    (cepa["id"], id_vino, dec2(porcentaje)),
                    (secundaria["id"], id_vino, dec2(100 - porcentaje)),
                )
            )
        else:
            otras = [
                candidata
                for candidata in cepas_por_tipo[cepa["tipo"]]
                if candidata["id"] != cepa["id"]
            ]
            secundarias = rng.sample(otras, 2)
            primero = rng.randint(30, 50)
            segundo = rng.randint(20, 35)
            tercero = 100 - primero - segundo
            composiciones.extend(
                (
                    (cepa["id"], id_vino, dec2(primero)),
                    (secundarias[0]["id"], id_vino, dec2(segundo)),
                    (secundarias[1]["id"], id_vino, dec2(tercero)),
                )
            )

        if id_vino == 1:
            elegidos_maridaje = [
                maridaje_por_nombre["Carnes rojas"],
                maridaje_por_nombre["Quesos duros"],
            ]
        else:
            elegidos_maridaje = rng.sample(list(maridajes), 2)
        vino_maridajes.extend(
            (id_vino, id_maridaje) for id_maridaje in elegidos_maridaje
        )

    insertar_lote(
        conexion,
        "vino",
        (
            "id",
            "nombre",
            "volumen",
            "precio",
            "graduacion",
            "tipo",
            "anada",
            "cuit_bodega",
        ),
        [
            (
                vino.id,
                vino.nombre,
                vino.volumen,
                vino.precio,
                vino.graduacion,
                vino.tipo,
                vino.anada,
                vino.cuit_bodega,
            )
            for vino in vinos.values()
        ],
        overriding=True,
    )
    insertar_lote(
        conexion,
        "composicion",
        ("id_cepa", "id_vino", "porcentaje"),
        composiciones,
    )
    insertar_lote(
        conexion,
        "vino_maridaje",
        ("cod_vino", "cod_maridaje"),
        vino_maridajes,
    )

    bodega_pequena = sorted(
        id_vino
        for id_vino, vino in vinos.items()
        if vino.cuit_bodega == bodegas[11]["cuit"]
    )
    vinos_estrella = sorted(
        {
            1,
            7,
            8,
            9,
            next(vino.id for vino in vinos.values() if vino.tipo == "blanco"),
        }
    )
    return vinos, bodega_pequena, vinos_estrella, bodegas[11]["cuit"]


def generar_stock_pares(
    rng: random.Random,
    salas: Sequence[tuple[int, int]],
    vinos: dict[int, VinoDatos],
    bodega_pequena: Sequence[int],
    vinos_estrella: Sequence[int],
) -> tuple[dict[int, list[int]], int]:
    vino_reservado = 500
    fijos = sorted(set(bodega_pequena) | set(vinos_estrella))
    todos = sorted(vinos)
    pares: dict[int, list[int]] = {}

    for id_sala, _ in salas:
        candidatos = [id_vino for id_vino in todos if id_vino not in fijos]
        if id_sala == salas[-1][0]:
            candidatos = [
                id_vino for id_vino in candidatos if id_vino != vino_reservado
            ]
        faltantes = 300 - len(fijos)
        seleccion = set(fijos)
        seleccion.update(rng.sample(candidatos, faltantes))
        pares[id_sala] = sorted(seleccion)

    return pares, vino_reservado


def generar_clientes(
    conexion: Connection,
    rng: random.Random,
    faker: Faker,
    localidades: dict[int, str],
    fecha_ref: date,
    inicio_ventas: date,
) -> tuple[dict[int, dict[str, Any]], set[int], set[int], set[int]]:
    no_compra = set(range(15201, 16001)) | NO_COMPRA_ANTIGUOS
    sin_tinto = set(range(10001, 10401))
    forzados = set(range(300, 320))

    clientes: dict[int, dict[str, Any]] = {}
    filas_clientes: list[tuple[Any, ...]] = []
    filas_socios: list[tuple[int, str, str]] = []
    filas_distribuidores: list[tuple[int, str, str, str]] = []
    filas_exportadores: list[tuple[int, str, str]] = []
    codigos = sorted(localidades)

    for id_cliente in range(1, 20001):
        if id_cliente <= 16000:
            tipo_cliente = "socio"
            tipo_documento = "DNI"
            num_documento = f"{10_000_000 + id_cliente:08d}"
            descuento = dec2(10)
            nombre = faker.first_name()
            apellido = faker.last_name()
        elif id_cliente <= 19000:
            tipo_cliente = "distribuidor"
            tipo_documento = "CUIT"
            num_documento = f"{30_000_000_000 + id_cliente}"
            descuento = dec2(20)
            nombre = ""
            apellido = ""
        else:
            tipo_cliente = "exportador"
            tipo_documento = "CUIT"
            num_documento = f"{30_000_000_000 + id_cliente}"
            descuento = dec2(30)
            nombre = ""
            apellido = ""

        if id_cliente in no_compra or id_cliente in SOCIOS_ANTIGUOS:
            fecha_alta = fecha_aleatoria(
                rng,
                fecha_ref - timedelta(days=6 * 365),
                fecha_ref - timedelta(days=5 * 365 + 30),
            )
        elif rng.random() < 0.75:
            fecha_alta = inicio_ventas - timedelta(days=rng.randint(0, 3 * 365))
        else:
            fecha_alta = fecha_aleatoria(
                rng, inicio_ventas, fecha_ref - timedelta(days=10)
            )

        codigo_postal = rng.choice(codigos)
        calle = faker.street_name()
        numero_calle = str(rng.randint(1, 5000))
        clientes[id_cliente] = {
            "id": id_cliente,
            "tipo": tipo_cliente,
            "descuento": descuento,
            "fecha_alta": fecha_alta,
        }
        filas_clientes.append(
            (
                id_cliente,
                tipo_cliente,
                tipo_documento,
                num_documento,
                fecha_alta,
                calle,
                numero_calle,
                descuento,
                codigo_postal,
            )
        )

        if tipo_cliente == "socio":
            filas_socios.append((id_cliente, nombre, apellido))
        elif tipo_cliente == "distribuidor":
            filas_distribuidores.append(
                (
                    id_cliente,
                    localidades[codigo_postal],
                    f"HAB-{id_cliente:05d}",
                    f"Distribuidora {faker.last_name()}",
                )
            )
        else:
            filas_exportadores.append(
                (
                    id_cliente,
                    rng.choice(PAISES_DESTINO),
                    f"Exportadora {faker.last_name()}",
                )
            )

    insertar_lote(
        conexion,
        "clientes",
        (
            "id",
            "tipoCliente",
            "tipo_documento",
            "num_documento",
            "fecha_alta",
            "calle",
            "numeroCalle",
            "descuento",
            "codigo_postal",
        ),
        filas_clientes,
        overriding=True,
    )
    insertar_lote(
        conexion,
        "socio_club",
        ("id", "nombre", "apellido"),
        filas_socios,
    )
    insertar_lote(
        conexion,
        "distribuidores",
        ("id", "zona_cobertura", "num_habilitacion", "razonSocial"),
        filas_distribuidores,
    )
    insertar_lote(
        conexion,
        "exportadores",
        ("id", "pais_destino", "razonSocial"),
        filas_exportadores,
    )

    permisos: list[tuple[str, date, date, int]] = []
    for indice, id_exportador in enumerate(range(19001, 20001)):
        cantidad = 1 + (indice % 5)

        for numero_permiso in range(1, cantidad + 1):
            emision = fecha_ref - timedelta(days=rng.randint(200, 1800))
            dias_maximos = (fecha_ref - emision).days - 1
            vigencia = rng.randint(120, min(900, dias_maximos))
            permisos.append(
                (
                    f"EXP-{id_exportador:05d}-{numero_permiso:02d}",
                    emision,
                    emision + timedelta(days=vigencia),
                    id_exportador,
                )
            )

    insertar_lote(
        conexion,
        "permisos",
        ("id", "fecha_emision", "fecha_vencimiento", "id_exportador"),
        permisos,
    )

    return clientes, no_compra, sin_tinto, forzados


def preparar_pares_venta(
    vinos: dict[int, VinoDatos],
    pares_sala: dict[int, list[int]],
) -> dict[int, list[tuple[int, date, str]]]:
    return {
        id_sala: [
            (id_vino, fecha_venta_vino(vinos[id_vino]), vinos[id_vino].tipo)
            for id_vino in ids_vino
        ]
        for id_sala, ids_vino in pares_sala.items()
    }


def elegir_vinos_para_venta(
    rng: random.Random,
    id_sala: int,
    fecha: date,
    id_cliente: int,
    cantidad: int,
    pares_sala_venta: dict[int, list[tuple[int, date, str]]],
    sin_tinto: set[int],
) -> list[int]:
    elegibles = [
        id_vino
        for id_vino, fecha_venta, tipo in pares_sala_venta[id_sala]
        if fecha_venta <= fecha
        and (id_cliente not in sin_tinto or tipo != "tinto")
    ]
    cantidad = min(cantidad, len(elegibles))
    if cantidad == 0:
        raise RuntimeError(f"No hay vinos elegibles para la sala {id_sala} en {fecha}")
    return rng.sample(elegibles, cantidad)


def generar_comprobantes(
    conexion: Connection,
    rng: random.Random,
    clientes: dict[int, dict[str, Any]],
    no_compra: set[int],
    sin_tinto: set[int],
    forzados: set[int],
    salas: Sequence[tuple[int, int]],
    vinos: dict[int, VinoDatos],
    pares_sala_venta: dict[int, list[tuple[int, date, str]]],
    bodega_pequena: Sequence[int],
    vinos_estrella: Sequence[int],
    inicio_ventas: date,
    fecha_ref: date,
) -> tuple[
    dict[tuple[int, int], int],
    list[tuple[date, int, int, int]],
]:
    comprobantes: list[tuple[Any, ...]] = []
    detalles: list[tuple[Any, ...]] = []
    ventas_por_par: dict[tuple[int, int], int] = defaultdict(int)
    ventas_eventos: list[tuple[date, int, int, int]] = []
    ids_salas = [id_sala for id_sala, _ in salas]
    clientes_compra = sorted(set(clientes) - no_compra)
    objetivos = 150_000
    inicio_comprobantes = perf_counter()

    def agregar_comprobante(
        id_cliente: int,
        id_sala: int,
        fecha: date,
        ids_vino: Sequence[int],
        cantidades: Sequence[int] | None = None,
    ) -> None:
        fecha = max(fecha, clientes[id_cliente]["fecha_alta"])
        ids_vino = [
            id_vino
            for id_vino in ids_vino
            if id_cliente not in sin_tinto or vinos[id_vino].tipo != "tinto"
        ]
        if not ids_vino:
            raise RuntimeError(
                f"El cliente {id_cliente} no tiene vinos válidos para comprar"
            )
        ids_vino = list(dict.fromkeys(ids_vino))
        if cantidades is None:
            cantidades = [rng.randint(1, 6) for _ in ids_vino]
        if len(cantidades) != len(ids_vino):
            raise RuntimeError("La cantidad de vinos y cantidades no coincide")

        numero = len(comprobantes) + 1
        subtotal = Decimal("0.00")
        descuento_total = Decimal("0.00")
        total = Decimal("0.00")
        porcentaje = clientes[id_cliente]["descuento"]

        for id_vino, cantidad in zip(ids_vino, cantidades):
            vino = vinos[id_vino]
            bruto = dec2(vino.precio * cantidad)
            descuento = dec2(bruto * porcentaje / Decimal(100))
            subtotal_linea = dec2(bruto - descuento)
            detalles.append(
                (
                    numero,
                    id_vino,
                    cantidad,
                    vino.precio,
                    descuento,
                    subtotal_linea,
                )
            )
            subtotal += bruto
            descuento_total += descuento
            total += subtotal_linea
            ventas_por_par[(id_sala, id_vino)] += cantidad
            ventas_eventos.append((fecha, id_sala, id_vino, cantidad))

        comprobantes.append(
            (
                numero,
                fecha,
                dec2(subtotal),
                dec2(descuento_total),
                dec2(total),
                id_sala,
                id_cliente,
            )
        )
        if numero % PROGRESO_COMPROBANTES == 0:
            logger.info(
                "Comprobantes generados: %d/%d (%.1f s)",
                numero,
                objetivos,
                perf_counter() - inicio_comprobantes,
            )

    for id_cliente in sorted(forzados):
        id_sala = rng.choice(ids_salas)
        fecha = fecha_aleatoria(
            rng,
            max(clientes[id_cliente]["fecha_alta"], fecha_ref - timedelta(days=30)),
            fecha_ref,
        )
        agregar_comprobante(
            id_cliente,
            id_sala,
            fecha,
            list(bodega_pequena),
            [rng.randint(1, 3) for _ in bodega_pequena],
        )

    disponibles_estrella = [
        id_cliente
        for id_cliente in clientes_compra
        if id_cliente not in forzados and id_cliente not in sin_tinto
    ]
    clientes_estrella = rng.sample(disponibles_estrella, len(salas))
    for id_sala, id_cliente in zip(ids_salas, clientes_estrella):
        fecha = fecha_aleatoria(
            rng,
            max(clientes[id_cliente]["fecha_alta"], fecha_ref - timedelta(days=90)),
            fecha_ref,
        )
        agregar_comprobante(
            id_cliente,
            id_sala,
            fecha,
            list(vinos_estrella),
            [rng.randint(1, 2) for _ in vinos_estrella],
        )

    cubiertos = forzados | set(clientes_estrella)
    for id_cliente in clientes_compra:
        if id_cliente in cubiertos:
            continue
        id_sala = rng.choice(ids_salas)
        fecha = fecha_aleatoria(
            rng,
            max(clientes[id_cliente]["fecha_alta"], inicio_ventas),
            fecha_ref,
        )
        cantidad_lineas = rng.choices((2, 3, 4, 5), weights=(15, 35, 35, 15))[0]
        ids_vino = elegir_vinos_para_venta(
            rng,
            id_sala,
            fecha,
            id_cliente,
            cantidad_lineas,
            pares_sala_venta,
            sin_tinto,
        )
        agregar_comprobante(id_cliente, id_sala, fecha, ids_vino)

    while len(comprobantes) < objetivos:
        id_cliente = rng.choice(clientes_compra)
        id_sala = rng.choice(ids_salas)
        fecha = fecha_aleatoria(
            rng,
            max(clientes[id_cliente]["fecha_alta"], inicio_ventas),
            fecha_ref,
        )
        cantidad_lineas = rng.choices((2, 3, 4, 5), weights=(15, 35, 35, 15))[0]
        ids_vino = elegir_vinos_para_venta(
            rng,
            id_sala,
            fecha,
            id_cliente,
            cantidad_lineas,
            pares_sala_venta,
            sin_tinto,
        )
        agregar_comprobante(id_cliente, id_sala, fecha, ids_vino)

    insertar_lote(
        conexion,
        "comprobante",
        (
            "numero",
            "fecha",
            "subtotal",
            "descuento",
            "total",
            "id_sala",
            "id_cliente",
        ),
        comprobantes,
        overriding=True,
    )
    insertar_lote(
        conexion,
        "detalle_comprobante",
        (
            "cod_comprobante",
            "cod_vino",
            "cantidad",
            "precio_unit",
            "descuento",
            "subtotal",
        ),
        detalles,
    )
    return dict(ventas_por_par), ventas_eventos


def dividir_entero(
    rng: random.Random,
    total: int,
    partes: int,
) -> list[int]:
    if partes <= 1:
        return [total]
    puntos = sorted(rng.sample(range(1, total), partes - 1))
    valores: list[int] = []
    anterior = 0
    for punto in puntos:
        valores.append(punto - anterior)
        anterior = punto
    valores.append(total - anterior)
    return valores


def generar_transferencias(
    conexion: Connection,
    rng: random.Random,
    salas: Sequence[tuple[int, int]],
    vinos: dict[int, VinoDatos],
    pares_sala: dict[int, list[int]],
    ventas_por_par: dict[tuple[int, int], int],
    inicio_suministro: date,
    fecha_ref: date,
) -> tuple[dict[int, int], dict[tuple[int, int], int]]:
    filas: list[tuple[int, date, str, int]] = []
    detalles: list[tuple[int, int, int]] = []
    transferido_por_vino: dict[int, int] = defaultdict(int)
    stock_sala_final: dict[tuple[int, int], int] = defaultdict(int)
    ids_salas = [id_sala for id_sala, _ in salas]
    inicio = inicio_suministro + timedelta(days=21)
    fin = inicio_suministro + timedelta(days=60)

    for id_sala, _ in salas:
        fecha = fecha_aleatoria(rng, inicio, fin)
        filas.append((id_sala, fecha, "procesado", id_sala))
        for id_vino in pares_sala[id_sala]:
            cantidad = ventas_por_par.get((id_sala, id_vino), 0) + rng.randint(20, 150)
            detalles.append((id_sala, id_vino, cantidad))
            transferido_por_vino[id_vino] += cantidad
            stock_sala_final[(id_sala, id_vino)] += cantidad

    id_documento = len(salas) + 1
    for indice in range(1800):
        id_sala = rng.choice(ids_salas)
        cantidad_lineas = 3 if indice < 1150 else 2

        if indice < 1650:
            fecha = fecha_aleatoria(rng, inicio, fin)
        elif indice < 1790:
            fecha = fecha_aleatoria(
                rng,
                inicio_suministro + timedelta(days=61),
                fecha_ref - timedelta(days=16),
            )
        else:
            fecha = fecha_aleatoria(rng, fecha_ref - timedelta(days=14), fecha_ref)
        filas.append((id_documento, fecha, "procesado", id_sala))
        for id_vino in rng.sample(pares_sala[id_sala], cantidad_lineas):
            cantidad = rng.randint(20, 120)
            detalles.append((id_documento, id_vino, cantidad))
            transferido_por_vino[id_vino] += cantidad
            stock_sala_final[(id_sala, id_vino)] += cantidad
        id_documento += 1

    for indice in range(185):
        id_sala = rng.choice(ids_salas)
        cantidad_lineas = 2 if indice < 65 else 1
        estado = "terminado" if indice < 100 else "en_confeccion"
        fecha = fecha_aleatoria(rng, inicio, fin)
        filas.append((id_documento, fecha, estado, id_sala))
        for id_vino in rng.sample(pares_sala[id_sala], cantidad_lineas):
            detalles.append((id_documento, id_vino, rng.randint(10, 100)))
        id_documento += 1

    for (id_sala, id_vino), cantidad in ventas_por_par.items():
        stock_sala_final[(id_sala, id_vino)] -= cantidad

    insertar_lote(
        conexion,
        "transferencias",
        ("num_solicitud", "fecha_confeccion", "estado", "id_sala"),
        filas,
        overriding=True,
    )
    insertar_lote(
        conexion,
        "detalle_transferencia",
        ("num_transferencia", "cod_vino", "cantidad"),
        detalles,
    )
    return dict(transferido_por_vino), dict(stock_sala_final)


def generar_ingresos(
    conexion: Connection,
    rng: random.Random,
    bodegas: Sequence[dict[str, Any]],
    empresas: Sequence[dict[str, Any]],
    vinos: dict[int, VinoDatos],
    transferido_por_vino: dict[int, int],
    inicio_suministro: date,
    fecha_ref: date,
) -> dict[int, int]:
    todos_los_vinos = sorted(vinos)
    central_objetivo = {id_vino: rng.randint(150, 900) for id_vino in todos_los_vinos}
    central_objetivo[500] = max(central_objetivo[500], 800)
    requerido = {
        id_vino: transferido_por_vino.get(id_vino, 0) + central_objetivo[id_vino]
        for id_vino in todos_los_vinos
    }

    lineas_por_vino = {id_vino: 1 for id_vino in todos_los_vinos}
    pesos = [requerido[id_vino] for id_vino in todos_los_vinos]
    for _ in range(4000):
        id_vino = rng.choices(todos_los_vinos, weights=pesos)[0]
        lineas_por_vino[id_vino] += 1

    items: list[tuple[int, int]] = []
    for id_vino in todos_los_vinos:
        cantidades = dividir_entero(rng, requerido[id_vino], lineas_por_vino[id_vino])
        items.extend((id_vino, cantidad) for cantidad in cantidades)
    rng.shuffle(items)

    capacidades = [3 if indice < 1100 else 2 for indice in range(1700)]
    lineas_por_documento: list[list[tuple[int, int]]] = [[] for _ in range(1700)]
    vinos_por_documento: list[set[int]] = [set() for _ in range(1700)]
    cursor_documento = 0
    for id_vino, cantidad in items:
        for _ in range(len(capacidades)):
            indice = cursor_documento % len(capacidades)
            cursor_documento += 1
            if capacidades[indice] > 0 and id_vino not in vinos_por_documento[indice]:
                lineas_por_documento[indice].append((id_vino, cantidad))
                vinos_por_documento[indice].add(id_vino)
                capacidades[indice] -= 1
                break
        else:
            raise RuntimeError("No se pudieron distribuir los renglones de ingreso")

    filas: list[tuple[int, date, str, str, int]] = []
    detalles: list[tuple[int, int, int]] = []
    ingreso_procesado: dict[int, int] = defaultdict(int)
    inicio_old = inicio_suministro - timedelta(days=90)
    fin_old = inicio_suministro - timedelta(days=1)

    for indice, lineas in enumerate(lineas_por_documento, start=1):
        fecha = fecha_aleatoria(rng, inicio_old, fin_old)
        bodega = rng.choice(bodegas)
        empresa = rng.choice(empresas)
        filas.append(
            (
                indice,
                fecha,
                "procesado",
                bodega["cuit"],
                empresa["cod_transporte"],
            )
        )
        for id_vino, cantidad in lineas:
            detalles.append((indice, id_vino, cantidad))
            ingreso_procesado[id_vino] += cantidad

    for indice in range(300):
        id_documento = 1701 + indice
        if indice < 60:
            fecha = fecha_ref - timedelta(days=rng.randint(0, 6))
            empresa = empresas[rng.randint(0, 4)]
        elif indice < 150:
            fecha = fecha_ref - timedelta(days=rng.randint(7, 29))
            empresa = empresas[rng.randint(0, 7)]
        else:
            fecha = fecha_ref - timedelta(days=rng.randint(30, 89))
            empresa = empresas[rng.randint(0, 9)]

        if indice < 150:
            estado = "procesado"
        elif indice < 200:
            estado = "terminado"
        else:
            estado = "en_confeccion"
        cantidad_lineas = 2 if indice < 200 else 1
        bodega = rng.choice(bodegas)
        filas.append(
            (
                id_documento,
                fecha,
                estado,
                bodega["cuit"],
                empresa["cod_transporte"],
            )
        )
        for id_vino in rng.sample(todos_los_vinos, cantidad_lineas):
            cantidad = rng.randint(20, 200)
            detalles.append((id_documento, id_vino, cantidad))
            if estado == "procesado":
                ingreso_procesado[id_vino] += cantidad

    stock_central_final = {
        id_vino: ingreso_procesado.get(id_vino, 0)
        - transferido_por_vino.get(id_vino, 0)
        for id_vino in todos_los_vinos
    }
    if any(cantidad < 0 for cantidad in stock_central_final.values()):
        raise RuntimeError("Se generó stock central negativo")

    insertar_lote(
        conexion,
        "ingresos",
        ("id", "fecha", "estado", "cuit_bodega", "cod_transporte"),
        filas,
        overriding=True,
    )
    insertar_lote(
        conexion,
        "detalle_ingreso",
        ("num_ingreso", "cod_vino", "cantidad"),
        detalles,
    )
    return stock_central_final


def generar_stocks(
    conexion: Connection,
    stock_sala_final: dict[tuple[int, int], int],
    stock_central_final: dict[int, int],
) -> None:
    filas_central = [
        (id_vino, cantidad) for id_vino, cantidad in sorted(stock_central_final.items())
    ]
    filas_sala = [
        (id_sala, id_vino, cantidad)
        for (id_sala, id_vino), cantidad in sorted(stock_sala_final.items())
        if cantidad > 0
    ]
    insertar_lote(
        conexion,
        "stock_central",
        ("codigo_vino", "cantidad"),
        filas_central,
    )
    insertar_lote(
        conexion,
        "stock_sala",
        ("id_sala", "cod_vino", "cantidad"),
        filas_sala,
    )


def generar_auditoria_precio(
    conexion: Connection,
    rng: random.Random,
    vinos: dict[int, VinoDatos],
    fecha_ref: date,
) -> None:
    usuarios = ("admin", "gerencia", "sistema", "comercial")
    filas: list[tuple[int, Decimal, Decimal, date, time, str, int]] = []
    for indice, id_vino in enumerate(rng.sample(sorted(vinos), 30), start=1):
        precio_anterior = vinos[id_vino].precio
        precio_nuevo = dec2(precio_anterior * Decimal("1.10"))
        fecha = fecha_aleatoria(rng, fecha_ref - timedelta(days=730), fecha_ref)
        hora = time(
            rng.randint(8, 21),
            rng.randint(0, 59),
            rng.randint(0, 59),
        )
        filas.append(
            (
                indice,
                precio_anterior,
                precio_nuevo,
                fecha,
                hora,
                rng.choice(usuarios),
                id_vino,
            )
        )

    insertar_lote(
        conexion,
        "auditoria_precio",
        (
            "id",
            "precio_anterior",
            "precio_nuevo",
            "fecha",
            "hora",
            "usuario",
            "id_vino",
        ),
        filas,
        overriding=True,
    )


def generar_datos(
    conexion: Connection,
    rng: random.Random,
    faker: Faker,
    fecha_ref: date,
    tiempos: list[tuple[str, float]],
) -> None:
    inicio_suministro = fecha_ref - timedelta(days=6 * 365)
    inicio_ventas = inicio_suministro + timedelta(days=61)

    def medir(nombre: str, funcion: Any) -> Any:
        logger.info("Iniciando etapa: %s", nombre)
        inicio = perf_counter()
        resultado = funcion()
        transcurrido = perf_counter() - inicio
        tiempos.append((nombre, transcurrido))
        logger.info("Etapa finalizada: %s (%.2f s)", nombre, transcurrido)
        return resultado

    localidades = medir(
        "Localidades y encargados",
        lambda: generar_localidades(conexion),
    )
    medir(
        "Encargados regionales",
        lambda: generar_encargados(conexion, rng, faker, localidades),
    )
    salas = medir(
        "Salas de venta",
        lambda: generar_salas(conexion, rng, faker, localidades),
    )
    medir(
        "Empleados",
        lambda: generar_empleados(conexion, rng, faker, salas, fecha_ref),
    )
    bodegas = medir(
        "Bodegas",
        lambda: generar_bodegas(conexion, rng, faker),
    )
    empresas = medir(
        "Empresas de transporte",
        lambda: generar_empresas_transporte(conexion, rng, faker),
    )
    medir(
        "Cobertura de transporte",
        lambda: generar_coberturas(conexion, rng, localidades, empresas),
    )
    fincas = medir(
        "Fincas",
        lambda: generar_fincas(conexion, rng, faker),
    )
    cepas, maridajes = medir(
        "Catálogos de cepas y maridajes",
        lambda: leer_catalogos(conexion),
    )
    parcelas = medir(
        "Parcelas",
        lambda: generar_parcelas(conexion, rng, fincas, cepas, fecha_ref),
    )
    medir(
        "Lotes y análisis",
        lambda: generar_lotes_y_analisis(conexion, rng, parcelas, bodegas, fecha_ref),
    )
    vinos, bodega_pequena, vinos_estrella, _ = medir(
        "Vinos, composición y maridajes",
        lambda: generar_vinos(conexion, rng, bodegas, cepas, maridajes, fecha_ref),
    )
    pares_sala, _ = medir(
        "Stock por sala (pares)",
        lambda: generar_stock_pares(
            rng, salas, vinos, bodega_pequena, vinos_estrella
        ),
    )
    pares_sala_venta = medir(
        "Índice de venta por sala",
        lambda: preparar_pares_venta(vinos, pares_sala),
    )
    clientes, no_compra, sin_tinto, forzados = medir(
        "Clientes y permisos",
        lambda: generar_clientes(
            conexion, rng, faker, localidades, fecha_ref, inicio_ventas
        ),
    )
    ventas_por_par, ventas_eventos = medir(
        "Comprobantes y ventas",
        lambda: generar_comprobantes(
            conexion,
            rng,
            clientes,
            no_compra,
            sin_tinto,
            forzados,
            salas,
            vinos,
            pares_sala_venta,
            bodega_pequena,
            vinos_estrella,
            inicio_ventas,
            fecha_ref,
        ),
    )
    primera_venta = min(evento[0] for evento in ventas_eventos)
    if primera_venta <= inicio_suministro + timedelta(days=60):
        raise RuntimeError(
            "Hay ventas anteriores a la primera transferencia de suministro"
        )
    transferido_por_vino, stock_sala_final = medir(
        "Transferencias",
        lambda: generar_transferencias(
            conexion,
            rng,
            salas,
            vinos,
            pares_sala,
            ventas_por_par,
            inicio_suministro,
            fecha_ref,
        ),
    )
    stock_central_final = medir(
        "Ingresos",
        lambda: generar_ingresos(
            conexion,
            rng,
            bodegas,
            empresas,
            vinos,
            transferido_por_vino,
            inicio_suministro,
            fecha_ref,
        ),
    )
    medir(
        "Stock y auditoría",
        lambda: generar_stocks(conexion, stock_sala_final, stock_central_final),
    )
    medir(
        "Auditoría de precios",
        lambda: generar_auditoria_precio(conexion, rng, vinos, fecha_ref),
    )


def contar_tablas(conexion: Connection) -> dict[str, int]:
    conteos: dict[str, int] = {}
    with conexion.cursor() as cursor:
        for tabla in TABLAS_HASH:
            cursor.execute(f"SELECT COUNT(*) FROM {tabla}")
            conteos[tabla] = cursor.fetchone()[0]
    return conteos


def hash_tabla(conexion: Connection, tabla: str) -> str:
    columnas_pk = ", ".join(PK_HASH[tabla])
    resumen = hashlib.sha256()
    with conexion.cursor(name=f"hash_{tabla}") as cursor:
        cursor.itersize = 10_000
        cursor.execute(f"SELECT * FROM {tabla} ORDER BY {columnas_pk}")
        for fila in cursor:
            resumen.update(repr(fila).encode("utf-8"))
            resumen.update(b"\n")
    return resumen.hexdigest()


def imprimir_reporte(conexion: Connection, tiempos: Sequence[tuple[str, float]]) -> int:
    logger.info("Calculando conteos por tabla...")
    with conexion.transaction():
        conteos = contar_tablas(conexion)
        logger.info("Conteos listos; calculando hashes por tabla...")
        hashes: dict[str, str] = {}
        for tabla in TABLAS_HASH:
            hashes[tabla] = hash_tabla(conexion, tabla)
            logger.info("Hash calculado: %s", tabla)
    logger.info("Reporte calculado")

    print("\n=== Reporte de carga ===")
    print(f"{'Tabla':<28}{'Filas':>10}  SHA-256")
    for tabla in TABLAS_HASH:
        print(f"{tabla:<28}{conteos[tabla]:>10}  {hashes[tabla]}")

    total_filas = sum(conteos.values())
    print(f"\nTotal de filas: {total_filas}")
    print("\nTiempos por etapa:")
    for nombre, segundos in tiempos:
        print(f"  {nombre:<30}{segundos:>8.2f} s")

    tablas_mas_de_10k = sum(1 for cantidad in conteos.values() if cantidad > 10_000)
    tablas_mas_de_100k = sum(1 for cantidad in conteos.values() if cantidad > 100_000)
    print("\nVerificación de volumen:")
    print(f"  tablas con más de 10.000 filas: {tablas_mas_de_10k}")
    print(f"  tablas con más de 100.000 filas: {tablas_mas_de_100k}")

    resumen_global = hashlib.sha256()
    for tabla in sorted(TABLAS_HASH):
        resumen_global.update(f"{tabla}:{hashes[tabla]}\n".encode("utf-8"))
    print(f"\nHash global: {resumen_global.hexdigest()}")

    return 0 if tablas_mas_de_10k >= 3 and tablas_mas_de_100k >= 1 else 1


if __name__ == "__main__":
    sys.exit(main())
