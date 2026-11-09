-- FN 1: Devuelve el stock disponible de un vino en una sala específica
CREATE OR REPLACE FUNCTION fn_stock_sala(p_id_sala INTEGER, p_cod_vino INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT cantidad FROM stock_sala WHERE id_sala = p_id_sala AND cod_vino = p_cod_vino),
        0
    );
$$;

-- FN 2: (RN-06) Porcentaje de descuento de un cliente.
-- Parámetros: p_id_cliente (clientes.id).
-- Devuelve clientes.descuento, que es la única fuente de verdad: su coherencia
-- con el tipo de cliente la garantiza chk_clientes_descuento_valido, y así un
-- cambio como el de la consigna U6 (exportadores al 35 %) impacta en las ventas.
-- STABLE: lee tablas, no las modifica.
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente INTEGER)
RETURNS NUMERIC(5, 2)
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT descuento FROM clientes WHERE id = p_id_cliente),
        0.00
    );
$$;

-- FN 3: (RN-08) Calcula el total acumulado de un comprobante desde sus renglones
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_numero_comprobante INTEGER)
RETURNS NUMERIC(12, 2)
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(SUM(subtotal), 0.00)
    FROM detalle_comprobante
    WHERE cod_comprobante = p_numero_comprobante;
$$;

-- FN 4: Calcula la antigüedad en años enteros transcurridos
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha DATE)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT DATE_PART('year', AGE(CURRENT_DATE, p_fecha))::INTEGER;
$$;