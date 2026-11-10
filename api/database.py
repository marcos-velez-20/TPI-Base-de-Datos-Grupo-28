"""Pool de conexiones y manejo explícito de transacciones (psycopg 3, sin ORM)."""
import os
from contextlib import contextmanager

from dotenv import load_dotenv
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

load_dotenv()

pool: ConnectionPool | None = None


def _conninfo() -> str:
    usuario = os.getenv("DB_USER", "app_rw")
    if usuario in ("postgres", ""):
        # Requisito de la Etapa 6: la API jamás usa el rol administrador.
        raise RuntimeError("DB_USER no puede ser 'postgres': usá el rol de mínimos privilegios app_rw.")
    return make_conninfo(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5433"),
        user=usuario,
        password=os.environ["DB_PASSWORD"],
        dbname=os.getenv("DB_NAME", "bodegas_del_atuel"),
    )


def init_pool() -> None:
    global pool
    # autocommit=True: las transacciones las abrimos nosotros con `transaction()`
    # (BEGIN / COMMIT / ROLLBACK explícitos); fuera de ella cada sentencia es atómica.
    pool = ConnectionPool(
        _conninfo(),
        min_size=2,
        max_size=10,
        timeout=10,
        kwargs={"autocommit": True, "row_factory": dict_row},
        open=False,
    )
    pool.open()


def close_pool() -> None:
    if pool is not None:
        pool.close()


@contextmanager
def transaction():
    """Entrega una conexión dentro de una transacción explícita.

    BEGIN al entrar; COMMIT al salir sin error; ROLLBACK si hay excepción.
    Los constraint triggers diferidos (RN-05) se evalúan en el COMMIT, por lo que
    su error se lanza al salir de este bloque.
    """
    with pool.connection() as conn:
        with conn.transaction():
            yield conn
