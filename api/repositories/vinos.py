"""Acceso a datos de vinos: una función por consulta, SQL puro y parametrizado."""


def _filtros(tipo, cepa, bodega, anada):
    """Arma el WHERE sumando fragmentos SQL FIJOS; los valores del usuario viajan
    siempre en la lista de parámetros (%s), nunca dentro del texto SQL."""
    condiciones: list[str] = []
    params: list = []
    if tipo:
        condiciones.append("v.tipo = %s")
        params.append(tipo)
    if anada is not None:
        condiciones.append("v.anada = %s")
        params.append(anada)
    if bodega:
        condiciones.append("(b.cuit = %s OR b.razon_social ILIKE %s)")
        params.extend([bodega, f"%{bodega}%"])  # el comodín va en el VALOR, no en el SQL
    if cepa:
        condiciones.append(
            "EXISTS (SELECT 1 FROM composicion co JOIN cepa ce ON ce.identificador = co.id_cepa "
            "WHERE co.id_vino = v.id AND lower(ce.nombre) = lower(%s))"
        )
        params.append(cepa)
    where = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    return where, params


def listar_vinos(conn, tipo, cepa, bodega, anada, limit, offset):
    where, params = _filtros(tipo, cepa, bodega, anada)
    sql = (
        "SELECT v.id, v.nombre, v.tipo, v.anada, v.volumen, v.precio, v.graduacion, "
        "v.cuit_bodega, b.razon_social AS bodega "
        "FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega"
        + where
        + " ORDER BY v.id LIMIT %s OFFSET %s"
    )
    return conn.execute(sql, [*params, limit, offset]).fetchall()


def contar_vinos(conn, tipo, cepa, bodega, anada) -> int:
    where, params = _filtros(tipo, cepa, bodega, anada)
    sql = "SELECT COUNT(*) AS total FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega" + where
    return conn.execute(sql, params).fetchone()["total"]


def obtener_vino(conn, cod):
    return conn.execute(
        "SELECT v.id, v.nombre, v.tipo, v.anada, v.volumen, v.precio, v.graduacion, "
        "v.cuit_bodega, b.razon_social AS bodega "
        "FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega WHERE v.id = %s",
        (cod,),
    ).fetchone()


def cepas_de_vino(conn, cod):
    return conn.execute(
        "SELECT ce.identificador AS id_cepa, ce.nombre AS cepa, ce.tipo, co.porcentaje "
        "FROM composicion co JOIN cepa ce ON ce.identificador = co.id_cepa "
        "WHERE co.id_vino = %s ORDER BY co.porcentaje DESC, ce.nombre",
        (cod,),
    ).fetchall()


def maridajes_de_vino(conn, cod):
    return conn.execute(
        "SELECT m.id, m.nombre AS maridaje, m.temperatura "
        "FROM vino_maridaje vm JOIN maridaje m ON m.id = vm.cod_maridaje "
        "WHERE vm.cod_vino = %s ORDER BY m.nombre",
        (cod,),
    ).fetchall()


def insertar_vino(conn, d) -> int:
    return conn.execute(
        "INSERT INTO vino (nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega) "
        "VALUES (%(nombre)s, %(volumen)s, %(precio)s, %(graduacion)s, %(tipo)s, %(anada)s, %(cuit_bodega)s) "
        "RETURNING id",
        d,
    ).fetchone()["id"]


def insertar_composicion(conn, id_vino, items):
    """items: lista de (id_cepa, porcentaje)."""
    with conn.cursor() as cur:
        cur.executemany(
            "INSERT INTO composicion (id_cepa, id_vino, porcentaje) VALUES (%s, %s, %s)",
            [(id_cepa, id_vino, pct) for id_cepa, pct in items],
        )


def insertar_maridajes(conn, id_vino, ids_maridaje):
    with conn.cursor() as cur:
        cur.executemany(
            "INSERT INTO vino_maridaje (cod_vino, cod_maridaje) VALUES (%s, %s)",
            [(id_vino, m) for m in ids_maridaje],
        )


def actualizar_vino(conn, cod, d) -> int:
    cur = conn.execute(
        "UPDATE vino SET nombre = %(nombre)s, volumen = %(volumen)s, precio = %(precio)s, "
        "graduacion = %(graduacion)s, tipo = %(tipo)s, anada = %(anada)s, cuit_bodega = %(cuit_bodega)s "
        "WHERE id = %(id)s",
        {**d, "id": cod},
    )
    return cur.rowcount


def borrar_composicion(conn, cod):
    conn.execute("DELETE FROM composicion WHERE id_vino = %s", (cod,))


def borrar_maridajes(conn, cod):
    conn.execute("DELETE FROM vino_maridaje WHERE cod_vino = %s", (cod,))


def eliminar_vino(conn, cod) -> int:
    return conn.execute("DELETE FROM vino WHERE id = %s", (cod,)).rowcount


def auditoria_precio(conn, cod):
    return conn.execute(
        "SELECT id, precio_anterior, precio_nuevo, fecha, hora, usuario "
        "FROM auditoria_precio WHERE id_vino = %s ORDER BY id DESC",
        (cod,),
    ).fetchall()
