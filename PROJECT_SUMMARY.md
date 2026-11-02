# TimeBank — Complete Project Summary

**A Peer Tutoring Credit Exchange Management System**
BACSE202 Database Systems · VIT · Fall Semester 2026-27
Repository: `github.com/namitg105/TimeBank` · Lead: **Namit Gupta (25BDE0068)**

> Students teach each other and pay in **hours instead of money**. One hour of teaching earns one credit; one hour of learning spends one. The database guarantees the books always balance.

---

## Table of contents

1. [The idea in one minute](#1-the-idea-in-one-minute)
2. [Architecture](#2-architecture)
3. [Repository layout](#3-repository-layout)
4. [The database](#4-the-database)
5. [The five member modules](#5-the-five-member-modules)
6. [The REST API](#6-the-rest-api)
7. [The Flutter app](#7-the-flutter-app)
8. [Sign-in, roles and the admin account](#8-sign-in-roles-and-the-admin-account)
9. [Live SQL in the API terminal](#9-live-sql-in-the-api-terminal)
10. [How to run everything](#10-how-to-run-everything)
11. [Demo script for the review](#11-demo-script-for-the-review)
12. [Troubleshooting](#12-troubleshooting)
13. [Git, branches and commits](#13-git-branches-and-commits)
14. [Design rules we followed](#14-design-rules-we-followed)
15. [Decisions and fixes log](#15-decisions-and-fixes-log)
16. [Viva questions with answers](#16-viva-questions-with-answers)
17. [Known limitations and next steps](#17-known-limitations-and-next-steps)

---

## 1. The idea in one minute

| Problem | TimeBank's answer |
|---|---|
| Good students help friends for free and burn out | Teaching earns credits they can spend on subjects *they* are weak in |
| Paid tutoring excludes students without money | The currency is time, and everyone starts with the same opening balance |
| Informal help has no record, no accountability | Every session, rating, complaint and credit movement is stored and auditable |
| Credits could be faked | Credits only move inside a PL/SQL procedure; the ledger is append-only; a trigger refuses edits |

A student can be a **tutor**, a **tutee**, or **both** (overlapping specialization). A session goes:

```
book (credits set aside)  →  check-in with code  →  session ends  →  tutee confirms
     →  credits transferred to tutor  →  both sides review  →  (optional) complaint
```

---

## 2. Architecture

```
┌──────────────────────┐   HTTP / JSON    ┌───────────────────────────┐    JDBC     ┌──────────────────────┐
│  Flutter (Chrome)    │ ───────────────▶ │  Spring Boot API :8081    │ ──────────▶ │  Oracle XE 11g  :1521 │
│  timebank/           │ ◀─────────────── │  api/                     │ ◀────────── │  schema TIMEBANK      │
│  screens, no SQL     │                  │  controllers → DAOs → SQL │             │  tables, triggers,    │
└──────────────────────┘                  │  prints every statement   │             │  PKG_TIMEBANK         │
                                          └───────────────────────────┘             └──────────────────────┘
```

**Why three tiers?** Dart has no Oracle driver; JDBC is a Java API. The Spring Boot service is the bridge, and it is where all the real SQL lives — which is exactly what the DBMS course grades.

| Layer | Technology | Version / setting |
|---|---|---|
| Database | Oracle Database XE 11g | service `XE`, port 1521, user `timebank/timebank` |
| Driver | ojdbc8 + UCP connection pool | 19.23.0.0 (pinned via `oracle-database.version` in `pom.xml`) |
| API | Spring Boot (plain JDBC, no JPA) | 3.3.5, **port 8081** (8080 belongs to Oracle APEX) |
| Java | JDK | 26.0.1 at `C:\Program Files\Java\jdk-26.0.1` |
| Build | Maven | 3.9.9 at `%USERPROFILE%\tools\apache-maven-3.9.9` |
| App | Flutter web (Chrome) | SDK at `C:\flutterdev\fluttersdk\flutter` |
| State | flutter_bloc + get_it | clean architecture for students / bookings / ledger |

---

## 3. Repository layout

```
TimeBank/
├── PROJECT_SUMMARY.md        ← this file
├── README.md                 project overview
├── RUNBOOK.md                cold-start guide, step by step
├── DBMS_GUIDE.md             study + viva guide (normalization, EER, indexing, TCL…)
├── SETUP_XE11G.md            installing Oracle XE 11g and creating the user
├── START_DEMO.bat            opens Oracle / API / SQL*Plus / Flutter windows (run as admin)
├── out_member1.txt           spooled output of Member 1's file
├── main.dart.flutter-default.bak
├── console-app/              early Java console prototype (not part of the build)
│
├── sql/                      ── the DBMS deliverable ──
│   ├── 00_drop_all.sql       drop everything (safe to rerun)
│   ├── 01_ddl.sql            14 tables, 6 sequences, 3 views, all constraints
│   ├── 02_indexes.sql        6 B+ tree indexes + CREDIT_POLICY table
│   ├── 03_triggers.sql       6 business-rule triggers
│   ├── 04_packages.sql       PKG_TIMEBANK (2 functions, 8 procedures)
│   ├── 05_seed.sql           92 INSERTs — departments, students, subjects, history
│   ├── onboarding.sql        Member 1
│   ├── 07_member2_skills.sql Member 2
│   ├── 08_member3_booking.sql Member 3
│   ├── 09_member4_credit.sql Member 4
│   ├── 10_member5_feedback_disputes.sql Member 5
│   ├── 11_group_tcl_plans.sql  COMMIT / SAVEPOINT / ROLLBACK + EXPLAIN PLAN
│   ├── 12_inspect_database.sql data-dictionary queries (USER_TABLES, USER_CONSTRAINTS…)
│   ├── QUERY_PLAN.md         execution plans explained
│   ├── run_all.sql           first-time build
│   ├── rerun.sql             drop + rebuild + all member files, spools demo_output.txt
│   └── check.sql             quick look: row counts, newest students, ledger, audit
│
├── api/                      ── Spring Boot JDBC service ──
│   ├── pom.xml
│   └── src/main/
│       ├── resources/application.properties   port, admin credential
│       ├── resources/db.properties            JDBC url, user, password
│       └── java/com/timebank/
│           ├── api/TimeBankApiApplication.java   entry point + CORS for /api/**
│           ├── api/dto/        Requests.java, Responses.java
│           ├── api/web/        10 controllers + ApiError, GlobalExceptionHandler, RequestBanner
│           ├── dao/            8 DAOs — every SQL statement in the API lives here
│           ├── db/             Database.java (pool), SqlLog.java (terminal tracer)
│           └── model/          Booking, LedgerEntry, Student
│
└── timebank/                 ── Flutter app ──
    ├── pubspec.yaml
    └── lib/
        ├── main.dart                 WelcomePage / StudentShell / AdminShell
        ├── core/                     di, error, network/api_client.dart, theme, usecase
        ├── shared/widgets/           app_widgets.dart
        └── features/
            ├── auth/       welcome, student sign-in/up, admin sign-in, session
            ├── profile/    "Me" tab
            ├── students/   admin student list, register, deactivate      (clean arch)
            ├── skills/     subjects, skills, free hours
            ├── bookings/   sessions, book, check-in, confirm, cancel      (clean arch)
            ├── ledger/     passbook, audit, leaderboard                   (clean arch)
            └── admin/      complaints, accounts, suspicious pairs
```

---

## 4. The database

### 4.1 Tables (15)

| # | Table | Type | Key | Purpose |
|---|---|---|---|---|
| 1 | `DEPARTMENT` | strong | `dept_id` | SCOPE, SENSE, SELECT… |
| 2 | `STUDENT` | strong (superclass) | `student_id` (surrogate), `reg_no` UNIQUE (natural) | everyone; `is_active` for soft delete |
| 3 | `STUDENT_PHONE` | multivalued attribute | `(student_id, phone)` | 1NF: phones moved out of STUDENT |
| 4 | `TUTOR` | subclass | `tutor_id` → STUDENT | badge, rate, hours taught |
| 5 | `TUTEE` | subclass | `tutee_id` → STUDENT | learning profile |
| 6 | `TUTEE_PREFTIME` | multivalued attribute | `(tutee_id, pref_day, …)` | preferred study times |
| 7 | `SUBJECT` | strong | `subject_id`, `code` UNIQUE | BACSE202, BMAT201… |
| 8 | `TUTOR_SKILL` | M:N associative | `(tutor_id, subject_id)` | who teaches what, at what proficiency |
| 9 | `SLOT` | **weak** (owner TUTOR) | `(tutor_id, slot_no)` | a tutor's weekly free hours |
| 10 | `BOOKING` | strong (ternary relationship made an entity) | `booking_id` | tutor × tutee × subject × time |
| 11 | `FEEDBACK` | **weak** (owner BOOKING) | `(booking_id, reviewer_role)` | one review per side |
| 12 | `ADMIN` | strong | `admin_id` | who resolves complaints |
| 13 | `DISPUTE` | **weak** (owner BOOKING) | `(booking_id, dispute_no)` | any number of complaints |
| 14 | `CREDIT_TXN` | append-only ledger | `txn_id` | every credit movement ever |
| 15 | `CREDIT_POLICY` | config | — | opening balance, rates (in 02_indexes.sql) |

**Sequences:** `seq_dept`, `seq_student` (start 1000), `seq_subject`, `seq_booking`, `seq_txn`, `seq_admin`.

**Views:** `v_student_balance` (derived balance = SUM of ledger), `v_tutor_profile`, `v_slot_detail`.

### 4.2 Constraints used (syllabus Module 1 topics 6–7)

| Kind | Example |
|---|---|
| Domain / CHECK | `rating BETWEEN 1 AND 5`, `status IN ('BOOKED','CHECKED_IN','COMPLETED','CANCELLED')`, `end_time > start_time` |
| Key | primary keys on all tables; `UQ_STUDENT_REG` on `reg_no` |
| NOT NULL | names, reg_no, booking times |
| Entity integrity | no PK column can be NULL |
| Referential integrity | every FK, e.g. `BOOKING.tutor_id → TUTOR`, `SLOT.tutor_id → TUTOR ON DELETE CASCADE` |
| Constraint violations | demonstrated deliberately in member files (ORA-00001, ORA-02291, ORA-02292, ORA-20001) |

### 4.3 Indexes (`02_indexes.sql`) — B+ trees

| Index | Columns | Speeds up |
|---|---|---|
| `idx_skill_subject` | `tutor_skill(subject_id)` | "who teaches DBMS?" |
| `idx_txn_student_time` | `credit_txn(student_id, txn_time)` | passbook |
| `idx_booking_tutor` / `idx_booking_tutee` | `booking(tutor_id)` / `(tutee_id)` | "my sessions" |
| `idx_booking_sched` | `booking(scheduled_start)` | clash checks, upcoming list |
| `idx_dispute_open` | `dispute(status)` | complaint queue |

### 4.4 Triggers (`03_triggers.sql`)

| Trigger | Rule it enforces |
|---|---|
| `trg_txn_immutable` | `CREDIT_TXN` can never be UPDATEd or DELETEd → raises **ORA-20001** |
| `trg_credit_floor` | a student's balance cannot go below the floor |
| `trg_confirm_after_end` | a session can only be confirmed after it has ended |
| `trg_booking_fits_slot` | a booking must fall inside one of the tutor's free hours |
| `trg_feedback_valid` | only completed sessions can be reviewed, by a real participant |
| `trg_badge_promote` | auto-promote a tutor's badge as hours taught grow |

### 4.5 Package `PKG_TIMEBANK` (`04_packages.sql`)

| Routine | What it does |
|---|---|
| `fn_balance(student_id)` | current credits (derived attribute) |
| `fn_hours_taught(tutor_id)` | derived attribute |
| `enrol_student` | add STUDENT + TUTOR/TUTEE rows + opening credit in one transaction |
| `book_session` | clash checks, inserts BOOKING, posts **HOLD** (credits set aside) |
| `check_in` | verifies the session code, moves to CHECKED_IN |
| `confirm_session` | releases the hold and posts one **TRANSFER** to the tutor |
| `cancel_booking` | releases the hold back to the tutee |
| `raise_dispute` / `resolve_dispute` | complaint lifecycle, with refunds as compensating rows |
| `audit_economy` | proves total credits issued = total credits held → prints **BALANCED** |
| `post_txn` (private) | the only code allowed to INSERT into CREDIT_TXN |

### 4.6 Seed data (`05_seed.sql`)

92 INSERTs: departments, ~15 students (`25BCE1001…25BCE1005`, `25BME2001`, `25BEE3001`, `25BAS4001`, `25BBS5001`…), subjects (`BACSE202` Database Systems, `BACSE203` Networks, `BACSE201` TOC, `BMAT201`, `BPHY101`, `BEEE202`, `BMEE201`, `BMGT101`), skills, slots, past bookings, reviews, disputes and a balanced ledger.

### 4.7 EER concepts shown (syllabus Module 2)

- **Specialization**: STUDENT → TUTOR, TUTEE — *overlapping* (one person can be both) and *partial* (a student may be neither yet)
- **Weak entities**: SLOT, FEEDBACK, DISPUTE — each with a different kind of partial key (counter, role, counter)
- **M:N**: TUTOR_SKILL with relationship attributes (proficiency)
- **Multivalued**: STUDENT_PHONE, TUTEE_PREFTIME
- **Derived**: age (from DOB), balance (from ledger), hours taught
- **Normalization**: all tables in 3NF/BCNF; reasoning in `DBMS_GUIDE.md`

---

## 5. The five member modules

Each member owns tables, a SQL file, API code and screens. Every SQL file follows the brief: DML first (INSERT / UPDATE / DELETE), then SELECTs of increasing difficulty.

| Member | Module | Tables owned | SQL file | INS / UPD / DEL / SEL |
|---|---|---|---|---|
| **1 — Namit** | Onboarding, roles, profiles | STUDENT, STUDENT_PHONE, DEPARTMENT, TUTOR, TUTEE | `onboarding.sql` | 2 / 2 / 1 / 6 |
| **2 — Namit** | Skills, subjects, availability | SUBJECT, TUTOR_SKILL, SLOT, TUTEE_PREFTIME | `07_member2_skills.sql` | 4 / 1 / 1 / 7 |
| **3** | Booking lifecycle | BOOKING | `08_member3_booking.sql` | 2 / 1 / 1 / 7 |
| **4** | Credits, ledger, audit | CREDIT_TXN, CREDIT_POLICY | `09_member4_credit.sql` | 1 / 4 / 2 / 7 |
| **5** | Feedback, disputes, fraud | FEEDBACK, DISPUTE, ADMIN | `10_member5_feedback_disputes.sql` | 1 / 1 / 2 / 10 |
| Group | TCL + query plans | — | `11_group_tcl_plans.sql` | 2 / 0 / 0 / 15 |

### Member 1 — Onboarding (Namit)

- **In the app:** student sign-up, sign-in by registration number, Me tab (profile, phones add/remove, balance), become tutor / tutee, admin deactivate / reactivate.
- **SQL highlights:** `enrol_student` procedure (STUDENT + subclass + opening credit atomically); soft delete via `UPDATE student SET is_active = 'N'` (never DELETE — ledger rows reference the student); phone multivalued attribute; outer joins to list students with *or without* a role; age as a derived attribute.
- **Code:** `AuthDao`, `StudentDao`, `RoleDao`, `StudentLookup`, `AuthController`, `StudentController`, `RoleController`; Flutter `auth/`, `profile/`, `students/`.

### Member 2 — Skills and availability (Namit)

- **In the app:** Subjects tab — subject catalogue, add a skill with proficiency, update proficiency, add/remove free hours (slots), skill matrix, gaps (subjects nobody teaches), tutor capacity.
- **SQL highlights:** weak entity SLOT with `slot_no = MAX+1` per tutor; M:N TUTOR_SKILL; `GROUP BY … HAVING` for coverage; anti-join (`NOT EXISTS`) for subject gaps; `ON DELETE CASCADE` from TUTOR to SLOT.
- **Code:** `SkillsDao`, `SkillsController`; Flutter `skills/skills_page.dart`.

### Member 3 — Booking

- **In the app:** Sessions tab — book (choose learn/teach, the other person by reg no, subject, pick a free hour), session code, check-in, confirm, cancel; admin can clear abandoned bookings.
- **SQL highlights:** `book_session` with overlap check `(start < other_end AND end > other_start)`; status state machine via CHECK; `trg_booking_fits_slot`; `trg_confirm_after_end`.
- **Code:** `BookingDao`, `BookingController`, `GuidedBookingController`; Flutter `bookings/`.

### Member 4 — Credits

- **In the app:** Credits tab — passbook (running balance), admin audit (BALANCED / not), adjustments as compensating rows, leaderboard; "prove the ledger can't be edited" button (triggers ORA-20001 safely).
- **SQL highlights:** escrow pattern (HOLD then a single TRANSFER); `SUM(...) OVER (ORDER BY txn_time)` running balance; closed-economy audit; append-only trigger.
- **Code:** `LedgerDao`, `LedgerController`, `AdminDao.proveImmutable`; Flutter `ledger/`.

### Member 5 — Feedback, disputes and fraud

- **In the app (main):** Complaints tab — queue, mark as being looked into, rule on it (refund / no refund), suspicious pairs (collusion detector).
- **Separate branch `member5-feedback-disputes`:** full Reviews and Disputes screens (`reviews_page.dart`, `disputes_page.dart`), `FeedbackDao`, `FeedbackController` (`/api/feedback`), plus `README_MEMBER5.md` and `MEMBER5_GUIDE.md` written so the teammate can run it with no Flutter knowledge.
- **SQL highlights:** composite PK `(booking_id, reviewer_role)`; FEEDBACK self-join with OUTER joins (student's view vs tutor's view); **collusion detector** — BOOKING self-join finding pairs who tutor each other both ways with 5-star reviews, `b1.tutor_id < b1.tutee_id` to report each pair once.

---

## 6. The REST API

Base URL: `http://localhost:8081`. All responses are JSON; errors come back as `{ "message": "plain sentence" }` via `GlobalExceptionHandler`.

| Controller | Method & path | Member | Does |
|---|---|---|---|
| **Auth** | `POST /api/auth/login` | 1 | sign in with registration number |
| | `POST /api/auth/signup` | 1 | create account (calls `enrol_student`) |
| | `POST /api/auth/admin` | 1 | admin sign-in (credential from properties) |
| | `GET /api/auth/departments` | 1 | department dropdown |
| **Students** | `GET /api/students` · `GET /search` | 1 | list / search |
| | `POST /api/students` | 1 | register (admin) |
| | `GET /api/students/{id}/balance` | 1/4 | balance |
| | `DELETE /api/students/{id}` | 1 | **soft** delete (an UPDATE) |
| | `POST /{id}/phones` · `DELETE /{id}/phones/{phone}` | 1 | multivalued phones |
| **Roles** | `GET /api/roles/{studentId}` · `GET /subjects` | 1 | what roles a student has |
| | `POST /{id}/tutor` · `/{id}/tutee` | 1 | become tutor / tutee |
| | `POST /{id}/skills` · `/{id}/slots` | 2 | first skill / slot while enrolling |
| **Skills** | `GET /api/skills/subjects` · `/matrix` · `/gaps` · `/capacity` | 2 | catalogue and reports |
| | `GET /api/skills/slots/{ref}` | 2 | a tutor's free hours (**accepts reg no or id**) |
| | `POST /slots/{tutorId}` · `DELETE /slots/{tutorId}/{slotNo}` | 2 | add / remove free hour |
| | `POST /{tutorId}` · `PUT /{tutorId}/{subjectId}` | 2 | add skill / change proficiency |
| **Bookings** | `GET /api/bookings` · `GET /student/{id}` | 3 | all / mine |
| | `POST /api/bookings` | 3 | book by ids |
| | `POST /api/bookings/guided` | 3 | book by **registration numbers**; enrols tutor/tutee role if missing |
| | `POST /{id}/checkin` · `/{id}/confirm` · `/{id}/cancel` | 3/4 | lifecycle |
| | `DELETE /api/bookings/abandoned` | 3 | clean up never-started bookings |
| **Ledger** | `GET /api/ledger/student/{id}` | 4 | passbook |
| | `GET /audit` · `GET /leaderboard` | 4 | audit, top tutors |
| | `POST /adjustments` | 4 | compensating entry |
| | `GET /collusion` | 5 | suspicious pairs |
| **Admin** | `GET /api/admin/accounts` · `GET /disputes` | 5 | overview, complaint queue |
| | `POST /disputes/{b}/{n}/triage` · `/resolve` | 5 | complaint workflow |
| | `POST /api/admin/prove-immutable` | 4 | demonstrates ORA-20001 |

### Java classes

| Package | Classes |
|---|---|
| `api` | `TimeBankApiApplication` |
| `api.dto` | `Requests`, `Responses` (records) |
| `api.web` | `AuthController`, `StudentController`, `RoleController`, `SkillsController`, `BookingController`, `GuidedBookingController`, `LedgerController`, `AdminController`, `ApiError`, `GlobalExceptionHandler`, `RequestBanner` |
| `dao` | `AuthDao`, `StudentDao`, `RoleDao`, `SkillsDao`, `BookingDao`, `LedgerDao`, `AdminDao`, `StudentLookup` |
| `db` | `Database` (UCP pool, `showAfter` read-backs), `SqlLog` (terminal tracer) |
| `model` | `Student`, `Booking`, `LedgerEntry` |

**`StudentLookup`** turns whatever the user typed into a `student_id`: all digits → checked id; otherwise `WHERE UPPER(reg_no) = UPPER(?)`. That's why every form accepts `25BDE0068`. (Surrogate key for joins, natural key for humans.)

---

## 7. The Flutter app

### 7.1 Screens

**Welcome** → "I'm a student" or "I am the administrator".

**Student shell** (bottom tabs):

| Tab | Page | What the student does |
|---|---|---|
| Me | `profile_page.dart` | profile, phones, balance, become tutor/tutee |
| Subjects | `skills_page.dart` | what I teach, add skills, my free hours |
| Sessions | `bookings_page.dart`, `book_session_page.dart` | my sessions only: book; the tutor enters the code; each side confirms or cancels its own side |
| Credits | `ledger_page.dart` | my own passbook (nobody else's) |

**Admin shell**:

| Tab | Page | What the admin does |
|---|---|---|
| Students | `students_page.dart`, `register_student_page.dart` | everyone, register, deactivate / reactivate |
| Subjects | `skills_page.dart` | catalogue, matrix, gaps, capacity |
| Sessions | `bookings_page.dart` | every session, clean up abandoned ones |
| Credits | `audit_page.dart` | audit, leaderboard, adjustments, ledger proof |
| Complaints | `admin_page.dart` | complaint queue, rulings, suspicious pairs |

### 7.2 Booking a session (latest flow)

1. Choose **I want to learn** or **I want to teach**.
2. Type the other person's registration number in **Who with** (your own comes from the session).
3. Pick the subject.
4. The **free-hours picker** loads the tutor's slots (`/api/skills/slots/{reg}`) — the other person when learning, yourself when teaching. Tapping one sets the day and start time.
5. Submit → `POST /api/bookings/guided`. If you lack the tutor/tutee role, it is created first, then the booking.

If you're teaching and have no free hours, the picker says so — add some in the Subjects tab first. (This replaced the old "slot number" box that caused *"Tutor 1003 has no slot number 13"*.)

### 7.3 Code structure

- **Clean architecture** (`data → domain → presentation`, datasource → repository → use case → Bloc) for `students`, `bookings`, `ledger`; wired in `core/di/injection.dart` with get_it.
- **Direct `ApiClient` calls** for `auth`, `profile`, `skills`, `admin` (simple forms; no Bloc needed).
- `core/network/api_client.dart` — base URL `http://localhost:8081`.
- `features/auth/session.dart` — `ValueNotifier<Session?> currentSession`; `main.dart` rebuilds on change. Auth pages call `Navigator.popUntil(isFirst)` after login so the home screen is visible (fix for "stuck on sign-in").
- Blocs are provided once above the shells so data survives tab switches; `IndexedStack` keeps scroll position.

---

## 8. Sign-in, roles and the admin account

| Who | How |
|---|---|
| Student | Registration number (e.g. `25BCE1001`, or your own after sign-up like `25BDE0068`) |
| New student | Sign up: name, reg no, email, department, DOB → `enrol_student` runs and is printed |
| Administrator | username **`namit`**, password **`timebank@2026`** (in `application.properties`, single admin by design) |

Mentor/mentee = tutor/tutee. A student becomes one from the Me tab, or automatically when they book.

---

## 9. Live SQL in the API terminal

Requirement from ma'am: *every click must show the query in the terminal and prove it reached the database.* `SqlLog` prints, for every statement:

```
──── POST /api/auth/signup ─────────────────────────────
MEMBER 1 . Create a student account
  BEGIN pkg_timebank.enrol_student(?, ?, ?, ?, ?, ?, ?); END;
  with: 25BDE0068, Namit, Gupta, ...
  inside the procedure:
    INSERT INTO student (...) VALUES (...)
    INSERT INTO credit_txn (...) VALUES (...)
  ✓ done in 14 ms
  now in the table:
    STUDENT_ID REG_NO     NAME
    1016       25BDE0068  Namit Gupta
```

- `RequestBanner` prints one line per HTTP request.
- Labels are plain English with the owning member ("MEMBER 2 . Add a free hour").
- `showAfter` re-reads the changed rows **after commit**, so the terminal shows the row is really in Oracle.
- No stack traces or framework noise for expected errors — a one-line reason instead.
- Cross-check anytime in SQL*Plus with `@check.sql`.

---

## 10. How to run everything

### First time only

```powershell
# Administrator PowerShell
net start OracleServiceXE
net start OracleXETNSListener

sqlplus system/<your SYSTEM password>@localhost:1521/XE
```
```sql
CREATE USER timebank IDENTIFIED BY timebank;
GRANT CONNECT, RESOURCE TO timebank;
GRANT CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER, CREATE SEQUENCE TO timebank;
ALTER USER timebank QUOTA UNLIMITED ON USERS;
EXIT;
```

### Every time (three windows)

**Window 1 — database (rebuild clean, no "already inserted" errors)**
```powershell
cd C:\Users\gnami\Desktop\TimeBank\sql
sqlplus timebank/timebank@localhost:1521/XE "@rerun.sql"
```
Expect: no invalid objects, audit prints **BALANCED**, and two intentional `ORA-20001` lines (the ledger refusing edits).

**Window 2 — API (keep open; this is where SQL appears)**
```powershell
cd C:\Users\gnami\Desktop\TimeBank\api
mvn -q clean compile
mvn spring-boot:run
```
Wait for `Started TimeBankApiApplication`. Test: open `http://localhost:8081/api/students`.

**Window 3 — app**
```powershell
cd C:\Users\gnami\Desktop\TimeBank\timebank
flutter pub get
flutter run -d chrome
```

The app talks to `http://localhost:8081` by default. To point it somewhere else (a phone on Wi-Fi, a second API on another port) without editing code, add `--dart-define=API_BASE_URL=http://192.168.1.14:8081`.

**Optional window 4 — watch the tables**
```powershell
cd C:\Users\gnami\Desktop\TimeBank\sql
sqlplus timebank/timebank@localhost:1521/XE
```
```sql
@check.sql
```

**Shortcut:** right-click `START_DEMO.bat` → Run as administrator.

---

## 11. Demo script for the review

1. Show `rerun.sql` finishing with **BALANCED**.
2. Sign up a new student → point at the INSERTs in the API window → `@check.sql` shows the row.
3. Add a phone, remove it (multivalued attribute, INSERT / DELETE).
4. Subjects → add a skill, add a free hour (weak entity, `slot_no` = next number).
5. Sessions → book with another student by reg no, pick a free hour → HOLD row in the ledger. The session code appears in a dialog — write it down.
6. Check in with the code → confirm → TRANSFER row; passbook shows running balance. **See "Finishing a session live" below** — a session can only be confirmed after it has ended.
7. Admin → Credits → audit still BALANCED; Complaints → "Check the protection" → the API window shows ORA-20001.
8. Admin → Students → deactivate (an UPDATE, not a DELETE — history stays).
9. Admin → Complaints → rule on a dispute; then **create a suspicious pair live** (below) and show the detector catching it.

Each member demos only their own rows of this list and their own SQL file.

### Finishing a session live

`trg_confirm_after_end` refuses to confirm a session before it has ended — correct, but it means a session booked for next week cannot be finished during the review. Book one in the **past** instead (the date picker allows up to 30 days back):

1. Sign in as **Diya (25BCE1002)** → Sessions → + → I am learning → tutor **25BCE1001** → Database Systems → tap the **Monday 16:00–18:00** hour, *then* change the date to last Monday → book. Note the code.
2. Each student only sees their own side's buttons, exactly as in real life:
   - Sign out, sign in as **Aarav (25BCE1001)** → Enter code → I confirm it happened.
   - Sign out, sign in as Diya → I confirm it happened → TRANSFER posted; both passbooks update.
3. Short on time? The **administrator's** Sessions tab can act for both sides on one screen.

### Creating a suspicious pair live

The seed data has no pair who tutored each other both ways, so "suspicious pairs" starts empty — which is correct. Aarav already taught Arjun (session 7). Make Arjun teach Aarav back:

1. Sign in as **Aarav (25BCE1001)** → book, I am learning, tutor **25BCE1005** (Arjun), Probability and Statistics, the **Thursday** hour, date = last Thursday.
2. Arjun enters the code and confirms; Aarav confirms (or do both from the admin Sessions tab).
3. Admin → Complaints → suspicious pairs → **Aarav Sharma ↔ Arjun Patel : 1 and 1 sessions**.

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Every screen errors / "can't reach server" | API window closed or still compiling | restart Window 2 |
| `Port 8080 was already in use` | old build; APEX owns 8080 | this build uses 8081 |
| `ORA-12541: no listener` | Oracle not started | `net start OracleXETNSListener` (admin) |
| `ORA-00001 unique constraint` | a member file run twice | use `@rerun.sql` |
| `SP2-0640: Not connected` | SQL*Plus opened without login | `CONNECT timebank/timebank@localhost:1521/XE` |
| `SP2-0734 unknown command` | PowerShell command typed inside SQL*Plus | `EXIT` first |
| `ORA-00911` running a script | `--` comment after `;` (SQL*Plus 11.2) | already fixed in all files |
| `mvn` not recognised | new window without PATH | PATH is now persisted; open a fresh window |
| Red imports in VS Code (Java) | Maven jars not downloaded yet | `mvn -q clean compile` once, then "Java: Clean Workspace" |
| pom "overrides version" warning | Oracle BOM versions | fixed with `oracle-database.version` property |
| Passbook 500 | Oracle returns `BigDecimal` | fixed — read as `Number` |
| "studentId is required" | API running an older build | stop API, `mvn -q clean compile`, run again |
| Stuck on sign-in page | pushed auth route covered home | fixed with `popUntil(isFirst)` |
| "Tutor X has no slot number N" | typed slot number | replaced by free-hours picker |
| Free hours never appear after typing the tutor | they loaded only on Enter | fixed — they also load when you click away |
| Session code flashes and vanishes after booking | form closed the code dialog instead of itself | fixed — form closes, then the list shows the code |
| A student saw everyone's sessions | list loaded `/api/bookings` | fixed — students load `/api/bookings/student/{id}` |
| "It cannot be confirmed before then" | the session has not ended yet (trigger rule) | book a past date to finish one live — see §11 |
| "foreign key" error when teaching a new subject / new student | skill or learner role was missing | fixed — both are created before booking |
| Two free hours overlapping on one day | no overlap check | fixed — refused with a sentence |
| "Check the protection" showed ORA-01438 | test value too big for `NUMBER(4,1)` | fixed — now proves ORA-20001 |
| `flutter analyze` | — | now reports **No issues found** |

---

## 13. Git, branches and commits

- **Author:** `NAMITG105 <namitg105@gmail.com>` on every commit; no tool attribution.
- **Push:** from your PowerShell — `git push origin main` (the cloud session has no GitHub credentials).

| Branch | Contents |
|---|---|
| `main` | full app: all five modules, no DB jargon in the UI |
| `member5-feedback-disputes` | Member 5's standalone version with Reviews + Disputes screens and full guides |

Commit history on main:

```
(+ latest: end-to-end bug sweep — see §15)
560a930 Registration numbers everywhere, free-hours picker, sign-in fix, project summary
1fa52e0 Add the imports the restored modules needed
afa4a58 Restore all five modules, and take the database out of the UI
1c14fc5 Sign-in, and scope the app to Members 1 and 2
1f3d018 Live SQL tracing, role enrolment from the booking form, admin area
a3064a5 fixed
7ad9b44 Fix SQL*Plus 11.2 incompatibilities found on first real run
663093d Add data dictionary inspection script
9daf9a2 Add DBMS study and viva guide
dfcc6c3 TimeBank: Oracle schema, JDBC API and Flutter front end
```

---

## 14. Design rules we followed

These came from your instructions during the project:

1. **The UI never shows database detail.** No "UPDATE", "escrow", "row", "Oracle", "soft delete". Example: the dialog says *"Deactivate this account? They will no longer be able to sign in. Their past sessions and credits stay on record, and you can reactivate the account at any time."* The explanation is yours to give in the viva.
2. **The terminal shows all of it** — plain-English label, full SQL, values, outcome, and the rows afterwards — without framework noise.
3. **Each member shows their own role, screens and statements.** Labels in the terminal carry the member number.
4. **People type registration numbers, never internal ids.**
5. **Credits only move through `PKG_TIMEBANK`;** the ledger is append-only.
6. **Nothing is ever hard-deleted that history depends on** (students are deactivated; ledger corrections are new rows).
7. **SQL files must run on Oracle 11g SQL*Plus** as-is.
8. **Commits under your GitHub identity.**
9. **Secrets:** only the throwaway local `timebank/timebank` login is committed; the SYSTEM password never goes in any file.

---

## 15. Decisions and fixes log

| Decision / fix | Why |
|---|---|
| Spring Boot + JDBC instead of JPA | the course grades SQL; JPA would hide it |
| Port 8081 | Oracle XE's APEX listener owns 8080 |
| ojdbc8/ucp 19.23 via property | removes pom warning, works with XE 11g |
| `rerun.sql` | member files start with INSERTs; rerunning needs a clean rebuild |
| `onboarding.sql` rename | user's choice; `rerun.sql` updated to `@@onboarding.sql` |
| `SqlLog` + `showAfter` | ma'am wants proof that each click reaches Oracle |
| Admin from `application.properties` | single administrator for now |
| Guided booking endpoint | students book by reg no; roles created on demand |
| `StudentLookup` | accept `25BDE0068` anywhere |
| Free-hours picker | removed confusing "slot number" input |
| Interactive batch demo file | built, then removed at your request |
| Scope narrowed to Members 1+2, then restored to all five | final: all modules, no jargon |
| Member 5 branch with docs | teammate has no Flutter / Claude; four commands to run |
| **Bug sweep (2 Nov):** guided booking adds a missing skill (existing tutor) and enrols the learner (TEACH) | both rows are required by `FK_BK_SKILL` / `FK_BK_TUTEE` |
| Learning from someone who doesn't teach that subject is refused before any enrolment | a sentence instead of ORA-02291, and no stray role rows |
| Free-hour overlap check + `SELECT … FOR UPDATE` on the tutor row | overlapping hours made the picker ambiguous; the lock also serialises `MAX(slot_no)+1` |
| Students see only their own sessions, and only their own side's buttons | the session code and dual confirmation mean nothing if one person can press both |
| Passbook has no "open another student" box | credit history is private; admin has the audit screen |
| Confirm message says when credits were actually paid | the second confirmation used to say "credits move once both confirm" |
| "Check the protection" counts only ORA-20001 as proof | it used to report any error as "blocked" |
| Remaining DB words removed from on-screen messages | design rule 1 |

---

## 16. Viva questions with answers

**Why is `student_id` a surrogate key when `reg_no` is already unique?**
Joins and FKs use a short, never-changing number; `reg_no` stays as the natural key with a UNIQUE constraint so people can still identify themselves by it. `StudentLookup` translates.

**Why is deactivating a student an UPDATE, not a DELETE?**
BOOKING, FEEDBACK and CREDIT_TXN reference the student. A DELETE would either fail (ORA-02292) or, with cascade, erase financial history. `is_active = 'N'` keeps integrity and history.

**Why is SLOT a weak entity?**
`slot_no` only means something within one tutor — "slot 2" of tutor 1003 vs tutor 1007. Its key is `(tutor_id, slot_no)` and it dies with the tutor (`ON DELETE CASCADE`).

**Is the specialization disjoint or overlapping? Total or partial?**
Overlapping (a student can teach DBMS and learn Networks) and partial (a new student may have no role yet).

**How do you guarantee credits are never created out of thin air?**
Only `post_txn` inside the package inserts into CREDIT_TXN; `trg_txn_immutable` blocks UPDATE/DELETE; `audit_economy` checks total issued = sum of balances + holds → BALANCED.

**Why HOLD then TRANSFER, not deduct immediately?**
Escrow: the tutee's credits are reserved at booking but only paid to the tutor once the session is confirmed. Cancellation releases the hold; no money moves for sessions that never happened.

**Which normal form are your tables in?**
3NF / BCNF: every determinant is a candidate key. Phones and preferred times were split out for 1NF; department name lives only in DEPARTMENT (no transitive dependency through STUDENT).

**Why is `reviewer_role` in FEEDBACK's primary key?**
A booking has exactly two possible reviews; the role distinguishes them and the PK blocks double-reviewing for free. Tutor ratings average only `reviewer_role = 'TUTEE'` rows.

**What does the collusion query detect?**
Pairs who tutor each other in both directions with high ratings — net zero credits, inflated reputation. BOOKING self-join; `tutor_id < tutee_id` reports each pair once.

**Where is indexing used and why B+ trees?**
Six indexes on FK and lookup columns (see §4.3); Oracle's default index is a B+ tree, giving O(log n) lookups and ordered range scans for time-based queries. Plans in `QUERY_PLAN.md`.

**Show TCL.**
`11_group_tcl_plans.sql`: `SAVEPOINT`, partial `ROLLBACK TO`, `COMMIT`; plus `EXPLAIN PLAN` before/after indexes.

More in `DBMS_GUIDE.md` and `MEMBER5_GUIDE.md` (branch).

---

## 17. Known limitations and next steps

| Item | Status |
|---|---|
| Whole app | **verified 2 Nov:** clean `rerun.sql`, API compiles, `flutter analyze` clean, 35 API checks pass, student + admin flows clicked through in Chrome |
| Admin login | one credential in config, not a hashed table — fine for the demo, mention as future work |
| Student sign-in | registration number only, no password — prototype scope. The app shows each student only their own side's buttons, but the API itself trusts the caller (no tokens), so the rule is enforced in the UI, not the server |
| `console-app/` | early prototype, not compiled or used |
| Reviews / Disputes full screens | live on the `member5-feedback-disputes` branch; main has the admin Complaints tab |
| Mobile build | Android emulator already uses `10.0.2.2`; a real phone needs `--dart-define=API_BASE_URL=http://<PC's Wi-Fi IP>:8081` |
| Guided booking is two steps | a role created just before a booking that then fails (e.g. slot already taken) stays — harmless under the overlapping specialization |
| Future work | password hashing and API tokens, notifications, recommendations by preferred time, deployment on a server |
