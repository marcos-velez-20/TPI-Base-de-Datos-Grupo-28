import { useCallback, useEffect, useState } from "react";

/**
 * Ejecuta una función de src/api al montar y cada vez que cambian las dependencias.
 *   const { data, error, loading, recargar } = useApi(() => listarVinos({ page }), [page]);
 */
export function useApi(funcion, dependencias = []) {
  const [estado, setEstado] = useState({ data: null, error: null, loading: true });
  const [version, setVersion] = useState(0);

  useEffect(() => {
    let activo = true;
    setEstado((e) => ({ ...e, loading: true, error: null }));
    funcion()
      .then((data) => activo && setEstado({ data, error: null, loading: false }))
      .catch((error) => activo && setEstado({ data: null, error, loading: false }));
    return () => {
      activo = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...dependencias, version]);

  const recargar = useCallback(() => setVersion((v) => v + 1), []);
  return { ...estado, recargar };
}
