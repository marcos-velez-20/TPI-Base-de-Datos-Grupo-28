from fastapi import APIRouter, HTTPException, Query
from enum import Enum

import schemas
from database import transaction
from repositories import transferencias as repo

router = APIRouter(prefix="/transferencias", tags=["Transferencias"])


class EnumEstadoTransferencia(str, Enum):
    en_confeccion = "en_confeccion"
    terminado = "terminado"
    procesado = "procesado"


def _completa(conn, nro):
    cabecera = repo.obtener_transferencia(conn, nro)
    if cabecera is None:
        raise HTTPException(404, f"La transferencia {nro} no existe")
    cabecera["renglones"] = repo.renglones_de_transferencia(conn, nro)
    return cabecera


def _exigir_existencia(conn, nro):
    if not repo.existe(conn, nro):
        raise HTTPException(404, f"La transferencia {nro} no existe")


@router.get("")
def listar_transferencias(
    estado: EnumEstadoTransferencia | None = Query(
        None, description="Estado de la transferencia (en_confeccion, terminado, procesado)"
    ),
    id_sala: int | None = Query(None, description="ID de la sala"),
    page: int = Query(1, ge=1, description="Número de página"),
    limit: int = Query(10, ge=1, le=100, description="Elementos por página"),
):
    offset = (page - 1) * limit
    with transaction() as conn:
        items = repo.listar_transferencias(conn, estado, id_sala, limit, offset)
        total = repo.contar_transferencias(conn, estado, id_sala)
    return {"page": page, "limit": limit, "total": total, "items": items}


@router.post("", status_code=201)
def crear_transferencia(body: schemas.TransferenciaIn):
    with transaction() as conn:
        nro = repo.insertar_transferencia(conn, body.id_sala)
        return _completa(conn, nro)


@router.get("/{nro}")
def obtener_transferencia(nro: int):
    with transaction() as conn:
        return _completa(conn, nro)


@router.post("/{nro}/renglones", status_code=201)
def agregar_renglon(nro: int, body: schemas.RenglonIn):
    with transaction() as conn:
        _exigir_existencia(conn, nro)
        repo.insertar_renglon(conn, nro, body.cod_vino, body.cantidad)  # RN-12 lo controla el trigger
        return _completa(conn, nro)


@router.post("/{nro}/terminar")
def terminar(nro: int):
    with transaction() as conn:
        _exigir_existencia(conn, nro)
        repo.marcar_terminada(conn, nro)
        return _completa(conn, nro)


@router.post("/{nro}/procesar")
def procesar(nro: int):
    with transaction() as conn:
        _exigir_existencia(conn, nro)
        repo.procesar(conn, nro)  # CALL sp_procesar_transferencia(...)
        return _completa(conn, nro)
