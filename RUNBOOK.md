# Running TimeBank from scratch

Four stages, in this order. Each one depends on the one before it.

```
Oracle XE :1521   →   schema built   →   Spring Boot API :8081   →   Flutter app
```

**The shortcut:** right-click `START_DEMO.bat` → *Run as administrator*. It
does stages 1, 3 and 4 and opens the three windows for you. Use the
manual steps below when something goes wrong, or when the schema needs
rebuilding (stage 2, which the batch file deliberately does **not** do —
it would wipe your data every time).

---

## Stage 1 — Oracle

Oracle runs as a Windows service and stops when the machine restarts.

**Administrator PowerShell** (right-click → Run as administrator):

```powershell
net start OracleServiceXE
net start OracleXETNSListener
```

"Service has already been started" is fine. Check:

```powershell
lsnrctl status
```

You want **`The command completed successfully`** and a line showing
service `XE`. If you get `TNS-12541: no listener`, run `lsnrctl start`.

---

## Stage 2 — The schema (only when you want a clean slate)

Skip this if the database already has your data and you want to keep it.

```powershell
cd C:\Users\gnami\Desktop\TimeBank\sql
sqlplus timebank/timebank@localhost:1521/XE "@rerun.sql"
```

This **drops everything and rebuilds**: 15 tables, 6 sequences, 3 views,
7 indexes, 6 triggers, the package, the seed data, then all 45 member
queries. Takes a couple of minutes and writes a transcript to
`demo_output.txt`.

Two things to check at the end:

1. the invalid-objects query returns **no rows**
2. the audit prints **`BALANCED`**

The only errors you should see are the two deliberate ones in Member 4,
printed as `Blocked as designed -> ORA-20001`. That is the append-only
trigger refusing to let the ledger be edited. Anything else is real.

> **Why a full rebuild rather than re-running one file?** Each member
> file opens with an INSERT, so it is written to run once against a
> fresh seed. Running `06` twice tries to register the same student
> again and raises ORA-00001. Rebuilding first makes every run identical.

---

## Stage 3 — The API

```powershell
cd C:\Users\gnami\Desktop\TimeBank\api
mvn -q clean compile
mvn spring-boot:run
```

`-q` prints nothing on success, so **silence means it worked**. Wait for:

```
Tomcat started on port 8081 (http)
Started TimeBankApiApplication in 3.9 seconds
```

**Leave this window open.** It is the API, and it is also where every
SQL statement prints. Closing it kills the app's data source.

Check it in a browser:

```
localhost:8081/api/students
```

JSON means Flutter → Java → JDBC → Oracle is working end to end.

### If `mvn` is not recognised

A new PowerShell window that predates the PATH change. Either open a
fresh one, or set it for this window:

```powershell
$env:PATH += ";$env:USERPROFILE\tools\apache-maven-3.9.9\bin"
$env:JAVA_HOME = "C:\Program Files\Java\jdk-26.0.1"
```

### If port 8081 is already in use

An API from an earlier run is still holding it:

```powershell
Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

> Port **8080** is Oracle XE's own APEX console. That is why this API
> listens on 8081.

---

## Stage 4 — The app

A **second** PowerShell window:

```powershell
cd C:\Users\gnami\Desktop\TimeBank\timebank
flutter run -d chrome
```

First build takes a minute or two. Chrome opens by itself.

In that window: **`r`** hot reload, **`R`** hot restart, **`q`** quit.

Use Chrome rather than the Windows desktop target — the Windows build
needs Visual Studio with the C++ workload, which is a long install. The
API already allows cross-origin requests on `/api/**`, so the browser
will not block it.

---

## Checking the data

A **third** window, for proving that what the app did reached the disk:

```powershell
cd C:\Users\gnami\Desktop\TimeBank\sql
sqlplus timebank/timebank@localhost:1521/XE
```

```sql
@check.sql
```

Run it before an action and again after. Row counts move, new rows
appear at the top, and the closed-economy audit still balances.

If SQL*Plus says **`SP2-0640: Not connected`**, you started it without
credentials. Connect at the prompt:

```sql
CONNECT timebank/timebank@localhost:1521/XE
```

---

## The layout to demonstrate with

| Window | What it shows |
|---|---|
| Chrome | what a user does |
| **API terminal** | **the SQL that click ran, and the rows it changed** |
| SQL*Plus | the rows now stored |

The middle one is the point. Click *Register* in the app and that window
prints the procedure call, its bind values, the INSERT statements that
ran inside the package, and then the STUDENT and CREDIT_TXN rows that
now exist — all before you have touched the database by hand.

---

## When something is wrong

| Symptom | Cause |
|---|---|
| Every screen in the app errors | the API window is closed, or was never started |
| `ORA-12541: no listener` | stage 1 was skipped, or the machine restarted |
| `Port 8080 was already in use` | you are running an old build; 8081 is correct |
| `SP2-0640: Not connected` | SQL\*Plus started without credentials |
| `ORA-00001 unique constraint` | a member file run twice — rebuild with `rerun.sql` |
| Red squiggles in VS Code, Java | `Ctrl+Shift+P` → *Java: Clean Workspace* |

`SETUP_XE11G.md` has the longer troubleshooting list, including
`ORA-12154` and `ORA-12514`.
