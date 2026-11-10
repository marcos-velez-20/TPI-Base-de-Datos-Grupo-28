from fastapi import APIRouter, HTTPException, Query

from database import transaction
from repositories import reportes as repo

router = APIRouter(prefix="/reportes", tags=["Reportes"])


@router.get("/top-vinos")
def top_vinos(limit: int = Query(10, ge=1, le=100)):
    """S1: vinos con más botellas vendidas en toda la red."""
    with transaction() as conn:
        return repo.top_vinos(conn, limit)


@router.get("/ventas-por-sala")
def ventas_por_sala():
    """S8: monto vendido por sala en el último trimestre."""
    with transaction() as conn:
        return repo.ventas_por_sala(conn)


@router.get("/vinos-sin-stock")
def vinos_sin_stock(sala: int = Query(..., description="id de la sala")):
    """S6: vinos sin stock en la sala pero con stock en el depósito central."""
    with transaction() as conn:
        return repo.vinos_sin_stock_en_sala(conn, sala)


@router.get("/transportista-mayor-actividad")
def transportista_mayor_actividad():
    """S7: empresa(s) de transporte con más ingresos en el último mes."""
    with transaction() as conn:
        return repo.transportista_mayor_actividad(conn)


@router.get("/ficha-vino/{cod}")
def ficha_vino(cod: int):
    """S9: ficha/trazabilidad de un vino (bodega, cepas, maridajes y stock total)."""
    with transaction() as conn:
        ficha = repo.ficha_vino_datos(conn, cod)
        if ficha is None:
            raise HTTPException(404, f"El vino {cod} no existe")
        ficha["cepas"] = repo.ficha_vino_cepas(conn, cod)
        ficha["maridajes"] = repo.ficha_vino_maridajes(conn, cod)
        return ficha
