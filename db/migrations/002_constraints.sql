-- UQ 1: (RN-01) No repetir vino por nombre, añada y volumen
ALTER TABLE vino
    ADD CONSTRAINT uq_vino_nombre_anada_volumen 
    UNIQUE (nombre, anada, volumen);

-- UQ 2: Nombre de maridaje único
ALTER TABLE localidades
    ADD CONSTRAINT uq_localidad_provincia 
    UNIQUE (nombre, provincia);

-- UQ 3: Razón social única en transportistas
ALTER TABLE empresa_transporte
    ADD CONSTRAINT uq_transporte_razon_social 
    UNIQUE (razon_social);

-- UQ 4: Cepa única por parcela (RN-04)
ALTER TABLE parcelas
    ADD CONSTRAINT uq_parcela_cepa 
    UNIQUE (id_finca, identificador, id_cepa);

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
ALTER TABLE deposito_sala
    ADD CONSTRAINT chk_stock_sala_no_negativo 
    CHECK (cantidad >= 0);

ALTER TABLE deposito_central
    ADD CONSTRAINT chk_stock_deposito_no_negativo 
    CHECK (cantidad >= 0);

-- CHK 7: (RN-07) [ENTRE COLUMNAS] Vencimiento posterior a emisión
ALTER TABLE permisos
    ADD CONSTRAINT chk_permiso_fechas_coherentes 
    CHECK (fecha_vencimiento > fecha_emision);

-- CHK 8: (RN-06) Descuento permitido en clientes según regla de negocio
ALTER TABLE clientes
    ADD CONSTRAINT chk_clientes_descuento_valido 
    CHECK (descuento IN (0.00, 10.00, 20.00, 30.00, 35.00));

-- CHK 9: (RN-15) Cantidad en renglones positiva
ALTER TABLE detalle_comprobante
    ADD CONSTRAINT chk_detalle_comprobante_cant 
    CHECK (cantidad > 0);

ALTER TABLE detalle_ingreso
    ADD CONSTRAINT chk_detalle_ingreso_cant 
    CHECK (cantidad > 0);

ALTER TABLE contenido_transferencia
    ADD CONSTRAINT chk_contenido_transferencia_cant 
    CHECK (cantidad > 0);

-- CHK 10: Salario de empleados positivo
ALTER TABLE empleado
    ADD CONSTRAINT chk_empleado_salario_positivo 
    CHECK (salario > 0);

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