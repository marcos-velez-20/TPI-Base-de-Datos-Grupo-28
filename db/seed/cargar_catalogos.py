#!/usr/bin/env python3
"""Carga idempotente de los catálogos de Bodegas del Atuel.

Uso:
    python db/seed/cargar_catalogos.py

Variables de entorno:
    DB_HOST / PGHOST        (default: localhost)
    DB_PORT / PGPORT        (default: 5433)
    DB_USER / PGUSER        (default: postgres)
    DB_PASSWORD / PGPASSWORD (default: postgres)
    DB_NAME / PGDATABASE    (default: bodegas_del_atuel)
"""

from __future__ import annotations

import csv
import os
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

import psycopg
from psycopg import Connection

SEED_DIR = Path(__file__).resolve().parent

TIPOS_CEPA_VALIDOS = frozenset({"tinta", "blanca"})
TIPOS_VINO_VALIDOS = frozenset({"tinto", "blanco", "rosado", "espumante"})

SQL_INSERTAR_CEPA = """
    INSERT INTO cepa (tipo, nombre)
    VALUES (%s, %s)
    ON CONFLICT (nombre) DO NOTHING
"""

SQL_INSERTAR_MARIDAJE = """
    INSERT INTO maridaje (nombre, temperatura)
    VALUES (%s, %s)
    ON CONFLICT (nombre) DO NOTHING
"""


def obtener_config_db() -> dict[str, Any]:
    puerto_texto = os.getenv("DB_PORT", os.getenv("PGPORT", "5433"))
    try:
        puerto = int(puerto_texto)
    except ValueError as exc:
        raise ValueError(f"DB_PORT/PGPORT inválido: {puerto_texto!r}") from exc

    return {
        "host": os.getenv("DB_HOST", os.getenv("PGHOST", "localhost")),
        "port": puerto,
        "user": os.getenv("DB_USER", os.getenv("PGUSER", "postgres")),
        "password": os.getenv("DB_PASSWORD", os.getenv("PGPASSWORD", "postgres")),
        "dbname": os.getenv("DB_NAME", os.getenv("PGDATABASE", "bodegas_del_atuel")),
    }


def leer_csv(
    nombre_archivo: str, columnas_esperadas: tuple[str, ...]
) -> list[tuple[int, dict[str, str]]]:
    ruta = SEED_DIR / nombre_archivo
    if not ruta.is_file():
        raise FileNotFoundError(f"No se encontró el archivo {ruta}")

    with ruta.open("r", encoding="utf-8-sig", newline="") as archivo:
        lector = csv.DictReader(archivo)
        columnas = tuple(lector.fieldnames or ())
        faltantes = [
            columna for columna in columnas_esperadas if columna not in columnas
        ]
        if faltantes:
            raise ValueError(
                f"{nombre_archivo}: faltan las columnas {', '.join(faltantes)}"
            )

        filas: list[tuple[int, dict[str, str]]] = []
        for numero_linea, fila in enumerate(lector, start=2):
            datos = {
                columna: (fila.get(columna) or "").strip()
                for columna in columnas_esperadas
            }
            if not any(datos.values()):
                continue
            filas.append((numero_linea, datos))

    return filas


def error_fila(nombre_archivo: str, numero_linea: int, mensaje: str) -> ValueError:
    return ValueError(f"{nombre_archivo}, línea {numero_linea}: {mensaje}")


def preparar_departamentos(
    nombre_archivo: str, filas: list[tuple[int, dict[str, str]]]
) -> list[tuple[str, str]]:
    preparados: list[tuple[str, str]] = []
    vistos: set[tuple[str, str]] = set()

    for numero_linea, datos in filas:
        departamento = datos["departamento"]
        provincia = datos["provincia"]

        if not departamento:
            raise error_fila(nombre_archivo, numero_linea, "el departamento está vacío")
        if not provincia:
            raise error_fila(nombre_archivo, numero_linea, "la provincia está vacía")

        clave = (departamento.casefold(), provincia.casefold())
        if clave in vistos:
            raise error_fila(nombre_archivo, numero_linea, "departamento duplicado")
        vistos.add(clave)
        preparados.append((departamento, provincia))

    return preparados


def preparar_tipos_vino(
    nombre_archivo: str, filas: list[tuple[int, dict[str, str]]]
) -> list[str]:
    preparados: list[str] = []

    for numero_linea, datos in filas:
        tipo = datos["tipo"]
        if tipo not in TIPOS_VINO_VALIDOS:
            permitidos = ", ".join(sorted(TIPOS_VINO_VALIDOS))
            raise error_fila(
                nombre_archivo,
                numero_linea,
                f"tipo de vino inválido {tipo!r}; permitidos: {permitidos}",
            )
        preparados.append(tipo)

    return preparados


def preparar_cepas(
    nombre_archivo: str, filas: list[tuple[int, dict[str, str]]]
) -> list[tuple[str, str]]:
    preparadas: list[tuple[str, str]] = []

    for numero_linea, datos in filas:
        tipo = datos["tipo"]
        nombre = datos["nombre"]

        if tipo not in TIPOS_CEPA_VALIDOS:
            permitidos = ", ".join(sorted(TIPOS_CEPA_VALIDOS))
            raise error_fila(
                nombre_archivo,
                numero_linea,
                f"tipo de cepa inválido {tipo!r}; permitidos: {permitidos}",
            )
        if not nombre:
            raise error_fila(nombre_archivo, numero_linea, "el nombre está vacío")

        preparadas.append((tipo, nombre))

    return preparadas


def preparar_maridajes(
    nombre_archivo: str, filas: list[tuple[int, dict[str, str]]]
) -> list[tuple[str, Decimal]]:
    preparados: list[tuple[str, Decimal]] = []

    for numero_linea, datos in filas:
        nombre = datos["nombre"]
        temperatura_texto = datos["temperatura"]

        if not nombre:
            raise error_fila(nombre_archivo, numero_linea, "el nombre está vacío")

        try:
            temperatura = Decimal(temperatura_texto)
        except InvalidOperation as exc:
            raise error_fila(
                nombre_archivo,
                numero_linea,
                f"temperatura inválida {temperatura_texto!r}",
            ) from exc

        preparados.append((nombre, temperatura))

    return preparados


def cargar_cepas(conexion: Connection, cepas: list[tuple[str, str]]) -> int:
    if not cepas:
        return 0

    with conexion.cursor() as cursor:
        cursor.executemany(SQL_INSERTAR_CEPA, cepas)
        return max(cursor.rowcount, 0)


def cargar_maridajes(conexion: Connection, maridajes: list[tuple[str, Decimal]]) -> int:
    if not maridajes:
        return 0

    with conexion.cursor() as cursor:
        cursor.executemany(SQL_INSERTAR_MARIDAJE, maridajes)
        return max(cursor.rowcount, 0)


def main() -> int:
    try:
        filas_departamentos = leer_csv(
            "departamentos.csv", ("departamento", "provincia")
        )
        filas_tipos_vino = leer_csv("tipos_vino.csv", ("tipo",))
        filas_cepas = leer_csv("cepas.csv", ("tipo", "nombre"))
        filas_maridajes = leer_csv("maridajes.csv", ("nombre", "temperatura"))

        departamentos = preparar_departamentos("departamentos.csv", filas_departamentos)
        tipos_vino = preparar_tipos_vino("tipos_vino.csv", filas_tipos_vino)
        cepas = preparar_cepas("cepas.csv", filas_cepas)
        maridajes = preparar_maridajes("maridajes.csv", filas_maridajes)
        config = obtener_config_db()
    except (FileNotFoundError, ValueError) as exc:
        print(f"Error de validación: {exc}", file=sys.stderr)
        return 1

    print(
        f"Conectando a {config['host']}:{config['port']}/{config['dbname']} "
        f"como {config['user']}..."
    )

    try:
        with psycopg.connect(**config) as conexion:
            with conexion.transaction():
                cepas_insertadas = cargar_cepas(conexion, cepas)
                maridajes_insertados = cargar_maridajes(conexion, maridajes)
    except psycopg.Error as exc:
        print(f"Error de base de datos: {exc}", file=sys.stderr)
        return 1

    print("Catálogos cargados:")
    print(
        f"  cepa: {len(cepas)} leídas, {cepas_insertadas} insertadas, "
        f"{len(cepas) - cepas_insertadas} omitidas"
    )
    print(
        f"  maridaje: {len(maridajes)} leídos, {maridajes_insertados} insertados, "
        f"{len(maridajes) - maridajes_insertados} omitidos"
    )
    print("Archivos validados sin tabla destino:")
    print(f"  departamentos: {len(departamentos)} filas")
    print(f"  tipos de vino: {len(tipos_vino)} filas")

    return 0


if __name__ == "__main__":
    sys.exit(main())
