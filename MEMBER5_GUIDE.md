# Member 5 — Feedback, Disputes and Fraud Detection

**Branch:** `member5-feedback-disputes`
**Project:** TimeBank — A Peer Tutoring Credit Exchange Management System
**Course:** BACSE202 Database Systems, VIT

---

## 1. What this module is

TimeBank lets students teach each other and pay in hours rather than
money. One credit buys one hour of help, and you earn credits back by
teaching. That only works if the ratings mean something — so this
module is the part that decides whether a session really happened, and
what it was worth.

Three jobs:

1. **Reviews.** After a finished session, each side rates the other.
2. **Disputes.** When something goes wrong, either party can complain,
   and a moderator rules on it.
3. **Fraud detection.** Spot the pairs who are gaming the system.

### The tables you own

| Table | What it holds | Rows in the seed |
|---|---|---|
| `FEEDBACK` | one rating + comment, from one side of one session | 13 |
| `DISPUTE` | a complaint about a session, and how it was settled | 1 |
| `ADMIN` | the moderators who can rule on disputes | 2 |

---

## 2. The three ideas this module owns

These are what you are actually being marked on. The queries are
evidence for them.

### 2.1 Two weak entities, two different kinds of partial key

Both FEEDBACK and DISPUTE are **weak entities** — neither has an
identity of its own, and neither can exist without the BOOKING it
belongs to. But the *reason* they need a partial key differs, and that
is the interesting part.

```sql
CREATE TABLE feedback (
  booking_id     NUMBER(10)    NOT NULL,
  reviewer_role  VARCHAR2(5)   NOT NULL,   -- partial key: a ROLE
  rating         NUMBER(2,1)   NOT NULL,
  comments       VARCHAR2(400),
  feedback_date  DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_feedback   PRIMARY KEY (booking_id, reviewer_role),
  CONSTRAINT fk_fb_booking FOREIGN KEY (booking_id)
                           REFERENCES booking (booking_id)
                           ON DELETE CASCADE,
  CONSTRAINT chk_fb_role   CHECK (reviewer_role IN ('TUTOR','TUTEE')),
  CONSTRAINT chk_fb_rating CHECK (rating BETWEEN 1.0 AND 5.0)
);
```

```sql
CREATE TABLE dispute (
  booking_id       NUMBER(10)    NOT NULL,
  dispute_no       NUMBER(3)     NOT NULL,   -- partial key: a COUNTER
  raised_by_role   VARCHAR2(5)   NOT NULL,
  reason           VARCHAR2(400) NOT NULL,
  raised_on        DATE          DEFAULT SYSDATE NOT NULL,
  status           VARCHAR2(12)  DEFAULT 'OPEN' NOT NULL,
  resolution_note  VARCHAR2(400),
  resolved_by      NUMBER(6),
  CONSTRAINT pk_dispute      PRIMARY KEY (booking_id, dispute_no),
  CONSTRAINT fk_dp_booking   FOREIGN KEY (booking_id)
                             REFERENCES booking (booking_id)
                             ON DELETE CASCADE,
  CONSTRAINT fk_dp_admin     FOREIGN KEY (resolved_by)
                             REFERENCES admin (admin_id),
  CONSTRAINT chk_dp_role     CHECK (raised_by_role IN ('TUTOR','TUTEE')),
  CONSTRAINT chk_dp_status   CHECK (status IN
                               ('OPEN','UNDER_REVIEW','RESOLVED')),
  CONSTRAINT chk_dp_resolved CHECK (
       (status = 'RESOLVED' AND resolved_by IS NOT NULL
                            AND resolution_note IS NOT NULL)
    OR (status <> 'RESOLVED'))
);
```

**The distinction, in one line each:**

- FEEDBACK uses a **role**, because there are exactly two possible
  reviews of a session and the *side* is what tells them apart.
- DISPUTE uses a **counter**, because there can be any number of
  complaints and they need *numbering*.

Same shape, different partial key, for different reasons. Being able to
say that is worth more than the queries.

**Why `ON DELETE CASCADE` on both?** A review or a complaint about a
session that no longer exists is meaningless. Contrast this with
CREDIT_TXN, which has **no** `ON DELETE` — money must survive, opinions
need not.

**Why `CHK_DP_RESOLVED`?** A closed complaint must name who closed it
and why. The constraint makes "resolved by nobody, for no stated
reason" impossible to store, rather than merely discouraged.

### 2.2 The self join

One booking carries two reviews. To see them side by side you join
FEEDBACK **to itself**, telling the two copies apart by `reviewer_role`.

That is only possible *because the role is part of the key*. If the key
were a surrogate `feedback_id`, there would be nothing to join on that
distinguishes "the student's review" from "the tutor's review".

### 2.3 Collusion detection

Two students who repeatedly tutor each other net out to zero credits
but collect a five-star review every time. The credits balance, the
audit stays clean, and both their ratings climb without anybody
learning anything.

In graph terms it is a **2-cycle** between two student nodes — which is
the Module 6 connection, if she asks.

No database can stop two people who agree to lie. What it can do is
make the pattern cheap to spot and not worth the effort.

---

## 3. The consequence you must state unprompted

This is the single thing that shows you understood your own design, so
say it before you are asked:

> Because `reviewer_role` is part of the key, a tutor's rating must
> average **only** the rows where `reviewer_role = 'TUTEE'`.
>
> Averaging both directions would mix in that tutor's own opinions of
> their students. A tutor who writes generous reviews would appear to
> be a better teacher, which measures nothing at all.

Every query in `FeedbackDao.java` carries that filter. Open one and
point at the `WHERE f.reviewer_role = 'TUTEE'` line.

---

## 4. Your nine statements

File: **`sql/10_member5_feedback_disputes.sql`** — 3 DML + 6 SELECT.

| # | Kind | What it does |
|---|---|---|
| INSERT | DML | leave a review, raise a dispute |
| UPDATE | DML | triage the dispute queue |
| DELETE | DML | retract a review, drop colluded ratings |
| Q1 | simple | every review and dispute written so far |
| Q2 | **self join** | both sides of each session |
| Q3 | nested | tutors above the campus average |
| Q4 | **correlated** | **the collusion detector** |
| Q5 | aggregate | rating distribution by subject, with ROLLUP |
| Q6 | analytic | is each tutor improving or slipping? |

### Q2 — the self join, in detail

```sql
FROM   booking b
       JOIN      subject  sub ON sub.subject_id   = b.subject_id
       JOIN      student  tr  ON tr.student_id    = b.tutor_id
       JOIN      student  te  ON te.student_id    = b.tutee_id
       LEFT JOIN feedback ft  ON ft.booking_id    = b.booking_id
                             AND ft.reviewer_role = 'TUTEE'
       LEFT JOIN feedback fe  ON fe.booking_id    = b.booking_id
                             AND fe.reviewer_role = 'TUTOR'
       LEFT JOIN dispute  d   ON d.booking_id     = b.booking_id
```

`ft` and `fe` are the same table twice. The `AND ft.reviewer_role = ...`
is what separates them.

**Both joins must be OUTER.** Many sessions get a review from only one
side — that is the **partial participation** of BOOKING in *receives* —
and an inner join would drop them, along with every session that got no
review at all. Those are exactly the rows worth chasing.

Note also that the role filter is in the **ON clause**, not the WHERE.
Move it to WHERE and the outer join collapses into an inner one,
because a NULL row cannot satisfy `ft.reviewer_role = 'TUTEE'`. That is
a real trap and worth knowing.

### Q4 — the collusion detector, in detail

```sql
FROM   booking b1
       JOIN student a ON a.student_id = b1.tutor_id
       JOIN student c ON c.student_id = b1.tutee_id
WHERE  b1.status   = 'COMPLETED'
AND    b1.tutor_id < b1.tutee_id
AND    EXISTS (SELECT 1 FROM booking b4
               WHERE  b4.tutor_id = b1.tutee_id
               AND    b4.tutee_id = b1.tutor_id
               AND    b4.status   = 'COMPLETED')
```

Three things to point at:

1. **`EXISTS` with the ids swapped** finds the reverse direction — did
   the tutee ever teach the tutor? That is the cycle.

2. **`b1.tutor_id < b1.tutee_id`** reports each pair once. Without it,
   A–B and B–A come back as two separate findings for the same pair.

3. **The subqueries are correlated** — they reference `b1.tutor_id` and
   `b1.tutee_id` from the outer row, so they are re-evaluated per pair
   rather than run once.

### Q3 — why the average is taken twice

```sql
(SELECT AVG(per_tutor)
 FROM  (SELECT AVG(f3.rating) AS per_tutor
        FROM   feedback f3 JOIN booking b3 ON ...
        WHERE  f3.reviewer_role = 'TUTEE'
        GROUP  BY b3.tutor_id))
```

The inner query averages *each tutor's* ratings. The outer averages
*those averages*.

A plain `AVG(rating)` over all rows would let a tutor with twenty
sessions drown out one with two, and the "campus average" would really
just be the busiest tutor's average. Averaging per-tutor first gives
every tutor one vote.

---

## 5. The trigger that protects your table

`TRG_FEEDBACK_VALID`, in `sql/03_triggers.sql`:

```sql
CREATE OR REPLACE TRIGGER trg_feedback_valid
BEFORE INSERT ON feedback
FOR EACH ROW
DECLARE
  v_status booking.status%TYPE;
BEGIN
  SELECT status INTO v_status FROM booking
  WHERE  booking_id = :NEW.booking_id;

  IF v_status <> 'COMPLETED' THEN
    RAISE_APPLICATION_ERROR (-20008,
      'Feedback can only be left on a COMPLETED session. '
      || 'This booking is ' || v_status || '.');
  END IF;
END;
```

**Why a trigger and not a constraint?** A CHECK constraint can only see
one row of one table. This rule needs the *status of another table*, so
a CHECK cannot express it.

**What the primary key already does, so the trigger does not have to:**
`PK_FEEDBACK (booking_id, reviewer_role)` stops anyone reviewing the
same session twice from the same side. The trigger only adds the
*timing* rule.

**Why the rule exists:** without it, a tutee could cancel a session and
then leave a one-star review out of spite, and that rating would drag
down an average built from sessions that really happened.

**Demonstrate it.** Try to review a session that has not finished and
watch Oracle refuse with `ORA-20008`. A database that says no is more
convincing than one that only says yes.

---

## 6. How disputes are settled

A ruling is not one write. The escrowed credits have to go back to one
party, a penalty may be posted against the other, and the complaint has
to close — all of it, or none of it. So it lives in
`PKG_TIMEBANK.RESOLVE_DISPUTE`:

```sql
PROCEDURE resolve_dispute (
    p_booking_id  IN NUMBER,
    p_dispute_no  IN NUMBER,
    p_admin_id    IN NUMBER,
    p_in_favour   IN VARCHAR2,   -- 'TUTOR' or 'TUTEE'
    p_note        IN VARCHAR2);
```

A `PENALTY` is **the only way credits ever leave the economy**. That is
why the closed-economy audit still balances after a ruling — point at
the Audit figure before and after.

---

## 7. The code

| File | What it is |
|---|---|
| `sql/10_member5_feedback_disputes.sql` | your nine statements |
| `api/.../dao/FeedbackDao.java` | the same queries, over JDBC |
| `api/.../dao/AdminDao.java` | the dispute queue and rulings |
| `api/.../api/web/FeedbackController.java` | the HTTP endpoints |
| `timebank/lib/features/feedback/.../reviews_page.dart` | the Reviews screen |
| `timebank/lib/features/feedback/.../disputes_page.dart` | the Disputes screen |

### How a click reaches Oracle

```
Flutter  --HTTP/JSON-->  Spring Boot  --JDBC-->  Oracle XE
```

Flutter cannot reach Oracle directly: JDBC is a Java API and there is no
Oracle driver for Dart. The Spring Boot service in `api/` is the bridge,
and that is where the real JDBC work happens.

Every statement is sent with `?` placeholders and a `PreparedStatement`.
Two reasons, both worth knowing:

- **SQL injection.** A bind variable is never parsed as SQL. If someone
  typed `'; DROP TABLE feedback; --` as a comment, it would be stored
  as that literal text. String concatenation would have run it.
- **Speed.** Oracle parses `WHERE booking_id = ?` once and reuses the
  plan for every value.

---

## 8. Running it on your laptop

See **`README_MEMBER5.md`** on this branch for the full setup — what to
install, and four commands to get it running.

The short version, once Oracle is up:

```powershell
cd sql
sqlplus timebank/timebank@localhost:1521/XE "@rerun.sql"

cd ..\api
mvn spring-boot:run

# second window
cd ..\timebank
flutter run -d chrome
```

Sign in as the administrator — username `namit`, password
`timebank@2026`.

---

## 9. What to demonstrate, in order

Put two windows side by side: **Chrome** on the left, the **API
terminal** on the right. Every click prints its SQL on the right.

| # | Do this | Say this |
|---|---|---|
| 1 | **Disputes → Suspicious** | "This is the collusion detector. A pair tutoring each other in circles nets out to zero credits but collects a five-star review every time." |
| 2 | point at the terminal | "That is the self join on BOOKING finding pairs that go both ways, and two correlated subqueries counting how often." |
| 3 | **Reviews → Both sides** | "FEEDBACK joined to itself, the two copies told apart by `reviewer_role`. Both joins are OUTER because many sessions only get one review." |
| 4 | **Reviews → Sessions**, rate one | watch the INSERT and the row it wrote |
| 5 | try reviewing an unfinished session | `ORA-20008` — the trigger refusing |
| 6 | **Disputes → Queue**, rule on one | "A penalty is the only way credits leave the economy — and the audit still balances." |

Step 1 is your lead. It is the most distinctive query in the project.

---

## 10. The questions, with answers

**"Why is `reviewer_role` part of the primary key?"**

Because one booking carries two reviews, one from each side.
`(booking_id, reviewer_role)` identifies exactly one of them, and it
enforces "nobody reviews the same session twice" for free — the primary
key does work a trigger would otherwise have to do.

Then state the consequence from section 3 without being prompted.

**"Why did DISPUTE not need a relationship to STUDENT?"**

Because only the two participants of a booking can raise one, so
`(booking_id, raised_by_role)` already identifies the complainant.
Adding a foreign key to STUDENT would let someone raise a dispute about
a session they were not part of — it would make an invalid state
expressible.

**"Both your tables are weak entities. Are they the same?"**

No. Both hang off BOOKING, but FEEDBACK's partial key is a **role**
(there are exactly two possible reviews, and the side tells them apart)
while DISPUTE's is a **counter** (there can be any number of
complaints, so they need numbering).

**"Why is the role filter in the ON clause and not the WHERE?"**

Because moving it to WHERE turns the outer join into an inner one. A
NULL row from a missing review cannot satisfy
`ft.reviewer_role = 'TUTEE'`, so every session with only one review
would vanish from the result.

**"What stops someone reviewing a session that never happened?"**

`TRG_FEEDBACK_VALID` — and it has to be a trigger rather than a CHECK
constraint, because the rule depends on the status of a *different*
table and a CHECK can only see one row of one table.

**"Could two people game this?"**

Yes, and no database can stop two people who agree to lie. What Q4 does
is make the pattern visible and cheap to find, so it stops being worth
the effort. That is the honest answer, and it is a better one than
claiming the system is fraud-proof.

---

## 11. What is on this branch and what is not

This branch has **screens for Member 5's module only**.

The database is complete and unchanged — `sql/` holds all five members'
files, the full schema, the PL/SQL package and every trigger. Only the
Flutter screens are scoped. The other members' UI code sits in
`timebank/other_members/`, out of the build.

If asked why: the schema is the team's work, the screens are this
member's.
