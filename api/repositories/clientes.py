"""Acceso a datos de clientes (supertipo) y subtipos socio / distribuidor / exportador."""


_FROM_LISTADO = (
    " FROM clientes c "
    "LEFT JOIN socio_club s ON s.id = c.id "
    "LEFT JOIN distribuidores d ON d.id = c.id "
    "LEFT JOIN exportadores e ON e.id = c.id"
)


def _filtros(tipo, nombre):
    """WHERE con fragmentos SQL fijos; los valores del usuario viajan como parámetros."""
    condiciones, params = [], []
    if tipo:
        condiciones.append("lower(c.tipoCliente) = lower(%s)")
        params.append(tipo)
    if nombre:
        condiciones.append(
            "(s.nombre ILIKE %s OR s.apellido ILIKE %s OR (s.nombre || ' ' || s.apellido) ILIKE %s "
            "OR d.razonSocial ILIKE %s OR e.razonSocial ILIKE %s)"
        )
        params.extend([f"%{nombre}%"] * 5)
    where = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    return where, params


def listar_clientes(conn, tipo, nombre, limit, offset):
    where, params = _filtros(tipo, nombre)
    sql = (
        "SELECT c.id, c.tipoCliente AS tipo_cliente, c.tipo_documento, c.num_documento, "
        "c.fecha_alta, c.descuento, c.codigo_postal, "
        "COALESCE(s.nombre || ' ' || s.apellido, d.razonSocial, e.razonSocial) AS nombre"
        + _FROM_LISTADO
        + where
        + " ORDER BY c.id LIMIT %s OFFSET %s"
    )
    return conn.execute(sql, [*params, limit, offset]).fetchall()


def contar_clientes(conn, tipo, nombre=None) -> int:
    where, params = _filtros(tipo, nombre)
    return conn.execute("SELECT COUNT(*) AS total" + _FROM_LISTADO + where, params).fetchone()["total"]


def obtener_cliente(conn, id_cliente):
    return conn.execute(
        "SELECT c.id, c.tipoCliente AS tipo_cliente, c.tipo_documento, c.num_documento, c.fecha_alta, "
        "c.calle, c.numeroCalle AS numero_calle, c.descuento, c.codigo_postal, "
        "s.nombre AS socio_nombre, s.apellido AS socio_apellido, "
        "d.zona_cobertura, d.num_habilitacion, d.razonSocial AS distribuidor_razon_social, "
        "e.pais_destino, e.razonSocial AS exportador_razon_social "
        "FROM clientes c "
        "LEFT JOIN socio_club s ON s.id = c.id "
        "LEFT JOIN distribuidores d ON d.id = c.id "
        "LEFT JOIN exportadores e ON e.id = c.id "
        "WHERE c.id = %s",
        (id_cliente,),
    ).fetchone()


def tipo_de_cliente(conn, id_cliente):
    fila = conn.execute(
        "SELECT lower(tipoCliente) AS tipo FROM clientes WHERE id = %s FOR UPDATE", (id_cliente,)
    ).fetchone()
    return fila["tipo"] if fila else None


def insertar_cliente(conn, d) -> int:
    return conn.execute(
        "INSERT INTO clientes (tipoCliente, tipo_documento, num_documento, calle, numeroCalle, descuento, codigo_postal) "
        "VALUES (%(tipo_cliente)s, %(tipo_documento)s, %(num_documento)s, %(calle)s, %(numero_calle)s, "
        "%(descuento)s, %(codigo_postal)s) RETURNING id",
        d,
    ).fetchone()["id"]


def insertar_socio(conn, id_cliente, d):
    conn.execute(
        "INSERT INTO socio_club (id, nombre, apellido) VALUES (%s, %s, %s)",
        (id_cliente, d["nombre"], d["apellido"]),
    )


def insertar_distribuidor(conn, id_cliente, d):
    conn.execute(
        "INSERT INTO distribuidores (id, zona_cobertura, num_habilitacion, razonSocial) VALUES (%s, %s, %s, %s)",
        (id_cliente, d["zona_cobertura"], d["num_habilitacion"], d["razon_social"]),
    )


def insertar_exportador(conn, id_cliente, d):
    conn.execute(
        "INSERT INTO exportadores (id, pais_destino, razonSocial) VALUES (%s, %s, %s)",
        (id_cliente, d["pais_destino"], d["razon_social"]),
    )


def actualizar_cliente(conn, id_cliente, d) -> int:
    # COALESCE(parámetro, columna): si el campo no viene (NULL) se conserva el valor actual.
    return conn.execute(
        "UPDATE clientes SET "
        "tipo_documento = COALESCE(%(tipo_documento)s, tipo_documento), "
        "num_documento = COALESCE(%(num_documento)s, num_documento), "
        "calle = COALESCE(%(calle)s, calle), "
        "numeroCalle = COALESCE(%(numero_calle)s, numeroCalle), "
        "descuento = COALESCE(%(descuento)s, descuento), "
        "codigo_postal = COALESCE(%(codigo_postal)s, codigo_postal) "
        "WHERE id = %(id)s",
        {**d, "id": id_cliente},
    ).rowcount


def actualizar_socio(conn, id_cliente, d):
    conn.execute(
        "UPDATE socio_club SET nombre = COALESCE(%(nombre)s, nombre), apellido = COALESCE(%(apellido)s, apellido) "
        "WHERE id = %(id)s",
        {**d, "id": id_cliente},
    )


def actualizar_distribuidor(conn, id_cliente, d):
    conn.execute(
        "UPDATE distribuidores SET zona_cobertura = COALESCE(%(zona_cobertura)s, zona_cobertura), "
        "num_habilitacion = COALESCE(%(num_habilitacion)s, num_habilitacion), "
        "razonSocial = COALESCE(%(razon_social)s, razonSocial) WHERE id = %(id)s",
        {**d, "id": id_cliente},
    )


def actualizar_exportador(conn, id_cliente, d):
    conn.execute(
        "UPDATE exportadores SET pais_destino = COALESCE(%(pais_destino)s, pais_destino), "
        "razonSocial = COALESCE(%(razon_social)s, razonSocial) WHERE id = %(id)s",
        {**d, "id": id_cliente},
    )


def eliminar_cliente(conn, id_cliente) -> int:
    return conn.execute("DELETE FROM clientes WHERE id = %s", (id_cliente,)).rowcount
