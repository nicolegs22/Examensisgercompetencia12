-- ============================================================================
-- 1. CREACIÓN DE ESQUEMA GOLD
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'gold')
    EXEC('CREATE SCHEMA gold');
GO


-- ============================================================================
-- 4. CAPA GOLD (Modelo Estrella / Data Warehouse)
-- ============================================================================

-- Limpieza previa en orden de dependencias
DROP TABLE IF EXISTS gold.fact_facturacion;
DROP TABLE IF EXISTS gold.fact_admisiones;
DROP TABLE IF EXISTS gold.dim_diagnostico;
DROP TABLE IF EXISTS gold.dim_servicio_cargo;
DROP TABLE IF EXISTS gold.dim_departamento;
DROP TABLE IF EXISTS gold.dim_paciente;
DROP TABLE IF EXISTS gold.dim_fecha;
GO

-- ----------------------------------------------------------------------------
-- 4.1 DIMENSIÓN FECHA / TIEMPO
-- ----------------------------------------------------------------------------
CREATE TABLE gold.dim_fecha (
    fecha_key           INT NOT NULL,             -- Formato YYYYMMDD (ej: 20240727)
    fecha_completa      DATE NOT NULL,
    anio                SMALLINT NOT NULL,
    trimestre           TINYINT NOT NULL,
    trimestre_nombre    VARCHAR(10) NOT NULL,     -- 'T1', 'T2', 'T3', 'T4'
    mes                 TINYINT NOT NULL,
    mes_nombre          VARCHAR(20) NOT NULL,     -- 'Enero', 'Febrero', etc.
    mes_corto           CHAR(3) NOT NULL,         -- 'Ene', 'Feb', etc.
    semana_anio         TINYINT NOT NULL,
    dia_mes             TINYINT NOT NULL,
    dia_semana          TINYINT NOT NULL,         -- 1 (Lunes) a 7 (Domingo)
    dia_nombre          VARCHAR(20) NOT NULL,     -- 'Lunes', 'Martes', etc.
    es_fin_de_semana    BIT NOT NULL,             -- 1 = Fin de semana, 0 = Hábil
    CONSTRAINT PK_gold_dim_fecha PRIMARY KEY (fecha_key)
);
GO

-- ----------------------------------------------------------------------------
-- 4.2 DIMENSIÓN PACIENTE (SCD Tipo 1 / 2 según estrategia)
-- ----------------------------------------------------------------------------
CREATE TABLE gold.dim_paciente (
    paciente_key        INT IDENTITY(1,1) NOT NULL, -- Surrogate Key
    patient_id_bk       INT NOT NULL,               -- Business Key origen
    nombre_completo     NVARCHAR(250) NOT NULL,
    genero              VARCHAR(20) NOT NULL,       -- Estandarizado ('Masculino', 'Femenino', 'Otro')
    fecha_nacimiento    DATE NULL,
    rango_etario        VARCHAR(50) NULL,           -- '0-18', '19-35', '36-60', '60+'
    correo_electronico  VARCHAR(255) NULL,
    direccion           NVARCHAR(500) NULL,
    proveedor_seguro    NVARCHAR(150) NOT NULL,
    CONSTRAINT PK_gold_dim_paciente PRIMARY KEY (paciente_key)
);
GO

-- ----------------------------------------------------------------------------
-- 4.3 DIMENSIÓN DEPARTAMENTO / MÉDICO
-- ----------------------------------------------------------------------------
CREATE TABLE gold.dim_departamento (
    departamento_key    INT IDENTITY(1,1) NOT NULL,
    nombre_departamento NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_gold_dim_departamento PRIMARY KEY (departamento_key)
);
GO

-- ----------------------------------------------------------------------------
-- 4.4 DIMENSIÓN DIAGNÓSTICO
-- ----------------------------------------------------------------------------
CREATE TABLE gold.dim_diagnostico (
    diagnostico_key        INT IDENTITY(1,1) NOT NULL,
    codigo_icd             VARCHAR(50) NOT NULL,
    descripcion_patologia  NVARCHAR(500) NULL,
    nivel_severidad        VARCHAR(50) NOT NULL,
    CONSTRAINT PK_gold_dim_diagnostico PRIMARY KEY (diagnostico_key)
);
GO

-- ----------------------------------------------------------------------------
-- 4.5 DIMENSIÓN SERVICIO / CARGO
-- ----------------------------------------------------------------------------
CREATE TABLE gold.dim_servicio_cargo (
    servicio_cargo_key  INT IDENTITY(1,1) NOT NULL,
    tipo_cargo          VARCHAR(100) NOT NULL,     -- 'Surgery', 'Medication', 'Imaging', etc.
    estado_pago         VARCHAR(50) NOT NULL,      -- 'Paid', 'Unpaid', 'Pending'
    CONSTRAINT PK_gold_dim_servicio_cargo PRIMARY KEY (servicio_cargo_key)
);
GO

-- ----------------------------------------------------------------------------
-- 4.6 TABLA DE HECHOS: ADMISIONES (Fact Hospital Encounters)
-- ----------------------------------------------------------------------------
CREATE TABLE gold.fact_admisiones (
    admision_key         BIGINT IDENTITY(1,1) NOT NULL,
    admission_id_bk      INT NOT NULL,              -- Business Key
    paciente_key         INT NOT NULL,
    departamento_key     INT NOT NULL,
    diagnostico_key      INT NOT NULL,
    fecha_ingreso_key    INT NOT NULL,
    fecha_alta_key       INT NULL,
    medico_id            INT NOT NULL,
    -- Métricas / Medidas
    dias_estancia        INT NULL,                  -- DATEDIFF en días entre alta e ingreso
    conteo_admisiones    INT NOT NULL DEFAULT 1,
    CONSTRAINT PK_gold_fact_admisiones PRIMARY KEY (admision_key),
    CONSTRAINT FK_fact_adm_paciente FOREIGN KEY (paciente_key) 
        REFERENCES gold.dim_paciente(paciente_key),
    CONSTRAINT FK_fact_adm_departamento FOREIGN KEY (departamento_key) 
        REFERENCES gold.dim_departamento(departamento_key),
    CONSTRAINT FK_fact_adm_diagnostico FOREIGN KEY (diagnostico_key) 
        REFERENCES gold.dim_diagnostico(diagnostico_key),
    CONSTRAINT FK_fact_adm_fecha_ingreso FOREIGN KEY (fecha_ingreso_key) 
        REFERENCES gold.dim_fecha(fecha_key),
    CONSTRAINT FK_fact_adm_fecha_alta FOREIGN KEY (fecha_alta_key) 
        REFERENCES gold.dim_fecha(fecha_key)
);
GO

-- ----------------------------------------------------------------------------
-- 4.7 TABLA DE HECHOS: FACTURACIÓN (Fact Billing Transactions)
-- ----------------------------------------------------------------------------
CREATE TABLE gold.fact_facturacion (
    facturacion_key      BIGINT IDENTITY(1,1) NOT NULL,
    billing_id_bk        INT NOT NULL,              -- Business Key
    admission_id_bk      INT NOT NULL,
    paciente_key         INT NOT NULL,
    departamento_key     INT NOT NULL,
    servicio_cargo_key   INT NOT NULL,
    fecha_pago_key       INT NULL,                  -- Si está impago, puede ser NULL o clave -1
    -- Métricas
    monto_facturado      DECIMAL(12, 2) NOT NULL,
    conteo_transacciones INT NOT NULL DEFAULT 1,
    CONSTRAINT PK_gold_fact_facturacion PRIMARY KEY (facturacion_key),
    CONSTRAINT FK_fact_fact_paciente FOREIGN KEY (paciente_key) 
        REFERENCES gold.dim_paciente(paciente_key),
    CONSTRAINT FK_fact_fact_departamento FOREIGN KEY (departamento_key) 
        REFERENCES gold.dim_departamento(departamento_key),
    CONSTRAINT FK_fact_fact_servicio FOREIGN KEY (servicio_cargo_key) 
        REFERENCES gold.dim_servicio_cargo(servicio_cargo_key),
    CONSTRAINT FK_fact_fact_fecha_pago FOREIGN KEY (fecha_pago_key) 
        REFERENCES gold.dim_fecha(fecha_key)
);
GO
