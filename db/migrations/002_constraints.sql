-- UQ 1: (RN-01) No repetir vino por nombre, añada y volumen
ALTER TABLE vino
    ADD CONSTRAINT uq_vino_nombre_anada_volumen 
    UNIQUE (nombre, anada, volumen);

-- UQ 2: No repetir una localidad dentro de la misma provincia
ALTER TABLE localidades
    ADD CONSTRAINT uq_localidad_provincia 
    UNIQUE (nombre, provincia);

-- UQ 3: Razón social única en transportistas
ALTER TABLE empresa_transporte
    ADD CONSTRAINT uq_transporte_razon_social 
    UNIQUE (razon_social);

-- RN-04 (una cepa por parcela) ya lo garantiza la columna parcelas.id_cepa
-- y (una cosecha por campaña) el UNIQUE (id_finca, id_parcela, campania) de lote_uva.

-- CHK 1: (RN-01, RN-15) Precio de venta positivo
ALTER TABLE vino
    ADD CONSTRAINT chk_vino_precio_positivo 
    CHECK (precio > 0);

-- CHK 2: (RN-15) Graduación alcohólica entre 5° y 20°
ALTER TABLE vino
    ADD CONSTRAINT chk_vino_graduacion_rango 
    CHECK (graduacion BETWEEN 5.00 AND 20.00);

-- CHK 3: (RN-15) Tipos de vino válidos
ALTER TABLE vino
    ADD CONSTRAINT chk_vino_tipo_valido 
    CHECK (tipo IN ('tinto', 'blanco', 'rosado', 'espumante'));

-- CHK 4: (RN-15) Kilos de uva cosechados positivos
ALTER TABLE lote_uva
    ADD CONSTRAINT chk_lote_kilos_positivos 
    CHECK (kilo_cosechado > 0);

-- CHK 5: (RN-15) Superficies estrictamente positivas
ALTER TABLE finca
    ADD CONSTRAINT chk_finca_superficie_positiva 
    CHECK (superficie > 0);

ALTER TABLE parcelas
    ADD CONSTRAINT chk_parcela_superficie_positiva 
    CHECK (superficie > 0);

-- CHK 6: (RN-09, RN-15) Stock nunca negativo
ALTER TABLE stock_sala
    ADD CONSTRAINT chk_stock_sala_no_negativo 
    CHECK (cantidad >= 0);

ALTER TABLE stock_central
    ADD CONSTRAINT chk_stock_deposito_no_negativo 
    CHECK (cantidad >= 0);

-- CHK 7: (RN-07) [ENTRE COLUMNAS] Vencimiento posterior a emisión
ALTER TABLE permisos
    ADD CONSTRAINT chk_permiso_fechas_coherentes 
    CHECK (fecha_vencimiento > fecha_emision);

-- CHK 8: (RN-06) Tipo de cliente válido y descuento coherente con el tipo.
-- socio 10 %, distribuidor 20 %, exportador 30 % (35 % habilitado por la consigna U6).
-- Se compara en minúsculas para aceptar 'Socio' o 'socio'.
ALTER TABLE clientes
    ADD CONSTRAINT chk_clientes_tipo_valido
    CHECK (lower(tipoCliente) IN ('socio', 'distribuidor', 'exportador'));

ALTER TABLE clientes
    ADD CONSTRAINT chk_clientes_descuento_valido
    CHECK (
        (lower(tipoCliente) = 'socio'        AND descuento = 10.00) OR
        (lower(tipoCliente) = 'distribuidor' AND descuento = 20.00) OR
        (lower(tipoCliente) = 'exportador'   AND descuento IN (30.00, 35.00))
    );

-- CHK 9: (RN-15) Cantidad en renglones positiva
ALTER TABLE detalle_comprobante
    ADD CONSTRAINT chk_detalle_comprobante_cant 
    CHECK (cantidad > 0);

ALTER TABLE detalle_ingreso
    ADD CONSTRAINT chk_detalle_ingreso_cant 
    CHECK (cantidad > 0);

ALTER TABLE detalle_transferencia
    ADD CONSTRAINT chk_detalle_transferencia_cant 
    CHECK (cantidad > 0);

-- CHK 10: Salario de empleados positivo
ALTER TABLE empleado
    ADD CONSTRAINT chk_empleado_salario_positivo 
    CHECK (salario > 0);

-- CHK 11: (RN-15) Importes de venta: precio congelado positivo e importes no negativos
ALTER TABLE detalle_comprobante
    ADD CONSTRAINT chk_detalle_comprobante_precio_positivo CHECK (precio_unit > 0),
    ADD CONSTRAINT chk_detalle_comprobante_importes CHECK (descuento >= 0 AND subtotal >= 0);

ALTER TABLE comprobante
    ADD CONSTRAINT chk_comprobante_importes
    CHECK (subtotal >= 0 AND descuento >= 0 AND total >= 0);

-- CHK 12: (RN-13, RN-15) Precios auditados positivos
ALTER TABLE auditoria_precio
    ADD CONSTRAINT chk_auditoria_precios_positivos
    CHECK (precio_anterior > 0 AND precio_nuevo > 0);

-- CHK 13: (RN-15) Presentación y años válidos
ALTER TABLE vino
    ADD CONSTRAINT chk_vino_volumen_positivo CHECK (volumen > 0),
    ADD CONSTRAINT chk_vino_anada_rango CHECK (anada BETWEEN 1900 AND 2100);

ALTER TABLE parcelas
    ADD CONSTRAINT chk_parcela_ano_plantacion CHECK (ano_plantacion BETWEEN 1900 AND 2100);

ALTER TABLE lote_uva
    ADD CONSTRAINT chk_lote_campania CHECK (campania BETWEEN 1900 AND 2100);

-- CHK 14: Valores de análisis de calidad positivos
ALTER TABLE analisis_calidad
    ADD CONSTRAINT chk_analisis_valores_positivos
    CHECK (brix > 0 AND ph > 0 AND acidez_total > 0);

-- CHK 15: (RN-05) Cada porcentaje de corte está entre 0 (excluido) y 100
ALTER TABLE composicion
    ADD CONSTRAINT chk_composicion_porcentaje
    CHECK (porcentaje > 0 AND porcentaje <= 100);

-- CHK 16: Catálogos de valores cerrados
ALTER TABLE cepa
    ADD CONSTRAINT chk_cepa_tipo CHECK (tipo IN ('tinta', 'blanca'));

-- dia_cierre y tipo_documento se comparan en minúsculas y con o sin tilde.
-- AJUSTAR a los valores exactos que genera db/seed/generar_datos.py.
ALTER TABLE sala_de_ventas
    ADD CONSTRAINT chk_sala_dia_cierre
    CHECK (lower(dia_cierre) IN ('lunes', 'martes', 'miércoles', 'miercoles', 'jueves',
                                 'viernes', 'sábado', 'sabado', 'domingo'));

ALTER TABLE clientes
    ADD CONSTRAINT chk_clientes_tipo_documento
    CHECK (upper(tipo_documento) IN ('DNI', 'CUIT', 'CUIL', 'PASAPORTE'));

-- 3. VALORES DEFAULT
ALTER TABLE ingresos
    ALTER COLUMN estado SET DEFAULT 'en_confeccion'::estado_documento,
    ALTER COLUMN fecha SET DEFAULT CURRENT_DATE;

ALTER TABLE transferencias
    ALTER COLUMN estado SET DEFAULT 'en_confeccion'::estado_documento,
    ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE;

ALTER TABLE clientes
    ALTER COLUMN fecha_alta SET DEFAULT CURRENT_DATE;

ALTER TABLE comprobante
    ALTER COLUMN fecha SET DEFAULT CURRENT_DATE;


-- Los importes del comprobante arrancan en 0 y los completa el trigger (RN-08).
ALTER TABLE comprobante
    ALTER COLUMN subtotal SET DEFAULT 0,
    ALTER COLUMN descuento SET DEFAULT 0,
    ALTER COLUMN total SET DEFAULT 0;