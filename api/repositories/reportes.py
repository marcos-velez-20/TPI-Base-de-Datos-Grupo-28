"""Consultas avanzadas (solo lectura)."""


def top_vinos(conn, limit):  # S1
    return conn.execute(
        "SELECT v.id, v.nombre, v.anada, v.volumen, SUM(dc.cantidad) AS botellas "
        "FROM detalle_comprobante dc JOIN vino v ON v.id = dc.cod_vino "
        "GROUP BY v.id, v.nombre, v.anada, v.volumen "
        "ORDER BY botellas DESC LIMIT %s",
        (limit,),
    ).fetchall()


def ventas_por_sala(conn):  # S8
    return conn.execute(
        "SELECT c.id_sala, l.nombre AS localidad, SUM(c.total) AS monto "
        "FROM comprobante c "
        "JOIN sala_de_ventas s ON s.id_sala = c.id_sala "
        "JOIN localidades l ON l.codigo_postal = s.codigo_postal "
        "WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months' "
        "GROUP BY c.id_sala, l.nombre ORDER BY monto DESC"
    ).fetchall()


def vinos_sin_stock_en_sala(conn, id_sala):  # S6
    return conn.execute(
        "SELECT v.id, v.nombre, sc.cantidad AS stock_deposito "
        "FROM vino v "
        "JOIN stock_central sc ON sc.codigo_vino = v.id "
        "LEFT JOIN stock_sala ss ON ss.cod_vino = v.id AND ss.id_sala = %s "
        "WHERE sc.cantidad > 0 AND (ss.cantidad IS NULL OR ss.cantidad = 0) "
        "ORDER BY sc.cantidad DESC, v.id",
        (id_sala,),
    ).fetchall()


def transportista_mayor_actividad(conn):  # S7
    return conn.execute(
        "SELECT et.cod_transporte, et.razon_social, COUNT(i.id) AS ingresos "
        "FROM empresa_transporte et JOIN ingresos i ON i.cod_transporte = et.cod_transporte "
        "WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month' "
        "GROUP BY et.cod_transporte, et.razon_social "
        "HAVING COUNT(i.id) = ("
        "  SELECT MAX(cant) FROM ("
        "    SELECT COUNT(*) AS cant FROM ingresos "
        "    WHERE fecha >= CURRENT_DATE - INTERVAL '1 month' GROUP BY cod_transporte"
        "  ) AS conteos)"
    ).fetchall()


def ficha_vino_datos(conn, cod):  # S9 (a)
    return conn.execute(
        "SELECT v.id, v.nombre, v.tipo, v.anada, v.volumen, v.graduacion, v.precio, "
        "b.razon_social AS bodega, "
        "(SELECT COUNT(*) FROM composicion co WHERE co.id_vino = v.id) AS cantidad_cepas, "
        "(SELECT COUNT(*) FROM vino_maridaje vm WHERE vm.cod_vino = v.id) AS cantidad_maridajes, "
        "st.stock_deposito, st.stock_salas, st.stock_total "
        "FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega "
        "JOIN vista_stock_total_vino st ON st.cod_vino = v.id "
        "WHERE v.id = %s",
        (cod,),
    ).fetchone()


def ficha_vino_cepas(conn, cod):  # S9 (b)
    return conn.execute(
        "SELECT ce.nombre AS cepa, co.porcentaje FROM composicion co "
        "JOIN cepa ce ON ce.identificador = co.id_cepa "
        "WHERE co.id_vino = %s ORDER BY co.porcentaje DESC",
        (cod,),
    ).fetchall()


def ficha_vino_maridajes(conn, cod):  # S9 (c)
    return conn.execute(
        "SELECT m.nombre AS maridaje, m.temperatura FROM vino_maridaje vm "
        "JOIN maridaje m ON m.id = vm.cod_maridaje WHERE vm.cod_vino = %s ORDER BY m.nombre",
        (cod,),
    ).fetchall()


def listar_anadas(conn, limit: int = 100, offset: int = 0) -> list:
    """Añadas distintas de vinos, ordenadas de forma descendente para el filtro."""
    return conn.execute(
        "SELECT DISTINCT anada FROM vino ORDER BY anada DESC LIMIT %s OFFSET %s",
        (limit, offset),
    ).fetchall()
