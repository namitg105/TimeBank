# For the team — getting the project and running it

Everything below is typed into **Command Prompt** on Windows. Nothing
here needs an IDE.

Two things to know before you start:

- **Oracle runs on your own machine.** The database is not shared. You
  build it once from the scripts in `sql/`, and it lives on your laptop.
  So pulling new code never changes anyone else's data.
- **Watch the API window.** Every click in the app prints the SQL it
  ran, with the values, the row count and the rows afterwards. That
  window is the proof the app really reached Oracle, and it is what the
  evaluator wants to see.

---

## Table of contents

1. [First time only](#1-first-time-only)
2. [Taking a pull](#2-taking-a-pull)
3. [Starting the system, every time](#3-starting-the-system-every-time)
4. [Checking it worked](#4-checking-it-worked)
5. [Sending your own work back](#5-sending-your-own-work-back)
6. [When something goes wrong](#6-when-something-goes-wrong)

---

## 1. First time only

Do this once per laptop. After that, section 2 is all you need.

### 1.1 Install the four tools

| Tool | Version we use | Where it goes |
|---|---|---|
| Oracle Database XE | **11g** (service name `XE`, port 1521) | `C:\oraclexe\...` |
| JDK | 17 or newer | anywhere; set `JAVA_HOME` |
| Maven | 3.9.x | anywhere; put its `bin` on PATH |
| Flutter | stable | anywhere; put its `bin` on PATH |
| Git | latest | installs **Git Bash**, which you will use for git commands |

`SETUP_XE11G.md` in this repository walks through the Oracle install
step by step, including the one screen people get wrong.

After installing, check each one in a **new** Command Prompt. A window
opened before you changed PATH will not see the change:

```bat
mvn -v
```
```bat
flutter --version
```

`sqlplus` is usually **not** on PATH. That is fine — every command in
this guide gives its full path. If you would rather type just
`sqlplus`, add this folder to your PATH:

```
C:\oraclexe\app\oracle\product\11.2.0\server\bin
```

### 1.2 Create the database user

Open Command Prompt **as Administrator** and start Oracle:

```bat
net start OracleServiceXE
```
```bat
net start OracleXETNSListener
```

Connect as SYSTEM, using the password you chose during the Oracle
install:

```bat
C:\oraclexe\app\oracle\product\11.2.0\server\bin\sqlplus system@localhost:1521/XE
```

Then, at the `SQL>` prompt, create the schema user the project uses:

```sql
CREATE USER timebank IDENTIFIED BY timebank;
GRANT CONNECT, RESOURCE TO timebank;
GRANT CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER, CREATE SEQUENCE TO timebank;
ALTER USER timebank QUOTA UNLIMITED ON USERS;
EXIT;
```

`timebank/timebank` is a throwaway local password. It is committed in
`api/src/main/resources/db.properties` on purpose, so nobody has to
configure anything. **Never put a real password in this repository.**

### 1.3 Get the code

Open **Git Bash** (not Command Prompt — git is usually not on the
Command Prompt PATH) and clone into your Desktop:

```bash
cd ~/Desktop
```
```bash
git clone https://github.com/namitg105/TimeBank.git
```

You now have `C:\Users\<you>\Desktop\TimeBank`.

> Everywhere below says `C:\Users\gnami\Desktop\TimeBank`. Replace
> `gnami` with your own Windows username.

### 1.4 Build the database

This creates the tables, triggers, the PL/SQL package and the sample
data, then runs all five members' query files:

```bat
cd C:\Users\gnami\Desktop\TimeBank\sql
```
```bat
C:\oraclexe\app\oracle\product\11.2.0\server\bin\sqlplus timebank/timebank@localhost:1521/XE "@rerun.sql"
```

**What a good run looks like**

- `no rows selected` under *Checking for invalid objects* — everything
  compiled
- the audit printing **`RESULT: BALANCED`**
- exactly **four** `ORA-` lines, which are deliberate: two `ORA-20001`
  (the ledger refusing to be edited) and two more that member files
  raise on purpose

Any other `ORA-` is a real failure. Read it rather than carrying on.

### 1.5 Download the Flutter packages

```bat
cd C:\Users\gnami\Desktop\TimeBank\timebank
```
```bat
flutter pub get
```

---

## 2. Taking a pull

Do this whenever someone says there are new changes. Use **Git Bash**.

**Step 1 — check you have nothing half-finished:**

```bash
cd ~/Desktop/TimeBank
```
```bash
git status
```

If it lists files under *Changes not staged for commit*, deal with them
first — see section 5. If it says *nothing to commit, working tree
clean*, carry on.

**Step 2 — pull:**

```bash
git pull origin main
```

**Step 3 — react to what changed.** Read the file names git printed:

| If the pull touched | Then run |
|---|---|
| anything in `sql/` | rebuild the database (section 1.4) — **required**, or the API will call procedures that no longer match |
| anything in `api/` | nothing special; starting the API rebuilds it |
| anything in `timebank/` | `flutter pub get` if `pubspec.yaml` changed; otherwise nothing |

When in doubt, rebuilding the database is always safe. It only ever
touches the `TIMEBANK` schema on your own laptop.

---

## 3. Starting the system, every time

Three windows, in this order. Only the first needs Administrator.

### Window 1 — Oracle's listener (Administrator)

The database service starts with Windows on its own. The **listener**
usually does not, and without it you get `ORA-12541: TNS:no listener`.

```bat
net start OracleXETNSListener
```

If it says *the service has already been started*, good — skip it.
You only need this once per restart of Windows.

### Window 2 — the API. Keep this one visible; the SQL appears here

```bat
cd C:\Users\gnami\Desktop\TimeBank\api
```
```bat
mvn spring-boot:run
```

Wait for the line `Started TimeBankApiApplication`. It listens on
**port 8081** (8080 belongs to Oracle's own APEX page).

### Window 3 — the app

```bat
cd C:\Users\gnami\Desktop\TimeBank\timebank
```
```bat
flutter run -d chrome
```

Chrome opens by itself after a minute or so.

### Optional window 4 — watching the rows

Handy during a demo: run this before and after an action and show the
rows change.

```bat
cd C:\Users\gnami\Desktop\TimeBank\sql
```
```bat
C:\oraclexe\app\oracle\product\11.2.0\server\bin\sqlplus timebank/timebank@localhost:1521/XE
```

Then at the `SQL>` prompt:

```sql
@check.sql
```

### Stopping everything

Press `Ctrl + C` in the API and app windows, or just close them. Leave
Oracle running — it is a Windows service and costs you nothing.

---

## 4. Checking it worked

**Is the API alive?** Open this in a browser:

```
http://localhost:8081/api/students
```

A page of JSON means the whole chain works: browser → Spring Boot →
JDBC → Oracle.

**Signing in to the app**

| Who | How |
|---|---|
| Student | a registration number: `25BCE1001` (Aarav, a tutor), `25BCE1002` (Diya, a learner), `25BCE1003` (Kabir, who is both) |
| Administrator | username `namit`, password `timebank@2026` |

**Your own queries.** Each member's SELECTs live in their own file.
Run yours from the SQL\*Plus window after a `@rerun.sql`:

| Member | File |
|---|---|
| 1 — onboarding and profiles | `@onboarding.sql` |
| 2 — subjects and free hours | `@07_member2_skills.sql` |
| 3 — the booking engine | `@08_member3_booking.sql` |
| 4 — credits and the ledger | `@09_member4_credit.sql` |
| 5 — reviews and complaints | `@10_member5_feedback_disputes.sql` |
| everyone — COMMIT / ROLLBACK, query plans | `@11_group_tcl_plans.sql` |

Run them **in that order**. Later files use rows the earlier ones
create, so a file run on its own may fail or come back empty.

---

## 5. Sending your own work back

**Commit as yourself.** Set your name once per laptop, in Git Bash:

```bash
git config --global user.name "Your Name"
```
```bash
git config --global user.email "your.email@example.com"
```

**Then, each time you finish something:**

```bash
git pull origin main
```
```bash
git add .
```
```bash
git commit -m "What you changed, in a sentence"
```
```bash
git push origin main
```

Pull **before** you push. If you push without pulling, git refuses and
tells you the branch is behind.

**If git reports a conflict**, it has marked the clash inside the file
with `<<<<<<<` and `>>>>>>>`. Open it, keep the version that is right,
delete the markers, then `git add` that file and commit. Ask in the
group before guessing — a bad merge in `sql/` breaks everyone's build.

**Never commit:** your Oracle SYSTEM password, anything from `target/`
or `build/`, or screenshots of a run. `.gitignore` already blocks the
build folders.

---

## 6. When something goes wrong

| What you see | What it means | What to do |
|---|---|---|
| `ORA-12541: TNS:no listener` | the listener is not running | `net start OracleXETNSListener` as Administrator |
| `ORA-01017: invalid username/password` | the `timebank` user does not exist yet | do section 1.2 |
| `'mvn' is not recognized` | PATH was set after this window opened | close it, open a new Command Prompt |
| `'sqlplus' is not recognized` | Oracle's bin is not on PATH | use the full path, as written above |
| `Port 8081 was already in use` | an API from an earlier run is still alive | close that window, or restart the machine |
| Every screen in the app says it cannot reach the server | the API window is closed, or still starting | look at the API window — it says what went wrong |
| `ORA-00001: unique constraint` while running a member file | that file was already run once | rebuild with `@rerun.sql`, then run the files in order |
| `SP2-0640: Not connected` | SQL\*Plus opened without signing in | `CONNECT timebank/timebank@localhost:1521/XE` |
| Red squiggles on Java imports in VS Code | Maven has not downloaded the jars yet | run `mvn -q clean compile` once in `api/` |
| The app shows old behaviour after a pull | the API is still running yesterday's build | stop it, then `mvn -q clean compile` and start it again |

Still stuck? Copy the **last 20 lines of the API window** into the
group chat. That window names the exact statement and the Oracle error,
which is almost always enough to spot the cause.

---

## The one-paragraph version

Pull in Git Bash with `git pull origin main`. If anything under `sql/`
changed, rebuild the database with `@rerun.sql`. Then open three
Command Prompts: `net start OracleXETNSListener` as Administrator,
`mvn spring-boot:run` in `api\`, and `flutter run -d chrome` in
`timebank\`. Watch the API window — that is where the SQL shows up.
