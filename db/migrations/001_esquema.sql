DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;


-- Dominio para CUIT de 11 dígitos
CREATE DOMAIN cuit_dom AS VARCHAR(11);

-- Tipo Enumerado para los estados de documentos (Ingresos y Transferencias)
CREATE TYPE estado_documento AS ENUM ('en_confeccion', 'terminado', 'procesado');

-- Localidades
CREATE TABLE localidades (
    codigo_postal INTEGER NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    provincia VARCHAR(100) NOT NULL,
    PRIMARY KEY (codigo_postal)
);

-- Encargado Regional (Responsable Comercial por localidad)
CREATE TABLE encargado_regional (
    identificador INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(100) NOT NULL,
    codigo_postal_localidad INTEGER NOT NULL,
    PRIMARY KEY (identificador),
    FOREIGN KEY (codigo_postal_localidad) REFERENCES localidades (codigo_postal) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Salas de Venta
CREATE TABLE sala_de_ventas (
    id_sala INTEGER GENERATED ALWAYS AS IDENTITY,
    calle VARCHAR(100) NOT NULL,
    numero INTEGER NOT NULL,
    dia_cierre VARCHAR(20) NOT NULL,
    codigo_postal INTEGER NOT NULL,
    PRIMARY KEY (id_sala),
    FOREIGN KEY (codigo_postal) REFERENCES localidades (codigo_postal) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Empleados
CREATE TABLE empleado (
    cuit cuit_dom NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    fecha_ingreso DATE NOT NULL,
    salario NUMERIC(10, 2) NOT NULL,
    id_sala INTEGER NOT NULL,
    PRIMARY KEY (cuit),
    FOREIGN KEY (id_sala) REFERENCES sala_de_ventas (id_sala) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Bodegas
CREATE TABLE bodega (
    cuit cuit_dom NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    calle VARCHAR(100) NOT NULL,
    num_calle INTEGER NOT NULL,
    PRIMARY KEY (cuit)
);

-- Empresas de Transporte
CREATE TABLE empresa_transporte (
    cod_transporte INTEGER GENERATED ALWAYS AS IDENTITY,
    razon_social VARCHAR(100) NOT NULL,
    cuit cuit_dom NOT NULL,
    email VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    calle VARCHAR(100) NOT NULL,
    num_calle INTEGER NOT NULL,
    PRIMARY KEY (cod_transporte)
);

-- Cobertura de Transportistas por Localidad (N:M)
CREATE TABLE transportista_de_localidad (
    codigo_postal INTEGER NOT NULL,
    cod_transporte INTEGER NOT NULL,
    PRIMARY KEY (codigo_postal, cod_transporte),
    FOREIGN KEY (codigo_postal) REFERENCES localidades (codigo_postal) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (cod_transporte) REFERENCES empresa_transporte (cod_transporte) ON DELETE CASCADE ON UPDATE CASCADE
);

-- Fincas
CREATE TABLE finca (
    id INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(100) NOT NULL,
    superficie NUMERIC(8, 2) NOT NULL,
    departamento VARCHAR(100) NOT NULL,
    provincia VARCHAR(100) NOT NULL,
    PRIMARY KEY (id)
);

-- Cepas (Catálogo)
CREATE TABLE cepa (
    identificador INTEGER GENERATED ALWAYS AS IDENTITY,
    tipo VARCHAR(10) NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    PRIMARY KEY (identificador)
);

-- Parcelas (Entidad Débil de Finca)
CREATE TABLE parcelas (
    id_finca INTEGER NOT NULL,
    identificador INTEGER NOT NULL,
    superficie NUMERIC(8, 2) NOT NULL,
    ano_plantacion SMALLINT NOT NULL,
    id_cepa INTEGER NOT NULL,
    PRIMARY KEY (id_finca, identificador),
    FOREIGN KEY (id_finca) REFERENCES finca (id) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (id_cepa) REFERENCES cepa (identificador) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Lote de Uva (Cosecha por parcela)
CREATE TABLE lote_uva (
    num_lote INTEGER GENERATED ALWAYS AS IDENTITY,
    fecha_cosecha DATE NOT NULL,
    kilo_cosechado NUMERIC(10, 2) NOT NULL,
    bodega_entrega cuit_dom NOT NULL,
    id_finca INTEGER NOT NULL,
    id_parcela INTEGER NOT NULL,
    PRIMARY KEY (num_lote),
    FOREIGN KEY (bodega_entrega) REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (id_finca, id_parcela) REFERENCES parcelas (id_finca, identificador) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Análisis de Calidad (Varios por lote)
CREATE TABLE analisis_calidad (
    identificador INTEGER GENERATED ALWAYS AS IDENTITY,
    fecha DATE NOT NULL,
    brix NUMERIC(5, 2) NOT NULL,
    ph NUMERIC(3, 2) NOT NULL,
    acidez_total NUMERIC(5, 2) NOT NULL,
    num_lote INTEGER NOT NULL,
    PRIMARY KEY (identificador),
    FOREIGN KEY (num_lote) REFERENCES lote_uva (num_lote) ON DELETE CASCADE ON UPDATE CASCADE
);

-- Vinos
CREATE TABLE vino (
    codigo INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(100) NOT NULL,
    volumen INTEGER NOT NULL,
    precio NUMERIC(10, 2) NOT NULL,
    graduacion NUMERIC(4, 2) NOT NULL,
    tipo VARCHAR(20) NOT NULL,
    anada SMALLINT NOT NULL,
    cuit_bodega cuit_dom NOT NULL,
    PRIMARY KEY (codigo),
    FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Composición de Vino / Corte (N:M Vino - Cepa)
CREATE TABLE elaboracion_vino (
    id_cepa INTEGER NOT NULL,
    id_vino INTEGER NOT NULL,
    porcentaje NUMERIC(5, 2) NOT NULL,
    PRIMARY KEY (id_cepa, id_vino),
    FOREIGN KEY (id_cepa) REFERENCES cepa (identificador) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (id_vino) REFERENCES vino (codigo) ON DELETE CASCADE ON UPDATE CASCADE
);

-- Maridajes (Catálogo)
CREATE TABLE maridaje (
    codigo INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(100) NOT NULL,
    temperatura NUMERIC(4, 2) NOT NULL,
    PRIMARY KEY (codigo)
);

-- Vino-Maridaje (N:M)
CREATE TABLE vino_maridaje (
    cod_vino INTEGER NOT NULL,
    cod_maridaje INTEGER NOT NULL,
    PRIMARY KEY (cod_vino, cod_maridaje),
    FOREIGN KEY (cod_vino) REFERENCES vino (codigo) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (cod_maridaje) REFERENCES maridaje (codigo) ON DELETE RESTRICT ON UPDATE CASCADE
);


-- Supertipo Clientes
CREATE TABLE clientes (
    id INTEGER GENERATED ALWAYS AS IDENTITY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100),
    razon_social VARCHAR(100),
    tipo_documento VARCHAR(10) NOT NULL,
    num_documento VARCHAR(20) NOT NULL,
    fecha_alta DATE NOT NULL,
    descuento NUMERIC(5, 2) NOT NULL,
    codigo_postal INTEGER NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (codigo_postal) REFERENCES localidades (codigo_postal) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Subtipo: Socio Club
CREATE TABLE socio_club (
    id INTEGER NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (id) REFERENCES clientes (id) ON DELETE CASCADE ON UPDATE CASCADE
);

-- Subtipo: Distribuidores
CREATE TABLE distribuidores (
    id INTEGER NOT NULL,
    zona_cobertura VARCHAR(100) NOT NULL,
    num_habilitacion VARCHAR(50) NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (id) REFERENCES clientes (id) ON DELETE CASCADE ON UPDATE CASCADE
);

-- Subtipo: Exportadores
CREATE TABLE exportadores (
    id INTEGER NOT NULL,
    pais_destino VARCHAR(100) NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (id) REFERENCES clientes (id) ON DELETE CASCADE ON UPDATE CASCADE
);

-- Permisos de Exportación (Varios por Exportador)
CREATE TABLE permisos (
    codigo VARCHAR(50) NOT NULL,
    fecha_emision DATE NOT NULL,
    fecha_vencimiento DATE NOT NULL,
    id_exportador INTEGER NOT NULL,
    PRIMARY KEY (codigo),
    FOREIGN KEY (id_exportador) REFERENCES exportadores (id) ON DELETE CASCADE ON UPDATE CASCADE
);

-- Stock de Depósito Central (Un solo depósito central)
CREATE TABLE deposito_central (
    codigo_vino INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (codigo_vino),
    FOREIGN KEY (codigo_vino) REFERENCES vino (codigo) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Stock por Sala de Ventas (N:M Sala - Vino)
CREATE TABLE deposito_sala (
    id_sala INTEGER NOT NULL,
    cod_vino INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (id_sala, cod_vino),
    FOREIGN KEY (id_sala) REFERENCES sala_de_ventas (id_sala) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (cod_vino) REFERENCES vino (codigo) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Ingresos al Depósito Central
CREATE TABLE ingresos (
    codigo INTEGER GENERATED ALWAYS AS IDENTITY,
    fecha DATE NOT NULL,
    estado estado_documento NOT NULL,
    cuit_bodega cuit_dom NOT NULL,
    cod_transporte INTEGER NOT NULL,
    PRIMARY KEY (codigo),
    FOREIGN KEY (cuit_bodega) REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (cod_transporte) REFERENCES empresa_transporte (cod_transporte) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Detalle / Renglón de Ingreso
CREATE TABLE detalle_ingreso (
    num_ingreso INTEGER NOT NULL,
    cod_vino INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (num_ingreso, cod_vino),
    FOREIGN KEY (num_ingreso) REFERENCES ingresos (codigo) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (cod_vino) REFERENCES vino (codigo) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Transferencias (Solicitudes de Sala a Depósito Central)
CREATE TABLE transferencias (
    num_solicitud INTEGER GENERATED ALWAYS AS IDENTITY,
    fecha_confeccion DATE NOT NULL,
    estado estado_documento NOT NULL,
    id_sala INTEGER NOT NULL,
    PRIMARY KEY (num_solicitud),
    FOREIGN KEY (id_sala) REFERENCES sala_de_ventas (id_sala) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Contenido / Renglón de Transferencia
CREATE TABLE contenido_transferencia (
    num_transferencia INTEGER NOT NULL,
    cod_vino INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (num_transferencia, cod_vino),
    FOREIGN KEY (num_transferencia) REFERENCES transferencias (num_solicitud) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (cod_vino) REFERENCES vino (codigo) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Comprobantes (Ventas en Salas)
CREATE TABLE comprobante (
    numero INTEGER GENERATED ALWAYS AS IDENTITY,
    fecha DATE NOT NULL,
    subtotal NUMERIC(12, 2) NOT NULL,
    descuento NUMERIC(12, 2) NOT NULL,
    total NUMERIC(12, 2) NOT NULL,
    id_sala INTEGER NOT NULL,
    id_cliente INTEGER NOT NULL,
    PRIMARY KEY (numero),
    FOREIGN KEY (id_sala) REFERENCES sala_de_ventas (id_sala) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (id_cliente) REFERENCES clientes (id) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Detalle / Renglón de Comprobante
CREATE TABLE detalle_comprobante (
    cod_comprobante INTEGER NOT NULL,
    cod_vino INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    precio_unit NUMERIC(10, 2) NOT NULL,
    descuento NUMERIC(10, 2) NOT NULL,
    subtotal NUMERIC(12, 2) NOT NULL,
    PRIMARY KEY (cod_comprobante, cod_vino),
    FOREIGN KEY (cod_comprobante) REFERENCES comprobante (numero) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (cod_vino) REFERENCES vino (codigo) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Tabla de Auditoría de Precio de Vino
CREATE TABLE auditoria_precio (
    id INTEGER GENERATED ALWAYS AS IDENTITY,
    precio_anterior NUMERIC(10, 2) NOT NULL,
    precio_nuevo NUMERIC(10, 2) NOT NULL,
    fecha DATE NOT NULL,
    hora TIME NOT NULL,
    usuario VARCHAR(50) NOT NULL,
    id_vino INTEGER NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (id_vino) REFERENCES vino (codigo) ON DELETE CASCADE ON UPDATE CASCADE
);