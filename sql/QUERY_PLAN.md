# TimeBank — SQL Query Plan

Five members. **Every member has exactly the same 9 queries**, covering
exactly the same six SELECT categories, so the split is obviously equal.

**45 queries total.** The rubric asks for 8 per person (1 insert, 1
update, 1 delete, 5 selects); each member here has 9.

---

## Who owns what

| Member | Module | Tables owned | File |
|---|---|---|---|
| 1 | Onboarding & student profiles | `DEPARTMENT`, `STUDENT`, `STUDENT_PHONE`, `TUTOR`, `TUTEE`, `TUTEE_PREFTIME` | `06_member1_onboarding.sql` |
| 2 | Skill verification & availability | `SUBJECT`, `TUTOR_SKILL`, `SLOT` | `07_member2_skills.sql` |
| 3 | Booking engine & scheduling | `BOOKING` | `08_member3_booking.sql` |
| 4 | Escrow & the credit ledger | `CREDIT_TXN`, `CREDIT_POLICY` | `09_member4_credit.sql` |
| 5 | Feedback, disputes & fraud analytics | `FEEDBACK`, `DISPUTE`, `ADMIN` | `10_member5_feedback_disputes.sql` |
| — | Group demo, run once together | all | `11_group_tcl_plans.sql` |

No two members touch the same tables for their DML, so nobody can break
anybody else's demo by running their file first.

---

## The 9 queries every member has

| # | Type | What it must show |
|---|---|---|
| — | **INSERT** | adds a row to a table they own |
| — | **UPDATE** | modifies a row, with the reason the schema allows it |
| — | **DELETE** | removes a row, with the guard that makes it safe |
| Q1 | **Simple** | single table or one join, `WHERE`, `ORDER BY`, SQL functions |
| Q2 | **Multi-table join** | 4–6 tables, rebuilding ER relationships from foreign keys |
| Q3 | **Nested subquery** | non-correlated — inner query runs once |
| Q4 | **Correlated subquery** | inner query re-runs per outer row |
| Q5 | **Aggregate** | `GROUP BY` + `HAVING` + conditional aggregation |
| Q6 | **Analytic** | window functions with `PARTITION BY` / `OVER` |

---

## Member-by-member detail

### Member 1 — Onboarding & Profiles
*ER feature: the overlapping, partial specialization*

| Query | What it does |
|---|---|
| INSERT | Register a student + starter credits + two phone numbers, one transaction |
| UPDATE | Close an account — a soft delete, because the FKs forbid a real one |
| DELETE | Remove a phone number (a multivalued-attribute row) |
| Q1 | Student directory with **derived age** |
| Q2 | 4-table join: **tutor / tutee / BOTH / NEITHER** — proves the specialization |
| Q3 | Balance below campus average (2-level nested) |
| Q4 | Registered 30+ days, never booked (`NOT EXISTS`) |
| Q5 | Department scoreboard — `COUNT`, `SUM(CASE)`, `AVG`, `RPAD`, `HAVING` |
| Q6 | Balance ranking within department — `RANK`, `DENSE_RANK`, `PERCENT_RANK`, `NTILE`, `LAG` |

**Q2 is the one to present.** It is the single clearest proof the EER
design is right.

### Member 2 — Skills & Availability
*ER features: the M:N relationship, and SLOT as a weak entity*

| Query | What it does |
|---|---|
| INSERT | A tutee becomes a tutor: `TUTOR` + `TUTOR_SKILL` + 2 slots (partial key restarts at 1) |
| UPDATE | Promote to EXPERT — two correlated subqueries set the bar |
| DELETE | Withdraw an unused slot, guarded against the composite FK |
| Q1 | Subject catalogue |
| Q2 | 5-table join: the skill matrix, flagging **cross-department tutoring** |
| Q3 | Subjects with no tutor — `NOT IN`, and why that is safe here |
| Q4 | Unbooked slots next week — correlated on **three** columns |
| Q5 | Capacity vs demand per subject |
| Q6 | Tutor ranking within subject — `RANK`, `COUNT OVER`, `LAG`, `FIRST_VALUE` |

### Member 3 — Booking Engine
*ER feature: two composite foreign keys sharing a column*

| Query | What it does |
|---|---|
| INSERT | Book a session through the package — lock, check, insert, escrow |
| UPDATE | Reschedule by a week, guarded by a correlated `NOT EXISTS` |
| DELETE | Purge abandoned requests — only rows no ledger entry points at |
| Q1 | Upcoming sessions, decimal hour converted to clock time |
| Q2 | **6-table join** — every ER relationship rebuilt from its FKs |
| Q3 | Tutors free all next week |
| Q4 | Tutors busier than average — **correlated and non-correlated side by side** |
| Q5 | Booking funnel by subject — conditional aggregation |
| Q6 | Running teaching load — `ROW_NUMBER`, `SUM OVER`, `RATIO_TO_REPORT` |

### Member 4 — Escrow & Ledger
*ER feature: the only nullable FK; a derived attribute deliberately not stored*

| Query | What it does |
|---|---|
| INSERT | Goodwill credit — `balance_snapshot` computed in the statement |
| UPDATE | Tighten the overdraft policy (policy lives in a table, not in code) |
| DELETE | Clear stale escrow markers, then a true delete + `ROLLBACK` |
| **PROOF** | Two attempts to tamper with the ledger, both failing with ORA-20001 |
| Q1 | Passbook for one student |
| Q2 | Ledger + session — **OUTER join**, because `booking_id` is NULL for grants |
| Q3 | Net givers and net takers |
| Q4 | **Tamper detection** — correlated, 3 levels, expects **zero rows** |
| Q5 | **The closed-economy audit** — `GROUPING SETS` + the balance equation |
| Q6 | Running balance rebuilt with window functions, checked against the stored snapshot |

**Q5 is the one to present.** It is the argument the whole design works.

### Member 5 — Feedback, Disputes & Fraud
*ER feature: two weak entities, each with a different kind of partial key*

| Query | What it does |
|---|---|
| INSERT | Leave a review + raise a dispute (`dispute_no` restarts per booking) |
| UPDATE | Triage the dispute queue, assigning the least-loaded admin |
| DELETE | Retract a review + discard colluded ratings |
| Q1 | Reviews and disputes — `UNION ALL` |
| Q2 | **Self join** — FEEDBACK joined to itself, split by `reviewer_role` |
| Q3 | Above-average tutors — **3-level nested**, average of averages |
| Q4 | **Credit-loop collusion detector** — the project's headline fraud query |
| Q5 | Rating distribution — `ROLLUP`, `STDDEV`, histogram buckets |
| Q6 | Rating trend per tutor — `LAG`, moving average, `DENSE_RANK`, `NTILE` |

**Q4 is the one to present.** It is the most distinctive query in the
project.

### Group file — run once, together

| Part | Module | What it shows |
|---|---|---|
| A | 4 | `SAVEPOINT`, partial `ROLLBACK`, atomicity of a failed booking |
| B | 4 | **Two-session double-booking demo** — run in two SQL Developer windows |
| C | 3 | `EXPLAIN PLAN` with and without an index, costs compared |
| D | — | Final closed-economy audit |
| E | 6 | Leaderboard (CTE), knowledge-flow graph (`CONNECT BY NOCYCLE`), cross-department `ROLLUP` |

**Part B is the strongest exhibit in the entire project.** Session 2
visibly hangs on session 1's row lock, then fails once session 1
commits. Screenshot it.

---

## Running order

```bash
sqlplus timebank/timebank@//localhost:1521/FREEPDB1

@run_all.sql                        -- builds the database (run once)

@06_member1_onboarding.sql          -- member 1 presents
@07_member2_skills.sql              -- member 2 presents
@08_member3_booking.sql             -- member 3 presents
@09_member4_credit.sql              -- member 4 presents
@10_member5_feedback_disputes.sql   -- member 5 presents
@11_group_tcl_plans.sql             -- everyone, together
```

Run them **in order**. Member 2's INSERT makes Meera a tutor, and
Member 3's booking assumes Sara exists as a tutee — files later in the
sequence build on earlier ones, exactly as a real session would.

To start over at any point: `@run_all.sql` rebuilds everything from
scratch.

---

## Coverage check against the rubric

> *"Expected at least one Insert, delete and update and five select
> queries including simple, complex, nested query and SQL functions."*

| Requirement | Per member | Total |
|---|---|---|
| INSERT | 1 | 5 |
| UPDATE | 1 | 5 |
| DELETE | 1 | 5 |
| SELECT — simple | 1 | 5 |
| SELECT — complex join | 1 | 5 |
| SELECT — nested | 1 | 5 |
| SELECT — correlated | 1 | 5 |
| SELECT — aggregate / SQL functions | 1 | 5 |
| SELECT — analytic | 1 | 5 |
| **Total** | **9** | **45** |

Plus the group file: TCL, concurrency, `EXPLAIN PLAN`, and hierarchical
queries.
