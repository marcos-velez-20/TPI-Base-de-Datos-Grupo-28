"""Fixtures. Las pruebas corren contra la base REAL (docker compose up -d db) ya
migrada y cargada con db/seed. Se asume: sala 1, transporte 1 y cepas 1 y 2 existentes."""
import uuid

import pytest
from fastapi.testclient import TestClient

from main import app


@pytest.fixture(scope="session")
def client():
    with TestClient(app) as c:  # dispara el lifespan: abre/cierra el pool
        yield c


@pytest.fixture(scope="session")
def cuit_bodega(client):
    items = client.get("/vinos", params={"limit": 1}).json()["items"]
    if not items:
        pytest.skip("La base no tiene vinos: ejecutá db/seed antes de correr las pruebas")
    return items[0]["cuit_bodega"]


@pytest.fixture(scope="session")
def codigo_postal(client):
    items = client.get("/clientes", params={"limit": 1}).json()["items"]
    if not items:
        pytest.skip("La base no tiene clientes: ejecutá db/seed antes de correr las pruebas")
    return items[0]["codigo_postal"]


@pytest.fixture
def vino_payload(cuit_bodega):
    def _armar(**cambios):
        datos = {
            "nombre": f"Vino Test {uuid.uuid4().hex[:10]}",
            "volumen": 750,
            "precio": "1000.00",
            "graduacion": "13.5",
            "tipo": "tinto",
            "anada": 2020,
            "cuit_bodega": cuit_bodega,
            "composicion": [{"id_cepa": 1, "porcentaje": "60"}, {"id_cepa": 2, "porcentaje": "40"}],
            "maridajes": [],
        }
        datos.update(cambios)
        return datos
    return _armar


@pytest.fixture
def socio_payload(codigo_postal):
    def _armar():
        return {
            "tipo_cliente": "socio",
            "tipo_documento": "DNI",
            "num_documento": str(uuid.uuid4().int)[:12],
            "calle": "Calle Test",
            "numero_calle": "123",
            "codigo_postal": codigo_postal,
            "socio": {"nombre": "Ana", "apellido": "Prueba"},
        }
    return _armar
