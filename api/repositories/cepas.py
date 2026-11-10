"""Acceso a datos de cepas."""


def listar_cepas(conn, limit: int = 100, offset: int = 0) -> list:
    return conn.execute(
        "SELECT identificador AS id_cepa, nombre, tipo FROM cepa ORDER BY nombre LIMIT %s OFFSET %s",
        (limit, offset),
    ).fetchall()