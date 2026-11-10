from decimal import Decimal

from fastapi import APIRouter, HTTPException, Query, Response

import schemas
from database import transaction
from repositories import clientes as repo

router = APIRouter(prefix="/clientes", tags=["Clientes"])

DESCUENTO_POR_DEFECTO = {"socio": Decimal("10.00"), "distribuidor": Decimal("20.00"), "exportador": Decimal("30.00")}


def _armar(fila):
    """Convierte la fila plana (supertipo + LEFT JOIN a subtipos) en JSON anidado."""
    tipo = fila["tipo_cliente"].lower()
    base = {k: fila[k] for k in (
        "id", "tipo_cliente", "tipo_documento", "num_documento", "fecha_alta",
        "calle", "numero_calle", "descuento", "codigo_postal")}
    if tipo == "socio":
        base["socio"] = {"nombre": fila["socio_nombre"], "apellido": fila["socio_apellido"]}
    elif tipo == "distribuidor":
        base["distribuidor"] = {
            "zona_cobertura": fila["zona_cobertura"],
            "num_habilitacion": fila["num_habilitacion"],
            "razon_social": fila["distribuidor_razon_social"],
        }
    elif tipo == "exportador":
        base["exportador"] = {"pais_destino": fila["pais_destino"], "razon_social": fila["exportador_razon_social"]}
    return base


def _obtener_o_404(conn, id_cliente):
    fila = repo.obtener_cliente(conn, id_cliente)
    if fila is None:
        raise HTTPException(404, f"El cliente {id_cliente} no existe")
    return _armar(fila)


@router.get("")
def listar_clientes(
    tipo: str | None = None,
    page: int = Query(1, ge=1),
    limit: int = Query(10, ge=1, le=100),
):
    with transaction() as conn:
        items = repo.listar_clientes(conn, tipo, limit, (page - 1) * limit)
        total = repo.contar_clientes(conn, tipo)
    return {"page": page, "limit": limit, "total": total, "items": items}


@router.get("/{id_cliente}")
def detalle_cliente(id_cliente: int):
    with transaction() as conn:
        return _obtener_o_404(conn, id_cliente)


@router.post("", status_code=201)
def crear_cliente(body: schemas.ClienteIn):
    datos = body.model_dump(exclude={"socio", "distribuidor", "exportador"})
    if datos["descuento"] is None:
        datos["descuento"] = DESCUENTO_POR_DEFECTO[body.tipo_cliente]
    with transaction() as conn:  # supertipo + subtipo en una sola transacción
        nuevo = repo.insertar_cliente(conn, datos)
        if body.tipo_cliente == "socio":
            repo.insertar_socio(conn, nuevo, body.socio.model_dump())
        elif body.tipo_cliente == "distribuidor":
            repo.insertar_distribuidor(conn, nuevo, body.distribuidor.model_dump())
        else:
            repo.insertar_exportador(conn, nuevo, body.exportador.model_dump())
    with transaction() as conn:
        return _obtener_o_404(conn, nuevo)


@router.put("/{id_cliente}")
def modificar_cliente(id_cliente: int, body: schemas.ClienteUpdate):
    """El tipo de cliente no se puede cambiar (lo impide el trigger de la jerarquía)."""
    datos = body.model_dump(exclude={"socio", "distribuidor", "exportador"})
    with transaction() as conn:
        tipo = repo.tipo_de_cliente(conn, id_cliente)
        if tipo is None:
            raise HTTPException(404, f"El cliente {id_cliente} no existe")
        repo.actualizar_cliente(conn, id_cliente, datos)
        if tipo == "socio" and body.socio:
            repo.actualizar_socio(conn, id_cliente, body.socio.model_dump())
        elif tipo == "distribuidor" and body.distribuidor:
            repo.actualizar_distribuidor(conn, id_cliente, body.distribuidor.model_dump())
        elif tipo == "exportador" and body.exportador:
            repo.actualizar_exportador(conn, id_cliente, body.exportador.model_dump())
    with transaction() as conn:
        return _obtener_o_404(conn, id_cliente)


@router.delete("/{id_cliente}", status_code=204)
def borrar_cliente(id_cliente: int):
    with transaction() as conn:
        if repo.eliminar_cliente(conn, id_cliente) == 0:
            raise HTTPException(404, f"El cliente {id_cliente} no existe")
    return Response(status_code=204)
