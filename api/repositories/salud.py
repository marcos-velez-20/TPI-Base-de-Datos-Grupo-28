def ping(conn) -> int:
    return conn.execute("SELECT 1 AS ok").fetchone()["ok"]
