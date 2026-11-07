-- TRG 1: Validación y cálculo de precios en renglón de venta (BEFORE INSERT) (RN-06, RN-08, RN-09)
CREATE OR REPLACE FUNCTION trg_validar_venta_renglon()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_sala INTEGER;
    v_id_cliente INTEGER;
    v_precio_actual NUMERIC(10, 2);
    v_stock_disp INTEGER;
    v_desc_pct NUMERIC(5, 2);
BEGIN
    SELECT id_sala, id_cliente INTO v_id_sala, v_id_cliente
    FROM comprobante
    WHERE numero = NEW.cod_comprobante;

    SELECT cantidad INTO v_stock_disp
    FROM stock_sala
    WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino
    FOR UPDATE;

    IF COALESCE(v_stock_disp, 0) < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente del vino % en la sala % (RN-09). Disponible: %, Solicitado: %',
            NEW.cod_vino, v_id_sala, COALESCE(v_stock_disp, 0), NEW.cantidad;
    END IF;

    SELECT precio INTO v_precio_actual FROM vino WHERE codigo = NEW.cod_vino;
    NEW.precio_unit := v_precio_actual;

    v_desc_pct := fn_descuento_cliente(v_id_cliente);
    NEW.descuento := ROUND((v_precio_actual * NEW.cantidad) * (v_desc_pct / 100.00), 2);
    NEW.subtotal := ROUND((v_precio_actual * NEW.cantidad) - NEW.descuento, 2);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_valida_stock_before
BEFORE INSERT ON detalle_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_validar_venta_renglon();

-- TRG 2: Descuento de stock en sala y recálculo de cabecera (AFTER INSERT/DELETE) (RN-08, RN-09)
CREATE OR REPLACE FUNCTION trg_actualizar_stock_y_totales_venta()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_nro_comp INTEGER;
    v_id_sala INTEGER;
    v_subtotal NUMERIC(12, 2);
    v_descuento NUMERIC(12, 2);
    v_total NUMERIC(12, 2);
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_nro_comp := NEW.cod_comprobante;
        SELECT id_sala INTO v_id_sala FROM comprobante WHERE numero = v_nro_comp;

        UPDATE stock_sala
        SET cantidad = cantidad - NEW.cantidad
        WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino;
    ELSE
        v_nro_comp := OLD.cod_comprobante;
    END IF;

    SELECT 
        COALESCE(SUM(precio_unit * cantidad), 0.00),
        COALESCE(SUM(descuento), 0.00),
        COALESCE(SUM(subtotal), 0.00)
    INTO v_subtotal, v_descuento, v_total
    FROM detalle_comprobante
    WHERE cod_comprobante = v_nro_comp;

    UPDATE comprobante
    SET subtotal = v_subtotal,
        descuento = v_descuento,
        total = v_total
    WHERE numero = v_nro_comp;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_venta_actualiza_stock_after
AFTER INSERT OR DELETE ON detalle_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_actualizar_stock_y_totales_venta();

-- TRG 3: Control de flujo de estados (BEFORE UPDATE) (RN-10, RN-11)
CREATE OR REPLACE FUNCTION trg_control_transicion_estados()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.estado = NEW.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado' THEN
        RETURN NEW;
    ELSIF OLD.estado = 'terminado' AND NEW.estado = 'procesado' THEN
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Transición de estado inválida de % a % (RN-10, RN-11).', OLD.estado, NEW.estado;
    END IF;
END;
$$;

CREATE TRIGGER trg_ingresos_estados_before
BEFORE UPDATE OF estado ON ingresos
FOR EACH ROW
EXECUTE FUNCTION trg_control_transicion_estados();

CREATE TRIGGER trg_transferencias_estados_before
BEFORE UPDATE OF estado ON transferencias
FOR EACH ROW
EXECUTE FUNCTION trg_control_transicion_estados();

-- TRG 4: Bloqueo de renglones si no está en confección (BEFORE INSERT/UPDATE/DELETE) (RN-12)
CREATE OR REPLACE FUNCTION trg_bloquear_renglones_documento()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_documento;
    v_doc_id INTEGER;
BEGIN
    IF TG_TABLE_NAME = 'detalle_ingreso' THEN
        v_doc_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.num_ingreso ELSE NEW.num_ingreso END;
        SELECT estado INTO v_estado FROM ingresos WHERE codigo = v_doc_id;
    ELSE
        v_doc_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.num_transferencia ELSE NEW.num_transferencia END;
        SELECT estado INTO v_estado FROM transferencias WHERE num_solicitud = v_doc_id;
    END IF;

    IF v_estado IS DISTINCT FROM 'en_confeccion' THEN
        RAISE EXCEPTION 'El documento % no está en confección (RN-12).', v_doc_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bloqueo_renglon_ingreso
BEFORE INSERT OR UPDATE OR DELETE ON detalle_ingreso
FOR EACH ROW
EXECUTE FUNCTION trg_bloquear_renglones_documento();

CREATE TRIGGER trg_bloqueo_renglon_transferencia
BEFORE INSERT OR UPDATE OR DELETE ON contenido_transferencia
FOR EACH ROW
EXECUTE FUNCTION trg_bloquear_renglones_documento();

-- TRG 5: Auditoría de cambios de precio (AFTER UPDATE) (RN-13)
CREATE OR REPLACE FUNCTION trg_auditar_precio_vino()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.precio IS DISTINCT FROM NEW.precio THEN
        INSERT INTO auditoria_precio (
            precio_anterior,
            precio_nuevo,
            fecha,
            hora,
            usuario,
            id_vino
        )
        VALUES (
            OLD.precio,
            NEW.precio,
            CURRENT_DATE,
            CURRENT_TIME,
            CURRENT_USER,
            NEW.codigo
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_vino_auditoria_precio_after
AFTER UPDATE OF precio ON vino
FOR EACH ROW
EXECUTE FUNCTION trg_auditar_precio_vino();

-- TRG 6: Validación de corte al 100% (CONSTRAINT TRIGGER DIFERIDO) (RN-05)
CREATE OR REPLACE FUNCTION trg_validar_porcentaje_corte()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_vino_id INTEGER;
    v_suma NUMERIC(5, 2);
BEGIN
    v_vino_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_vino ELSE NEW.id_vino END;

    IF NOT EXISTS (SELECT 1 FROM vino WHERE codigo = v_vino_id) THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(porcentaje), 0.00) INTO v_suma
    FROM composicion
    WHERE id_vino = v_vino_id;

    IF v_suma <> 100.00 THEN
        RAISE EXCEPTION 'Los porcentajes de corte del vino % suman % y deben sumar 100 (RN-05).',
            v_vino_id, v_suma;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_corte_suma_100
AFTER INSERT OR UPDATE OR DELETE ON composicion
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_porcentaje_corte();