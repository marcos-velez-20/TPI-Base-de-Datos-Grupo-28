-- SP 1: (RN-10) Procesar un ingreso terminado e impactar en el depósito central
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_codigo_ingreso INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_documento;
    r RECORD;
BEGIN
    SELECT estado INTO v_estado
    FROM ingresos
    WHERE codigo = p_codigo_ingreso
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ingreso % no existe.', p_codigo_ingreso;
    END IF;

    IF v_estado IS DISTINCT FROM 'terminado' THEN
        RAISE EXCEPTION 'El ingreso % no está terminado (estado actual: %). (RN-10)', p_codigo_ingreso, v_estado;
    END IF;

    FOR r IN (SELECT cod_vino, cantidad FROM detalle_ingreso WHERE num_ingreso = p_codigo_ingreso) LOOP
        INSERT INTO deposito_central (codigo_vino, cantidad)
        VALUES (r.cod_vino, r.cantidad)
        ON CONFLICT (codigo_vino)
        DO UPDATE SET cantidad = deposito_central.cantidad + EXCLUDED.cantidad;
    END LOOP;

    UPDATE ingresos
    SET estado = 'procesado'
    WHERE codigo = p_codigo_ingreso;
END;
$$;

-- SP 2: (RN-11) Procesar una transferencia terminada
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_num_solicitud INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_documento;
    v_id_sala INTEGER;
    r RECORD;
    v_stock_deposito INTEGER;
BEGIN
    SELECT estado, id_sala INTO v_estado, v_id_sala
    FROM transferencias
    WHERE num_solicitud = p_num_solicitud
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La transferencia % no existe.', p_num_solicitud;
    END IF;

    IF v_estado IS DISTINCT FROM 'terminado' THEN
        RAISE EXCEPTION 'La transferencia % no está en estado terminado (RN-11).', p_num_solicitud;
    END IF;

    FOR r IN (SELECT cod_vino, cantidad FROM contenido_transferencia WHERE num_transferencia = p_num_solicitud) LOOP
        SELECT cantidad INTO v_stock_deposito
        FROM deposito_central
        WHERE codigo_vino = r.cod_vino
        FOR UPDATE;

        IF NOT FOUND OR v_stock_deposito < r.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente en depósito central para el vino % (Requerido: %, Disponible: %). (RN-11)',
                r.cod_vino, r.cantidad, COALESCE(v_stock_deposito, 0);
        END IF;

        UPDATE deposito_central
        SET cantidad = cantidad - r.cantidad
        WHERE codigo_vino = r.cod_vino;

        INSERT INTO deposito_sala (id_sala, cod_vino, cantidad)
        VALUES (v_id_sala, r.cod_vino, r.cantidad)
        ON CONFLICT (id_sala, cod_vino)
        DO UPDATE SET cantidad = deposito_sala.cantidad + EXCLUDED.cantidad;
    END LOOP;

    UPDATE transferencias
    SET estado = 'procesado'
    WHERE num_solicitud = p_num_solicitud;
END;
$$;