from fastapi import APIRouter, HTTPException

import schemas
from database import transaction
from repositories import ingresos as repo

router = APIRouter(prefix="/ingresos", tags=["Ingresos"])


def _completo(conn, cod):
    cabecera = repo.obtener_ingreso(conn, cod)
    if cabecera is None:
        raise HTTPException(404, f"El ingreso {cod} no existe")
    cabecera["renglones"] = repo.renglones_de_ingreso(conn, cod)
    return cabecera


def _exigir_existencia(conn, cod):
    if not repo.existe(conn, cod):
        raise HTTPException(404, f"El ingreso {cod} no existe")


@router.post("", status_code=201)
def crear_ingreso(body: schemas.IngresoIn):
    with transaction() as conn:
        cod = repo.insertar_ingreso(conn, body.cuit_bodega, body.cod_transporte)
        return _completo(conn, cod)


@router.get("/{cod}")
def obtener_ingreso(cod: int):
    with transaction() as conn:
        return _completo(conn, cod)


@router.post("/{cod}/renglones", status_code=201)
def agregar_renglon(cod: int, body: schemas.RenglonIn):
    with transaction() as conn:
        _exigir_existencia(conn, cod)
        repo.insertar_renglon(conn, cod, body.cod_vino, body.cantidad)
        return _completo(conn, cod)


@router.post("/{cod}/terminar")
def terminar(cod: int):
    with transaction() as conn:
        _exigir_existencia(conn, cod)
        repo.marcar_terminado(conn, cod)
        return _completo(conn, cod)


@router.post("/{cod}/procesar")
def procesar(cod: int):
    with transaction() as conn:
        _exigir_existencia(conn, cod)
        repo.procesar(conn, cod)  # CALL sp_procesar_ingreso(...)
        return _completo(conn, cod)
