# TimeBank — A Peer Tutoring Credit Exchange Management System

BACSE202 Database Systems mini project

One hour of tutoring given earns one credit. One hour received costs one
credit. No money changes hands, and the ledger proves the economy stays
closed.

---

## Repository layout

```
TimeBank/
├── sql/           Oracle: schema, triggers, PL/SQL package, 40 queries
├── api/           Spring Boot REST service — this is the JDBC layer
├── console-app/   Java console front end (backup demo, no GUI needed)
└── timebank/      The Flutter app
```

## How the three tiers fit together

```
Flutter app  ──HTTP/JSON──►  Spring Boot  ──JDBC──►  Oracle
 timebank/                     api/                   sql/
```

**Flutter cannot use JDBC.** JDBC is a Java API and there is no Oracle
driver for Dart, so a Dart program has no way to open an Oracle
connection. The JDBC work is real and graded — it happens in `api/`,
which uses plain `PreparedStatement` and `CallableStatement` against
Oracle's thin driver. The Flutter app is the presentation tier.

`console-app/` is the same DAO layer behind a terminal menu. It needs no
emulator and no API running, so it is the safe fallback if anything goes
wrong during the demo.

---

## Running it, in order

### 1. Oracle

Install **Oracle AI Database Free**, or run it in Docker:

```bash
docker run -d --name oracle-free -p 1521:1521 \
  -e ORACLE_PWD=YourSysPassword \
  container-registry.oracle.com/database/free:latest
```

Create the schema user (connect as SYSTEM to `FREEPDB1`):

```sql
CREATE USER timebank IDENTIFIED BY timebank;
GRANT CONNECT, RESOURCE TO timebank;
GRANT CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER, CREATE SEQUENCE TO timebank;
ALTER USER timebank QUOTA UNLIMITED ON USERS;
```

Build the database:

```bash
cd sql
sqlplus timebank/timebank@//localhost:1521/FREEPDB1 @run_all.sql
```

The script ends by listing invalid objects. **No rows means everything
compiled.** It also prints the closed-economy audit, which should read
`BALANCED`.

### 2. The API

```bash
cd api
mvn spring-boot:run
```

Confirm it is alive:

```bash
curl http://localhost:8080/api/ledger/audit
```

### 3. The Flutter app

```bash
cd timebank
flutter pub get
flutter analyze      # do this before running
flutter run
```

**The thing that catches people out:** inside an Android emulator,
`localhost` means the emulator itself, not your laptop. The app already
handles this — `ApiClient.defaultBaseUrl` uses `10.0.2.2` on Android. On
a *real phone* you need your laptop's LAN address instead:

```dart
// lib/main.dart
await initDependencies(baseUrl: 'http://192.168.1.14:8080');
```

Both devices must be on the same Wi-Fi.

---

## What is graded, and where it lives

| Rubric component | Where |
|---|---|
| ER diagram and relational mapping | the A3 sheets |
| DDL, constraints, integrity | `sql/01_ddl.sql` |
| DML and population | `sql/05_seed.sql` |
| 18+ queries across members | `sql/06_` to `sql/11_` — **40 queries** |
| TCL (COMMIT / ROLLBACK / SAVEPOINT) | `sql/12_tcl_and_plans.sql` part A |
| Front end with JDBC connectivity | `api/` + `timebank/` (or `console-app/`) |

### Query inventory

| Member | Module | Queries |
|---|---|---|
| 1 | Onboarding and profiles | 3 DML + 6 SELECT |
| 2 | Skills and availability | 3 DML + 6 SELECT |
| 3 | Booking engine | 3 DML + 6 SELECT |
| 4 | Escrow and ledger | 3 DML + 6 SELECT |
| 5 | Feedback and reputation | 3 DML + 6 SELECT |
| 6 | Disputes and analytics | 3 DML + 7 SELECT |

Every member's set covers a simple query, a multi-table join, a nested
subquery, a correlated subquery, an aggregate with `GROUP BY`/`HAVING`,
and an analytic function.

---

## Three design decisions worth defending in the viva

**The specialization is overlapping and partial, so mapping option 8A is
the only correct one.** A student can tutor Physics and be tutored in
databases — Kabir (105) and Arjun (109) in the seed data are in both
subclass tables. Sara (108) starts in neither. Option 8B would duplicate
the shared columns for anyone in both, and would have nowhere to put
Sara.

**`BOOKING` has two composite foreign keys that share `tutor_id`:**

```sql
FOREIGN KEY (tutor_id, slot_no)    REFERENCES slot        (tutor_id, slot_no)
FOREIGN KEY (tutor_id, subject_id) REFERENCES tutor_skill (tutor_id, subject_id)
```

Because the same column feeds both, the database guarantees the booked
slot belongs to *that* tutor and the subject is one *that* tutor offers.
No trigger needed.

**Derived attributes are not stored.** `CreditBalance`, `Age`,
`TotalHoursTaught`, `AvgRatingAsTutor` and slot `Duration` are all
computed — see `v_student_balance`, `v_tutor_profile` and
`v_slot_detail`. The one controlled redundancy is `balance_snapshot`,
kept for auditing and never updated.

---

## How a session works

| Step | What happens | Ledger row |
|---|---|---|
| 1 | Tutee books | `HOLD` −1.5 — tutee debited now |
| 2 | Tutor enters the tutee's session code | — |
| 3 | Both confirm | `TRANSFER` +1.5 — tutor paid |

The tutee is debited **once**, at booking. Completion writes only the
positive transfer; a second negative row would charge them twice.

### The audit

At every moment:

```
sum of all balances + credits held in escrow = total granted − total penalised
```

`EXEC pkg_timebank.audit_economy` checks it. On the seed data both sides
come to **35.0**.

---

## Worth screenshotting for the report

1. `run_all.sql` finishing with no invalid objects
2. The audit reporting `BALANCED`
3. **The two-session concurrency demo** (`sql/12_tcl_and_plans.sql`
   part B) — session 2 visibly hanging on session 1's row lock, then
   failing once session 1 commits. This is the strongest exhibit in the
   project.
4. The two ledger-tamper attempts in `sql/09_member4_credit.sql` both
   failing with ORA-20001
5. `EXPLAIN PLAN` with and without the index, costs side by side
6. The Flutter app booking a session and showing the session code
