-- =====================================================================
--  TimeBank -- MEMBER 3 of 5 : Booking Engine & Session Scheduling
--  File    : 08_member3_booking.sql
--
--  Table owned : BOOKING  (the central entity of the whole model)
--  ER feature  : TWO COMPOSITE FOREIGN KEYS that share a column
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
--  Book a session.
--
--  This goes through PKG_TIMEBANK rather than a raw INSERT, because
--  booking is not one statement:
--     1. lock the tutor's slot row   (SELECT ... FOR UPDATE)
--     2. check nobody else took it
--     3. check the pair collusion cap
--     4. insert the booking
--     5. move the tutee's credits into escrow
--  All five must succeed together or none may. Step 1 is the one a
--  trigger could never do -- a trigger cannot hold a lock across its
--  own statement.
--
--  Sara (108) had registered but never booked, so she was in NEITHER
--  subclass. Her first request makes her a TUTEE, and that row has to
--  exist first: fk_bk_tutee is the database enforcing "only a tutee may
--  request a session".
-- #####################################################################
PROMPT
PROMPT ========== M3-INSERT : book a session ==========

INSERT INTO tutee (student_id, academic_need_tier) VALUES (108, 'BASIC');
INSERT INTO tutee_preftime VALUES (108, 'EVENING');

DECLARE
  v_bk    NUMBER;
  v_code  VARCHAR2(8);
BEGIN
  pkg_timebank.book_session (
      p_tutee_id     => 108,                       -- Sara
      p_tutor_id     => 105,                       -- Kabir
      p_subject_id   => 110,                       -- Operating Systems
      p_slot_no      => 2,                         -- Kabir's FRI 14-16
      p_sched_date   => TRUNC (SYSDATE,'IW') + 11, -- Friday next week
      p_start_time   => 14,
      p_duration     => 1.5,
      p_mode         => 'ONLINE',
      p_venue        => 'MS Teams',
      p_booking_id   => v_bk,
      p_session_code => v_code);

  DBMS_OUTPUT.PUT_LINE ('Booking ' || v_bk || ' created.');
  DBMS_OUTPUT.PUT_LINE ('Session code for the TUTEE only: ' || v_code);
  DBMS_OUTPUT.PUT_LINE ('Sara''s balance is now ' ||
                        pkg_timebank.fn_balance (108));
  COMMIT;
END;
/


-- #####################################################################
--  DML 2 of 3 -- UPDATE
--  Push a booking back by one week.
--
--  Two guards. The booking must still be live, and the new date must be
--  free for that tutor -- checked with a correlated NOT EXISTS against
--  BOOKING itself. Without it, rescheduling would be a way around the
--  double-booking rule that applies at insert time.
-- #####################################################################
PROMPT
PROMPT ========== M3-UPDATE : reschedule by one week ==========

UPDATE booking b
SET    b.sched_date = b.sched_date + 7,
       b.venue      = b.venue || ' (rescheduled)'
WHERE  b.status IN ('REQUESTED','CONFIRMED')
AND    b.sched_date > SYSDATE
AND    b.booking_id = (SELECT MIN (booking_id)
                       FROM   booking
                       WHERE  status     IN ('REQUESTED','CONFIRMED')
                       AND    sched_date > SYSDATE)
AND    NOT EXISTS (SELECT 1
                   FROM   booking x
                   WHERE  x.tutor_id    = b.tutor_id
                   AND    x.slot_no     = b.slot_no
                   AND    x.sched_date  = b.sched_date + 7
                   AND    x.booking_id <> b.booking_id
                   AND    x.status IN ('REQUESTED','CONFIRMED'));

COMMIT;


-- #####################################################################
--  DML 3 of 3 -- DELETE
--  Purge abandoned requests whose date has already passed.
--
--  Only REQUESTED rows may go. They never reached escrow, so no ledger
--  row points at them. A CONFIRMED or COMPLETED booking is referenced
--  by CREDIT_TXN, whose foreign key has no ON DELETE clause, so Oracle
--  refuses -- deliberately, because deleting it would orphan money.
-- #####################################################################
PROMPT
PROMPT ========== M3-DELETE : purge abandoned requests ==========

DELETE FROM booking b
WHERE  b.status     = 'REQUESTED'
AND    b.sched_date < TRUNC (SYSDATE)
AND    NOT EXISTS (SELECT 1 FROM credit_txn t
                   WHERE  t.booking_id = b.booking_id);

COMMIT;


-- #####################################################################
--  Q1 -- SIMPLE
--  Upcoming sessions.
--
--  sched_start_time is a decimal hour (16.5 means 16:30), not a
--  timestamp. Dividing by 24 turns it into a fraction of a day so it
--  can be added to the date and formatted as a clock time.
-- #####################################################################
PROMPT
PROMPT ===== M3-Q1 : upcoming sessions (SIMPLE) =====

SELECT b.booking_id,
       TO_CHAR (b.sched_date, 'DY DD-MON-YYYY')                  AS on_date,
       TO_CHAR (b.sched_date + b.sched_start_time/24, 'HH24:MI') AS starts,
       TO_CHAR (b.sched_date
                + (b.sched_start_time + b.duration_hours)/24,
                'HH24:MI')                                       AS ends,
       b.duration_hours,
       b.session_mode,
       b.venue,
       b.status,
       b.credits_held
FROM   booking b
WHERE  b.sched_date >= TRUNC (SYSDATE)
ORDER  BY b.sched_date, b.sched_start_time;


-- #####################################################################
--  Q2 -- MULTI-TABLE JOIN  (six tables)
--  The complete session sheet: who, with whom, for what, where, when.
--
--  Every join here is one relationship from the ER diagram being put
--  back together. In the ER model the diamonds held this information;
--  after mapping they survive ONLY as foreign keys, so a join is the
--  only way to recover them:
--
--     booking -> tutee    "requests"
--     booking -> tutor    "conducts"
--     booking -> subject  "covers"
--     booking -> slot     "occupies"   (composite FK, two columns)
--
--  The SLOT join needs BOTH tutor_id and slot_no, because SLOT is a
--  weak entity and its key is the pair.
-- #####################################################################
PROMPT
PROMPT ===== M3-Q2 : complete session sheet (SIX-TABLE JOIN) =====

SELECT b.booking_id,
       te.first_name || ' ' || te.last_name     AS tutee_name,
       tr.first_name || ' ' || tr.last_name     AS tutor_name,
       sub.subject_code,
       sl.day_of_week || ' ' || sl.start_time || '-' || sl.end_time
                                                AS tutor_slot,
       TO_CHAR (b.sched_date, 'DD-MON')         AS session_date,
       b.duration_hours                         AS hrs,
       b.status,
       NVL (TO_CHAR (b.check_in_at, 'DD-MON HH24:MI'), 'not checked in')
                                                AS check_in,
       b.confirm_by_tutor || '/' || b.confirm_by_tutee
                                                AS confirms
FROM   booking b
       JOIN tutee   e   ON e.student_id   = b.tutee_id
       JOIN student te  ON te.student_id  = e.student_id
       JOIN tutor   t   ON t.student_id   = b.tutor_id
       JOIN student tr  ON tr.student_id  = t.student_id
       JOIN subject sub ON sub.subject_id = b.subject_id
       JOIN slot    sl  ON sl.tutor_id    = b.tutor_id    -- composite FK
                       AND sl.slot_no     = b.slot_no     -- both columns
ORDER  BY b.booking_id;


-- #####################################################################
--  Q3 -- NESTED (NON-CORRELATED) SUBQUERY
--  Tutors with a completely clear diary next week.
--
--  The inner query runs once and lists every tutor who already has
--  something booked in that window; the outer query returns the ones
--  not in that list.
-- #####################################################################
PROMPT
PROMPT ===== M3-Q3 : tutors free all next week (NESTED) =====

SELECT s.first_name || ' ' || s.last_name      AS tutor_name,
       t.badge_level,
       (SELECT COUNT (*) FROM slot sl
        WHERE  sl.tutor_id = t.student_id)     AS slots_published,
       (SELECT COUNT (*) FROM tutor_skill ts
        WHERE  ts.tutor_id = t.student_id)     AS subjects_offered
FROM   tutor t
       JOIN student s ON s.student_id = t.student_id
WHERE  t.student_id NOT IN (
         SELECT b.tutor_id
         FROM   booking b
         WHERE  b.sched_date BETWEEN TRUNC (SYSDATE,'IW') + 7
                                 AND TRUNC (SYSDATE,'IW') + 13
         AND    b.status IN ('REQUESTED','CONFIRMED'))
ORDER  BY slots_published DESC;


-- #####################################################################
--  Q4 -- CORRELATED SUBQUERY
--  Tutors carrying more sessions than the average tutor.
--
--  This query deliberately contains BOTH kinds side by side so the
--  difference is visible in one place:
--
--    the CORRELATED one mentions t.student_id from the outer query, so
--      it must be re-run for every tutor
--    the NON-CORRELATED one mentions nothing outside itself, so Oracle
--      evaluates it a single time and reuses the number
-- #####################################################################
PROMPT
PROMPT ===== M3-Q4 : tutors busier than average (CORRELATED) =====

SELECT s.first_name || ' ' || s.last_name          AS tutor_name,
       (SELECT COUNT (*)                            -- CORRELATED
        FROM   booking b
        WHERE  b.tutor_id = t.student_id
        AND    b.status IN ('REQUESTED','CONFIRMED','COMPLETED'))
                                                   AS sessions_total,
       ROUND ((SELECT AVG (c)                       -- NON-correlated
               FROM  (SELECT COUNT (*) AS c
                      FROM   booking
                      GROUP  BY tutor_id)), 2)     AS campus_average
FROM   tutor t
       JOIN student s ON s.student_id = t.student_id
WHERE  (SELECT COUNT (*)
        FROM   booking b
        WHERE  b.tutor_id = t.student_id
        AND    b.status IN ('REQUESTED','CONFIRMED','COMPLETED'))
       >
       (SELECT AVG (c)
        FROM  (SELECT COUNT (*) AS c FROM booking GROUP BY tutor_id))
ORDER  BY sessions_total DESC;


-- #####################################################################
--  Q5 -- AGGREGATE with GROUP BY and HAVING
--  The booking funnel per subject: requested, finished, fallen through.
--
--  SUM(CASE ...) is conditional aggregation. It counts only the rows
--  matching a condition, which is how a status column is pivoted into
--  separate columns without a PIVOT clause -- and it works on every
--  Oracle version.
-- #####################################################################
PROMPT
PROMPT ===== M3-Q5 : booking funnel by subject (AGGREGATE) =====

SELECT sub.subject_code,
       sub.subject_name,
       COUNT (*)                                                AS total,
       SUM (CASE WHEN b.status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed,
       SUM (CASE WHEN b.status = 'CANCELLED' THEN 1 ELSE 0 END) AS cancelled,
       SUM (CASE WHEN b.status IN ('REQUESTED','CONFIRMED')
                 THEN 1 ELSE 0 END)                             AS upcoming,
       SUM (b.duration_hours)                                   AS total_hours,
       ROUND (100 * SUM (CASE WHEN b.status = 'COMPLETED'
                              THEN 1 ELSE 0 END) / COUNT (*), 1)
                                                                AS pct_done
FROM   booking b
       JOIN subject sub ON sub.subject_id = b.subject_id
GROUP  BY sub.subject_id, sub.subject_code, sub.subject_name
HAVING COUNT (*) >= 1
ORDER  BY total DESC, sub.subject_code;


-- #####################################################################
--  Q6 -- ANALYTIC (WINDOW) FUNCTIONS
--  Each tutor's teaching load, session by session, with a running total.
--
--    ROW_NUMBER()      which session this is for that tutor
--    SUM() OVER (...)  cumulative hours up to and including this row
--    RATIO_TO_REPORT() this session's share of their total
--    LAST_VALUE()      their most recent session date
--
--  The ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW clause is what
--  makes the SUM cumulative rather than a grand total. Without it the
--  same column would repeat the tutor's full hours on every row.
--
--  A GROUP BY could give the totals, but it would collapse the
--  individual sessions -- and the point here is to see both at once.
-- #####################################################################
PROMPT
PROMPT ===== M3-Q6 : running teaching load per tutor (ANALYTIC) =====

SELECT s.first_name || ' ' || s.last_name          AS tutor_name,
       b.booking_id,
       TO_CHAR (b.sched_date, 'DD-MON')            AS session_date,
       b.duration_hours                            AS hrs,
       ROW_NUMBER () OVER (PARTITION BY b.tutor_id
                           ORDER BY b.sched_date)  AS session_seq,
       SUM (b.duration_hours) OVER (
            PARTITION BY b.tutor_id
            ORDER BY b.sched_date
            ROWS BETWEEN UNBOUNDED PRECEDING
                     AND CURRENT ROW)              AS running_hours,
       SUM (b.duration_hours) OVER (
            PARTITION BY b.tutor_id)               AS their_total,
       ROUND (100 * RATIO_TO_REPORT (b.duration_hours)
                      OVER (PARTITION BY b.tutor_id), 1)
                                                   AS pct_of_their_load
FROM   booking b
       JOIN student s ON s.student_id = b.tutor_id
WHERE  b.status = 'COMPLETED'
ORDER  BY tutor_name, b.sched_date;


PROMPT
PROMPT ===== MEMBER 3 COMPLETE : 3 DML + 6 SELECT = 9 queries =====
