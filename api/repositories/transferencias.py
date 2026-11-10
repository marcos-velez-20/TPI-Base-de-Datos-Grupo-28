"""Transferencias sala <- depósito central. Estados: en_confeccion -> terminado -> procesado."""


def existe(conn, nro) -> bool:
    return conn.execute("SELECT 1 FROM transferencias WHERE num_solicitud = %s", (nro,)).fetchone() is not None


def insertar_transferencia(conn, id_sala) -> int:
    return conn.execute(
        "INSERT INTO transferencias (id_sala) VALUES (%s) RETURNING num_solicitud", (id_sala,)
    ).fetchone()["num_solicitud"]


def obtener_transferencia(conn, nro):
    return conn.execute(
        "SELECT num_solicitud, fecha_confeccion, estado, id_sala FROM transferencias WHERE num_solicitud = %s",
        (nro,),
    ).fetchone()


def renglones_de_transferencia(conn, nro):
    return conn.execute(
        "SELECT dt.cod_vino, v.nombre AS vino, dt.cantidad "
        "FROM detalle_transferencia dt JOIN vino v ON v.id = dt.cod_vino "
        "WHERE dt.num_transferencia = %s ORDER BY dt.cod_vino",
        (nro,),
    ).fetchall()


def insertar_renglon(conn, nro, cod_vino, cantidad):
    conn.execute(
        "INSERT INTO detalle_transferencia (num_transferencia, cod_vino, cantidad) VALUES (%s, %s, %s)",
        (nro, cod_vino, cantidad),
    )


def marcar_terminada(conn, nro) -> int:
    # El trigger trg_transferencias_estados_before valida la transición.
    return conn.execute(
        "UPDATE transferencias SET estado = 'terminado' WHERE num_solicitud = %s", (nro,)
    ).rowcount


def procesar(conn, nro):
    conn.execute("CALL sp_procesar_transferencia(%s::integer)", (nro,))
