-- =====================================================================
--  TimeBank -- MEMBER 4 of 5 : Escrow & the Credit Ledger
--  File    : 09_member4_credit.sql
--
--  Tables owned : CREDIT_TXN, CREDIT_POLICY
--  ER feature   : the ONLY NULLABLE FOREIGN KEY in the database, and a
--                 derived attribute that is deliberately not stored
--
--  A NOTE ON "UPDATE" AND "DELETE" FOR THIS MODULE
--  The ledger is append-only and a trigger physically blocks both. That
--  is the entire point of a ledger, so this module demonstrates its
--  UPDATE and DELETE on the tables it legitimately owns -- the policy
--  settings and the escrow marker -- and then PROVES the ledger itself
--  cannot be touched. Those two failures are worth screenshotting.
--
--  QUERY SHEET (identical in shape for all five members)
--    DML : 1 INSERT, 1 UPDATE, 1 DELETE
--    Q1 simple | Q2 join | Q3 nested | Q4 correlated
--    Q5 aggregate + GROUP BY/HAVING | Q6 analytic
-- =====================================================================

SET SERVEROUTPUT ON
SET LINESIZE 220
SET PAGESIZE 100


-- #####################################################################
--  DML 1 of 3 -- INSERT
--  An administrative goodwill credit.
--
--  balance_snapshot must be COMPUTED, not guessed: it is the balance
--  before this row plus this row's amount. Doing it with a scalar
--  subquery keeps the whole thing one atomic statement -- reading the
--  balance into a variable first would leave a gap in which another
--  session could post a row, and the snapshot would be wrong.
--
--  booking_id is NULL here. No session caused this, and it is the only
--  nullable foreign key in the schema: the partial participation of
--  CREDIT_TXN in the "generates" relationship.
-- #####################################################################
PROMPT
PROMPT ========== M4-INSERT : goodwill credit after an outage ==========

INSERT INTO credit_txn (
    txn_id, txn_type, amount, balance_snapshot,
    remarks, student_id, booking_id)
VALUES (
    seq_txn.NEXTVAL,
    'GRANT',
    1.0,
    (SELECT NVL (SUM (amount), 0) + 1.0
     FROM   credit_txn
     WHERE  student_id = 106),
    'Goodwill credit: scheduling outage on the platform',
    106,
    NULL);

COMMIT;


-- #####################################################################
--  DML 2 of 3 -- UPDATE
--  Tighten the overdraft policy from -5.0 to -4.0 credits.
--
--  The limit lives in a TABLE rather than hard-coded in the trigger, so
--  changing the rule is one UPDATE and needs no recompilation.
--  trg_credit_floor reads this row on every booking attempt.
-- #####################################################################
PROMPT
PROMPT ========== M4-UPDATE : tighten the overdraft policy ==========

UPDATE credit_policy
SET    policy_value = -4.0,
       description  = description || ' (tightened after review)'
WHERE  policy_key   = 'OVERDRAFT_FLOOR';

COMMIT;

-- Restore it so the rest of the demo runs against the documented rule.
UPDATE credit_policy
SET    policy_value = -5.0,
       description  = 'A balance may never fall below this value'
WHERE  policy_key   = 'OVERDRAFT_FLOOR';

COMMIT;


-- #####################################################################
--  DML 3 of 3 -- DELETE
--  Clear stale escrow markers, then a true row delete.
--
--  credits_held is a working column, not history: once a booking is
--  COMPLETED or CANCELLED the money has already moved, so any leftover
--  value is stale. That part is committed.
--
--  The DELETE then removes a policy row -- a genuine delete on a table
--  nothing references -- and is rolled back, because cancel_booking
--  reads that row.
-- #####################################################################
PROMPT
PROMPT ========== M4-DELETE : clear escrow, then a true delete ==========

UPDATE booking
SET    credits_held = 0
WHERE  status IN ('COMPLETED','CANCELLED')
AND    credits_held > 0;

COMMIT;       -- keep this part

DELETE FROM credit_policy
WHERE  policy_key = 'LATE_CANCEL_SHARE'
AND    NOT EXISTS (SELECT 1 FROM booking WHERE status = 'DISPUTED');

ROLLBACK;     -- but put the policy row back


-- #####################################################################
--  PROOF : the ledger really is immutable
--  Both blocks below are EXPECTED TO FAIL with ORA-20001.
--  Screenshot this output -- it proves the audit trail cannot be
--  rewritten, which is what makes Q5 below mean anything.
-- #####################################################################
PROMPT
PROMPT ========== M4-PROOF : attempts to tamper with the ledger ==========

BEGIN
  UPDATE credit_txn SET amount = 999 WHERE txn_id = 1;
  DBMS_OUTPUT.PUT_LINE ('!! UPDATE succeeded -- the ledger is NOT protected');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE ('Blocked as designed -> ' || SQLERRM);
END;
/

BEGIN
  DELETE FROM credit_txn WHERE txn_id = 1;
  DBMS_OUTPUT.PUT_LINE ('!! DELETE succeeded -- the ledger is NOT protected');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE ('Blocked as designed -> ' || SQLERRM);
END;
/


-- #####################################################################
--  Q1 -- SIMPLE
--  A passbook for one student: every movement, newest first.
--
--  This is the index idx_txn_student_time earning its keep. The leading
--  column narrows to one student, and the second delivers the rows
--  already sorted, so the ORDER BY needs no sort step at all.
-- #####################################################################
PROMPT
PROMPT ===== M4-Q1 : passbook for student 102 (SIMPLE) =====

SELECT t.txn_id,
       TO_CHAR (t.txn_timestamp, 'DD-MON HH24:MI') AS posted_at,
       t.txn_type,
       t.amount,
       t.balance_snapshot                          AS balance_after,
       NVL (TO_CHAR (t.booking_id), '-')           AS booking,
       t.remarks
FROM   credit_txn t
WHERE  t.student_id = 102
ORDER  BY t.txn_id DESC;


-- #####################################################################
--  Q2 -- MULTI-TABLE JOIN, with an OUTER JOIN
--  Every ledger row alongside the session that caused it.
--
--  The LEFT JOIN is essential, not cosmetic. booking_id is NULL for
--  GRANT and PENALTY rows, so an INNER join would silently drop every
--  starter grant -- and the totals in Q5 would stop balancing.
--
--  This is the partial participation of CREDIT_TXN in "generates",
--  showing up directly in the SQL.
-- #####################################################################
PROMPT
PROMPT ===== M4-Q2 : ledger with session context (OUTER JOIN) =====

SELECT t.txn_id,
       s.first_name || ' ' || s.last_name       AS student_name,
       t.txn_type,
       t.amount,
       NVL (sub.subject_code, 'n/a')            AS subject,
       NVL (TO_CHAR (b.sched_date, 'DD-MON'), 'no session')
                                                AS session_date,
       CASE WHEN t.booking_id IS NULL
            THEN 'system credit'
            ELSE 'session driven' END            AS origin
FROM   credit_txn t
       JOIN      student s   ON s.student_id   = t.student_id
       LEFT JOIN booking b   ON b.booking_id   = t.booking_id
       LEFT JOIN subject sub ON sub.subject_id = b.subject_id
ORDER  BY t.txn_id;


-- #####################################################################
--  Q3 -- NESTED (NON-CORRELATED) SUBQUERY
--  Net givers and net takers.
--
--  The inner query aggregates the ledger per student in an inline view;
--  the outer query classifies the result. Doing the aggregation inside
--  lets the CASE be written against clean column names instead of
--  repeating SUM(amount) three times.
-- #####################################################################
PROMPT
PROMPT ===== M4-Q3 : who gives and who takes (NESTED) =====

SELECT s.first_name || ' ' || s.last_name   AS student_name,
       led.total_in                         AS credits_in,
       led.total_out                        AS credits_out,
       led.balance,
       CASE
         WHEN led.balance > 3.0  THEN 'NET GIVER'
         WHEN led.balance < 1.0  THEN 'NET TAKER'
         ELSE                         'balanced'
       END                                  AS standing
FROM   student s
       JOIN (SELECT student_id,
                    SUM (CASE WHEN amount > 0 THEN amount ELSE 0 END) AS total_in,
                    SUM (CASE WHEN amount < 0 THEN amount ELSE 0 END) AS total_out,
                    SUM (amount)                                      AS balance
             FROM   credit_txn
             GROUP  BY student_id) led
         ON led.student_id = s.student_id
ORDER  BY led.balance DESC;


-- #####################################################################
--  Q4 -- CORRELATED SUBQUERY : tamper detection
--  Every balance_snapshot must equal the previous snapshot for THAT
--  student plus the current amount. Any row where it does not means the
--  ledger was edited behind the trigger's back.
--
--  The correlated subquery finds "the previous row for this student",
--  which needs both the outer row's student_id and its txn_id. The
--  nesting is three deep: find the previous txn_id, read its snapshot,
--  compare.
--
--  EXPECTED RESULT: NO ROWS. That is the pass condition, and it is the
--  companion to the immutability proof above -- one shows the ledger
--  cannot be edited, this one shows it has not been.
-- #####################################################################
PROMPT
PROMPT ===== M4-Q4 : ledger tamper check (CORRELATED) -- expect 0 rows =====

SELECT t.txn_id,
       t.student_id,
       t.amount,
       t.balance_snapshot                       AS recorded,
       NVL ((SELECT t2.balance_snapshot
             FROM   credit_txn t2
             WHERE  t2.student_id = t.student_id
             AND    t2.txn_id     = (SELECT MAX (t3.txn_id)
                                     FROM   credit_txn t3
                                     WHERE  t3.student_id = t.student_id
                                     AND    t3.txn_id     < t.txn_id)), 0)
         + t.amount                             AS expected
FROM   credit_txn t
WHERE  t.balance_snapshot <>
       NVL ((SELECT t2.balance_snapshot
             FROM   credit_txn t2
             WHERE  t2.student_id = t.student_id
             AND    t2.txn_id     = (SELECT MAX (t3.txn_id)
                                     FROM   credit_txn t3
                                     WHERE  t3.student_id = t.student_id
                                     AND    t3.txn_id     < t.txn_id)), 0)
         + t.amount
ORDER  BY t.txn_id;


-- #####################################################################
--  Q5 -- AGGREGATE : the closed-economy audit
--  The single most important query in the whole project.
--
--     sum of every balance  +  credits sitting in escrow
--                  =  total granted  -  total penalised
--
--  Every session writes one HOLD and one TRANSFER that cancel out, so a
--  finished session changes the grand total by nothing. Only a starter
--  GRANT adds credits and only a PENALTY removes them. If the two sides
--  ever disagree, credits were created or destroyed outside the ledger.
--
--  GROUPING SETS produces the per-type breakdown AND the grand total in
--  one pass, instead of two queries joined by UNION ALL.
--
--  The output column is aliased txn_kind, not txn_type. Reusing the
--  base column's name would make the ORDER BY bind to the alias --
--  which NVL has already made non-null -- and the grand total would not
--  sort to the bottom.
-- #####################################################################
PROMPT
PROMPT ===== M4-Q5 : closed-economy audit (AGGREGATE) =====

SELECT NVL (txn_type, '** ALL TYPES **')   AS txn_kind,
       COUNT (*)                           AS rows_posted,
       SUM (amount)                        AS net_credits,
       MIN (amount)                        AS smallest,
       MAX (amount)                        AS largest
FROM   credit_txn
GROUP  BY GROUPING SETS ((txn_type), ())
HAVING COUNT (*) >= 1
ORDER  BY GROUPING (txn_type), txn_kind;

PROMPT
PROMPT --- the balance equation itself ---

SELECT (SELECT NVL (SUM (amount), 0) FROM credit_txn)          AS all_balances,
       (SELECT NVL (SUM (credits_held), 0) FROM booking
        WHERE  status IN ('REQUESTED','CONFIRMED','DISPUTED')) AS in_escrow,
       (SELECT NVL (SUM (amount), 0) FROM credit_txn
        WHERE  txn_type IN ('GRANT','PENALTY'))                AS grants_less_penalties,
       (SELECT NVL (SUM (amount), 0) FROM credit_txn)
       + (SELECT NVL (SUM (credits_held), 0) FROM booking
          WHERE  status IN ('REQUESTED','CONFIRMED','DISPUTED'))
       - (SELECT NVL (SUM (amount), 0) FROM credit_txn
          WHERE  txn_type IN ('GRANT','PENALTY'))              AS drift,
       CASE WHEN (SELECT NVL (SUM (amount), 0) FROM credit_txn)
                 + (SELECT NVL (SUM (credits_held), 0) FROM booking
                    WHERE status IN ('REQUESTED','CONFIRMED','DISPUTED'))
                 - (SELECT NVL (SUM (amount), 0) FROM credit_txn
                    WHERE txn_type IN ('GRANT','PENALTY')) = 0
            THEN 'BALANCED'
            ELSE '*** BROKEN ***' END                          AS verdict
FROM   dual;


-- #####################################################################
--  Q6 -- ANALYTIC (WINDOW) FUNCTIONS
--  Rebuild each student's running balance from the ledger alone, and
--  compare it against the stored snapshot.
--
--    SUM() OVER (PARTITION BY ... ORDER BY ...)  the running total
--    LAG()                                       the previous row's type
--    FIRST_VALUE()                               their opening grant
--
--  The recomputed column should match balance_snapshot on EVERY row.
--  Two independent routes to the same number is what makes an audit
--  trail trustworthy -- and unlike Q4, this one needs no subqueries at
--  all, which is exactly why window functions exist.
-- #####################################################################
PROMPT
PROMPT ===== M4-Q6 : recomputed running balance (ANALYTIC) =====

SELECT s.first_name                                  AS student,
       t.txn_id,
       t.txn_type,
       t.amount,
       SUM (t.amount) OVER (PARTITION BY t.student_id
                            ORDER BY t.txn_id
                            ROWS BETWEEN UNBOUNDED PRECEDING
                                     AND CURRENT ROW) AS recomputed,
       t.balance_snapshot                             AS stored,
       CASE WHEN SUM (t.amount) OVER (PARTITION BY t.student_id
                                      ORDER BY t.txn_id
                                      ROWS BETWEEN UNBOUNDED PRECEDING
                                               AND CURRENT ROW)
                 = t.balance_snapshot
            THEN 'ok' ELSE 'MISMATCH' END             AS check_result,
       LAG (t.txn_type) OVER (PARTITION BY t.student_id
                              ORDER BY t.txn_id)      AS previous_type,
       FIRST_VALUE (t.amount) OVER (PARTITION BY t.student_id
                                    ORDER BY t.txn_id) AS opening_grant
FROM   credit_txn t
       JOIN student s ON s.student_id = t.student_id
ORDER  BY t.student_id, t.txn_id;


PROMPT
PROMPT ===== MEMBER 4 COMPLETE : 3 DML + 6 SELECT = 9 queries =====
