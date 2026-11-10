from fastapi import APIRouter, HTTPException

import schemas
from database import transaction
from repositories import comprobantes as repo

router = APIRouter(prefix="/comprobantes", tags=["Comprobantes (Ventas)"])


def _completo(conn, nro):
    cabecera = repo.obtener_comprobante(conn, nro)
    if cabecera is None:
        raise HTTPException(404, f"El comprobante {nro} no existe")
    cabecera["renglones"] = repo.renglones_de_comprobante(conn, nro)
    return cabecera


@router.post("", status_code=201)
def crear_comprobante(body: schemas.ComprobanteIn):
    """Cabecera + renglones en UNA transacción. La API no calcula nada: los triggers
    validan el stock (RN-09), congelan el precio, aplican el descuento y totalizan."""
    with transaction() as conn:
        nro = repo.insertar_comprobante(conn, body.id_sala, body.id_cliente)
        for r in body.renglones:
            repo.insertar_renglon(conn, nro, r.cod_vino, r.cantidad)
        # Si algún renglón falla, el ROLLBACK deshace también la cabecera.
        return _completo(conn, nro)


@router.get("/{nro}")
def obtener_comprobante(nro: int):
    with transaction() as conn:
        return _completo(conn, nro)
