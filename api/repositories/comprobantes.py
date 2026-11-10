"""Ventas. La API NO calcula precios, descuentos ni totales: lo hacen los triggers."""


def insertar_comprobante(conn, id_sala, id_cliente) -> int:
    return conn.execute(
        "INSERT INTO comprobante (id_sala, id_cliente) VALUES (%s, %s) RETURNING numero",
        (id_sala, id_cliente),
    ).fetchone()["numero"]


def insertar_renglon(conn, nro, cod_vino, cantidad):
    # precio_unit, descuento y subtotal los completa trg_renglon_valida_stock_before.
    conn.execute(
        "INSERT INTO detalle_comprobante (cod_comprobante, cod_vino, cantidad) VALUES (%s, %s, %s)",
        (nro, cod_vino, cantidad),
    )


def obtener_comprobante(conn, nro):
    return conn.execute(
        "SELECT numero, fecha, subtotal, descuento, total, id_sala, id_cliente "
        "FROM comprobante WHERE numero = %s",
        (nro,),
    ).fetchone()


def renglones_de_comprobante(conn, nro):
    return conn.execute(
        "SELECT dc.cod_vino, v.nombre AS vino, dc.cantidad, dc.precio_unit, dc.descuento, dc.subtotal "
        "FROM detalle_comprobante dc JOIN vino v ON v.id = dc.cod_vino "
        "WHERE dc.cod_comprobante = %s ORDER BY dc.cod_vino",
        (nro,),
    ).fetchall()
