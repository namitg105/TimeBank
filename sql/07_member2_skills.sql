-- =====================================================================
--  TimeBank -- MEMBER 2 of 5 : Skill Verification & Availability
--  File    : 07_member2_skills.sql
--
--  Tables owned : SUBJECT, TUTOR_SKILL, SLOT
--  ER features  : the M:N relationship "offers", and SLOT as a
--                 WEAK ENTITY with a partial key
--
--  QUERY SHEET (identical in shape for all five members)
--    DML : 1 INSERT, 1 UPDATE, 1 DELETE
--    Q1 simple | Q2 join | Q3 nested | Q4 correlated
--    Q5 aggregate + GROUP BY/HAVING | Q6 analytic
-- =====================================================================

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100


-- #####################################################################
--  DML 1 of 3 -- INSERT
--  A student signs up to tutor.
--
--  The order is forced by the foreign keys:
--     TUTOR must exist before TUTOR_SKILL  (fk_skill_tutor)
--     TUTOR must exist before SLOT         (fk_slot_tutor)
--
--  Meera (112) has only ever been a tutee. Adding her to TUTOR puts her
--  in BOTH subclasses -- the overlapping specialization in action.
--
--  Note slot_no restarts at 1 for her, even though other tutors already
--  have slots numbered 1 and 2. That is the PARTIAL KEY of a weak
--  entity: unique only within its owner.
-- #####################################################################
PROMPT
PROMPT ========== M2-INSERT : a student becomes a tutor ==========

INSERT INTO tutor (student_id, badge_level, verification_doc_no)
VALUES (112, 'BRONZE', 'VIT-GRD-1007');

INSERT INTO tutor_skill (tutor_id, subject_id, competency_level,
                         grade_proof, certified_on)
VALUES (112, 107, 'EXPERT', 'S', TRUNC (SYSDATE));   -- Signals & Systems

INSERT INTO slot (tutor_id, slot_no, day_of_week, start_time, end_time)
VALUES (112, 1, 'TUE', 16, 18);

INSERT INTO slot (tutor_id, slot_no, day_of_week, start_time, end_time)
VALUES (112, 2, 'SAT', 9, 11);

COMMIT;


-- #####################################################################
--  DML 2 of 3 -- UPDATE
--  Promote a tutor to EXPERT once they have proved themselves.
--
--  Two correlated subqueries in the WHERE clause set the bar: at least
--  2 completed sessions in that subject, averaging 4.0 or better.
--
--  Note the rating filter -- reviewer_role = 'TUTEE'. A booking holds
--  TWO feedback rows, one from each side. Averaging both would mix in
--  the tutor's own opinion of their students, which says nothing about
--  how well they teach.
-- #####################################################################
PROMPT
PROMPT ========== M2-UPDATE : promote proven tutors to EXPERT ==========

UPDATE tutor_skill ts
SET    ts.competency_level = 'EXPERT',
       ts.certified_on     = TRUNC (SYSDATE)
WHERE  ts.competency_level <> 'EXPERT'
AND    2 <= (SELECT COUNT (*)
             FROM   booking b
             WHERE  b.tutor_id   = ts.tutor_id
             AND    b.subject_id = ts.subject_id
             AND    b.status     = 'COMPLETED')
AND    4.0 <= (SELECT NVL (AVG (f.rating), 0)
               FROM   feedback f
                      JOIN booking b2 ON b2.booking_id = f.booking_id
               WHERE  b2.tutor_id     = ts.tutor_id
               AND    b2.subject_id   = ts.subject_id
               AND    f.reviewer_role = 'TUTEE');

COMMIT;


-- #####################################################################
--  DML 3 of 3 -- DELETE
--  Withdraw a slot the tutor no longer wants to offer.
--
--  The NOT EXISTS guard is essential, not decoration. BOOKING has a
--  COMPOSITE foreign key (tutor_id, slot_no) pointing at SLOT, so
--  deleting a slot that still has bookings raises ORA-02292, child
--  record found. Checking first turns a crash into a clean no-op.
-- #####################################################################
PROMPT
PROMPT ========== M2-DELETE : withdraw an unused slot ==========

DELETE FROM slot s
WHERE  s.tutor_id = 111
AND    s.slot_no  = 2
AND    NOT EXISTS (SELECT 1
                   FROM   booking b
                   WHERE  b.tutor_id = s.tutor_id
                   AND    b.slot_no  = s.slot_no);

COMMIT;


-- #####################################################################
--  Q1 -- SIMPLE
--  The subject catalogue, with each subject's owning department.
-- #####################################################################
PROMPT
PROMPT ===== M2-Q1 : subject catalogue (SIMPLE) =====

SELECT sub.subject_id,
       sub.subject_code,
       sub.subject_name,
       sub.category,
       d.school   AS owned_by
FROM   subject sub
       JOIN department d ON d.dept_id = sub.dept_id
ORDER  BY sub.category, sub.subject_code;


-- #####################################################################
--  Q2 -- MULTI-TABLE JOIN  (five tables)
--  The skill matrix: who can teach what.
--
--  TUTOR_SKILL is the relationship relation produced by mapping rule 5
--  (M:N). Rebuilding the original relationship therefore needs TWO
--  joins -- tutor -> tutor_skill -> subject. A 1:N relationship would
--  have needed only one. DEPARTMENT is joined twice, under two aliases,
--  because the tutor's department and the subject's department are
--  different facts.
--
--  The last column settles the question the design has to answer: a
--  student's department does NOT limit what they may teach. Rohan is
--  Mechanical and teaches Database Systems.
-- #####################################################################
PROMPT
PROMPT ===== M2-Q2 : skill matrix, incl. cross-department (JOIN) =====

SELECT s.first_name || ' ' || s.last_name  AS tutor_name,
       dt.school                           AS tutor_school,
       sub.subject_code,
       sub.subject_name,
       ds.school                           AS subject_school,
       ts.competency_level,
       ts.grade_proof,
       CASE WHEN dt.dept_id <> ds.dept_id
            THEN 'CROSS-DEPARTMENT' ELSE 'own department' END AS note
FROM   tutor_skill ts
       JOIN student    s   ON s.student_id   = ts.tutor_id
       JOIN department dt  ON dt.dept_id     = s.dept_id
       JOIN subject    sub ON sub.subject_id = ts.subject_id
       JOIN department ds  ON ds.dept_id     = sub.dept_id
ORDER  BY note, tutor_name, sub.subject_code;


-- #####################################################################
--  Q3 -- NESTED (NON-CORRELATED) SUBQUERY
--  Coverage gaps: subjects nobody has volunteered to teach.
--
--  This is the PARTIAL participation of SUBJECT in "offers", made
--  visible -- and it is exactly what the platform most needs to fix.
--
--  NOT IN is safe here only because tutor_skill.subject_id is NOT NULL.
--  A single NULL in the inner list would make NOT IN return no rows at
--  all, because comparing anything to NULL yields UNKNOWN rather than
--  TRUE. NOT EXISTS has no such trap, which is why Q4 uses it.
-- #####################################################################
PROMPT
PROMPT ===== M2-Q3 : subjects with no tutor (NESTED) =====

SELECT sub.subject_code,
       sub.subject_name,
       sub.category,
       d.school                              AS owning_school,
       (SELECT COUNT (*)
        FROM   booking b
        WHERE  b.subject_id = sub.subject_id) AS times_requested
FROM   subject sub
       JOIN department d ON d.dept_id = sub.dept_id
WHERE  sub.subject_id NOT IN (SELECT subject_id FROM tutor_skill)
ORDER  BY sub.subject_code;


-- #####################################################################
--  Q4 -- CORRELATED SUBQUERY
--  Availability that has been published but nobody has taken next week.
--
--  The NOT EXISTS correlates on THREE things at once -- tutor_id,
--  slot_no and the computed date -- so it is evaluated separately for
--  every candidate slot.
--
--  TRUNC(SYSDATE,'IW') is the Monday of the current ISO week. It is
--  used instead of NEXT_DAY because it does not depend on the session
--  language, so this behaves identically on every machine. Adding the
--  weekday offset turns a recurring "MON 16:00" slot into a real date.
-- #####################################################################
PROMPT
PROMPT ===== M2-Q4 : unbooked slots next week (CORRELATED) =====

SELECT s.first_name || ' ' || s.last_name       AS tutor_name,
       sl.slot_no,
       sl.day_of_week,
       sl.start_time,
       sl.end_time,
       sl.end_time - sl.start_time              AS hours_free,
       TRUNC (SYSDATE, 'IW') + 7
         + CASE sl.day_of_week
             WHEN 'MON' THEN 0 WHEN 'TUE' THEN 1 WHEN 'WED' THEN 2
             WHEN 'THU' THEN 3 WHEN 'FRI' THEN 4 WHEN 'SAT' THEN 5
             ELSE 6 END                         AS next_occurrence
FROM   slot sl
       JOIN student s ON s.student_id = sl.tutor_id
WHERE  NOT EXISTS (
         SELECT 1
         FROM   booking b
         WHERE  b.tutor_id   = sl.tutor_id          -- correlation 1
         AND    b.slot_no    = sl.slot_no           -- correlation 2
         AND    b.status IN ('REQUESTED','CONFIRMED')
         AND    b.sched_date = TRUNC (SYSDATE,'IW') + 7
                             + CASE sl.day_of_week  -- correlation 3
                                 WHEN 'MON' THEN 0 WHEN 'TUE' THEN 1
                                 WHEN 'WED' THEN 2 WHEN 'THU' THEN 3
                                 WHEN 'FRI' THEN 4 WHEN 'SAT' THEN 5
                                 ELSE 6 END)
ORDER  BY next_occurrence, sl.start_time;


-- #####################################################################
--  Q5 -- AGGREGATE with GROUP BY and HAVING
--  Teaching capacity against actual demand, per subject.
--
--  COUNT(DISTINCT ...) matters here: a tutor who offers a subject
--  appears once in TUTOR_SKILL, but the join could otherwise multiply
--  rows. HAVING then keeps only subjects that have at least one tutor.
-- #####################################################################
PROMPT
PROMPT ===== M2-Q5 : capacity versus demand (AGGREGATE) =====

SELECT sub.subject_code,
       sub.subject_name,
       COUNT (DISTINCT ts.tutor_id)                       AS tutors_available,
       SUM (CASE WHEN ts.competency_level = 'EXPERT'
                 THEN 1 ELSE 0 END)                       AS experts,
       MIN (ts.certified_on)                              AS first_certified,
       (SELECT COUNT (*)
        FROM   booking b
        WHERE  b.subject_id = sub.subject_id)             AS total_bookings,
       ROUND ((SELECT COUNT (*)
               FROM   booking b2
               WHERE  b2.subject_id = sub.subject_id)
              / COUNT (DISTINCT ts.tutor_id), 2)          AS load_per_tutor
FROM   subject sub
       JOIN tutor_skill ts ON ts.subject_id = sub.subject_id
GROUP  BY sub.subject_id, sub.subject_code, sub.subject_name
HAVING COUNT (DISTINCT ts.tutor_id) >= 1
ORDER  BY load_per_tutor DESC, tutors_available DESC;


-- #####################################################################
--  Q6 -- ANALYTIC (WINDOW) FUNCTIONS
--  Rank the tutors inside each subject, so a tutee searching for help
--  sees the strongest first.
--
--    RANK()        position within the subject
--    COUNT() OVER  how many tutors that subject has, repeated on each row
--    LAG()         the competency of the tutor ranked just above
--    FIRST_VALUE() the best tutor in that subject, shown on every row
--
--  PARTITION BY restarts the ranking for each subject. The ORDER BY
--  inside OVER() uses a CASE to turn the competency words into a sort
--  order, since alphabetically 'BEGINNER' would come before 'EXPERT'.
-- #####################################################################
PROMPT
PROMPT ===== M2-Q6 : tutor ranking within each subject (ANALYTIC) =====

SELECT sub.subject_code,
       s.first_name || ' ' || s.last_name           AS tutor_name,
       ts.competency_level,
       ts.grade_proof,
       RANK () OVER (PARTITION BY sub.subject_id
                     ORDER BY CASE ts.competency_level
                                WHEN 'EXPERT'     THEN 1
                                WHEN 'PROFICIENT' THEN 2
                                ELSE                   3 END,
                              ts.grade_proof)       AS rank_in_subject,
       COUNT (*) OVER (PARTITION BY sub.subject_id) AS tutors_in_subject,
       LAG (ts.competency_level) OVER (
            PARTITION BY sub.subject_id
            ORDER BY ts.grade_proof)                AS level_above,
       FIRST_VALUE (s.first_name) OVER (
            PARTITION BY sub.subject_id
            ORDER BY CASE ts.competency_level
                       WHEN 'EXPERT'     THEN 1
                       WHEN 'PROFICIENT' THEN 2
                       ELSE                   3 END)
                                                    AS top_tutor
FROM   tutor_skill ts
       JOIN subject sub ON sub.subject_id = ts.subject_id
       JOIN student s   ON s.student_id   = ts.tutor_id
ORDER  BY sub.subject_code, rank_in_subject;


PROMPT
PROMPT ===== MEMBER 2 COMPLETE : 3 DML + 6 SELECT = 9 queries =====
