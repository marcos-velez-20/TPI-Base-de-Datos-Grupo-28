-- Preparación de datos base mínimos para pruebas
INSERT INTO localidades (codigo_postal, nombre, provincia) VALUES (5600, 'San Rafael', 'Mendoza');
INSERT INTO bodega (cuit, nombre, calle, num_calle) VALUES ('20304050607', 'Bodega Test', 'Ruta 143', 100);
INSERT INTO sala_de_ventas (calle, numero, dia_cierre, codigo_postal) VALUES ('Av. Balloffet', 500, 'Domingo', 5600);
INSERT INTO clientes (nombre, apellido, tipo_documento, num_documento, direccion, descuento, codigo_postal)
VALUES ('Juan', 'Perez', 'DNI', '38123456', 'Calle Falsa 123', 10.00, 5600);
INSERT INTO socio_club (id) VALUES (1);

-- ----------------------------------------------------------------------------
-- PRUEBA RN-01: Precio de vino positivo y mayor a cero
-- ----------------------------------------------------------------------------
-- Debe funcionar:
INSERT INTO vino (nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega)
VALUES ('Malbec Roble', 750, 8500.00, 14.00, 'tinto', 2023, '20304050607');

-- Debe fallar (precio <= 0 viola chk_vino_precio_positivo):
-- INSERT INTO vino (nombre, volumen, precio, graduacion, tipo, anada, cuit_bodega)
-- VALUES ('Malbec Barato', 750, -100.00, 14.00, 'tinto', 2023, '20304050607');

-- ----------------------------------------------------------------------------
-- PRUEBA RN-05: Corte de uva suma exactamente 100% (Constraint Trigger diferido)
-- ----------------------------------------------------------------------------
INSERT INTO cepa (tipo, nombre) VALUES ('tinta', 'Malbec'), ('tinta', 'Cabernet Sauvignon');

-- Debe funcionar (ambos suman 100 al hacer commit):
BEGIN;
INSERT INTO elaboracion_vino (id_cepa, id_vino, porcentaje) VALUES (1, 1, 70.00);
INSERT INTO elaboracion_vino (id_cepa, id_vino, porcentaje) VALUES (2, 1, 30.00);
COMMIT;

-- Debe fallar (suma 80% y revierte en COMMIT por trg_corte_suma_100):
-- BEGIN;
-- INSERT INTO elaboracion_vino (id_cepa, id_vino, porcentaje) VALUES (1, 1, 50.00);
-- INSERT INTO elaboracion_vino (id_cepa, id_vino, porcentaje) VALUES (2, 1, 30.00);
-- COMMIT;

-- ----------------------------------------------------------------------------
-- PRUEBA RN-07: Permisos con fecha_vencimiento > fecha_emision
-- ----------------------------------------------------------------------------
INSERT INTO clientes (nombre, tipo_documento, num_documento, direccion, descuento, codigo_postal)
VALUES ('Exportadora SA', 'CUIT', '30708090102', 'Parque Industrial', 30.00, 5600);
INSERT INTO exportadores (id, pais_destino) VALUES (2, 'Estados Unidos');

-- Debe fallar (vencimiento antes de emision viola chk_permiso_fechas_coherentes):
-- INSERT INTO permisos (codigo, fecha_emision, fecha_vencimiento, id_exportador)
-- VALUES ('EXP-999', '2026-05-10', '2026-05-01', 2);

-- ----------------------------------------------------------------------------
-- PRUEBA RN-09: Validación de stock en venta
-- ----------------------------------------------------------------------------
INSERT INTO deposito_sala (id_sala, cod_vino, cantidad) VALUES (1, 1, 5);
INSERT INTO comprobante (id_sala, id_cliente, subtotal, descuento, total) VALUES (1, 1, 0, 0, 0);

-- Debe funcionar (hay 5, pide 2):
INSERT INTO detalle_comprobante (cod_comprobante, cod_vino, cantidad, precio_unit, descuento, subtotal)
VALUES (1, 1, 2, 0, 0, 0);

-- Debe fallar (quedan 3, pide 10; trg_renglon_valida_stock_before lanza excepción):
-- INSERT INTO detalle_comprobante (cod_comprobante, cod_vino, cantidad, precio_unit, descuento, subtotal)
-- VALUES (1, 1, 10, 0, 0, 0);

-- ----------------------------------------------------------------------------
-- PRUEBA RN-13: Auditoría de precios
-- ----------------------------------------------------------------------------
UPDATE vino SET precio = 9500.00 WHERE codigo = 1;
-- Verificación:
SELECT * FROM auditoria_precio WHERE id_vino = 1;