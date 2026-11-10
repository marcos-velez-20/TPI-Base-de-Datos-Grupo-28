from fastapi import APIRouter, HTTPException, Query, Response

import schemas
from database import transaction
from repositories import vinos as repo

router = APIRouter(prefix="/vinos", tags=["Vinos"])


def _detalle(conn, cod):
    vino = repo.obtener_vino(conn, cod)
    if vino is None:
        raise HTTPException(404, f"El vino {cod} no existe")
    vino["cepas"] = repo.cepas_de_vino(conn, cod)
    vino["maridajes"] = repo.maridajes_de_vino(conn, cod)
    return vino


@router.get("")
def listar_vinos(
    tipo: str | None = None,
    cepa: str | None = None,
    bodega: str | None = Query(None, description="CUIT exacto o parte de la razón social"),
    anada: int | None = None,
    page: int = Query(1, ge=1),
    limit: int = Query(10, ge=1, le=100),
):
    offset = (page - 1) * limit
    with transaction() as conn:
        items = repo.listar_vinos(conn, tipo, cepa, bodega, anada, limit, offset)
        total = repo.contar_vinos(conn, tipo, cepa, bodega, anada)
    return {"page": page, "limit": limit, "total": total, "items": items}


@router.get("/{cod}")
def detalle_vino(cod: int):
    with transaction() as conn:
        return _detalle(conn, cod)


@router.get("/{cod}/auditoria-precio")
def auditoria_precio(cod: int):
    """Historial de cambios de precio generado por el trigger RN-13."""
    with transaction() as conn:
        if repo.obtener_vino(conn, cod) is None:
            raise HTTPException(404, f"El vino {cod} no existe")
        return repo.auditoria_precio(conn, cod)


@router.post("", status_code=201)
def crear_vino(body: schemas.VinoIn):
    datos = body.model_dump(exclude={"composicion", "maridajes"})
    with transaction() as conn:
        cod = repo.insertar_vino(conn, datos)
        repo.insertar_composicion(conn, cod, [(c.id_cepa, c.porcentaje) for c in body.composicion])
        repo.insertar_maridajes(conn, cod, body.maridajes)
    # Al salir del bloque se hizo COMMIT: ahí dispara el trigger diferido RN-05
    # (corte = 100 %) y, si falla, la excepción ya fue traducida a 409.
    with transaction() as conn:
        return _detalle(conn, cod)


@router.put("/{cod}")
def modificar_vino(cod: int, body: schemas.VinoUpdate):
    datos = body.model_dump(exclude={"composicion", "maridajes"})
    with transaction() as conn:
        if repo.actualizar_vino(conn, cod, datos) == 0:  # RN-13 audita el precio por trigger
            raise HTTPException(404, f"El vino {cod} no existe")
        if body.composicion is not None:
            repo.borrar_composicion(conn, cod)
            repo.insertar_composicion(conn, cod, [(c.id_cepa, c.porcentaje) for c in body.composicion])
        if body.maridajes is not None:
            repo.borrar_maridajes(conn, cod)
            repo.insertar_maridajes(conn, cod, body.maridajes)
    with transaction() as conn:
        return _detalle(conn, cod)


@router.delete("/{cod}", status_code=204)
def borrar_vino(cod: int):
    with transaction() as conn:
        if repo.eliminar_vino(conn, cod) == 0:
            raise HTTPException(404, f"El vino {cod} no existe")
    return Response(status_code=204)
