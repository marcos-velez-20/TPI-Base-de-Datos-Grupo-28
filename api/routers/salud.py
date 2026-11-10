from fastapi import APIRouter

from database import transaction
from repositories import salud as repo

router = APIRouter(tags=["Salud"])


@router.get("/salud")
def salud():
    """Valida la conectividad con la base (SELECT 1). Si falla, responde 503."""
    with transaction() as conn:
        repo.ping(conn)
    return {"estado": "ok", "base_de_datos": "conectada"}
