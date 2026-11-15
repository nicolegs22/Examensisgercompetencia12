terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

# Autenticacion via Azure CLI (az login) con la cuenta de la U (Azure for Students).
# No se usa service principal: subscription_id y tenant_id quedan fijos, y las
# credenciales las toma de la sesion activa de az login.
provider "azurerm" {
  features {}
  subscription_id = "ab5b5685-8f0a-455f-8684-91cdf5f6dac7"
  tenant_id       = "cc28633f-12b8-46cb-bc15-951dae239b4d"
}

locals {
  # Incrementar conscientemente para recargar ERP: el primer script elimina tablas.
  dw_seed_version = "1"

  dw_sql_scripts = [
    "1_bronze.sql",
    "2_silver.sql",
    "3_gold.sql",
    "4_insert_bronze_patients.sql",
    "5_insert_bronze_admissions.sql",
    "6_insert_bronze_diagnoses.sql",
    "7_insert_bronze_billing.sql",
  ]
}

# 1. Grupo de recursos y almacenamiento en Brazil South.
resource "azurerm_resource_group" "rg" {
  name     = "DW-Hospital"
  location = "brazilsouth"
}

resource "azurerm_storage_account" "sa" {
  name                     = "saucbhospital13593697"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "raw" {
  name                  = "raw"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "blob"
}

# Sube los archivos de las carpetas locales datos_csv/ y datos_xls/ al contenedor raw.
resource "azurerm_storage_blob" "csv" {
  for_each = fileset("${path.module}/datos_csv", "*")

  name                   = "datos_csv/${each.value}"
  storage_account_name   = azurerm_storage_account.sa.name
  storage_container_name = azurerm_storage_container.raw.name
  type                   = "Block"
  source                 = "${path.module}/datos_csv/${each.value}"
  content_md5            = filemd5("${path.module}/datos_csv/${each.value}")
}

resource "azurerm_storage_blob" "xls" {
  for_each = fileset("${path.module}/datos_xls", "*")

  name                   = "datos_xls/${each.value}"
  storage_account_name   = azurerm_storage_account.sa.name
  storage_container_name = azurerm_storage_container.raw.name
  type                   = "Block"
  source                 = "${path.module}/datos_xls/${each.value}"
  content_md5            = filemd5("${path.module}/datos_xls/${each.value}")
}

# 2. Servidor y bases Azure SQL en Brazil South.
resource "azurerm_mssql_server" "sql_server" {
  name                         = "sql-ucb-server-hospital-13593697"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "nicole.gomez"
  administrator_login_password = "UcbDW!Hosp2025#7q"
  minimum_tls_version          = "1.2"

}

# Acceso desde cualquier IPv4, como en la configuracion original, para sqlcmd local.
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# Habilita explicitamente la conexion desde servicios alojados en Azure.
resource "azurerm_mssql_firewall_rule" "allow_azure_services_explicit" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_database" "db" {
  for_each = toset(["dw_hospital"])

  name                        = each.value
  server_id                   = azurerm_mssql_server.sql_server.id
  collation                   = "SQL_Latin1_General_CP1_CI_AS"
  sku_name                    = "GP_S_Gen5_1"
  max_size_gb                 = 32
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = 60
}

# 3. Carga inicial de DW: esquema, catalogos, datos 2024 y datos 2025.
# El primer script elimina tablas existentes. Para repetir la carga, incrementar
# dw_seed_version conscientemente antes de ejecutar terraform apply.
resource "terraform_data" "dw_schema" {
  triggers_replace = [
    azurerm_mssql_database.db["dw_hospital"].id,
    local.dw_seed_version,
  ]

  depends_on = [
    azurerm_mssql_firewall_rule.allow_azure_services,
  ]

  lifecycle {
    precondition {
      condition     = alltrue([for script in local.dw_sql_scripts : fileexists("${path.module}/sql/${script}")])
      error_message = "Deben existir los cuatro scripts SQL de carga DW en sql/."
    }
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      SQL_SERVER      = azurerm_mssql_server.sql_server.fully_qualified_domain_name
      SQL_DATABASE    = azurerm_mssql_database.db["dw_hospital"].name
      SQL_USER        = azurerm_mssql_server.sql_server.administrator_login
      SQLCMDPASSWORD  = azurerm_mssql_server.sql_server.administrator_login_password
      SQL_SCRIPT_DIR  = abspath("${path.module}/sql")
      SQL_SCRIPT_LIST = join(";", local.dw_sql_scripts)
    }

    command = <<-BASH
      set -euo pipefail

      command -v sqlcmd >/dev/null 2>&1 || { echo "Instale sqlcmd antes de ejecutar Terraform." >&2; exit 1; }

      COMMON_ARGS=(-S "$SQL_SERVER" -d "$SQL_DATABASE" -U "$SQL_USER" -b -r 1 -l 30)

      connected=0
      for attempt in $(seq 1 12); do
        if sqlcmd "$${COMMON_ARGS[@]}" -Q "SET NOCOUNT ON; SELECT 1;" >/dev/null 2>&1; then
          connected=1
          break
        fi
        sleep 10
      done
      if [ "$connected" -ne 1 ]; then
        echo "No se pudo conectar a la base DW despues de crearla y configurar el firewall." >&2
        exit 1
      fi

      IFS=';' read -ra SCRIPTS <<< "$SQL_SCRIPT_LIST"
      for script_name in "$${SCRIPTS[@]}"; do
        script_path="$SQL_SCRIPT_DIR/$script_name"
        if [ ! -f "$script_path" ]; then
          echo "No existe el script SQL: $script_path" >&2
          exit 1
        fi
        echo "Ejecutando $script_name en $SQL_DATABASE"
        sqlcmd "$${COMMON_ARGS[@]}" -i "$script_path"
      done
    BASH
  }
}

# 4. Factoria de integracion en East US.
resource "azurerm_data_factory" "adf" {
  name                = "adf-ucb-transporte-us-13593697"
  resource_group_name = azurerm_resource_group.rg.name
  location            = "eastus"
}