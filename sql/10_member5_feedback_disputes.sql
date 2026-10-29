-- =====================================================================
--  TimeBank -- MEMBER 5 of 5 : Feedback, Disputes & Fraud Analytics
--  File    : 10_member5_feedback_disputes.sql
--
--  Tables owned : FEEDBACK, DISPUTE, ADMIN
--  ER feature   : TWO WEAK ENTITIES, both owned by BOOKING, each
--                 identified by a role or counter as its PARTIAL KEY
--
--  THE RULE THAT GOVERNS THIS WHOLE MODULE
--  FEEDBACK is identified by (booking_id, reviewer_role), so ONE
--  booking carries TWO reviews -- the tutee's opinion of the tutor and
--  the tutor's opinion of the tutee. A tutor's reputation must
--  therefore average only the rows where reviewer_role = 'TUTEE'.
--  Averaging both would silently mix in that tutor's own ratings of
--  other people, which measures nothing.
--
--  QUERY SHEET (identical in shape for all five members)
--    DML : 1 INSERT, 1 UPDATE, 1 DELETE
--    Q1 simple | Q2 join | Q3 nested | Q4 correlated
--    Q5 aggregate + GROUP BY/HAVING | Q6 analytic
-- =====================================================================

SET SERVEROUTPUT ON
SET LINESIZE 230
SET PAGESIZE 120


-- #####################################################################
--  DML 1 of 3 -- INSERT
--  Leave a review, and raise a dispute.
--
--  Two rules fire automatically on the feedback insert:
--     trg_feedback_valid  the session must be COMPLETED
--     pk_feedback         (booking_id, reviewer_role) stops anyone
--                         reviewing the same session twice
--  The primary key doing that second job for free is the pay-off from
--  choosing the role as the partial key back in the ER diagram.
--
--  dispute_no is also a PARTIAL KEY, so it restarts at 1 for every
--  booking -- MAX+1 scoped to one booking, never a global sequence.
--  Raising a dispute freezes the escrow: the booking moves to DISPUTED
--  and no credits move until an admin rules.
-- #####################################################################
PROMPT
PROMPT ========== M5-INSERT : leave a review, raise a dispute ==========

-- (a) the tutor review that booking 6 never received
INSERT INTO feedback (
    booking_id, reviewer_role, rating, comments, feedback_date)
SELECT booking_id,
       'TUTOR',
       4.0,
       'Good session. Bring the lab sheet printed next time.',
       SYSDATE
FROM   booking
WHERE  status = 'COMPLETED'
AND    booking_id NOT IN (SELECT booking_id FROM feedback
                          WHERE  reviewer_role = 'TUTOR')
AND    ROWNUM = 1;

-- (b) a dispute on an upcoming session
DECLARE
  v_bk   NUMBER;
  v_dno  NUMBER;
BEGIN
  SELECT MIN (booking_id) INTO v_bk
  FROM   booking WHERE status = 'CONFIRMED';

  IF v_bk IS NULL THEN
    DBMS_OUTPUT.PUT_LINE ('No confirmed booking available to dispute.');
  ELSE
    pkg_timebank.raise_dispute (
        p_booking_id => v_bk,
        p_by_role    => 'TUTEE',
        p_reason     => 'Tutor changed the venue twice without telling me.',
        p_dispute_no => v_dno);
    DBMS_OUTPUT.PUT_LINE ('Dispute ' || v_dno || ' raised on booking ' || v_bk);
  END IF;
  COMMIT;
END;
/


-- #####################################################################
--  DML 2 of 3 -- UPDATE
--  Triage the dispute queue.
--
--  Open disputes older than two days move to UNDER_REVIEW and are
--  assigned to whichever admin is currently carrying the lightest
--  caseload. The scalar subquery picks that admin at the moment the
--  statement runs -- a fixed round robin would drift out of fairness as
--  soon as one case took longer than another.
-- #####################################################################
PROMPT
PROMPT ========== M5-UPDATE : triage the dispute queue ==========

UPDATE dispute d
SET    d.status      = 'UNDER_REVIEW',
       d.resolved_by = (SELECT a.admin_id
                        FROM  (SELECT a2.admin_id,
                                      COUNT (d2.booking_id) AS caseload
                               FROM   admin a2
                                      LEFT JOIN dispute d2
                                             ON d2.resolved_by = a2.admin_id
                                            AND d2.status <> 'RESOLVED'
                               GROUP  BY a2.admin_id
                               ORDER  BY caseload, a2.admin_id) a
                        WHERE  ROWNUM = 1)
WHERE  d.status    = 'OPEN'
AND    d.raised_on < SYSDATE - 2;

COMMIT;


-- #####################################################################
--  DML 3 of 3 -- DELETE
--  Retract a review, and discard ratings from colluding pairs.
--
--  (a) A reviewer changes their mind. Because the primary key is
--      (booking_id, reviewer_role), naming the role is enough to
--      identify exactly one row -- no surrogate review id is needed.
--
--  (b) Ratings written by a reciprocal pair are thrown away. Two
--      friends who tutor each other net out to zero credits but collect
--      a glowing review each time. On clean data this removes nothing,
--      which is the correct outcome -- the query is the guard, not the
--      accusation.
-- #####################################################################
PROMPT
PROMPT ========== M5-DELETE : retract a review, drop colluded ratings ==========

DELETE FROM feedback f
WHERE  f.reviewer_role = 'TUTOR'
AND    f.feedback_date > SYSDATE - 7
AND    f.rating        = 4.0
AND    NOT EXISTS (SELECT 1 FROM dispute d
                   WHERE  d.booking_id = f.booking_id);

DELETE FROM feedback f
WHERE  f.booking_id IN (
         SELECT b1.booking_id
         FROM   booking b1
         WHERE  b1.status = 'COMPLETED'
         AND    EXISTS (SELECT 1
                        FROM   booking b2
                        WHERE  b2.tutor_id = b1.tutee_id
                        AND    b2.tutee_id = b1.tutor_id
                        AND    b2.status   = 'COMPLETED'));

COMMIT;


-- #####################################################################
--  Q1 -- SIMPLE
--  The review feed and the dispute register side by side.
--
--  UNION ALL stacks two differently-shaped result sets into one list.
--  ALL rather than plain UNION because no duplicates are possible here
--  and UNION would pay for a sort to look for them.
-- #####################################################################
PROMPT
PROMPT ===== M5-Q1 : reviews and disputes (SIMPLE) =====

SELECT 'REVIEW'                               AS record_type,
       booking_id,
       reviewer_role                          AS written_by,
       TO_CHAR (rating)                       AS detail,
       TO_CHAR (feedback_date, 'DD-MON-YYYY') AS on_date,
       SUBSTR (comments, 1, 45) || '...'      AS note
FROM   feedback
UNION ALL
SELECT 'DISPUTE',
       booking_id,
       raised_by_role,
       status,
       TO_CHAR (raised_on, 'DD-MON-YYYY'),
       SUBSTR (reason, 1, 45) || '...'
FROM   dispute
ORDER  BY record_type, booking_id;


-- #####################################################################
--  Q2 -- MULTI-TABLE JOIN, including a SELF JOIN
--  Both sides of every session, with any dispute attached.
--
--  THE INTERESTING PART: both halves of the review come from the SAME
--  table, so FEEDBACK is joined to itself twice and the two copies are
--  told apart by reviewer_role. That is only possible because the role
--  is part of the primary key.
--
--  Both feedback joins are OUTER, because many sessions get only one
--  review or none -- the partial participation of BOOKING in
--  "receives". An inner join would quietly hide every one-sided
--  session, which is exactly the set worth chasing.
-- #####################################################################
PROMPT
PROMPT ===== M5-Q2 : both sides of each session (SELF JOIN) =====

SELECT b.booking_id,
       sub.subject_code,
       tr.first_name                   AS tutor,
       te.first_name                   AS tutee,
       ft.rating                       AS tutee_rated_tutor,
       fe.rating                       AS tutor_rated_tutee,
       NVL (d.status, '-')             AS dispute_status,
       CASE
         WHEN ft.rating IS NULL AND fe.rating IS NULL THEN 'no reviews'
         WHEN ft.rating IS NULL OR  fe.rating IS NULL THEN 'one-sided'
         WHEN ABS (ft.rating - fe.rating) >= 1.5      THEN 'DISAGREEMENT'
         ELSE                                              'both agree'
       END                             AS review_state
FROM   booking b
       JOIN      subject  sub ON sub.subject_id   = b.subject_id
       JOIN      student  tr  ON tr.student_id    = b.tutor_id
       JOIN      student  te  ON te.student_id    = b.tutee_id
       LEFT JOIN feedback ft  ON ft.booking_id    = b.booking_id
                             AND ft.reviewer_role = 'TUTEE'
       LEFT JOIN feedback fe  ON fe.booking_id    = b.booking_id
                             AND fe.reviewer_role = 'TUTOR'
       LEFT JOIN dispute  d   ON d.booking_id     = b.booking_id
ORDER  BY b.booking_id;


-- #####################################################################
--  Q3 -- NESTED (NON-CORRELATED) SUBQUERY, three levels deep
--  Tutors rated above the campus average.
--
--  Innermost: average each tutor's ratings.
--  Middle:    average those averages.
--  Outer:     keep the tutors above it.
--
--  It is the average of the per-tutor averages, NOT the average of all
--  ratings. Averaging every row would let a tutor with 20 sessions
--  drown out one with 2, and the "campus average" would really just be
--  the busiest tutor's average.
-- #####################################################################
PROMPT
PROMPT ===== M5-Q3 : above-average tutors (NESTED) =====

SELECT s.first_name || ' ' || s.last_name            AS tutor_name,
       t.badge_level,
       ROUND (AVG (f.rating), 2)                     AS their_average,
       COUNT (f.booking_id)                          AS reviews,
       (SELECT ROUND (AVG (per_tutor), 2)
        FROM  (SELECT AVG (f2.rating) AS per_tutor
               FROM   feedback f2
                      JOIN booking b2 ON b2.booking_id = f2.booking_id
               WHERE  f2.reviewer_role = 'TUTEE'
               GROUP  BY b2.tutor_id))               AS campus_average
FROM   feedback f
       JOIN booking b ON b.booking_id = f.booking_id
       JOIN tutor   t ON t.student_id = b.tutor_id
       JOIN student s ON s.student_id = t.student_id
WHERE  f.reviewer_role = 'TUTEE'          -- only reviews OF the tutor
GROUP  BY s.first_name, s.last_name, t.badge_level
HAVING AVG (f.rating) > (SELECT AVG (per_tutor)
                         FROM  (SELECT AVG (f3.rating) AS per_tutor
                                FROM   feedback f3
                                       JOIN booking b3
                                         ON b3.booking_id = f3.booking_id
                                WHERE  f3.reviewer_role = 'TUTEE'
                                GROUP  BY b3.tutor_id))
ORDER  BY their_average DESC;


-- #####################################################################
--  Q4 -- CORRELATED SUBQUERY : CREDIT-LOOP COLLUSION
--  The fraud this whole project was designed to catch.
--
--  Two students who repeatedly tutor EACH OTHER net out to zero credits
--  but collect a five-star review every time. The self-join on BOOKING
--  finds pairs going both ways; the correlated subqueries then count
--  how often and what they rated each other.
--
--  b1.tutor_id < b1.tutee_id keeps each pair ONCE instead of twice --
--  without it, A-B and B-A would both be reported as separate findings.
--
--  No database can stop two people who agree to lie. What it can do is
--  make the pattern cheap to spot and not worth the effort. In a graph
--  view this is simply a 2-cycle between two student nodes, which is
--  the Module 6 connection.
-- #####################################################################
PROMPT
PROMPT ===== M5-Q4 : credit-loop collusion detector (CORRELATED) =====

SELECT a.first_name || ' ' || a.last_name     AS student_a,
       c.first_name || ' ' || c.last_name     AS student_b,
       COUNT (*)                              AS sessions_a_taught_b,
       (SELECT COUNT (*)                       -- correlated, other way
        FROM   booking b2
        WHERE  b2.tutor_id = b1.tutee_id
        AND    b2.tutee_id = b1.tutor_id
        AND    b2.status   = 'COMPLETED')     AS sessions_b_taught_a,
       (SELECT ROUND (AVG (f.rating), 2)
        FROM   feedback f
               JOIN booking b3 ON b3.booking_id = f.booking_id
        WHERE  ((b3.tutor_id = b1.tutor_id AND b3.tutee_id = b1.tutee_id)
             OR (b3.tutor_id = b1.tutee_id AND b3.tutee_id = b1.tutor_id)))
                                              AS avg_rating_between_them,
       'REVIEW MANUALLY'                      AS recommended_action
FROM   booking b1
       JOIN student a ON a.student_id = b1.tutor_id
       JOIN student c ON c.student_id = b1.tutee_id
WHERE  b1.status = 'COMPLETED'
AND    b1.tutor_id < b1.tutee_id          -- report each pair only once
AND    EXISTS (SELECT 1
               FROM   booking b4
               WHERE  b4.tutor_id = b1.tutee_id
               AND    b4.tutee_id = b1.tutor_id
               AND    b4.status   = 'COMPLETED')
GROUP  BY b1.tutor_id, b1.tutee_id,
          a.first_name, a.last_name, c.first_name, c.last_name
HAVING COUNT (*) >= 1
ORDER  BY sessions_a_taught_b DESC;


-- #####################################################################
--  Q5 -- AGGREGATE with GROUP BY, HAVING and ROLLUP
--  Rating distribution per subject, with a grand total row.
--
--  SUM(CASE ...) builds the histogram buckets. STDDEV matters more than
--  it looks: a 4.0 average built from 4, 4, 4 means something very
--  different from a 4.0 built from 5, 5, 2 -- same mean, completely
--  different tutor.
--
--  ROLLUP adds the overall row. GROUPING() tells a real NULL apart from
--  a "this is the subtotal" NULL, which is why the CASE is needed
--  rather than a plain NVL.
-- #####################################################################
PROMPT
PROMPT ===== M5-Q5 : rating distribution by subject (AGGREGATE) =====

SELECT CASE WHEN GROUPING (sub.subject_code) = 1
            THEN '** ALL SUBJECTS **'
            ELSE sub.subject_code END                         AS subject,
       COUNT (*)                                              AS reviews,
       ROUND (AVG (f.rating), 2)                              AS avg_rating,
       ROUND (NVL (STDDEV (f.rating), 0), 2)                  AS spread,
       MIN (f.rating)                                         AS worst,
       MAX (f.rating)                                         AS best,
       SUM (CASE WHEN f.rating >= 4.5 THEN 1 ELSE 0 END)      AS excellent,
       SUM (CASE WHEN f.rating >= 3.5
                  AND f.rating <  4.5 THEN 1 ELSE 0 END)      AS good,
       SUM (CASE WHEN f.rating <  3.5 THEN 1 ELSE 0 END)      AS poor
FROM   feedback f
       JOIN booking b   ON b.booking_id  = f.booking_id
       JOIN subject sub ON sub.subject_id = b.subject_id
WHERE  f.reviewer_role = 'TUTEE'
GROUP  BY ROLLUP (sub.subject_code)
HAVING COUNT (*) >= 1
ORDER  BY GROUPING (sub.subject_code), avg_rating DESC;


-- #####################################################################
--  Q6 -- ANALYTIC (WINDOW) FUNCTIONS
--  Is each tutor getting better or worse over time?
--
--    LAG()                   the rating they got on the session before
--    AVG() OVER (... ROWS)   a moving average over the last 3 sessions
--    DENSE_RANK()            their standing across the whole campus
--    NTILE(3)                top / middle / bottom third
--
--  A plain GROUP BY could never show this. It collapses the history
--  into one number, and the trend -- which is the entire question -- is
--  exactly what gets lost. A tutor averaging 4.0 while improving is a
--  very different proposition from one averaging 4.0 while sliding.
-- #####################################################################
PROMPT
PROMPT ===== M5-Q6 : rating trend per tutor (ANALYTIC) =====

SELECT s.first_name                                     AS tutor,
       b.booking_id,
       TO_CHAR (b.sched_date, 'DD-MON')                 AS session_date,
       f.rating,
       LAG (f.rating) OVER (PARTITION BY b.tutor_id
                            ORDER BY b.sched_date)      AS previous_rating,
       ROUND (AVG (f.rating) OVER (
                PARTITION BY b.tutor_id
                ORDER BY b.sched_date
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)
                                                        AS moving_avg_3,
       CASE
         WHEN LAG (f.rating) OVER (PARTITION BY b.tutor_id
                                   ORDER BY b.sched_date) IS NULL
              THEN 'first review'
         WHEN f.rating > LAG (f.rating) OVER (PARTITION BY b.tutor_id
                                              ORDER BY b.sched_date)
              THEN 'improving'
         WHEN f.rating < LAG (f.rating) OVER (PARTITION BY b.tutor_id
                                              ORDER BY b.sched_date)
              THEN 'slipping'
         ELSE 'steady'
       END                                              AS trend,
       DENSE_RANK () OVER (ORDER BY f.rating DESC)      AS campus_rank,
       NTILE (3) OVER (ORDER BY f.rating DESC)          AS performance_third
FROM   feedback f
       JOIN booking b ON b.booking_id = f.booking_id
       JOIN student s ON s.student_id = b.tutor_id
WHERE  f.reviewer_role = 'TUTEE'
ORDER  BY tutor, b.sched_date;


PROMPT
PROMPT ===== MEMBER 5 COMPLETE : 3 DML + 6 SELECT = 9 queries =====
