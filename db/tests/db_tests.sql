-- ============================================================================
-- tests/db_tests.sql — Pruebas de reglas de negocio RN-01 a RN-15
-- ----------------------------------------------------------------------------
-- Los identificadores generados se capturan con \gset (una sentencia rechazada
-- igual consume valores de la secuencia IDENTITY).
-- Ejecutar sobre una base VACÍA recién migrada (001 a 008), como postgres:
--   psql -U postgres -d bodegas_test -v ON_ERROR_STOP=1 -f tests/db_tests.sql
--
-- Cada caso que debe fallar se ejecuta con pg_temp.debe_fallar(): la sentencia
-- corre en una subtransacción, el error esperado se informa como NOTICE «OK» y
-- sus efectos se descartan. Si la sentencia NO falla, el script se detiene.
-- Los casos de éxito se comprueban con pg_temp.afirmar().
-- ============================================================================

\set ON_ERROR_STOP 1
\pset tuples_only on
SET client_min_messages = notice;

CREATE FUNCTION pg_temp.debe_fallar(p_regla TEXT, p_error_esperado TEXT, VARIADIC p_sentencias TEXT[])
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    BEGIN
        FOREACH v_sql IN ARRAY p_sentencias LOOP
            EXECUTE v_sql;
        END LOOP;
        -- Dispara en este punto los constraint triggers diferidos (RN-05).
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT ILIKE '%' || p_error_esperado || '%' THEN
            RAISE EXCEPTION 'FALLO % : falló con un error inesperado: %', p_regla, SQLERRM;
        END IF;
        SET CONSTRAINTS ALL DEFERRED;
        RAISE NOTICE 'OK   % rechazado: %', p_regla, SQLERRM;
        RETURN;
    END;
    RAISE EXCEPTION 'FALLO % : la operación debía ser rechazada y fue aceptada', p_regla;
END;
$$;

CREATE FUNCTION pg_temp.afirmar(p_regla TEXT, p_condicion BOOLEAN, p_detalle TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_condicion IS NOT TRUE THEN
        RAISE EXCEPTION 'FALLO % : %', p_regla, p_detalle;
    END IF;
    RAISE NOTICE 'OK   % %', p_regla, p_detalle;
END;
$$;

-- ============================================================================
-- Datos base
-- ============================================================================
INSERT INTO localidades (codigo_postal, nombre, provincia) VALUES (5600, 'San Rafael', 'Mendoza');
INSERT INTO encargado_regional (nombre, codigo_postal_localidad) VALUES ('Roberto Gomez', 5600);
INSERT INTO finca (nombre, superficie, departamento, provincia) VALUES ('Finca El Sol', 50.00, 'San Rafael', 'Mendoza');
INSERT INTO bodega (cuit, razon_social, calle, num_calle) VALUES ('20304050607', 'Bodega Test', 'Ruta 143', 100);
INSERT INTO empresa_transporte (razon_social, cuit, email, telefono, calle, num_calle)
VALUES ('Transportes Cuyo', '30506070809', 'contacto@cuyo.com', '2604112233', 'Av. Mitre', 1000);
INSERT INTO sala_de_ventas (calle, numero, dia_cierre, codigo_postal) VALUES ('Av. Balloffet', 500, 'Domingo', 5600);
INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala)
VALUES ('20112233445', 'Carlos Lopez', '2023-01-15', 500000.00, 1);

INSERT INTO clientes (tipoCliente, tipo_documento, num_documento, calle, numeroCalle, descuento, codigo_postal)
VALUES ('socio', 'DNI', '38123456', 'Calle Falsa', '123', 10.00, 5600);          -- id 1
INSERT INTO socio_club (id, nombre, apellido) VALUES (1, 'Juan', 'Perez');
INSERT INTO clientes (tipoCliente, tipo_documento, num_documento, calle, numeroCalle, descuento, codigo_postal)
VALUES ('exportador', 'CUIT', '30708090102', 'Parque Industrial', 'S/N', 30.00, 5600); -- id 2
INSERT INTO exportadores (id, pais_destino, razonSocial) VALUES (2, 'Estados Unidos', 'Exportadora SA');

INSERT INTO cepa (tipo, nombre) VALUES ('tinta', 'Malbec'), ('tinta', 'Cabernet Sauvignon');
INSERT INTO parcelas (id_finca, identificador, superficie, ano_plantacion, id_cepa) VALUES (1, 1, 10.00, 2010, 1);

-- Vino 1 con su corte, en la misma transacción (RN-05)
BEGIN;
INSERT INTO vino (nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega)
VALUES ('Malbec Roble', 750, 8500.00, 14.00, 'tinto', 2023, '20304050607');
INSERT INTO composicion (id_cepa, id_vino, porcentaje) VALUES (1, 1, 70.00), (2, 1, 30.00);
COMMIT;

-- ============================================================================
-- RN-01: precio único y mayor que cero
-- ============================================================================
SELECT pg_temp.debe_fallar('RN-01', 'chk_vino_precio_positivo',
    $q$UPDATE vino SET precio = -100 WHERE id = 1$q$);

-- ============================================================================
-- RN-02: sala en una localidad existente; un único encargado por localidad
-- ============================================================================
SELECT pg_temp.debe_fallar('RN-02 sala', 'foreign key',
    $q$INSERT INTO sala_de_ventas (calle, numero, dia_cierre, codigo_postal) VALUES ('Av. Mitre', 100, 'Lunes', 9999)$q$);
SELECT pg_temp.debe_fallar('RN-02 encargado', 'duplicate key',
    $q$INSERT INTO encargado_regional (nombre, codigo_postal_localidad) VALUES ('Otro', 5600)$q$);

-- ============================================================================
-- RN-03: cada empleado trabaja en una sala
-- ============================================================================
SELECT pg_temp.debe_fallar('RN-03', 'not-null',
    $q$INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala) VALUES ('20998877665', 'Maria Gomez', '2024-01-01', 400000.00, NULL)$q$);

-- ============================================================================
-- RN-04: una cosecha por parcela y campaña
-- ============================================================================
INSERT INTO lote_uva (fecha_cosecha, campania, kilo_cosechado, bodega_entrega, id_finca, id_parcela)
VALUES ('2024-03-15', 2024, 5000.00, '20304050607', 1, 1);
SELECT pg_temp.debe_fallar('RN-04', 'lote_uva_id_finca_id_parcela_campania_key',
    $q$INSERT INTO lote_uva (fecha_cosecha, campania, kilo_cosechado, bodega_entrega, id_finca, id_parcela) VALUES ('2024-03-20', 2024, 2000.00, '20304050607', 1, 1)$q$);

-- ============================================================================
-- RN-05: el corte suma 100 (constraint trigger diferido)
-- ============================================================================
SELECT pg_temp.afirmar('RN-05', (SELECT SUM(porcentaje) FROM composicion WHERE id_vino = 1) = 100,
    'el vino 1 se confirmó con 70 % + 30 %');
SELECT pg_temp.debe_fallar('RN-05 suma 80', 'deben sumar 100',
    $q$INSERT INTO vino (nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega) VALUES ('Corte 80', 750, 9000, 14, 'tinto', 2023, '20304050607')$q$,
    $q$INSERT INTO composicion (id_cepa, id_vino, porcentaje) SELECT 1, id, 50 FROM vino WHERE nombre = 'Corte 80'$q$,
    $q$INSERT INTO composicion (id_cepa, id_vino, porcentaje) SELECT 2, id, 30 FROM vino WHERE nombre = 'Corte 80'$q$);
SELECT pg_temp.debe_fallar('RN-05 sin cepas', 'deben sumar 100',
    $q$INSERT INTO vino (nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega) VALUES ('Sin corte', 750, 9000, 14, 'tinto', 2023, '20304050607')$q$);

-- ============================================================================
-- RN-06: descuento según el tipo de cliente
-- ============================================================================
SELECT pg_temp.debe_fallar('RN-06 descuento', 'chk_clientes_descuento_valido',
    $q$INSERT INTO clientes (tipoCliente, tipo_documento, num_documento, calle, numeroCalle, descuento, codigo_postal) VALUES ('socio', 'DNI', '99887766', 'Calle 1', '1', 30.00, 5600)$q$);
SELECT pg_temp.debe_fallar('RN-06 dos subtipos', 'no puede registrarse como',
    $q$INSERT INTO exportadores (id, pais_destino, razonSocial) VALUES (1, 'Chile', 'Doble SA')$q$);
SELECT pg_temp.afirmar('RN-06', fn_descuento_cliente(1) = 10 AND fn_descuento_cliente(2) = 30,
    'fn_descuento_cliente devuelve 10 % (socio) y 30 % (exportador)');

-- ============================================================================
-- RN-07: vencimiento posterior a la emisión
-- ============================================================================
INSERT INTO permisos (id, fecha_emision, fecha_vencimiento, id_exportador) VALUES ('EXP-001', '2026-01-01', '2026-12-31', 2);
SELECT pg_temp.debe_fallar('RN-07', 'chk_permiso_fechas_coherentes',
    $q$INSERT INTO permisos (id, fecha_emision, fecha_vencimiento, id_exportador) VALUES ('EXP-002', '2026-12-31', '2026-01-01', 2)$q$);

-- ============================================================================
-- RN-08 / RN-09: totales calculados por la base y stock suficiente
-- ============================================================================
INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, 1, 5);
INSERT INTO comprobante (id_sala, id_cliente) VALUES (1, 1) RETURNING numero AS comp \gset
-- precio_unit, descuento y subtotal enviados con valores falsos: los recalcula el trigger
INSERT INTO detalle_comprobante (cod_comprobante, cod_vino, cantidad, precio_unit, descuento, subtotal)
VALUES (:comp, 1, 2, 1, 0, 0);

SELECT pg_temp.afirmar('RN-08', (SELECT subtotal = 17000 AND descuento = 1700 AND total = 15300 FROM comprobante WHERE numero = :comp),
    'cabecera = 2 x 8500 con 10 % de descuento de socio');
SELECT pg_temp.afirmar('RN-09', fn_stock_sala(1, 1) = 3, 'stock de la sala bajó de 5 a 3');

SELECT pg_temp.debe_fallar('RN-08 total a mano', 'no se cargan a mano',
    format('UPDATE comprobante SET total = 1 WHERE numero = %s', :comp));
SELECT pg_temp.debe_fallar('RN-09 venta sin stock', 'Stock insuficiente',
    $q$INSERT INTO comprobante (id_sala, id_cliente) VALUES (1, 1)$q$,
    $q$INSERT INTO detalle_comprobante (cod_comprobante, cod_vino, cantidad, precio_unit, descuento, subtotal) SELECT max(numero), 1, 10, 1, 0, 0 FROM comprobante$q$);
SELECT pg_temp.debe_fallar('RN-09 update sin stock', 'Stock insuficiente',
    format('UPDATE detalle_comprobante SET cantidad = 20 WHERE cod_comprobante = %s AND cod_vino = 1', :comp));

UPDATE detalle_comprobante SET cantidad = 3 WHERE cod_comprobante = :comp AND cod_vino = 1;
SELECT pg_temp.afirmar('RN-08/09 update', (SELECT total = 22950 FROM comprobante WHERE numero = :comp) AND fn_stock_sala(1, 1) = 2,
    'al pasar el renglón de 2 a 3 botellas se recalcula el total y baja el stock');

-- ============================================================================
-- RN-10: ingresos (estados y procedimiento)
-- ============================================================================
SELECT pg_temp.debe_fallar('RN-10 alta procesado', 'debe crearse en estado en_confeccion',
    $q$INSERT INTO ingresos (cuit_bodega, cod_transporte, estado) VALUES ('20304050607', 1, 'procesado')$q$);

INSERT INTO ingresos (cuit_bodega, cod_transporte) VALUES ('20304050607', 1) RETURNING id AS ing \gset
INSERT INTO detalle_ingreso (num_ingreso, cod_vino, cantidad) VALUES (:ing, 1, 200);

SELECT pg_temp.debe_fallar('RN-10 procesar en confeccion', 'no está terminado',
    format('CALL sp_procesar_ingreso(%s)', :ing));
UPDATE ingresos SET estado = 'terminado' WHERE id = :ing;
SELECT pg_temp.debe_fallar('RN-10 UPDATE directo', 'Solo el procedimiento',
    format('UPDATE ingresos SET estado = %L WHERE id = %s', 'procesado', :ing));

CALL sp_procesar_ingreso(:ing);
SELECT pg_temp.afirmar('RN-10', (SELECT estado = 'procesado' FROM ingresos WHERE id = :ing)
                                AND (SELECT cantidad = 200 FROM stock_central WHERE codigo_vino = 1),
    'el ingreso quedó procesado y sumó 200 botellas al depósito');
SELECT pg_temp.debe_fallar('RN-10 retroceso', 'Transición de estado inválida',
    format('UPDATE ingresos SET estado = %L WHERE id = %s', 'en_confeccion', :ing));

-- ============================================================================
-- RN-11: transferencias (fecha, estados, stock del depósito)
-- ============================================================================
INSERT INTO transferencias (id_sala, fecha_confeccion) VALUES (1, '2020-01-01') RETURNING num_solicitud AS tr1 \gset
SELECT pg_temp.afirmar('RN-11 fecha', (SELECT fecha_confeccion = CURRENT_DATE FROM transferencias WHERE num_solicitud = :tr1),
    'la fecha enviada (2020-01-01) se reemplaza por la actual');
SELECT pg_temp.debe_fallar('RN-11 modificar fecha', 'no puede modificarse',
    format('UPDATE transferencias SET fecha_confeccion = %L WHERE num_solicitud = %s', '2000-01-01', :tr1));

-- Éxito: 50 de las 200 botellas del depósito
INSERT INTO detalle_transferencia (num_transferencia, cod_vino, cantidad) VALUES (:tr1, 1, 50);
UPDATE transferencias SET estado = 'terminado' WHERE num_solicitud = :tr1;
CALL sp_procesar_transferencia(:tr1);
SELECT pg_temp.afirmar('RN-11', (SELECT cantidad = 150 FROM stock_central WHERE codigo_vino = 1) AND fn_stock_sala(1, 1) = 52,
    'depósito 200 -> 150 y sala 2 -> 52');

-- Falla: pide más de lo que hay y no deja cambios a medias
INSERT INTO transferencias (id_sala) VALUES (1) RETURNING num_solicitud AS tr2 \gset
INSERT INTO detalle_transferencia (num_transferencia, cod_vino, cantidad) VALUES (:tr2, 1, 1000);
UPDATE transferencias SET estado = 'terminado' WHERE num_solicitud = :tr2;
SELECT pg_temp.debe_fallar('RN-11 sin stock', 'Stock insuficiente en depósito central',
    format('CALL sp_procesar_transferencia(%s)', :tr2));
SELECT pg_temp.afirmar('RN-11 atomicidad', (SELECT estado = 'terminado' FROM transferencias WHERE num_solicitud = :tr2)
                                          AND (SELECT cantidad = 150 FROM stock_central WHERE codigo_vino = 1),
    'tras el error no cambió ni el estado ni el stock');

-- ============================================================================
-- RN-12: renglones bloqueados fuera de confección
-- ============================================================================
SELECT pg_temp.debe_fallar('RN-12 ingreso', 'no está en confección',
    format('UPDATE detalle_ingreso SET cantidad = 1 WHERE num_ingreso = %s', :ing));
SELECT pg_temp.debe_fallar('RN-12 transferencia', 'no está en confección',
    format('DELETE FROM detalle_transferencia WHERE num_transferencia = %s', :tr1));

-- El borrado completo de un documento (cascada a sus renglones) sí se permite (consigna D5)
INSERT INTO ingresos (cuit_bodega, cod_transporte) VALUES ('20304050607', 1) RETURNING id AS ing2 \gset
INSERT INTO detalle_ingreso (num_ingreso, cod_vino, cantidad) VALUES (:ing2, 1, 10);
DELETE FROM ingresos WHERE id = :ing2;
SELECT pg_temp.afirmar('RN-12 cascada', NOT EXISTS (SELECT 1 FROM detalle_ingreso WHERE num_ingreso = :ing2),
    'borrar la cabecera borra sus renglones');

-- ============================================================================
-- RN-13: auditoría de precios
-- ============================================================================
UPDATE vino SET precio = 9500.00 WHERE id = 1;
SELECT pg_temp.afirmar('RN-13', EXISTS (SELECT 1 FROM auditoria_precio
                                        WHERE id_vino = 1 AND precio_anterior = 8500 AND precio_nuevo = 9500),
    'el cambio de 8500 a 9500 quedó auditado');

-- ============================================================================
-- RN-14: no se borran datos con movimientos
-- ============================================================================
SELECT pg_temp.debe_fallar('RN-14 vino', 'foreign key', $q$DELETE FROM vino WHERE id = 1$q$);
SELECT pg_temp.debe_fallar('RN-14 bodega', 'foreign key', $q$DELETE FROM bodega WHERE cuit = '20304050607'$q$);
SELECT pg_temp.debe_fallar('RN-14 transportista', 'foreign key', $q$DELETE FROM empresa_transporte WHERE cod_transporte = 1$q$);

-- ============================================================================
-- RN-15: valores positivos y graduación entre 5 y 20
-- ============================================================================
SELECT pg_temp.debe_fallar('RN-15 superficie', 'chk_finca_superficie_positiva',
    $q$INSERT INTO finca (nombre, superficie, departamento, provincia) VALUES ('Finca Negativa', -5.00, 'San Rafael', 'Mendoza')$q$);
SELECT pg_temp.debe_fallar('RN-15 graduacion', 'chk_vino_graduacion_rango',
    $q$UPDATE vino SET graduacion = 25 WHERE id = 1$q$);
SELECT pg_temp.debe_fallar('RN-15 kilos', 'chk_lote_kilos_positivos',
    $q$UPDATE lote_uva SET kilo_cosechado = 0$q$);

\echo '>>> Todas las pruebas pasaron.'