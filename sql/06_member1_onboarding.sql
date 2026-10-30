-- =====================================================================
--  TimeBank -- MEMBER 1 of 5 : User Onboarding & Student Profiles
--  File    : 06_member1_onboarding.sql
--
--  Tables owned : DEPARTMENT, STUDENT, STUDENT_PHONE, TUTOR, TUTEE,
--                 TUTEE_PREFTIME
--  ER feature   : the overlapping, partial SPECIALIZATION
--
--  QUERY SHEET (identical in shape for all five members)
--    DML : 1 INSERT, 1 UPDATE, 1 DELETE
--    Q1  : simple
--    Q2  : multi-table join
--    Q3  : nested (non-correlated) subquery
--    Q4  : correlated subquery
--    Q5  : aggregate with GROUP BY and HAVING
--    Q6  : analytic (window) function
-- =====================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100


-- #####################################################################
--  DML 1 of 3 -- INSERT
--  Register a student and grant their starter credits.
--
--  Two writes, one transaction. A student must never exist without a
--  ledger row, which is the TOTAL participation of STUDENT in "posts"
--  in the ER diagram. Keeping both inside PL/SQL makes that impossible
--  to get wrong.
-- #####################################################################
PROMPT
PROMPT ========== M1-INSERT : register a student ==========

DECLARE
  v_new_id  NUMBER;
BEGIN
  pkg_timebank.enrol_student (
      p_reg_no     => '25BCE1099',
      p_first_name => 'Tanvi',
      p_last_name  => 'Krishnan',
      p_email      => 'tanvi.krishnan@vit.ac.in',
      p_dob        => DATE '2005-06-12',
      p_dept_id    => 1,
      p_block      => 'B Block',
      p_room_no    => '140',
      p_city       => 'Madurai',
      p_student_id => v_new_id);

  -- PhoneNo is a MULTIVALUED attribute, so it lives in its own table
  -- and a student may register more than one number.
  INSERT INTO student_phone VALUES (v_new_id, '9500011223');
  INSERT INTO student_phone VALUES (v_new_id, '9500099887');

  DBMS_OUTPUT.PUT_LINE ('Registered student ' || v_new_id ||
                        ', opening balance ' ||
                        pkg_timebank.fn_balance (v_new_id));
  COMMIT;
END;
/


-- #####################################################################
--  DML 2 of 3 -- UPDATE
--  Close an account.
--
--  This is an UPDATE, not a DELETE, and that is forced by the schema.
--  A student with bookings or ledger rows cannot be removed: those
--  foreign keys carry no ON DELETE clause, so Oracle blocks it to keep
--  session history and the ledger intact. Closing an account is a soft
--  delete.
-- #####################################################################
PROMPT
PROMPT ========== M1-UPDATE : close an account (soft delete) ==========

UPDATE student
SET    account_status = 'INACTIVE'
WHERE  student_id     = 108
AND    account_status = 'ACTIVE';

COMMIT;

-- Put it back so the rest of the demo runs on the full data set.
UPDATE student SET account_status = 'ACTIVE' WHERE student_id = 108;
COMMIT;


-- #####################################################################
--  DML 3 of 3 -- DELETE
--  Remove a phone number a student no longer uses.
--
--  STUDENT_PHONE is a genuine delete target: it came from a multivalued
--  attribute and nothing downstream references it. Contrast with the
--  UPDATE above -- the schema decides which rows may actually be
--  removed and which may only be marked.
-- #####################################################################
PROMPT
PROMPT ========== M1-DELETE : remove an unused phone number ==========

DELETE FROM student_phone
WHERE  student_id = 101
AND    phone_no   = '9003344556';

COMMIT;


-- #####################################################################
--  Q1 -- SIMPLE
--  Student directory with age, a DERIVED attribute.
--
--  Age is not stored anywhere. MONTHS_BETWEEN gives the gap in months,
--  /12 makes it years, FLOOR drops the fraction -- so it is correct on
--  the person's birthday rather than a day either side.
-- #####################################################################
PROMPT
PROMPT ===== M1-Q1 : student directory (SIMPLE) =====

SELECT s.student_id,
       s.reg_no,
       s.first_name || ' ' || s.last_name          AS full_name,
       FLOOR (MONTHS_BETWEEN (SYSDATE, s.dob)/12)  AS age,
       s.city,
       TO_CHAR (s.join_date, 'DD-MON-YYYY')        AS joined,
       s.account_status
FROM   student s
WHERE  s.account_status = 'ACTIVE'
ORDER  BY s.student_id;


-- #####################################################################
--  Q2 -- MULTI-TABLE JOIN  (four tables)
--  Who is a tutor, a tutee, both, or neither yet.
--
--  THIS IS THE MOST IMPORTANT QUERY IN MEMBER 1'S SET. The two LEFT
--  JOINs to the subclass tables reveal each student's role:
--
--    in TUTOR only   -> teaches
--    in TUTEE only   -> learns
--    in BOTH         -> only possible because the specialization is
--                       OVERLAPPING
--    in NEITHER      -> only possible because it is also PARTIAL
--
--  The joins must be OUTER. An inner join would silently drop every
--  student who is not in that subclass, and the last two categories
--  would vanish -- taking the proof with them.
-- #####################################################################
PROMPT
PROMPT ===== M1-Q2 : tutor / tutee / both / neither (JOIN) =====

SELECT s.student_id,
       s.first_name || ' ' || s.last_name  AS full_name,
       d.school,
       CASE
         WHEN t.student_id IS NOT NULL
          AND e.student_id IS NOT NULL THEN 'BOTH'
         WHEN t.student_id IS NOT NULL THEN 'TUTOR ONLY'
         WHEN e.student_id IS NOT NULL THEN 'TUTEE ONLY'
         ELSE                               'NEITHER YET'
       END                                 AS role_in_system,
       NVL (t.badge_level, '-')            AS badge,
       NVL (e.academic_need_tier, '-')     AS need_tier
FROM   student s
       JOIN      department d ON d.dept_id    = s.dept_id
       LEFT JOIN tutor      t ON t.student_id = s.student_id
       LEFT JOIN tutee      e ON e.student_id = s.student_id
ORDER  BY role_in_system, s.student_id;



PROMPT
PROMPT ===== M1-Q3 : balance below campus average (NESTED) =====

SELECT s.student_id,
       s.first_name || ' ' || s.last_name       AS full_name,
       pkg_timebank.fn_balance (s.student_id)   AS credit_balance,
       (SELECT policy_value
        FROM   credit_policy
        WHERE  policy_key = 'OVERDRAFT_FLOOR')  AS floor_is,
       CASE WHEN pkg_timebank.fn_balance (s.student_id) <= 0.5
            THEN 'NUDGE TO TUTOR' ELSE 'ok' END AS action
FROM   student s
WHERE  pkg_timebank.fn_balance (s.student_id) <
       (SELECT AVG (total)                      -- evaluated once
        FROM  (SELECT SUM (amount) AS total     -- inner-inner query
               FROM   credit_txn
               GROUP  BY student_id))
ORDER  BY credit_balance, s.student_id;


-- #####################################################################
--  Q4 -- CORRELATED SUBQUERY
--  Registered more than 30 days ago but has never booked anything.
--
--  NOT EXISTS is re-evaluated for EVERY outer row, using that row's
--  student_id -- that is the correlation. Oracle stops at the first
--  match it finds, so it is cheaper than counting all the rows and
--  comparing to zero.
-- #####################################################################
PROMPT
PROMPT ===== M1-Q4 : registered but never booked (CORRELATED) =====

SELECT s.student_id,
       s.first_name || ' ' || s.last_name      AS full_name,
       TRUNC (SYSDATE - s.join_date)           AS days_since_joining,
       pkg_timebank.fn_balance (s.student_id)  AS unused_credits
FROM   student s
WHERE  SYSDATE - s.join_date > 30
AND    NOT EXISTS (SELECT 1
                   FROM   booking b
                   WHERE  b.tutee_id = s.student_id)   -- correlation
ORDER  BY days_since_joining DESC;


-- #####################################################################
--  Q5 -- AGGREGATE with GROUP BY and HAVING
--  Department scoreboard.
--
--  WHERE filters ROWS before grouping; HAVING filters GROUPS after it.
--  HAVING can see COUNT(); WHERE cannot, because at the time WHERE runs
--  the groups do not exist yet.
--
--  SQL functions on show: COUNT, SUM with CASE (conditional
--  aggregation, which pivots a column into several without PIVOT),
--  AVG, ROUND, RPAD, GREATEST.
-- #####################################################################
PROMPT
PROMPT ===== M1-Q5 : department scoreboard (AGGREGATE) =====

SELECT d.school,
       d.dept_name,
       COUNT (s.student_id)                                AS students,
       SUM (CASE WHEN t.student_id IS NOT NULL
                 THEN 1 ELSE 0 END)                        AS tutors,
       SUM (CASE WHEN e.student_id IS NOT NULL
                 THEN 1 ELSE 0 END)                        AS tutees,
       ROUND (AVG (FLOOR (MONTHS_BETWEEN (SYSDATE, s.dob)/12)), 1)
                                                           AS avg_age,
       RPAD ('*', GREATEST (COUNT (s.student_id), 1), '*') AS size_bar
FROM   department d
       JOIN      student s ON s.dept_id    = d.dept_id
       LEFT JOIN tutor   t ON t.student_id = s.student_id
       LEFT JOIN tutee   e ON e.student_id = s.student_id
WHERE  s.account_status = 'ACTIVE'          -- filters ROWS
GROUP  BY d.school, d.dept_name
HAVING COUNT (s.student_id) >= 1            -- filters GROUPS
ORDER  BY students DESC;


-- #####################################################################
--  Q6 -- ANALYTIC (WINDOW) FUNCTIONS
--  Rank students by balance inside their own department.
--
--  An analytic function computes over a window of rows but, unlike
--  GROUP BY, keeps EVERY row in the output. That is the whole point
--  here: a GROUP BY could tell you the richest student per department,
--  but it could not list everyone alongside their rank.
--
--    RANK()         position within the department; ties share a rank
--                   and the next rank is skipped
--    DENSE_RANK()   same, but no gap after a tie
--    PERCENT_RANK() where they sit as a fraction of the field
--    NTILE(3)       splits each department into thirds
--    LAG()          the balance of the person one place above
--  PARTITION BY restarts the numbering for each department.
-- #####################################################################
PROMPT
PROMPT ===== M1-Q6 : balance ranking within department (ANALYTIC) =====

SELECT d.school,
       s.first_name || ' ' || s.last_name                  AS full_name,
       v.credit_balance,
       RANK () OVER (PARTITION BY s.dept_id
                     ORDER BY v.credit_balance DESC)       AS rank_in_dept,
       DENSE_RANK () OVER (PARTITION BY s.dept_id
                           ORDER BY v.credit_balance DESC) AS dense_rank,
       ROUND (PERCENT_RANK () OVER (PARTITION BY s.dept_id
                                    ORDER BY v.credit_balance), 2)
                                                           AS percentile,
       NTILE (3) OVER (PARTITION BY s.dept_id
                       ORDER BY v.credit_balance DESC)     AS third,
       LAG (v.credit_balance) OVER (PARTITION BY s.dept_id
                                    ORDER BY v.credit_balance DESC)
                                                           AS person_above,
       COUNT (*) OVER (PARTITION BY s.dept_id)             AS dept_size
FROM   student s
       JOIN department        d ON d.dept_id    = s.dept_id
       JOIN v_student_balance v ON v.student_id = s.student_id
ORDER  BY d.school, rank_in_dept;


PROMPT
PROMPT ===== MEMBER 1 COMPLETE : 3 DML + 6 SELECT = 9 queries =====
