"""Traducción de errores de PostgreSQL (SQLSTATE) a respuestas HTTP."""
import logging

import psycopg

log = logging.getLogger("api.errors")


def traducir_error_pg(exc: psycopg.Error) -> tuple[int, dict, dict]:
    """Devuelve (status_http, cuerpo_json, headers)."""
    sqlstate = exc.sqlstate
    diag = exc.diag
    mensaje = ((diag.message_primary if diag and diag.message_primary else None) or str(exc)).strip()
    detalle = diag.message_detail if diag else None
    extra = f" ({detalle})" if detalle else ""

    def resp(status: int, texto: str, headers: dict | None = None):
        return status, {"detail": texto, "sqlstate": sqlstate}, headers or {}

    # Sin SQLSTATE o clase 08: no hay conexión / pool agotado.
    if sqlstate is None or sqlstate.startswith("08"):
        log.error("Base de datos no disponible: %s", exc)
        return resp(503, "Base de datos no disponible", {"Retry-After": "5"})

    if sqlstate == "23505":  # unique_violation
        return resp(409, f"Conflicto de unicidad: {mensaje}{extra}")

    if sqlstate == "23503":  # foreign_key_violation
        # INSERT/UPDATE que apunta a algo inexistente -> 422; DELETE de algo que
        # tiene dependientes -> 409.
        if mensaje.startswith("insert or update"):
            return resp(422, f"Referencia a un dato inexistente: {mensaje}{extra}")
        return resp(409, f"No se puede completar: existen datos dependientes: {mensaje}{extra}")

    if sqlstate in ("23514", "23502"):  # check_violation / not_null_violation
        return resp(422, f"Error de validación de datos: {mensaje}")

    if sqlstate == "P0001":  # RAISE EXCEPTION (triggers y procedimientos)
        return resp(409, mensaje)  # mensaje exacto de la base

    if sqlstate == "22P02":  # invalid_text_representation
        return resp(400, f"Formato de datos inválido: {mensaje}")

    if sqlstate in ("22001", "22003"):  # valor demasiado largo / numérico fuera de rango
        return resp(422, f"Valor fuera de rango: {mensaje}")

    if sqlstate.startswith("22"):  # resto de data_exception
        return resp(400, f"Dato inválido: {mensaje}")

    if sqlstate in ("40001", "40P01"):  # serialization_failure / deadlock_detected
        return resp(503, "Conflicto de concurrencia, reintentá la operación", {"Retry-After": "1"})

    log.exception("Error de base de datos no mapeado (SQLSTATE %s): %s", sqlstate, exc)
    return resp(500, "Error interno de la base de datos")
