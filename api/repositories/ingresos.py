"""Ingresos al depósito central. Mismo circuito de estados que las transferencias."""


def existe(conn, cod) -> bool:
    return conn.execute("SELECT 1 FROM ingresos WHERE id = %s", (cod,)).fetchone() is not None


def insertar_ingreso(conn, cuit_bodega, cod_transporte) -> int:
    return conn.execute(
        "INSERT INTO ingresos (cuit_bodega, cod_transporte) VALUES (%s, %s) RETURNING id",
        (cuit_bodega, cod_transporte),
    ).fetchone()["id"]


def obtener_ingreso(conn, cod):
    return conn.execute(
        "SELECT id, fecha, estado, cuit_bodega, cod_transporte FROM ingresos WHERE id = %s", (cod,)
    ).fetchone()


def renglones_de_ingreso(conn, cod):
    return conn.execute(
        "SELECT di.cod_vino, v.nombre AS vino, di.cantidad "
        "FROM detalle_ingreso di JOIN vino v ON v.id = di.cod_vino "
        "WHERE di.num_ingreso = %s ORDER BY di.cod_vino",
        (cod,),
    ).fetchall()


def insertar_renglon(conn, cod, cod_vino, cantidad):
    conn.execute(
        "INSERT INTO detalle_ingreso (num_ingreso, cod_vino, cantidad) VALUES (%s, %s, %s)",
        (cod, cod_vino, cantidad),
    )


def marcar_terminado(conn, cod) -> int:
    return conn.execute("UPDATE ingresos SET estado = 'terminado' WHERE id = %s", (cod,)).rowcount


def procesar(conn, cod):
    conn.execute("CALL sp_procesar_ingreso(%s::integer)", (cod,))
