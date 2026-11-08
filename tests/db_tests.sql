
INSERT INTO localidades (codigo_postal, nombre, provincia) VALUES (5600, 'San Rafael', 'Mendoza');

-- Encargado, Finca y Bodega
INSERT INTO encargado_regional (nombre, codigo_postal_localidad) VALUES ('Roberto Gomez', 5600);
INSERT INTO finca (nombre, superficie, departamento, provincia) VALUES ('Finca El Sol', 50.00, 'San Rafael', 'Mendoza');
INSERT INTO bodega (cuit, razon_social, calle, num_calle) VALUES ('20304050607', 'Bodega Test', 'Ruta 143', 100);

-- Transportista y Sala de Ventas
INSERT INTO empresa_transporte (razon_social, cuit, email, telefono, calle, num_calle) 
VALUES ('Transportes Cuyo', '30506070809', 'contacto@cuyo.com', '2604112233', 'Av. Mitre', 1000);
INSERT INTO sala_de_ventas (calle, numero, dia_cierre, codigo_postal) VALUES ('Av. Balloffet', 500, 'Domingo', 5600);

-- Empleado base
INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala) 
VALUES ('20112233445', 'Carlos Lopez', '2023-01-15', 500000.00, 1);

-- Clientes (Socio y Exportador)
INSERT INTO clientes (tipoCliente, tipo_documento, num_documento, calle, numeroCalle, descuento, codigo_postal)
VALUES ('Socio', 'DNI', '38123456', 'Calle Falsa', '123', 10.00, 5600);
INSERT INTO socio_club (id, nombre, apellido) VALUES (1, 'Juan', 'Perez');

INSERT INTO clientes (tipoCliente, tipo_documento, num_documento, calle, numeroCalle, descuento, codigo_postal)
VALUES ('Exportador', 'CUIT', '30708090102', 'Parque Industrial', 'S/N', 30.00, 5600);
INSERT INTO exportadores (id, pais_destino, razonSocial) VALUES (2, 'Estados Unidos', 'Exportadora SA');

-- Cepas, Parcelas y Lote
INSERT INTO cepa (tipo, nombre) VALUES ('tinta', 'Malbec'), ('tinta', 'Cabernet Sauvignon');
INSERT INTO parcelas (id_finca, identificador, superficie, ano_plantacion, id_cepa) VALUES (1, 1, 10.00, 2010, 1);


-- ============================================================================
-- PRUEBA RN-01: Precio de vino único y positivo
-- ============================================================================
-- ÉXITO:
INSERT INTO vino (nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega)
VALUES ('Malbec Roble', 750, 8500.00, 14.00, 'tinto', 2023, '20304050607');

-- FALLA ESPERADA (Precio <= 0 viola chk_vino_precio_positivo):
-- INSERT INTO vino (nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega)
-- VALUES ('Malbec Barato', 750, -100.00, 14.00, 'tinto', 2023, '20304050607');


-- ============================================================================
-- PRUEBA RN-02: Sala pertenece a una sola localidad (FK)
-- ============================================================================
-- FALLA ESPERADA (Código postal inexistente viola FK con localidades):
-- INSERT INTO sala_de_ventas (calle, numero, dia_cierre, codigo_postal) 
-- VALUES ('Av. Mitre', 100, 'Lunes', 9999);


-- ============================================================================
-- PRUEBA RN-03: Empleado trabaja en una sola sala (NOT NULL / FK)
-- ============================================================================
-- FALLA ESPERADA (id_sala nulo viola NOT NULL):
-- INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario, id_sala) 
-- VALUES ('20998877665', 'Maria Gomez', '2024-01-01', 400000.00, NULL);


-- ============================================================================
-- PRUEBA RN-04: Parcela se cosecha máximo una vez por campaña (UNIQUE)
-- ============================================================================
-- ÉXITO (Primera cosecha):
INSERT INTO lote_uva (fecha_cosecha, campania, kilo_cosechado, bodega_entrega, id_finca, id_parcela) 
VALUES ('2024-03-15', 2024, 5000.00, '20304050607', 1, 1);

-- FALLA ESPERADA (Segunda cosecha misma campaña viola constraint UNIQUE):
-- INSERT INTO lote_uva (fecha_cosecha, campania, kilo_cosechado, bodega_entrega, id_finca, id_parcela) 
-- VALUES ('2024-03-20', 2024, 2000.00, '20304050607', 1, 1);


-- ============================================================================
-- PRUEBA RN-05: Porcentajes de corte suman 100 (Constraint Trigger Diferido)
-- ============================================================================
-- ÉXITO (Suman 100 en el commit):
BEGIN;
INSERT INTO composicion (id_cepa, id_vino, porcentaje) VALUES (1, 1, 70.00);
INSERT INTO composicion (id_cepa, id_vino, porcentaje) VALUES (2, 1, 30.00);
COMMIT;

-- FALLA ESPERADA (Suman 80%, aborta en el commit por trg_corte_suma_100):
-- BEGIN;
-- INSERT INTO composicion (id_cepa, id_vino, porcentaje) VALUES (1, 1, 50.00);
-- INSERT INTO composicion (id_cepa, id_vino, porcentaje) VALUES (2, 1, 30.00);
-- COMMIT;


-- ============================================================================
-- PRUEBA RN-06: Descuento permitido (0, 10, 20, 30, 35)
-- ============================================================================
-- FALLA ESPERADA (Descuento 15% viola chk_clientes_descuento_valido):
-- INSERT INTO clientes (tipoCliente, tipo_documento, num_documento, calle, numeroCalle, descuento, codigo_postal)
-- VALUES ('Socio', 'DNI', '99887766', 'Calle 1', '1', 15.00, 5600);


-- ============================================================================
-- PRUEBA RN-07: Vencimiento de permiso posterior a emisión (CHECK)
-- ============================================================================
-- ÉXITO:
INSERT INTO permisos (id, fecha_emision, fecha_vencimiento, id_exportador) 
VALUES ('EXP-001', '2026-01-01', '2026-12-31', 2);

-- FALLA ESPERADA (Vencimiento antes de emisión viola chk_permiso_fechas_coherentes):
-- INSERT INTO permisos (id, fecha_emision, fecha_vencimiento, id_exportador) 
-- VALUES ('EXP-002', '2026-12-31', '2026-01-01', 2);


-- ============================================================================
-- PRUEBA RN-08 y RN-09: Total calculado por trigger y validación de stock
-- ============================================================================
-- Inyectamos stock inicial en la sala
INSERT INTO stock_sala (id_sala, cod_vino, cantidad) VALUES (1, 1, 5);
-- Cabecera del comprobante
INSERT INTO comprobante (id_sala, id_cliente, subtotal, descuento, total) VALUES (1, 1, 0, 0, 0);

-- ÉXITO (Pide 2, hay 5. Materializa subtotales automáticamente):
INSERT INTO detalle_comprobante (cod_comprobante, cod_vino, cantidad, precio_unit, descuento, subtotal)
VALUES (1, 1, 2, 0, 0, 0);

-- Verificación visual de RN-08 (Comprobante totalizado):
-- SELECT * FROM comprobante WHERE numero = 1;

-- FALLA ESPERADA (Pide 10, quedan 3. trg_validar_venta_renglon lanza excepción):
-- INSERT INTO detalle_comprobante (cod_comprobante, cod_vino, cantidad, precio_unit, descuento, subtotal)
-- VALUES (1, 1, 10, 0, 0, 0);


-- ============================================================================
-- PRUEBA RN-10: Procesar ingreso (Estado y SP)
-- ============================================================================
INSERT INTO ingresos (cuit_bodega, cod_transporte, estado) VALUES ('20304050607', 1, 'en_confeccion');

-- FALLA ESPERADA (No se puede procesar si está 'en_confeccion'):
-- CALL sp_procesar_ingreso(1);

-- ÉXITO (Lo pasamos a 'terminado' y lo procesamos):
UPDATE ingresos SET estado = 'terminado' WHERE id = 1;
CALL sp_procesar_ingreso(1);


-- ============================================================================
-- PRUEBA RN-11: Procesar transferencia (Estado, Stock en Central y SP)
-- ============================================================================
INSERT INTO transferencias (id_sala, estado) VALUES (1, 'en_confeccion');
-- Simulamos que la sala pide 100 botellas del vino 1
INSERT INTO detalle_transferencia (num_transferencia, cod_vino, cantidad) VALUES (1, 1, 100);
UPDATE transferencias SET estado = 'terminado' WHERE num_solicitud = 1;

-- FALLA ESPERADA (El stock central está en 0, no alcanza para cubrir la transferencia):
-- CALL sp_procesar_transferencia(1);


-- ============================================================================
-- PRUEBA RN-12: Bloqueo de renglones si no está en confección
-- ============================================================================
-- El ingreso 1 ya fue procesado en la prueba RN-10
-- FALLA ESPERADA (Intentar agregar un renglón a un ingreso que no está en_confeccion):
-- INSERT INTO detalle_ingreso (num_ingreso, cod_vino, cantidad) VALUES (1, 1, 50);


-- ============================================================================
-- PRUEBA RN-13: Auditoría de precios (Trigger AFTER UPDATE)
-- ============================================================================
-- ÉXITO:
UPDATE vino SET precio = 9500.00 WHERE id = 1;
-- Verificación visual: 
-- SELECT * FROM auditoria_precio WHERE id_vino = 1;


-- ============================================================================
-- PRUEBA RN-14: No borrar datos con movimientos (ON DELETE RESTRICT)
-- ============================================================================
-- FALLA ESPERADA (Vino 1 tiene stock y renglones de venta. Viola FK RESTRICT):
-- DELETE FROM vino WHERE id = 1;


-- ============================================================================
-- PRUEBA RN-15: Cantidades y superficies estrictamente positivas
-- ============================================================================
-- FALLA ESPERADA (Superficie <= 0 viola chk_finca_superficie_positiva):
-- INSERT INTO finca (nombre, superficie, departamento, provincia) 
-- VALUES ('Finca Negativa', -5.00, 'San Rafael', 'Mendoza');