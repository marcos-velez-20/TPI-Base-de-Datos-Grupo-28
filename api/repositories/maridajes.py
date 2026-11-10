"""Acceso a datos de maridajes."""


def listar_maridajes(conn, limit: int = 100, offset: int = 0) -> list:
    return conn.execute(
        "SELECT id, nombre, temperatura FROM maridaje ORDER BY nombre LIMIT %s OFFSET %s",
        (limit, offset),
    ).fetchall()