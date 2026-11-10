"""Modelos de entrada. Solo validan tipos/forma: las reglas de negocio
(precio > 0, corte = 100 %, stock, estados, etc.) las decide la base de datos."""
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, model_validator


# ---------- Vinos ----------
class ComposicionIn(BaseModel):
    id_cepa: int
    porcentaje: Decimal


class VinoIn(BaseModel):
    nombre: str
    volumen: int
    precio: Decimal
    graduacion: Decimal
    tipo: str
    anada: int
    cuit_bodega: str
    composicion: list[ComposicionIn] = Field(default_factory=list)
    maridajes: list[int] = Field(default_factory=list)


class VinoUpdate(BaseModel):
    nombre: str
    volumen: int
    precio: Decimal
    graduacion: Decimal
    tipo: str
    anada: int
    cuit_bodega: str
    composicion: list[ComposicionIn] | None = None  # None = no tocar el corte
    maridajes: list[int] | None = None              # None = no tocar los maridajes


# ---------- Clientes ----------
class SocioIn(BaseModel):
    nombre: str
    apellido: str


class DistribuidorIn(BaseModel):
    zona_cobertura: str
    num_habilitacion: str
    razon_social: str


class ExportadorIn(BaseModel):
    pais_destino: str
    razon_social: str


class ClienteIn(BaseModel):
    tipo_cliente: Literal["socio", "distribuidor", "exportador"]
    tipo_documento: str
    num_documento: str
    calle: str
    numero_calle: str
    codigo_postal: int
    descuento: Decimal | None = None  # si falta: 10 / 20 / 30 según el tipo
    socio: SocioIn | None = None
    distribuidor: DistribuidorIn | None = None
    exportador: ExportadorIn | None = None

    @model_validator(mode="after")
    def _subtipo_coherente(self):
        if getattr(self, self.tipo_cliente) is None:
            raise ValueError(f"Falta el bloque '{self.tipo_cliente}' con los datos del subtipo")
        return self


class SocioUpdate(BaseModel):
    nombre: str | None = None
    apellido: str | None = None


class DistribuidorUpdate(BaseModel):
    zona_cobertura: str | None = None
    num_habilitacion: str | None = None
    razon_social: str | None = None


class ExportadorUpdate(BaseModel):
    pais_destino: str | None = None
    razon_social: str | None = None


class ClienteUpdate(BaseModel):
    tipo_documento: str | None = None
    num_documento: str | None = None
    calle: str | None = None
    numero_calle: str | None = None
    codigo_postal: int | None = None
    descuento: Decimal | None = None
    socio: SocioUpdate | None = None
    distribuidor: DistribuidorUpdate | None = None
    exportador: ExportadorUpdate | None = None


# ---------- Comprobantes ----------
class RenglonVentaIn(BaseModel):
    cod_vino: int
    cantidad: int


class ComprobanteIn(BaseModel):
    id_sala: int
    id_cliente: int
    renglones: list[RenglonVentaIn]


# ---------- Transferencias / Ingresos ----------
class TransferenciaIn(BaseModel):
    id_sala: int


class IngresoIn(BaseModel):
    cuit_bodega: str
    cod_transporte: int


class RenglonIn(BaseModel):
    cod_vino: int
    cantidad: int
