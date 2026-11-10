"""Acceso a datos de salas de venta."""


def listar_salas(conn, limit: int = 100, offset: int = 0) -> list:
    return conn.execute(
        "SELECT id_sala, calle, numero, dia_cierre, codigo_postal FROM sala_de_ventas ORDER BY id_sala LIMIT %s OFFSET %s",
        (limit, offset),
    ).fetchall()