-- ============================================================================
-- 1. CREACIÓN DE ESQUEMAS
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO

-- ============================================================================
-- 3. CAPA SILVER (Estructurada, Tipada y Relacional)
-- ============================================================================

DROP TABLE IF EXISTS silver.billing;
DROP TABLE IF EXISTS silver.diagnoses;
DROP TABLE IF EXISTS silver.admissions;
DROP TABLE IF EXISTS silver.patients;
GO

-- Tabla: Pacientes
CREATE TABLE silver.patients (
    patient_id          INT NOT NULL,
    full_name           NVARCHAR(250) NOT NULL,
    gender              VARCHAR(10) NULL,
    date_of_birth       DATE NULL,
    phone               VARCHAR(50) NULL,
    email               VARCHAR(255) NULL,
    address             NVARCHAR(500) NULL,
    insurance_provider  NVARCHAR(150) NULL,
    CONSTRAINT PK_silver_patients PRIMARY KEY (patient_id)
);
GO

-- Tabla: Admisiones
CREATE TABLE silver.admissions (
    admission_id        INT NOT NULL,
    patient_id          INT NOT NULL,
    admission_date      DATE NOT NULL,
    discharge_date      DATE NULL,
    department          NVARCHAR(100) NOT NULL,
    attending_doctor_id INT NOT NULL,
    CONSTRAINT PK_silver_admissions PRIMARY KEY (admission_id),
    CONSTRAINT FK_silver_admissions_patient FOREIGN KEY (patient_id) 
        REFERENCES silver.patients(patient_id)
);
GO

-- Tabla: Diagnósticos
CREATE TABLE silver.diagnoses (
    diagnosis_id          INT NOT NULL,
    admission_id          INT NOT NULL,
    icd_code              VARCHAR(50) NOT NULL,
    diagnosis_description NVARCHAR(500) NULL,
    severity              VARCHAR(50) NULL,
    CONSTRAINT PK_silver_diagnoses PRIMARY KEY (diagnosis_id),
    CONSTRAINT FK_silver_diagnoses_admission FOREIGN KEY (admission_id) 
        REFERENCES silver.admissions(admission_id)
);
GO

-- Tabla: Facturación
CREATE TABLE silver.billing (
    billing_id          INT NOT NULL,
    admission_id        INT NOT NULL,
    charge_type         VARCHAR(100) NOT NULL,
    amount              DECIMAL(12, 2) NOT NULL,
    payment_status      VARCHAR(50) NOT NULL,
    payment_date        DATE NULL,
    CONSTRAINT PK_silver_billing PRIMARY KEY (billing_id),
    CONSTRAINT FK_silver_billing_admission FOREIGN KEY (admission_id) 
        REFERENCES silver.admissions(admission_id)
);
GO

