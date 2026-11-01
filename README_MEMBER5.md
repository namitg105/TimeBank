# Member 5 — Feedback, disputes and fraud

This branch is your part of TimeBank, running as an app you can show on
your own laptop. You do not need to write any Flutter — four commands
and it runs.

**Your tables:** FEEDBACK, DISPUTE, ADMIN
**Your file:** `sql/10_member5_feedback_disputes.sql` — 3 DML + 6 SELECT

---

## Get it running

### 1. What you need installed

| | Check with | If missing |
|---|---|---|
| Oracle XE 11g | `lsnrctl status` | install Oracle Database XE 11g |
| Java 17 or newer | `java -version` | `winget install EclipseAdoptium.Temurin.21.JDK` |
| Maven | `mvn -v` | see "Installing Maven" below |
| Flutter | `flutter --version` | https://docs.flutter.dev/get-started/install |

### 2. Get the code

```powershell
git clone -b member5-feedback-disputes https://github.com/namitg105/TimeBank.git
cd TimeBank
```

### 3. Build the database

Start Oracle first, in an **Administrator** PowerShell:

```powershell
net start OracleServiceXE
net start OracleXETNSListener
```

Create the schema user — the SYSTEM password is the one set when Oracle
was installed:

```powershell
sqlplus system/YOUR_SYSTEM_PASSWORD@localhost:1521/XE
```
```sql
CREATE USER timebank IDENTIFIED BY timebank;
GRANT CONNECT, RESOURCE TO timebank;
GRANT CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER, CREATE SEQUENCE TO timebank;
ALTER USER timebank QUOTA UNLIMITED ON USERS;
EXIT;
```

Then build everything:

```powershell
cd sql
sqlplus timebank/timebank@localhost:1521/XE "@rerun.sql"
cd ..
```

That drops, rebuilds, seeds, and runs all 45 queries. Two things to
check at the end: the invalid-objects query returns **no rows**, and the
audit prints **BALANCED**.

The only errors you should see are two deliberate ones printed as
`Blocked as designed -> ORA-20001`. That is the append-only trigger
refusing to let the credit ledger be edited — it is supposed to fail.

### 4. Start the API — leave this window open

```powershell
cd api
mvn -q clean compile
mvn spring-boot:run
```

Wait for `Started TimeBankApiApplication`. **This window is the one that
matters** — every click in the app prints its SQL here.

Check it works: open `localhost:8081/api/feedback/collusion` in a
browser.

> Port 8081, not 8080. Oracle XE's own web console owns 8080.

### 5. Start the app — a second window

```powershell
cd timebank
flutter pub get
flutter run -d chrome
```

Sign in as **I am the administrator**, username `namit`, password
`timebank@2026`. Or as a student with registration number `25BCE1001`.

---

## What to show, and what to say

### The screens

| Tab | What it shows |
|---|---|
| **Reviews → Sessions** | finished sessions; leave or remove a review from either side |
| **Reviews → Both sides** | what the student said and what the tutor said, next to each other |
| **Reviews → Top rated** | tutors above the campus average, and the spread per subject |
| **Disputes → Queue** | complaints; mark one as being looked into, or rule on it |
| **Disputes → Suspicious** | **the collusion detector** |
| **Disputes → Trends** | whether each tutor is improving or slipping |

### Lead with the collusion detector

It is the most distinctive query in the whole project. Open
**Disputes → Suspicious** and watch the API window.

> Two students who repeatedly tutor each other net out to zero credits
> but collect a five-star review every time. The self join on BOOKING
> finds pairs going both ways; the correlated subqueries then count how
> often, and what they rated each other.
>
> `b1.tutor_id < b1.tutee_id` reports each pair once. Without it, A–B
> and B–A would come back as two separate findings.
>
> No database can stop two people who agree to lie. What it can do is
> make the pattern cheap to spot and not worth the effort. In graph
> terms it is a 2-cycle between two student nodes.

### The three questions you will be asked

**"Why is `reviewer_role` part of the primary key?"**

Because one booking carries two reviews, one from each side.
`(booking_id, reviewer_role)` identifies exactly one of them, and it
enforces "nobody reviews the same session twice" for free — the primary
key does work a trigger would otherwise have to do.

**State the consequence without being asked**, because it is the part
that shows you understood it: a tutor's rating must average only the
rows where `reviewer_role = 'TUTEE'`. Averaging both directions would
mix in that tutor's own opinions of their students, which measures
nothing. Every query in `FeedbackDao` has that filter — point at one.

**"Why did DISPUTE not need a relationship to STUDENT?"**

Because only the two participants of a booking can raise one, so
`(booking_id, raised_by_role)` already identifies the complainant.
Adding a foreign key to STUDENT would let someone raise a dispute about
a session they were not in.

**"Both of your tables are weak entities. Are they the same?"**

No, and this is the nice distinction. Both hang off BOOKING, but the
partial key differs because the reason differs:

- FEEDBACK uses a **role** — there are exactly two possible reviews and
  the side tells them apart
- DISPUTE uses a **counter** — there can be any number of complaints, so
  they need numbering

### On Q2, the self join

FEEDBACK is joined to itself twice, the copies told apart by
`reviewer_role`. That is only possible **because** the role is part of
the key.

Both joins are OUTER. Many sessions get only one review — that is the
partial participation of BOOKING in *receives* — and an inner join would
drop them, along with every session that got no review at all, which is
exactly the set worth chasing.

---

## Your SQL file, run on its own

For the written report:

```powershell
cd sql
sqlplus timebank/timebank@localhost:1521/XE
```
```sql
SPOOL member5_output.txt
@10_member5_feedback_disputes.sql
SPOOL OFF
EXIT;
```

Run `@rerun.sql` first if you have already run it once — each member
file starts with an INSERT, so a second run on the same data raises
ORA-00001.

---

## Installing Maven

`winget` does not carry it. Paste this whole block into PowerShell:

```powershell
$ver  = "3.9.9"
$dest = "$env:USERPROFILE\tools"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Invoke-WebRequest "https://archive.apache.org/dist/maven/maven-3/$ver/binaries/apache-maven-$ver-bin.zip" -OutFile "$dest\maven.zip"
Expand-Archive "$dest\maven.zip" -DestinationPath $dest -Force

$old = [Environment]::GetEnvironmentVariable("PATH","User")
[Environment]::SetEnvironmentVariable("PATH", "$old;$dest\apache-maven-$ver\bin", "User")
$env:PATH += ";$dest\apache-maven-$ver\bin"

mvn -v
```

If `mvn -v` says JAVA_HOME is not defined, set it to wherever your JDK
is — `ls "C:\Program Files\Java"` will show you:

```powershell
[Environment]::SetEnvironmentVariable("JAVA_HOME","C:\Program Files\Java\jdk-21","User")
```

Then open a **new** PowerShell window.

---

## When something goes wrong

| What you see | What it means |
|---|---|
| every screen errors | the API window was closed — restart it |
| `ORA-12541: no listener` | Oracle is not started; see step 3 |
| `Port 8080 was already in use` | you are on an old build; this one uses 8081 |
| `SP2-0640: Not connected` | SQL\*Plus started without credentials — type `CONNECT timebank/timebank@localhost:1521/XE` |
| `ORA-00001 unique constraint` | a member file was run twice; rebuild with `@rerun.sql` |
| `mvn` not recognised | new window without the PATH — see "Installing Maven" |

---

## What is on this branch and what is not

This branch has screens for **your module only**. The database, the
PL/SQL package and all five members' SQL files are complete and
unchanged — `sql/` still holds everything. The other members' Flutter
code sits in `timebank/other_members/`, out of the build.

That is deliberate, and it is the honest answer if you are asked: the
schema is the team's, the screens are yours.
