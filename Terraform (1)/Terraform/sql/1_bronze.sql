-- ============================================================================
-- 1. CREACIÓN DE ESQUEMAS
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'bronze')
    EXEC('CREATE SCHEMA bronze');
GO

-- ============================================================================
-- 2. CAPA BRONZE (Tablas Raw / Landing)
-- ============================================================================

DROP TABLE IF EXISTS bronze.patients;
CREATE TABLE bronze.patients (
    patient_id          NVARCHAR(100),
    full_name           NVARCHAR(500),
    gender              NVARCHAR(100),
    date_of_birth       NVARCHAR(200),
    phone               NVARCHAR(200),
    email               NVARCHAR(500),
    address             NVARCHAR(1000),
    insurance_provider  NVARCHAR(300),
);
GO

DROP TABLE IF EXISTS bronze.admissions;
CREATE TABLE bronze.admissions (
    admission_id        NVARCHAR(100),
    patient_id          NVARCHAR(100),
    admission_date      NVARCHAR(200),
    discharge_date      NVARCHAR(200),
    department          NVARCHAR(300),
    attending_doctor_id NVARCHAR(100),
);
GO

DROP TABLE IF EXISTS bronze.diagnoses;
CREATE TABLE bronze.diagnoses (
    diagnosis_id          NVARCHAR(100),
    admission_id          NVARCHAR(100),
    icd_code              NVARCHAR(200),
    diagnosis_description NVARCHAR(1000),
    severity              NVARCHAR(100),
);
GO

DROP TABLE IF EXISTS bronze.billing;
CREATE TABLE bronze.billing (
    billing_id          NVARCHAR(100),
    admission_id        NVARCHAR(100),
    charge_type         NVARCHAR(200),
    amount              NVARCHAR(200),
    payment_status      NVARCHAR(200),
    payment_date        NVARCHAR(200),
);
GO