import pytest

SALA = 1
TRANSPORTE = 1


# ------------------------------------------------------------ funcionales
def test_01_salud(client):
    r = client.get("/salud")
    assert r.status_code == 200
    assert r.json()["estado"] == "ok"


def test_02_listar_vinos_con_paginacion(client):
    r = client.get("/vinos", params={"page": 1, "limit": 3})
    assert r.status_code == 200
    cuerpo = r.json()
    assert len(cuerpo["items"]) <= 3
    assert cuerpo["limit"] == 3 and cuerpo["total"] >= len(cuerpo["items"])


def test_03_filtro_por_tipo(client):
    r = client.get("/vinos", params={"tipo": "tinto", "limit": 20})
    assert r.status_code == 200
    assert all(v["tipo"] == "tinto" for v in r.json()["items"])


def test_04_vino_inexistente_404(client):
    assert client.get("/vinos/999999999").status_code == 404


def test_05_inyeccion_sql_es_texto_plano(client):
    """Los caracteres maliciosos viajan como parámetro: se buscan como texto literal."""
    antes = client.get("/vinos").json()["total"]
    for payload in ("' OR '1'='1", "'; DROP TABLE vino; --", "x' UNION SELECT NULL--"):
        r = client.get("/vinos", params={"tipo": payload})
        assert r.status_code == 200
        assert r.json()["items"] == []          # ningún vino tiene ese "tipo"
        r = client.get("/vinos", params={"bodega": payload})
        assert r.status_code == 200
        assert r.json()["items"] == []
    assert client.get("/vinos").json()["total"] == antes  # la tabla sigue intacta


def test_06_crud_cliente_socio(client, socio_payload):
    creado = client.post("/clientes", json=socio_payload())
    assert creado.status_code == 201
    cli = creado.json()
    assert cli["tipo_cliente"] == "socio" and float(cli["descuento"]) == 10.0
    assert cli["socio"]["nombre"] == "Ana"

    mod = client.put(f"/clientes/{cli['id']}", json={"socio": {"nombre": "Beatriz"}})
    assert mod.status_code == 200 and mod.json()["socio"]["nombre"] == "Beatriz"

    assert client.delete(f"/clientes/{cli['id']}").status_code == 204
    assert client.get(f"/clientes/{cli['id']}").status_code == 404


# ------------------------------------------- nuevos endpoints etapa 7
def test_07_listar_cepas(client):
    r = client.get("/cepas")
    assert r.status_code == 200
    cuerpo = r.json()
    assert isinstance(cuerpo["items"], list)
    assert cuerpo["total"] >= len(cuerpo["items"])


def test_08_listar_bodegas(client):
    r = client.get("/bodegas")
    assert r.status_code == 200
    cuerpo = r.json()
    assert isinstance(cuerpo["items"], list)
    assert cuerpo["total"] >= len(cuerpo["items"])


def test_09_listar_salas(client):
    r = client.get("/salas")
    assert r.status_code == 200
    cuerpo = r.json()
    assert isinstance(cuerpo["items"], list)
    assert cuerpo["total"] >= len(cuerpo["items"])


def test_10_listar_maridajes(client):
    r = client.get("/maridajes")
    assert r.status_code == 200
    cuerpo = r.json()
    assert isinstance(cuerpo["items"], list)
    assert cuerpo["total"] >= len(cuerpo["items"])


def test_11_clientes_busqueda_por_nombre(client, socio_payload, codigo_postal):
    """Búsqueda simple por nombre en el endpoint GET /clientes?nombre=<texto>."""
    # Crear un cliente socio para tener un nombre de subtipo que buscar
    creado = client.post("/clientes", json=socio_payload(codigo_postal=codigo_postal()))
    assert creado.status_code == 201
    cli = creado.json()
    # Buscar por el nombre "Ana" que pusimos en la fixture
    r = client.get("/clientes", params={"nombre": "Ana"})
    assert r.status_code == 200
    cuerpo = r.json()
    assert len(cuerpo["items"]) >= 1
    # Verificar que el cliente creado aparezca en los resultados
    assert all("nombre" in c for c in cuerpo["items"])
    assert any("Ana" in c["nombre"] for c in cuerpo["items"])


def test_12_vinos_anadas(client):
    """GET /vinos/anadas: devuelve las añadas distintas disponibles."""
    r = client.get("/vinos/anadas")
    assert r.status_code == 200
    cuerpo = r.json()
    assert isinstance(cuerpo["items"], list)
    assert len(cuerpo["items"]) > 0


def test_13_transferencias_listado(client):
    """GET /transferencias: listado paginado con filtros opcionales."""
    # Crear unas transferencias para tener datos
    t1 = client.post("/transferencias", json={"id_sala": SALA})
    t2 = client.post("/transferencias", json={"id_sala": SALA})
    # Listar todas
    r = client.get("/transferencias")
    assert r.status_code == 200
    cuerpo = r.json()
    assert isinstance(cuerpo["items"], list)
    assert cuerpo["total"] >= 2


def test_14_transferencias_filtro_estado(client):
    """GET /transferencias con filtro por estado."""
    # Primero terminar una transferencia para poder filtrar
    t = client.post("/transferencias", json={"id_sala": SALA})
    client.post(f"/transferencias/{t.json()['num_solicitud']}/terminar")
    client.post(f"/transferencias/{t.json()['num_solicitud']}/procesar")
    # Filtrar por estado 'procesado'
    r = client.get("/transferencias", params={"estado": "procesado"})
    assert r.status_code == 200
    cuerpo = r.json()
    assert isinstance(cuerpo["items"], list)
    # Todos los items deberían tener estado 'procesado'
    for item in cuerpo["items"]:
        assert item["estado"] == "procesado"


def test_15_transferencias_estado_invalido_422(client):
    """GET /transferencias con estado inválido debe devolver 422, nunca 500."""
    r = client.get("/transferencias", params={"estado": "invalido"})
    assert r.status_code == 422


# ------------------------------------------- violaciones de reglas de la BD
def test_15_precio_negativo_422(client, vino_payload):
    """CHECK chk_vino_precio_positivo (SQLSTATE 23514) -> 422."""
    r = client.post("/vinos", json=vino_payload(precio="-50"))
    assert r.status_code == 422
    assert r.json()["sqlstate"] == "23514"
    assert "chk_vino_precio_positivo" in r.json()["detail"]


def test_16_corte_distinto_de_100_409(client, vino_payload):
    """Trigger diferido RN-05 (P0001, se dispara en el COMMIT) -> 409."""
    r = client.post("/vinos", json=vino_payload(
        composicion=[{"id_cepa": 1, "porcentaje": "60"}, {"id_cepa": 2, "porcentaje": "30"}]))
    assert r.status_code == 409
    assert "RN-05" in r.json()["detail"]


def test_17_vino_duplicado_409(client, vino_payload):
    """UNIQUE (nombre, anada, volumen) RN-01 (SQLSTATE 23505) -> 409."""
    datos = vino_payload()
    assert client.post("/vinos", json=datos).status_code == 201
    r = client.post("/vinos", json=datos)
    assert r.status_code == 409
    assert r.json()["sqlstate"] == "23505"


def test_18_vender_sin_stock_409(client, vino_payload, socio_payload):
    """RN-09: el trigger rechaza vender un vino sin stock en la sala."""
    vino = client.post("/vinos", json=vino_payload()).json()
    cliente = client.post("/clientes", json=socio_payload()).json()
    r = client.post("/comprobantes", json={
        "id_sala": SALA, "id_cliente": cliente["id"],
        "renglones": [{"cod_vino": vino["id"], "cantidad": 1}]})
    assert r.status_code == 409
    assert "Stock insuficiente" in r.json()["detail"]


def test_19_procesar_transferencia_sin_terminar_409(client):
    """Estado inválido: el procedimiento exige estado 'terminado' (P0001) -> 409."""
    t = client.post("/transferencias", json={"id_sala": SALA})
    assert t.status_code == 201
    r = client.post(f"/transferencias/{t.json()['num_solicitud']}/procesar")
    assert r.status_code == 409
    assert "terminado" in r.json()["detail"]


# ----------------------------------------------------- flujo de punta a punta
def test_20_flujo_completo_ingreso_transferencia_venta(client, vino_payload, socio_payload, cuit_bodega):
    vino = client.post("/vinos", json=vino_payload(precio="1000.00")).json()["id"]

    # Ingreso al depósito central: 10 botellas
    ing = client.post("/ingresos", json={"cuit_bodega": cuit_bodega, "cod_transporte": 1}).json()["id"]
    assert client.post(f"/ingresos/{ing}/renglones", json={"cod_vino": vino, "cantidad": 10}).status_code == 201
    assert client.post(f"/ingresos/{ing}/terminar").json()["estado"] == "terminado"
    assert client.post(f"/ingresos/{ing}/procesar").json()["estado"] == "procesado"

    # Transferencia a la sala: 5 botellas
    tr = client.post("/transferencias", json={"id_sala": SALA}).json()["num_solicitud"]
    assert client.post(f"/transferencias/{tr}/renglones", json={"cod_vino": vino, "cantidad": 5}).status_code == 201
    client.post(f"/transferencias/{tr}/terminar")
    assert client.post(f"/transferencias/{tr}/procesar").json()["estado"] == "procesado"

    # Un renglón en un documento ya procesado se rechaza (RN-12)
    tarde = client.post(f"/transferencias/{tr}/renglones", json={"cod_vino": vino, "cantidad": 1})
    assert tarde.status_code == 409 and "RN-12" in tarde.json()["detail"]

    # Venta a un socio (10 %): 2 x 1000 = 2000, descuento 200, total 1800 (lo calcula la BD)
    cli = client.post("/clientes", json=socio_payload()).json()["id"]
    venta = client.post("/comprobantes", json={
        "id_sala": SALA, "id_cliente": cli, "renglones": [{"cod_vino": vino, "cantidad": 2}]})
    assert venta.status_code == 201
    c = venta.json()
    assert float(c["subtotal"]) == 2000.0 and float(c["descuento"]) == 200.0 and float(c["total"]) == 1800.0
    assert client.get(f"/comprobantes/{c['numero']}").status_code == 200

    # Quedan 3 en sala: pedir 4 debe fallar y NO dejar comprobante a medias
    r = client.post("/comprobantes", json={
        "id_sala": SALA, "id_cliente": cli, "renglones": [{"cod_vino": vino, "cantidad": 4}]})
    assert r.status_code == 409 and "Stock insuficiente" in r.json()["detail"]


@pytest.mark.parametrize("ruta", [
    "/reportes/top-vinos",
    "/reportes/ventas-por-sala",
    f"/reportes/vinos-sin-stock?sala={SALA}",
    "/reportes/transportista-mayor-actividad",
    "/cepas",
    "/bodegas",
    "/salas",
    "/maridajes",
])
def test_21_reportes_responden_200(client, ruta):
    r = client.get(ruta)
    assert r.status_code == 200
    assert isinstance(r.json(), list)
