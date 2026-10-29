-- =====================================================================
--  TimeBank
--  File    : 11_group_tcl_plans.sql
--  Purpose : The GROUP demonstration -- not owned by any one member.
--            Transaction control (Module 4), query optimisation
--            (Module 3) and contemporary trends (Module 6).
--
--  Each of the five members presents their own file (06 to 10). This
--  one is run once, together, because it demonstrates behaviour of the
--  database as a whole rather than any single module's queries.
-- =====================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 200


-- #####################################################################
--  PART A -- TCL : COMMIT, ROLLBACK and SAVEPOINT
--
--  An escrow transfer touches BOOKING and CREDIT_TXN together.  If the
--  machine died between the two, credits would vanish.  Wrapping them
--  in one transaction makes the pair atomic -- the A in ACID.
-- #####################################################################
PROMPT
PROMPT ========== PART A : TCL ==========
PROMPT
PROMPT --- A1. SAVEPOINT and partial rollback ---

DECLARE
  v_before  NUMBER;
  v_mid     NUMBER;
  v_after   NUMBER;
BEGIN
  v_before := pkg_timebank.fn_balance (104);
  DBMS_OUTPUT.PUT_LINE ('Balance at the start      : ' || v_before);

  SAVEPOINT before_adjustments;

  -- Adjustment 1: a goodwill credit.
  INSERT INTO credit_txn (txn_id, txn_type, amount, balance_snapshot,
                          remarks, student_id, booking_id)
  VALUES (seq_txn.NEXTVAL, 'GRANT', 2.0,
          (SELECT NVL (SUM (amount),0) + 2.0 FROM credit_txn
           WHERE student_id = 104),
          'Goodwill credit', 104, NULL);

  v_mid := pkg_timebank.fn_balance (104);
  DBMS_OUTPUT.PUT_LINE ('After the goodwill credit : ' || v_mid);

  SAVEPOINT after_goodwill;

  -- Adjustment 2: a penalty that we then decide was wrong.
  INSERT INTO credit_txn (txn_id, txn_type, amount, balance_snapshot,
                          remarks, student_id, booking_id)
  VALUES (seq_txn.NEXTVAL, 'PENALTY', -2.0,
          (SELECT NVL (SUM (amount),0) - 2.0 FROM credit_txn
           WHERE student_id = 104),
          'Penalty applied in error', 104, NULL);

  DBMS_OUTPUT.PUT_LINE ('After the penalty         : ' ||
                        pkg_timebank.fn_balance (104));

  -- Undo ONLY the penalty. The goodwill credit survives, because
  -- ROLLBACK TO rewinds to a savepoint instead of to the start.
  ROLLBACK TO after_goodwill;

  v_after := pkg_timebank.fn_balance (104);
  DBMS_OUTPUT.PUT_LINE ('After ROLLBACK TO savepoint: ' || v_after);

  IF v_after = v_mid THEN
    DBMS_OUTPUT.PUT_LINE ('=> Correct: the penalty was undone, the credit kept.');
  END IF;

  -- Now discard everything and leave the data as it was.
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE ('After full ROLLBACK        : ' ||
                        pkg_timebank.fn_balance (104));
END;
/


PROMPT
PROMPT --- A2. Atomicity: a failed booking leaves no trace ---

DECLARE
  v_bk     NUMBER;
  v_code   VARCHAR2(8);
  v_rows   NUMBER;
BEGIN
  SELECT COUNT (*) INTO v_rows FROM credit_txn;
  DBMS_OUTPUT.PUT_LINE ('Ledger rows before : ' || v_rows);

  -- This booking is doomed: tutor 101 has no slot number 9. The package
  -- catches it at the SELECT ... FOR UPDATE, before anything is written.
  -- Had it got past that, the composite foreign key (tutor_id, slot_no)
  -- would have stopped it at the INSERT.
  BEGIN
    pkg_timebank.book_session (
        p_tutee_id => 102, p_tutor_id => 101, p_subject_id => 101,
        p_slot_no  => 9,                      -- tutor 101 has no slot 9
        p_sched_date => TRUNC (SYSDATE,'IW') + 14,
        p_start_time => 16, p_duration => 1.0,
        p_mode => 'OFFLINE', p_venue => 'SJT 512',
        p_booking_id => v_bk, p_session_code => v_code);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE ('Rejected as expected -> ' ||
                            SUBSTR (SQLERRM, 1, 90));
      ROLLBACK;
  END;

  SELECT COUNT (*) INTO v_rows FROM credit_txn;
  DBMS_OUTPUT.PUT_LINE ('Ledger rows after  : ' || v_rows ||
                        '   (unchanged = atomic)');
END;
/


-- #####################################################################
--  PART B -- CONCURRENCY : the double-booking anomaly
--
--  RUN THIS BY HAND IN TWO SQL DEVELOPER SESSIONS SIDE BY SIDE.
--  It is the clearest demonstration in the whole project, and a
--  screenshot of the second session hanging is worth including.
--
--  Oracle uses multiversion read consistency, NOT textbook two-phase
--  locking: an ordinary SELECT never blocks and never sees another
--  session's uncommitted work.  So without an explicit row lock, both
--  sessions would read "slot free" and both would insert.
--
--  ---------------- SESSION 1 ----------------------------------------
--    SET SERVEROUTPUT ON
--    DECLARE v_bk NUMBER; v_c VARCHAR2(8); BEGIN
--      pkg_timebank.book_session (102, 101, 101, 1,
--        TRUNC(SYSDATE,'IW')+21, 16, 1.0, 'OFFLINE', 'SJT 512', v_bk, v_c);
--      DBMS_OUTPUT.PUT_LINE ('Session 1 got booking ' || v_bk);
--    END;
--    /
--    -- DO NOT COMMIT YET. Leave this session sitting here.
--
--  ---------------- SESSION 2 (a different connection) ----------------
--    DECLARE v_bk NUMBER; v_c VARCHAR2(8); BEGIN
--      pkg_timebank.book_session (112, 101, 101, 1,
--        TRUNC(SYSDATE,'IW')+21, 16, 1.0, 'OFFLINE', 'SJT 512', v_bk, v_c);
--    END;
--    /
--    -- This session now HANGS at the SELECT ... FOR UPDATE inside
--    -- book_session. It is waiting for session 1's row lock.
--
--  ---------------- BACK IN SESSION 1 --------------------------------
--    COMMIT;
--
--  ---------------- SESSION 2 WAKES UP -------------------------------
--    -- It now sees the committed booking and fails with:
--    --   ORA-20005: That slot is already booked on ...
--    -- Exactly one booking exists. The anomaly was prevented.
--
--  To see what happens WITHOUT the lock, comment out the FOR UPDATE in
--  book_session, recompile, and repeat: both sessions succeed and the
--  tutor is double-booked.
-- #####################################################################
PROMPT
PROMPT ========== PART B : see the comments for the two-session demo ==========


-- #####################################################################
--  PART C -- QUERY OPTIMISATION (Module 3)
--
--  EXPLAIN PLAN shows the access path the optimiser chose.  Read the
--  plan from the MOST INDENTED line outwards -- that is the order the
--  steps actually run in.
-- #####################################################################
PROMPT
PROMPT ========== PART C : query plans ==========
PROMPT
PROMPT --- C1. Tutor search WITH the index (expect INDEX RANGE SCAN) ---

EXPLAIN PLAN SET STATEMENT_ID = 'with_index' FOR
SELECT ts.tutor_id, ts.competency_level
FROM   tutor_skill ts
WHERE  ts.subject_id = 101;

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY (NULL, 'with_index', 'BASIC +COST'));


PROMPT
PROMPT --- C2. The same question WITHOUT the index (expect FULL scan) ---
PROMPT --- /*+ FULL */ forces the optimiser to ignore it, so the two  ---
PROMPT --- costs can be compared directly.                            ---

EXPLAIN PLAN SET STATEMENT_ID = 'no_index' FOR
SELECT /*+ FULL(ts) */ ts.tutor_id, ts.competency_level
FROM   tutor_skill ts
WHERE  ts.subject_id = 101;

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY (NULL, 'no_index', 'BASIC +COST'));


PROMPT
PROMPT --- C3. Heuristic optimisation: pushing selection down the tree ---
PROMPT --- Both queries below return the same rows. The first filters  ---
PROMPT --- early (good), the second joins everything then filters.     ---

-- Relational algebra for the good version:
--   pi_{name, rating} ( sigma_{role='TUTEE' AND rating>=4.5} (FEEDBACK)
--                       |><|  BOOKING  |><|  STUDENT )
-- The selection sits INSIDE the join, so fewer rows are ever joined.

EXPLAIN PLAN SET STATEMENT_ID = 'pushed' FOR
SELECT s.first_name, f.rating
FROM   feedback f
       JOIN booking b ON b.booking_id = f.booking_id
       JOIN student s ON s.student_id = b.tutor_id
WHERE  f.reviewer_role = 'TUTEE'
AND    f.rating       >= 4.5;

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY (NULL, 'pushed', 'BASIC +COST'));


PROMPT
PROMPT --- C4. Index-only scan: the answer comes from the index alone ---
PROMPT --- Look for "INDEX FAST FULL SCAN" and the absence of any     ---
PROMPT --- TABLE ACCESS step -- the table is never touched.           ---

EXPLAIN PLAN SET STATEMENT_ID = 'index_only' FOR
SELECT subject_id, COUNT (*)
FROM   tutor_skill
GROUP  BY subject_id;

SELECT * FROM TABLE (DBMS_XPLAN.DISPLAY (NULL, 'index_only', 'BASIC +COST'));


-- #####################################################################
--  PART D -- final integrity check
-- #####################################################################
PROMPT
PROMPT ========== PART D : final audit ==========

EXEC pkg_timebank.audit_economy;


-- #####################################################################
--  PART E -- MODULE 6 : CONTEMPORARY TRENDS
--  Graph thinking, without a graph database.
--
--  The syllabus asks about graph databases. A relational database can
--  already walk a graph -- these two queries show how, which is a
--  stronger answer than describing Neo4j from a slide.
-- #####################################################################
PROMPT
PROMPT ========== PART E : Module 6, graph analytics ==========
PROMPT
PROMPT --- E1. Tutor leaderboard (CTE + four analytic functions) ---

-- WITH names the intermediate result so the analytic functions stay
-- readable instead of nesting four subqueries deep.
WITH tutor_stats AS (
    SELECT b.tutor_id,
           COUNT (*)                      AS sessions,
           SUM (b.duration_hours)         AS hours,
           (SELECT ROUND (AVG (f.rating), 2)
            FROM   feedback f
                   JOIN booking b2 ON b2.booking_id = f.booking_id
            WHERE  b2.tutor_id     = b.tutor_id
            AND    f.reviewer_role = 'TUTEE')  AS avg_rating
    FROM   booking b
    WHERE  b.status = 'COMPLETED'
    GROUP  BY b.tutor_id)
SELECT DENSE_RANK () OVER (ORDER BY ts.hours DESC)         AS rnk,
       s.first_name || ' ' || s.last_name                  AS tutor_name,
       d.school,
       t.badge_level,
       ts.sessions,
       ts.hours,
       NVL (ts.avg_rating, 0)                              AS rating,
       ROUND (ts.hours * NVL (ts.avg_rating, 0), 2)        AS impact_score,
       ROUND (PERCENT_RANK () OVER (ORDER BY ts.hours), 2) AS percentile,
       NTILE (4) OVER (ORDER BY ts.hours DESC)             AS quartile,
       LEAD (ts.hours) OVER (ORDER BY ts.hours DESC)       AS next_tutor_hours
FROM   tutor_stats ts
       JOIN tutor      t ON t.student_id = ts.tutor_id
       JOIN student    s ON s.student_id = ts.tutor_id
       JOIN department d ON d.dept_id    = s.dept_id
ORDER  BY ts.hours DESC;


PROMPT
PROMPT --- E2. Knowledge-flow chains (HIERARCHICAL query) ---

-- Each completed session is an edge  tutee -> tutor  ("learned from").
-- CONNECT BY walks those edges outward from one student to find the
-- chain of people whose knowledge reached them indirectly:
-- A learned from B, who learned from C.
--
-- NOCYCLE is what stops it looping for ever on a reciprocal pair --
-- the same collusion that Member 5's Q4 hunts for. Without NOCYCLE,
-- a pair who tutored each other would make this query run until it
-- raised ORA-01436.
--
-- The edges are built in a CTE first, names included, so the CONNECT BY
-- walks a single flat row source. Mixing joins into a hierarchical
-- query works but is far harder to read, and harder to debug.
WITH learning_edge AS (
    SELECT DISTINCT
           b.tutee_id                AS learner_id,
           b.tutor_id                AS teacher_id,
           le.first_name             AS learner_name,
           te.first_name             AS teacher_name
    FROM   booking b
           JOIN student le ON le.student_id = b.tutee_id
           JOIN student te ON te.student_id = b.tutor_id
    WHERE  b.status = 'COMPLETED')
SELECT LEVEL                                                AS hop,
       LPAD (' ', (LEVEL - 1) * 3) || learner_name          AS learner_chain,
       teacher_name                                         AS learned_from,
       SYS_CONNECT_BY_PATH (teacher_name, ' <- ')           AS knowledge_path,
       CONNECT_BY_ISLEAF                                    AS end_of_chain
FROM   learning_edge
START WITH learner_id = 102
CONNECT BY NOCYCLE PRIOR teacher_id = learner_id
ORDER  SIBLINGS BY learner_name;


PROMPT
PROMPT --- E3. Cross-department knowledge flow (ROLLUP) ---

-- The query that answers the design question "why is DEPARTMENT in the
-- model at all?". It measures how much tutoring crosses departmental
-- boundaries -- which a student's own department never restricts.
SELECT CASE WHEN GROUPING (sd.school) = 1 THEN '** ALL SCHOOLS **'
            ELSE sd.school END                      AS tutor_school,
       CASE WHEN GROUPING (subd.school) = 1 THEN '** all subjects **'
            ELSE subd.school END                    AS subject_school,
       COUNT (*)                                    AS sessions,
       SUM (b.duration_hours)                       AS hours,
       COUNT (DISTINCT b.tutor_id)                  AS tutors
FROM   booking b
       JOIN student    s    ON s.student_id    = b.tutor_id
       JOIN department sd   ON sd.dept_id      = s.dept_id
       JOIN subject    sub  ON sub.subject_id  = b.subject_id
       JOIN department subd ON subd.dept_id    = sub.dept_id
WHERE  b.status = 'COMPLETED'
GROUP  BY ROLLUP (sd.school, subd.school)
ORDER  BY GROUPING (sd.school), tutor_school,
          GROUPING (subd.school), subject_school;
