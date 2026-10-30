# Getting the database running — Oracle XE 11g

Your machine has **Oracle Database XE 11g (11.2.0.2)**. That is an older
release than the one the generic instructions assume, and two things
differ:

| | XE 11g (yours) | 23ai Free (the generic docs) |
|---|---|---|
| Service name | **`XE`** | `FREEPDB1` |
| Pluggable databases | none — there is only one database | CDB with PDBs inside |
| `ALTER SESSION SET CONTAINER` | does not exist | needed |

Everything in this project works on 11g. The scripts have been adjusted.

---

## Step 1 — Start the services

PowerShell, **as Administrator** (right-click → Run as administrator):

```powershell
net start OracleXETNSListener
net start OracleServiceXE
```

If a service is already running you get "service has already been
started" — that is fine.

Check:

```powershell
lsnrctl status
```

You want **`The command completed successfully`** and a line showing
service `XE`. If you still get `TNS-12541: no listener`, see
Troubleshooting below.

---

## Step 2 — Create the schema user

```powershell
sqlplus system/YOUR_SYSTEM_PASSWORD@localhost:1521/XE
```

The SYSTEM password is the one you set when XE was installed. Then:

```sql
CREATE USER timebank IDENTIFIED BY timebank;
GRANT CONNECT, RESOURCE TO timebank;
GRANT CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER, CREATE SEQUENCE TO timebank;
ALTER USER timebank QUOTA UNLIMITED ON USERS;

-- optional, lets section 12 of the inspection script read v$sql
GRANT SELECT ON v_$sql TO timebank;

EXIT;
```

**No `ALTER SESSION SET CONTAINER`.** That is a 12c command; 11g has no
containers.

> **Why `GRANT CREATE VIEW` separately?** In XE, the `RESOURCE` role does
> not include it, so without this line `01_ddl.sql` fails when it reaches
> the views.

---

## Step 3 — Build the schema

```powershell
cd C:\Users\gnami\Desktop\TimeBank\sql
sqlplus timebank/timebank@localhost:1521/XE @run_all.sql
```

Watch for two things at the end:

1. The invalid-objects query returns **no rows**
2. The audit prints **`BALANCED`**

If either fails, stop and read the error — do not carry on.

---

## Step 4 — See the tables

### Option A — SQL Developer (what you want for the demo)

Create a connection:

| Field | Value |
|---|---|
| Name | `timebank` |
| Username | `timebank` |
| Password | `timebank` |
| Hostname | `localhost` |
| Port | `1521` |
| **Connection type** | Basic |
| **SID** | `XE` |

**Use SID, not Service name.** XE 11g registers as a SID. If "Service
name" fails, switch the radio button to SID and enter `XE`.

Then in the left panel:

```
Connections
└── timebank
    ├── Tables (15)        ← click a table → Columns / Data / Constraints
    ├── Views (3)
    ├── Indexes (7)
    ├── Packages           ← PKG_TIMEBANK
    ├── Procedures
    ├── Triggers (6)
    └── Sequences (6)
```

Click any table, then the **Data** tab. That is your database.

### Option B — the browser console XE ships with

XE 11g includes APEX at:

```
http://localhost:8080/apex
```

Workspace `INTERNAL`, user `ADMIN`. Slower than SQL Developer, but it
needs no download.

### Option C — straight from SQL*Plus

```sql
-- every table you own
SELECT table_name FROM user_tabs ORDER BY table_name;

-- the full tour
@12_inspect_database.sql
```

---

## Step 5 — Run the member query files

```sql
@06_member1_onboarding.sql
@07_member2_skills.sql
@08_member3_booking.sql
@09_member4_credit.sql
@10_member5_feedback_disputes.sql
@11_group_tcl_plans.sql
```

In that order — later files depend on data earlier ones create.

To capture everything for the report:

```sql
SPOOL C:\Users\gnami\Desktop\TimeBank\output_member1.txt
@06_member1_onboarding.sql
SPOOL OFF
```

---

## Troubleshooting

**`TNS-12541: no listener` even after `net start`**

The service names may differ on your install. List them:

```powershell
Get-Service | Where-Object {$_.Name -like "*Oracle*"}
```

Start whatever appears, by name:

```powershell
Start-Service OracleServiceXE
Start-Service OracleXETNSListener
```

If the listener service exists but will not start, start it directly:

```powershell
lsnrctl start
```

**`ORA-12514: listener does not currently know of service requested`**

The listener is up but the database is not registered yet. Either wait
thirty seconds and retry, or:

```powershell
sqlplus / as sysdba
```
```sql
STARTUP;
ALTER SYSTEM REGISTER;
EXIT;
```

**`ORA-01031: insufficient privileges` while running `01_ddl.sql`**

A grant from step 2 is missing — almost always `CREATE VIEW`. Re-run the
grants as SYSTEM.

**`ORA-00955: name is already used by an existing object`**

A previous build is still there. Run `@00_drop_all.sql` first, or just
`@run_all.sql`, which starts by clearing everything.

**I forgot the SYSTEM password**

```powershell
sqlplus / as sysdba
```
```sql
ALTER USER system IDENTIFIED BY NewPassword123;
```

That works because your Windows account is in the `ORA_DBA` group.

---

## What changed in the project for 11g

| File | Change |
|---|---|
| `sql/12_inspect_database.sql` | `search_condition_vc` → `search_condition` (the `_vc` column is 12c+) |
| `sql/run_all.sql`, docs | Connection strings now use `XE` |
| `app/pom.xml`, `api/pom.xml` | Driver `ojdbc11` 23ai → **`ojdbc8` 19.23**, the last line certified for 11.2 |
| `*/db.properties` | `jdbc:oracle:thin:@//localhost:1521/XE` |

Everything else was already 11g-compatible. Worth knowing which features
were close calls, because she may ask:

- `LISTAGG` — needs 11gR2. You have 11.2, so it works
- **Compound triggers** — 11gR1. Works
- Index-organised tables, function-based indexes — 9i. Fine
- `GROUPING SETS`, `ROLLUP`, all the analytic functions — 9i. Fine
- `REGEXP_LIKE` in a `CHECK` constraint — 10g. Fine
- `ROWNUM` rather than `FETCH FIRST n ROWS` — deliberate; `FETCH FIRST`
  is 12c+ and would have failed here

---

## XE 11g limits

| Limit | Value | Matters here? |
|---|---|---|
| User data | 11 GB | No — this schema is a few MB |
| RAM | 1 GB | No |
| CPU | 1 core | No — though the concurrency demo still works, since it blocks on a row lock rather than on CPU |
