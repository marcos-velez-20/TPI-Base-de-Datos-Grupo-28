-- TRG 1: Validación de stock y cálculo del renglón de venta (BEFORE INSERT/UPDATE) (RN-06, RN-08, RN-09)
-- * INSERT: valida stock (bloqueando la fila con FOR UPDATE) y congela el precio vigente.
-- * UPDATE: el comprobante y el vino del renglón no pueden cambiar; se conserva el
--   precio congelado y, si aumenta la cantidad, se valida solo la diferencia.
-- * En ambos casos descuento y subtotal se calculan aquí: nunca se cargan a mano.
CREATE OR REPLACE FUNCTION trg_validar_venta_renglon()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_sala INTEGER;
    v_id_cliente INTEGER;
    v_stock_disp INTEGER;
    v_requerido INTEGER;
    v_desc_pct NUMERIC(5, 2);
BEGIN
    IF TG_OP = 'UPDATE' AND (NEW.cod_comprobante <> OLD.cod_comprobante OR NEW.cod_vino <> OLD.cod_vino) THEN
        RAISE EXCEPTION 'No se puede cambiar el comprobante ni el vino de un renglón; bórrelo y cree uno nuevo (RN-08).';
    END IF;

    SELECT id_sala, id_cliente INTO v_id_sala, v_id_cliente
    FROM comprobante
    WHERE numero = NEW.cod_comprobante;

    v_requerido := CASE WHEN TG_OP = 'INSERT' THEN NEW.cantidad
                        ELSE NEW.cantidad - OLD.cantidad END;

    IF v_requerido > 0 THEN
        SELECT cantidad INTO v_stock_disp
        FROM stock_sala
        WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino
        FOR UPDATE;

        IF COALESCE(v_stock_disp, 0) < v_requerido THEN
            RAISE EXCEPTION 'Stock insuficiente del vino % en la sala % (RN-09). Disponible: %, Solicitado: %',
                NEW.cod_vino, v_id_sala, COALESCE(v_stock_disp, 0), v_requerido;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT precio INTO NEW.precio_unit FROM vino WHERE id = NEW.cod_vino;
    ELSE
        NEW.precio_unit := OLD.precio_unit;  -- precio congelado al momento de la venta
    END IF;

    v_desc_pct := fn_descuento_cliente(v_id_cliente);
    NEW.descuento := ROUND((NEW.precio_unit * NEW.cantidad) * (v_desc_pct / 100.00), 2);
    NEW.subtotal := ROUND((NEW.precio_unit * NEW.cantidad) - NEW.descuento, 2);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_valida_stock_before
BEFORE INSERT OR UPDATE ON detalle_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_validar_venta_renglon();

-- TRG 2: Descuento de stock en sala y recálculo de cabecera (AFTER INSERT/UPDATE/DELETE) (RN-08, RN-09)
-- * INSERT descuenta la cantidad vendida; UPDATE descuenta (o devuelve) la diferencia.
-- * DELETE no devuelve stock: borrar comprobantes históricos (consigna D1) no debe
--   reponer botellas que ya salieron de la sala.
-- * El total de la cabecera se obtiene con fn_total_comprobante.
CREATE OR REPLACE FUNCTION trg_actualizar_stock_y_totales_venta()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_nro_comp INTEGER;
    v_id_sala INTEGER;
    v_delta INTEGER;
    v_subtotal NUMERIC(12, 2);
    v_descuento NUMERIC(12, 2);
BEGIN
    v_nro_comp := CASE WHEN TG_OP = 'DELETE' THEN OLD.cod_comprobante ELSE NEW.cod_comprobante END;

    IF TG_OP <> 'DELETE' THEN
        v_delta := CASE WHEN TG_OP = 'INSERT' THEN NEW.cantidad
                        ELSE NEW.cantidad - OLD.cantidad END;
        IF v_delta <> 0 THEN
            SELECT id_sala INTO v_id_sala FROM comprobante WHERE numero = v_nro_comp;
            UPDATE stock_sala
            SET cantidad = cantidad - v_delta
            WHERE id_sala = v_id_sala AND cod_vino = NEW.cod_vino;
        END IF;
    END IF;

    SELECT
        COALESCE(SUM(precio_unit * cantidad), 0.00),
        COALESCE(SUM(descuento), 0.00)
    INTO v_subtotal, v_descuento
    FROM detalle_comprobante
    WHERE cod_comprobante = v_nro_comp;

    UPDATE comprobante
    SET subtotal = v_subtotal,
        descuento = v_descuento,
        total = fn_total_comprobante(v_nro_comp)
    WHERE numero = v_nro_comp;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_venta_actualiza_stock_after
AFTER INSERT OR UPDATE OR DELETE ON detalle_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_actualizar_stock_y_totales_venta();

-- TRG 2b: Protección de importes de la cabecera (BEFORE UPDATE en comprobante) (RN-08)
-- subtotal, descuento y total solo pueden cambiar desde TRG 2 (trigger anidado,
-- pg_trigger_depth() > 1). Un UPDATE directo sobre esas columnas se rechaza.
CREATE OR REPLACE FUNCTION trg_proteger_totales_comprobante()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF pg_trigger_depth() < 2
       AND (NEW.subtotal, NEW.descuento, NEW.total)
           IS DISTINCT FROM (OLD.subtotal, OLD.descuento, OLD.total) THEN
        RAISE EXCEPTION 'Los importes del comprobante % se calculan desde sus renglones y no se cargan a mano (RN-08).',
            OLD.numero;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_comprobante_totales_before
BEFORE UPDATE ON comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_proteger_totales_comprobante();

-- TRG 3: Control de flujo de estados (BEFORE INSERT/UPDATE) (RN-10, RN-11)
-- * Todo documento nace en 'en_confeccion'.
-- * Solo se permite en_confeccion -> terminado -> procesado, sin retrocesos.
-- * El paso a 'procesado' solo lo puede hacer sp_procesar_ingreso o
--   sp_procesar_transferencia, que activan la marca local de transacción
--   'bodegas.via_procedimiento'. Así un UPDATE directo no puede marcar como
--   procesado un documento que nunca impactó en el stock.
CREATE OR REPLACE FUNCTION trg_control_transicion_estados()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.estado IS DISTINCT FROM 'en_confeccion' THEN
            RAISE EXCEPTION 'Un documento nuevo debe crearse en estado en_confeccion, no % (RN-10, RN-11).', NEW.estado;
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.estado = NEW.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado' THEN
        RETURN NEW;
    ELSIF OLD.estado = 'terminado' AND NEW.estado = 'procesado' THEN
        IF COALESCE(current_setting('bodegas.via_procedimiento', true), 'off') <> 'on' THEN
            RAISE EXCEPTION 'Solo el procedimiento de procesamiento puede pasar el documento a procesado (RN-10, RN-11).';
        END IF;
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Transición de estado inválida de % a % (RN-10, RN-11).', OLD.estado, NEW.estado;
    END IF;
END;
$$;

CREATE TRIGGER trg_ingresos_estados_before
BEFORE INSERT OR UPDATE OF estado ON ingresos
FOR EACH ROW
EXECUTE FUNCTION trg_control_transicion_estados();

CREATE TRIGGER trg_transferencias_estados_before
BEFORE INSERT OR UPDATE OF estado ON transferencias
FOR EACH ROW
EXECUTE FUNCTION trg_control_transicion_estados();

-- TRG 4: Bloqueo de renglones si no está en confección (BEFORE INSERT/UPDATE/DELETE) (RN-12)
-- Si la cabecera ya no existe, el DELETE viene de un ON DELETE CASCADE
-- (se está borrando el documento completo) y se permite.
-- En un UPDATE se controlan el documento de origen y el de destino.
CREATE OR REPLACE FUNCTION trg_bloquear_renglones_documento()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado estado_documento;
    v_doc_id INTEGER;
    v_docs   INTEGER[];
BEGIN
    IF TG_TABLE_NAME = 'detalle_ingreso' THEN
        v_docs := CASE TG_OP
                    WHEN 'INSERT' THEN ARRAY[NEW.num_ingreso]
                    WHEN 'DELETE' THEN ARRAY[OLD.num_ingreso]
                    ELSE ARRAY[OLD.num_ingreso, NEW.num_ingreso] END;
    ELSE
        v_docs := CASE TG_OP
                    WHEN 'INSERT' THEN ARRAY[NEW.num_transferencia]
                    WHEN 'DELETE' THEN ARRAY[OLD.num_transferencia]
                    ELSE ARRAY[OLD.num_transferencia, NEW.num_transferencia] END;
    END IF;

    FOREACH v_doc_id IN ARRAY v_docs LOOP
        IF TG_TABLE_NAME = 'detalle_ingreso' THEN
            SELECT estado INTO v_estado FROM ingresos WHERE id = v_doc_id;
        ELSE
            SELECT estado INTO v_estado FROM transferencias WHERE num_solicitud = v_doc_id;
        END IF;

        -- Cabecera inexistente en un DELETE: borrado en cascada del documento.
        IF NOT FOUND AND TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;

        IF v_estado IS DISTINCT FROM 'en_confeccion' THEN
            RAISE EXCEPTION 'El documento % no está en confección (RN-12).', v_doc_id;
        END IF;
    END LOOP;

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
BEFORE INSERT OR UPDATE OR DELETE ON detalle_transferencia
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
            NEW.id
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
    IF TG_TABLE_NAME = 'vino' THEN
        v_vino_id := NEW.id;   -- alta de vino: debe tener composición al confirmar
    ELSE
        v_vino_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_vino ELSE NEW.id_vino END;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM vino WHERE id = v_vino_id) THEN
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

-- Un vino nuevo sin ninguna fila en composicion también se rechaza al COMMIT:
-- el vino y su corte se deben dar de alta en la misma transacción.
CREATE CONSTRAINT TRIGGER trg_vino_requiere_corte
AFTER INSERT ON vino
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION trg_validar_porcentaje_corte();


-- TRG 7: Fecha de confección de transferencia (BEFORE INSERT/UPDATE) (RN-11)
-- Al insertar se fuerza la fecha actual, sin importar lo que envíe el cliente.
-- Una vez creada, la fecha de confección no puede modificarse.
-- No se usa un CHECK porque CURRENT_DATE no es determinístico.
CREATE OR REPLACE FUNCTION trg_fecha_confeccion_transferencia()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
    ELSIF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
        RAISE EXCEPTION 'La fecha de confección de la transferencia % no puede modificarse (RN-11).',
            OLD.num_solicitud;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_transferencias_fecha_before
BEFORE INSERT OR UPDATE OF fecha_confeccion ON transferencias
FOR EACH ROW
EXECUTE FUNCTION trg_fecha_confeccion_transferencia();

-- TRG 8: Jerarquía de clientes exclusiva (BEFORE INSERT/UPDATE) (RN-06)
-- Un id solo puede estar en la tabla del subtipo que indica clientes.tipoCliente,
-- de modo que un cliente no puede pertenecer a dos subtipos a la vez.
-- Además, no se puede cambiar tipoCliente si el cliente ya tiene fila de subtipo.
CREATE OR REPLACE FUNCTION trg_validar_subtipo_cliente()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_tipo     TEXT;
    v_esperado TEXT;
BEGIN
    v_esperado := CASE TG_TABLE_NAME
                    WHEN 'socio_club'     THEN 'socio'
                    WHEN 'distribuidores' THEN 'distribuidor'
                    WHEN 'exportadores'   THEN 'exportador' END;

    SELECT lower(tipoCliente) INTO v_tipo FROM clientes WHERE id = NEW.id;

    IF v_tipo IS DISTINCT FROM v_esperado THEN
        RAISE EXCEPTION 'El cliente % es de tipo % y no puede registrarse como % (RN-06).',
            NEW.id, COALESCE(v_tipo, 'inexistente'), v_esperado;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_socio_subtipo_before
BEFORE INSERT OR UPDATE OF id ON socio_club
FOR EACH ROW EXECUTE FUNCTION trg_validar_subtipo_cliente();

CREATE TRIGGER trg_distribuidor_subtipo_before
BEFORE INSERT OR UPDATE OF id ON distribuidores
FOR EACH ROW EXECUTE FUNCTION trg_validar_subtipo_cliente();

CREATE TRIGGER trg_exportador_subtipo_before
BEFORE INSERT OR UPDATE OF id ON exportadores
FOR EACH ROW EXECUTE FUNCTION trg_validar_subtipo_cliente();

CREATE OR REPLACE FUNCTION trg_bloquear_cambio_tipo_cliente()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF lower(NEW.tipoCliente) IS DISTINCT FROM lower(OLD.tipoCliente)
       AND (EXISTS (SELECT 1 FROM socio_club     WHERE id = OLD.id)
         OR EXISTS (SELECT 1 FROM distribuidores WHERE id = OLD.id)
         OR EXISTS (SELECT 1 FROM exportadores   WHERE id = OLD.id)) THEN
        RAISE EXCEPTION 'No se puede cambiar el tipo del cliente % porque ya tiene datos de subtipo (RN-06).', OLD.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_clientes_tipo_before
BEFORE UPDATE OF tipoCliente ON clientes
FOR EACH ROW EXECUTE FUNCTION trg_bloquear_cambio_tipo_cliente();