-- 1) COMPUESTO — Q2/S3: ventas de una sala en un rango de fechas.
--    Igualdad primero (id_sala), rango después (fecha).
CREATE INDEX idx_comprobante_sala_fecha
    ON comprobante (id_sala, fecha);
 
-- 2) VARIANTE INCLUDE (covering) — Q3/S8: ventas por sala en un rango de fechas.
CREATE INDEX idx_comprobante_fecha_cubriente
    ON comprobante (fecha) INCLUDE (id_sala, total);
 
-- 3) CLAVE FORÁNEA — Q4/Q5, D4, D6: comprobantes por cliente.
CREATE INDEX idx_comprobante_cliente
    ON comprobante (id_cliente);
 
-- 4) CLAVE FORÁNEA + INCLUDE — Q1/S1, S2, S11: renglones por vino.
CREATE INDEX idx_detalle_comprobante_vino
    ON detalle_comprobante (cod_vino) INCLUDE (cantidad);
 
-- 5) PARCIAL — Q7/S5: solo transferencias no procesadas.
CREATE INDEX idx_transferencias_pendientes
    ON transferencias (id_sala, fecha_confeccion)
    WHERE estado <> 'procesado';
 
-- 6) EXPRESIÓN — Q6: búsqueda por apellido sin distinguir mayúsculas.
CREATE INDEX idx_socio_apellido_lower
    ON socio_club (lower(apellido) text_pattern_ops);