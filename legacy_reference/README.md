# Financial Data Reconciliation System — Oracle Connection Settings

**Project Details**

* Project Name: Financial Data Reconciliation System
* Project Folder: `C:\Users\mayank\Documents\financial-data-reconciliation-system`
* Database: Oracle AI Database 26ai Free
* Oracle Version: `23.26.3.0.0`
* Editor: Visual Studio Code
* Extension: Oracle SQL Developer

**VS Code Connection Settings**

| Setting         | Value                      |
| --------------- | -------------------------- |
| Connection Name | `FIN_RECON_LOCAL`          |
| Connection Type | Basic                      |
| Username        | `ANALYTICS_PROJECT`        |
| Password        | Your saved schema password |
| Hostname        | `127.0.0.1`                |
| Port            | `1521`                     |
| Service Name    | `FREEPDB1`                 |
| Role            | Default                    |

**Oracle Installation**

* Oracle Home: `C:\app\mayank\product\26ai\dbhomeFree`
* Listener Configuration: `C:\app\mayank\product\26ai\dbhomeFree\network\admin\listener.ora`
* Listener Host: `127.0.0.1`
* Listener Port: `1521`
* Database Service: `FREE`
* Pluggable Database (PDB): `FREEPDB1`
* Project Schema: `ANALYTICS_PROJECT`

**Current Status**

* Oracle database: Running
* PDB `FREEPDB1`: Open in READ WRITE mode
* Listener: Running and services registered
* VS Code connection: Connected successfully

**Connection Verification Query**

```sql
SELECT
    USER AS connected_user,
    SYS_CONTEXT('USERENV', 'CON_NAME') AS container_name,
    SYS_CONTEXT('USERENV', 'DB_NAME') AS database_name
FROM dual;
```

Expected user: `ANALYTICS_PROJECT`
Expected container: `FREEPDB1`

**Project Goal**

Build a Financial Data Reconciliation System using Oracle SQL and PL/SQL, with reconciliation rules, mismatch detection, exception reporting, and audit tracking.
