# TimeBank — Study and Viva Guide

Everything you need to understand before the review, in the order you
should learn it.

**Read Part 1 and Part 2 whatever your module is.** Then read your own
section in Part 4. Part 5 is the question bank.

---

## Contents

1. [The project in sixty seconds](#part-1)
2. [The shared core — every member must know this](#part-2)
3. [Where each syllabus module appears](#part-3)
4. [Per-member deep dive](#part-4)
5. [Viva question bank, with answers](#part-5)
6. [Traps that catch people out](#part-6)
7. [Demo script](#part-7)

---

<a name="part-1"></a>
## Part 1 — The project in sixty seconds

> TimeBank is a peer tutoring exchange for a campus. Instead of money,
> students trade **time**. One hour of tutoring given earns one credit;
> one hour received costs one credit. Every student starts with three
> credits and may borrow down to minus five, which forces people to
> teach before they can keep taking. Credits are held in escrow during a
> session and move only when both sides confirm it happened. The whole
> economy is provably closed: the credits in the system never change
> except through a starter grant or a penalty.

If you can say that, you understand the project. Everything below is
detail.

**Why it is a good database project:** it has a weak entity that is
genuinely weak, a many-to-many relationship that genuinely carries its
own attributes, a specialization that is genuinely overlapping, and a
concurrency problem that is genuinely real. None of it is bolted on to
satisfy the rubric.

---

<a name="part-2"></a>
## Part 2 — The shared core

### 2.1 The fourteen tables

| Relation | Kind | Why it exists |
|---|---|---|
| `DEPARTMENT` | strong | Owns subjects, enrols students |
| `STUDENT` | strong | The superclass |
| `TUTOR` | **subclass** | Someone who teaches |
| `TUTEE` | **subclass** | Someone who learns |
| `STUDENT_PHONE` | from a multivalued attribute | A student may have several numbers |
| `TUTEE_PREFTIME` | from a multivalued attribute | Several preferred time bands |
| `SUBJECT` | strong | What can be taught |
| `TUTOR_SKILL` | from the **M:N** "offers" | Which tutor teaches which subject |
| `SLOT` | **weak**, owner `TUTOR` | A weekly hour of availability |
| `BOOKING` | strong | One session. The centre of the model |
| `FEEDBACK` | **weak**, owner `BOOKING` | A review |
| `DISPUTE` | **weak**, owner `BOOKING` | A complaint |
| `ADMIN` | strong | Resolves disputes |
| `CREDIT_TXN` | strong | The append-only ledger |

### 2.2 The three decisions that matter

#### Decision 1 — The specialization is overlapping and partial

A student can tutor Physics *and* be tutored in databases. So `TUTOR`
and `TUTEE` are not separate kinds of person — they are **roles the same
person can hold at once**.

- **Overlapping** means one entity may be in both subclasses.
  In the seed data, Kabir (105) and Arjun (109) are in both.
- **Partial** means an entity may be in neither.
  Sara (108) registers and starts in neither.

This forces **mapping option 8A**: keep `STUDENT`, and give each
subclass its own table keyed by `student_id`.

Why the others fail:

| Option | Why it fails here |
|---|---|
| 8B — subclass tables only | Needs total **and** disjoint. Sara is in neither, so she could not be stored at all; Kabir is in both, so his name and email would be duplicated |
| 8C — one table, one type column | Needs disjoint. A single "type" value cannot say "both" |
| 8D — one table, Boolean flags | Would work, but `badge_level` and `academic_need_tier` would be NULL for everyone not in that role |

**The query that proves it:** `M1-Q2`. Two LEFT JOINs to the subclass
tables produce four categories — TUTOR ONLY, TUTEE ONLY, BOTH,
NEITHER YET. If the joins were INNER, the last two would vanish and the
proof with them.

#### Decision 2 — Two composite foreign keys sharing one column

```sql
CONSTRAINT fk_bk_slot  FOREIGN KEY (tutor_id, slot_no)
                       REFERENCES slot        (tutor_id, slot_no),
CONSTRAINT fk_bk_skill FOREIGN KEY (tutor_id, subject_id)
                       REFERENCES tutor_skill (tutor_id, subject_id)
```

`tutor_id` appears in **both**. Because it is the same physical column,
the database guarantees two things at once with no trigger:

- the booked slot belongs to **that** tutor, not someone else's slot
- the booked subject is one **that** tutor actually offers

Had you used separate columns, nothing would stop a booking pairing
Arjun as tutor with Priya's Monday slot.

**Why composite at all?** Because `SLOT` is a weak entity — its key is
the pair `(tutor_id, slot_no)`, and a foreign key must have the same
number of columns, in the same order, as the key it references. You
cannot reference half a key.

#### Decision 3 — Derived attributes are not stored

| Derived value | Computed from |
|---|---|
| `Age` | `dob` |
| `Duration` (slot) | `end_time − start_time` |
| `TotalHoursTaught` | `SUM(duration_hours)` over completed bookings |
| `AvgRatingAsTutor` | `AVG(rating)` where `reviewer_role = 'TUTEE'` |
| `CreditBalance` | `SUM(amount)` over that student's ledger rows |

Mapping rule 6 says a derived attribute becomes no column at all. They
are exposed through views instead: `v_student_balance`,
`v_tutor_profile`, `v_slot_detail`.

**The deeper reason** is which value is the source of truth. The ledger
records what happened; the balance is just its total. Storing both
independently would let them disagree — and a balance updated without a
matching ledger row means credits appeared from nowhere.

**The one exception:** `balance_snapshot` in `CREDIT_TXN` *is* stored,
and is also technically derivable. Be ready for this question — the
answer is in Part 5.

### 2.3 How a session works, end to end

| Step | What happens | Ledger row written |
|---|---|---|
| 1 | Tutee books a 1.5h session | `HOLD −1.5` against the tutee |
| 2 | Tutor types in the tutee's session code | — |
| 3 | Both sides confirm | `TRANSFER +1.5` to the tutor |

**The single most common mistake is thinking completion writes two
rows.** It does not. The tutee was already debited at booking time by
the `HOLD`. Writing a second negative row at completion would charge
them twice.

Why hold the credits at booking?

- The tutee cannot commit the same credits to five sessions at once
- The tutor knows the credits are real before giving up their hour

What if it goes wrong:

| Situation | Where the escrow goes |
|---|---|
| Tutor cancels, any time | All back to the tutee (`RELEASE`) |
| Tutee cancels more than 24h ahead | All back to the tutee (`RELEASE`) |
| Tutee cancels inside 24h | Split — the tutor had blocked out the hour |
| Dispute raised | Frozen until an admin rules |
| Admin rules for the tutee | `RELEASE` to tutee, `PENALTY` on the tutor |

A `PENALTY` is **the only way credits ever leave the system**.

### 2.4 The closed-economy audit

At every moment:

```
sum of all balances  +  credits held in escrow
            =  total granted  −  total penalised
```

Every session writes one `HOLD` and one `TRANSFER` that cancel out, so a
finished session changes the grand total by **nothing**. On the seed
data both sides come to **35.0**.

`EXEC pkg_timebank.audit_economy` prints it, and `M4-Q5` runs it as a
query.

This only means something because the ledger is **append-only**. If rows
could be edited, the numbers could simply be adjusted to agree.
`trg_txn_immutable` blocks `UPDATE` and `DELETE` on `CREDIT_TXN`
entirely; a mistake is corrected by posting a compensating row, exactly
like real accounting.

### 2.5 Preventing fraud

| Cheat | Defence |
|---|---|
| Tutor claims a session that never happened | Dual confirmation — credits move only when **both** flags are `Y` |
| Tutor claims a no-show | **Session code** — issued to the tutee only; the tutor must enter it, and `trg_confirm_after_end` refuses to complete a booking where `check_in_at` is NULL |
| Confirming before the session ends | Same trigger checks `SYSDATE` against the scheduled end |
| Two friends farming ratings | Cannot be prevented — but `M5-Q4` detects reciprocal pairs, and the package caps a pair at 2 sessions per week |

Be honest about the last one in the viva: **no database can stop two
people who agree to lie.** What it can do is make the pattern visible
and not worth the effort. That answer scores better than pretending
otherwise.

---

<a name="part-3"></a>
## Part 3 — Where each syllabus module appears

### Module 1 — Relational model and constraints

| Concept | Where |
|---|---|
| Domain constraints | `CHECK (duration_hours IN (0.5,1.0,1.5,2.0))`, `CHECK (rating BETWEEN 1.0 AND 5.0)` |
| Key constraints | 14 primary keys, 4 of them composite |
| Entity integrity | Every PK column is `NOT NULL` by definition |
| Referential integrity | 18 foreign keys, including 2 composite |
| Constraints on nulls | **`CREDIT_TXN.booking_id` is the only nullable FK** in the whole schema |
| Dealing with violations | `ON DELETE CASCADE` on weak entities; nothing on `BOOKING`'s FKs, so Oracle blocks the delete |

**The nullable FK is the question to be ready for.** `booking_id` is NULL
for `GRANT` and `PENALTY` rows because no session caused them. That is
the *partial participation* of `CREDIT_TXN` in the "generates"
relationship, surviving the mapping as a nullable column.

The rule in general:

| In the ER diagram | After mapping |
|---|---|
| Total participation on the FK-holding side | FK is `NOT NULL` |
| Partial participation on the FK-holding side | FK allows `NULL` |

### Module 2 — ER / EER modelling and normalization

Covered throughout. The normalization examples to know:

| Form | Example in this schema |
|---|---|
| **1NF** | `PhoneNo` and `PreferredTimeBand` were multivalued; mapping rule 6 split them into `STUDENT_PHONE` and `TUTEE_PREFTIME` |
| **2NF** | A naive `TUTOR_SKILL(TutorID, SubjectID, SubjectName, GradeProof)` has `SubjectName` depending on `SubjectID` alone — a partial dependency on part of the composite key. Fixed by keeping `SubjectName` in `SUBJECT` |
| **3NF / BCNF** | Satisfied once `DEPARTMENT` is its own entity |
| **4NF** | `Tutor →→ Subject` and `Tutor →→ Slot` are **independent** multivalued facts. Keeping both in one table would give the Cartesian product of every subject against every free hour. Splitting into `TUTOR_SKILL` and `SLOT` resolves the MVD |

**Do not claim BCNF implies 4NF.** It does not. You have to show the
multivalued dependency explicitly, which is what the `TUTOR_SKILL` /
`SLOT` split does.

### Module 3 — File structures, indexing, query processing

| Concept | Where |
|---|---|
| B+ tree index | `02_indexes.sql` — every `CREATE INDEX` builds one |
| Multi-level index | What a B+ tree is: the non-leaf levels *are* the index on the index |
| Index-organised table | `CREDIT_POLICY` — the data lives inside the B+ tree leaves, no separate table segment |
| Function-based index | `idx_dispute_open` indexes a `CASE` expression, so resolved disputes become NULL and are not indexed at all — the index stays tiny |
| Index-only scan | `idx_skill_subject (subject_id, tutor_id)` answers the lookup from the index alone, never touching the table |
| Relational algebra | Commented above `11_group_tcl_plans.sql` part C3 |
| Heuristic optimisation | Same file — pushing selection down the query tree |
| `EXPLAIN PLAN` | Part C, with and without an index, costs compared |

**Oracle does not have a "clustered B+ tree".** If your proposal said so,
correct it — the nearest equivalent is an index-organised table.

**What not to index:** `avg_rating_as_tutor` changes after every
session, so indexing it would mean constant index maintenance for a
value that is derived anyway.

### Module 4 — Transactions, concurrency, recovery

| Concept | Where |
|---|---|
| ACID | The escrow transfer touches `BOOKING` and `CREDIT_TXN` together |
| TCL | `11_group_tcl_plans.sql` part A — `SAVEPOINT`, partial `ROLLBACK`, `COMMIT` |
| Concurrency problem | Part B — two tutees booking the same slot |
| Locking | `pkg_timebank.book_session` does `SELECT ... FOR UPDATE` on the slot row |
| Recovery | Oracle handles write-ahead logging itself; discuss deferred vs immediate update in the report |

**Part B is the strongest exhibit in the whole project.** Run it in two
SQL Developer sessions side by side. Session 2 visibly *hangs* on
session 1's row lock, then fails with ORA-20005 once session 1 commits.
Screenshot the hang.

**The subtlety that earns marks:** Oracle uses **multiversion read
consistency**, not textbook two-phase locking. An ordinary `SELECT`
never blocks and never sees another session's uncommitted work. So
without an *explicit* row lock, both sessions would read "slot free",
both would pass the check, and both would insert. The `FOR UPDATE` is
what serialises them.

### Module 5 — Distributed and NoSQL

**Not implemented, and say so plainly.** These cannot be done in Oracle,
so they belong in a "future scope and architecture discussion" section:

- Horizontal fragmentation of `STUDENT` and `BOOKING` by `dept_id` —
  this is *why* `DEPARTMENT` is worth having
- Redis for session token caching
- MongoDB for unstructured chat logs

Claiming you implemented these when you did not is worse than saying
they are future scope.

### Module 6 — Contemporary trends

`11_group_tcl_plans.sql` part E:

- **E2** walks the tutoring graph with `CONNECT BY NOCYCLE` — "A learned
  from B, who learned from C". A relational database walking a graph is
  a stronger answer than describing Neo4j from a slide.
- `NOCYCLE` is what stops it looping for ever on a reciprocal pair — the
  same collusion `M5-Q4` hunts for. Without it you get ORA-01436.

---

<a name="part-4"></a>
## Part 4 — Per-member deep dive

Every member has the same nine: 1 INSERT, 1 UPDATE, 1 DELETE, then six
SELECTs — simple, join, nested, correlated, aggregate, analytic.

### Member 1 — Onboarding and profiles

**Own these ideas:** the overlapping-partial specialization, derived
attributes, soft delete.

**Lead with Q2.** It produces TUTOR ONLY / TUTEE ONLY / BOTH /
NEITHER YET in one four-table join and is the clearest proof the EER
design is right.

**Be ready for:** *"Why is closing an account an UPDATE and not a
DELETE?"* Because `BOOKING` and `CREDIT_TXN` reference `STUDENT` with no
`ON DELETE` clause, so Oracle blocks the delete to protect history. The
DELETE you do demonstrate is on `STUDENT_PHONE`, which came from a
multivalued attribute and owns nothing.

**Know the difference Q3 vs Q4:** Q3's subquery runs **once** (it never
mentions the outer row). Q4's `NOT EXISTS` re-runs **per outer row**
because it references `s.student_id`.

### Member 2 — Skills and availability

**Own these ideas:** the M:N relationship, weak entities and partial
keys, cross-department tutoring.

**Lead with Q2.** Five tables, and it flags cross-department tutoring —
Rohan is Mechanical and teaches Database Systems.

**Be ready for:** *"Why does `TUTOR_SKILL` exist at all?"* Because
`offers` is M:N and a single column cannot hold many values. Its three
attributes — `competency_level`, `grade_proof`, `certified_on` —
describe *one tutor's skill in one subject*, so they belong on the
relationship, not on `TUTOR` or `SUBJECT`.

**And:** *"Why does `slot_no` restart at 1 for each tutor?"* Because it
is a **partial key**. `SLOT` is weak; its full identity is
`(tutor_id, slot_no)`.

**Why Q3 uses `NOT IN` but Q4 uses `NOT EXISTS`:** `NOT IN` is only safe
because `tutor_skill.subject_id` is `NOT NULL`. A single NULL in the
inner list makes `NOT IN` return no rows at all, because comparing
anything to NULL gives UNKNOWN rather than TRUE. `NOT EXISTS` has no
such trap.

### Member 3 — Booking engine

**Own these ideas:** composite foreign keys, why booking is a strong
entity, why the writes go through a package.

**Lead with Q2.** Six tables. Every join is one ER relationship being
rebuilt from its foreign keys — in the relational model the diamonds
survive *only* as foreign keys, so a join is the only way to recover
them.

**Be ready for:** *"Why is `BOOKING` an entity and not a relationship?"*
Because it has its own identity and lifecycle, and three other things
depend on it — feedback, disputes and ledger rows. A relationship cannot
be the owner of a weak entity.

**And:** *"Why does your INSERT call a procedure?"* Because booking is
five steps that must be atomic: lock the slot, check it is free, check
the collusion cap, insert, move credits to escrow. Step one is the part
a trigger could never do — a trigger cannot hold a lock across its own
statement.

**Q4 is worth pointing at:** it contains a correlated subquery and a
non-correlated one side by side, so the difference is visible in a
single statement.

### Member 4 — Escrow and the ledger

**Own these ideas:** the append-only ledger, the only nullable FK, the
closed-economy audit.

**Lead with Q5** — the audit. It is the argument the whole design works.
Then show the **PROOF** block: two attempts to tamper with the ledger,
both failing with ORA-20001. Screenshot those errors.

**Be ready for:** *"If `CreditBalance` is derived and not stored, why is
`balance_snapshot` stored? Is it not also derivable?"*

Yes — and the distinction is the whole answer:

| | `CreditBalance` | `balance_snapshot` |
|---|---|---|
| Belongs to | a student | one transaction |
| Changes | constantly | **never** |
| Purpose | current state | historical evidence |

An immutable historical fact is safe to store; a constantly changing
summary is not. Call it **controlled redundancy retained for
auditability**, and say it is never updated. `M4-Q4` is the query that
verifies the chain: every snapshot must equal the previous one plus the
current amount.

**And:** *"Why is `booking_id` nullable?"* Starter grants and penalties
have no originating session. It is the only nullable FK in the schema,
and it is the partial participation of `CREDIT_TXN` in "generates".

**Why Q2 must be an OUTER join:** `booking_id` is NULL for grants, so an
INNER join would silently drop every starter grant — and the totals in
Q5 would stop balancing.

### Member 5 — Feedback, disputes and fraud

**Own these ideas:** two weak entities with different kinds of partial
key, the self-join, collusion detection.

**Lead with Q4** — the credit-loop collusion detector. It is the most
distinctive query in the project.

**Be ready for:** *"Why is `reviewer_role` part of the primary key?"*
Because one booking carries **two** reviews, one from each side.
`(booking_id, reviewer_role)` identifies exactly one, and it enforces
"nobody reviews the same session twice" for free — the primary key does
the work a trigger would otherwise do.

**The consequence you must state:** a tutor's rating must average only
rows where `reviewer_role = 'TUTEE'`. Averaging both would mix in that
tutor's own opinions of their students, which measures nothing.

**And:** *"Why did `DISPUTE` not need a relationship to `STUDENT`?"*
Because only the two participants of a booking can raise one, so
`(booking_id, raised_by_role)` already identifies the complainant.

**Q2 is a self join:** `FEEDBACK` joined to itself twice, the two copies
told apart by `reviewer_role`. Only possible because the role is part of
the key. Both joins are OUTER, because many sessions get only one review
— the partial participation of `BOOKING` in "receives".

---

<a name="part-5"></a>
## Part 5 — Viva question bank

### On the ER model

**Q: Why is `SLOT` a weak entity?**
"Monday 4–5 pm" has no meaning on its own — only as *somebody's*
availability. And slot numbers restart for every tutor, so `slot_no`
alone cannot identify a row. Its full key is `(tutor_id, slot_no)`, and
it has total participation in the identifying relationship.

**Q: Show me a derived attribute and justify it.**
`CreditBalance` = `SUM(amount)` over that student's ledger rows. It is
drawn as a dashed oval and becomes no column — the ledger is the source
of truth and the balance is just its total.

**Q: Why not store `CreditBalance` for speed?**
You could, but then it is a deliberate **denormalization** maintained by
trigger on every ledger insert, and you must say so. Left as derived, it
cannot drift.

**Q: Your specialization — disjoint or overlapping? Total or partial?**
Overlapping and partial. Overlapping because one student teaches and
learns; partial because a new student is neither yet. Both facts are
visible in the seed data and in `M1-Q2`.

**Q: Should foreign keys appear in the ER diagram?**
No. In an ER diagram the relationship diamond **is** the foreign key.
Drawing a `DeptID` oval on Student records the same fact twice and mixes
the conceptual level with the implementation level. Foreign keys first
appear during ER-to-relational mapping.

### On the mapping

**Q: Walk me through your mapping steps.**
1 strong entities → 2 weak entities → 3 one-to-one (none here) → 4 one-to-many → 5 many-to-many → 6 multivalued attributes → 7 n-ary (none here) → 8 specialization (option 8A) → 9 union types (none here).

**Q: Can one foreign key be made of two columns?**
Yes — a composite foreign key, required whenever the referenced primary
key is composite. It must have the same number of columns, in the same
order, with the same types. `BOOKING` has two, and they share
`tutor_id`.

**Q: Why not two separate single-column constraints instead?**
Because that would check that a valid tutor exists and a valid slot
number exists, but not that the *pair* exists. Arjun could be booked
into Priya's slot.

### On SQL

**Q: Difference between a correlated and a non-correlated subquery?**
A non-correlated subquery never mentions the outer query, so Oracle
evaluates it once. A correlated one references an outer column, so it is
re-evaluated per outer row. `M3-Q4` shows both in one statement.

**Q: `WHERE` versus `HAVING`?**
`WHERE` filters rows *before* grouping and cannot see aggregates.
`HAVING` filters groups *after* aggregation and can. `M1-Q5` uses both.

**Q: Why use an analytic function instead of `GROUP BY`?**
`GROUP BY` collapses rows; an analytic function keeps every row. `M3-Q6`
shows a running total *beside* each individual session — `GROUP BY`
could give the total but would destroy the detail.

**Q: Why bind variables in the Java code?**
Two reasons. SQL injection: a bind value is never parsed as SQL.
Performance: Oracle parses `WHERE id = ?` once and reuses the plan,
whereas concatenation produces a new statement every time and fills the
shared pool with one-shot plans.

### On triggers and PL/SQL

**Q: Why are these rules triggers and not CHECK constraints?**
A CHECK constraint can only look at the columns of the row being
changed. It cannot call `SYSDATE`, cannot run a subquery, and cannot
compare one row with another. Every rule we implemented as a trigger
needs at least one of those.

**Q: What is the mutating-table restriction?**
A `FOR EACH ROW` trigger may not query the table its own statement is
changing — Oracle raises ORA-04091 — because it would see a
half-finished statement and an inconsistent view of the data.

**Q: How did you work around it?**
Three ways, and the choice is in the comments at the top of
`03_triggers.sql`:
- the double-booking and collusion checks moved into `PKG_TIMEBANK`,
  where the slot row can also be locked — a better home anyway
- badge promotion became a **compound trigger**: tutor ids are collected
  in `AFTER EACH ROW` and the `SUM` runs in `AFTER STATEMENT`, by which
  time the table is no longer mutating
- every remaining trigger reads a *different* table from the one it
  fires on

**Q: Why is the ledger append-only?**
So the audit means something. If rows could be edited, `SUM(amount)`
would prove nothing. Corrections are made by posting a compensating row,
exactly like real accounting.

### On concurrency

**Q: Two students book the same slot at the same instant. What happens?**
The second session blocks at `SELECT ... FOR UPDATE` inside
`book_session`, waiting for the first session's row lock. When the first
commits, the second wakes, sees the committed booking and fails with
ORA-20005. Exactly one booking exists.

**Q: Why not rely on the `SELECT` alone?**
Oracle uses multiversion read consistency. An ordinary `SELECT` never
blocks and never sees uncommitted work, so both sessions would read
"free" and both would insert. Explicit row locking is the only way to
serialise them.

**Q: Is this two-phase locking?**
Not textbook 2PL — Oracle's default is read consistency plus row locks
taken on demand and held to commit. The lock we take manually behaves
like the growing phase of 2PL for that one row.

### On the architecture

**Q: Your front end is Flutter. How does it use JDBC?**
It does not, and it cannot — JDBC is a Java API and no Oracle driver
exists for Dart. The architecture is three tiers: Flutter speaks
HTTP/JSON to a Spring Boot service, and that service speaks JDBC to
Oracle. The JDBC work is real; it lives in `api/`.

**Q: Why not put the business rules in Java?**
Because then they would hold only for requests that came through the
app. Rules in the database hold for every client — the app, the console
front end, and anyone connecting with SQL Developer.

---

<a name="part-6"></a>
## Part 6 — Traps that catch people out

| Trap | The correct position |
|---|---|
| "Completion writes two ledger rows" | **No.** One `HOLD` at booking, one `TRANSFER` at completion. A second debit would charge the tutee twice |
| "BCNF implies 4NF" | **No.** You must show the MVD explicitly |
| "Oracle has clustered B+ tree indexes" | **No.** The nearest thing is an index-organised table |
| "We used two-phase locking" | Oracle uses multiversion read consistency; you took an explicit row lock |
| "A tutor's rating is the average of all feedback" | Only rows where `reviewer_role = 'TUTEE'` |
| "A student's department limits what they can tutor" | **No.** Nothing in the schema does that, and three tutors teach outside their department |
| "We implemented Redis and MongoDB" | You did not. Future scope |
| "`balance_snapshot` is redundant, so it is a mistake" | It is *controlled* redundancy, immutable, kept for auditing |
| Foreign keys drawn on the ER diagram | They belong in the relational schema, not the ER diagram |

---

<a name="part-7"></a>
## Part 7 — Demo script

### Setup, before she arrives

```bash
cd sql
sqlplus timebank/timebank@//localhost:1521/FREEPDB1 @run_all.sql
```

Check two things:
1. The invalid-objects query at the end returns **no rows**
2. The audit prints **BALANCED**

Then start the API and leave it running:

```bash
cd ../api && mvn spring-boot:run
```

Open a **second** SQL Developer connection now, for the concurrency
demo. Doing it live under pressure wastes time.

### Running order

| # | What | Who |
|---|---|---|
| 1 | `@06_member1_onboarding.sql` | Member 1 |
| 2 | `@07_member2_skills.sql` | Member 2 |
| 3 | `@08_member3_booking.sql` | Member 3 |
| 4 | `@09_member4_credit.sql` | Member 4 |
| 5 | `@10_member5_feedback_disputes.sql` | Member 5 |
| 6 | `@11_group_tcl_plans.sql` | Everyone |
| 7 | The Flutter app | Whoever |

Run them **in order** — Member 2's INSERT makes Meera a tutor, and
Member 3's booking assumes Sara exists as a tutee. Later files build on
earlier ones. If anything goes wrong, `@run_all.sql` resets everything.

### What to say while your file runs

Each member: name the ER feature you own, point at your strongest query,
and give one sentence on *why it is written that way*. Not what it does
— she can read that — but why.

Examples:

- *"Q2 is a four-table join with two LEFT joins. They have to be outer,
  because an inner join would hide every student who is in neither
  subclass — and that is the partial specialization."*
- *"Q4 returns no rows, and that is the pass condition. It checks every
  balance snapshot against the previous one plus the amount."*
- *"The slot is locked with `FOR UPDATE` before the check, because
  Oracle's ordinary `SELECT` would not see the other session's
  uncommitted booking."*

### The three things to make sure she sees

1. **The concurrency demo** — part B, two sessions, the visible hang.
   Nothing else in the project demonstrates Module 4 as convincingly.
2. **The audit reporting BALANCED**, straight after the two
   ledger-tamper attempts fail with ORA-20001. The pair together make
   the argument: the ledger cannot be edited, and it adds up.
3. **`M1-Q2`** — the four role categories. It is the EER design proving
   itself in one result set.

---

## One last thing

If you only memorise one paragraph, memorise this:

> The specialization is overlapping and partial, which forces mapping
> option 8A. `BOOKING` carries two composite foreign keys that share
> `tutor_id`, so the database guarantees the slot and the subject both
> belong to that tutor. Derived attributes are not stored. The ledger is
> append-only, so the closed-economy audit means something — and it
> balances at 35.0.

Everything else you can reason out from the schema in front of you.
