"""Acceso a datos de bodegas."""


def listar_bodegas(conn, limit: int = 100, offset: int = 0) -> list:
    return conn.execute(
        "SELECT cuit, razon_social, calle, num_calle FROM bodega ORDER BY razon_social LIMIT %s OFFSET %s",
        (limit, offset),
    ).fetchall()