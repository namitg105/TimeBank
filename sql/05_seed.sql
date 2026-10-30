-- =====================================================================
--  TimeBank
--  File    : 05_seed.sql
--  Purpose : Populate the database with a realistic campus.
--
--  TWO-PART STRATEGY
--  1. MASTER data (departments, students, subjects, skills, slots) is
--     inserted directly, with small readable IDs so the query files can
--     refer to them.
--  2. TRANSACTIONAL data (bookings, ledger rows, disputes) is created
--     ONLY by calling PKG_TIMEBANK.  Hand-written INSERTs could easily
--     produce a ledger that does not balance; going through the package
--     means the seed data is correct by construction.
--
--  DATES
--  Every date is computed from TRUNC(SYSDATE,'IW') -- the Monday of the
--  current ISO week.  That is independent of the NLS language setting,
--  and it means this script still works correctly whenever it is run.
--     last week  = TRUNC(SYSDATE,'IW') - 7 + offset   (already happened)
--     next week  = TRUNC(SYSDATE,'IW') + 7 + offset   (still upcoming)
--  offset: 0=MON 1=TUE 2=WED 3=THU 4=FRI 5=SAT 6=SUN
-- =====================================================================

SET SERVEROUTPUT ON
SET DEFINE OFF


-- =====================================================================
--  DEPARTMENT
-- =====================================================================
INSERT INTO department VALUES (1, 'Computer Science and Engineering', 'Dr. S. Ramanathan', 'SCOPE');
INSERT INTO department VALUES (2, 'Mechanical Engineering',           'Dr. P. Venkatesh',  'SMEC');
INSERT INTO department VALUES (3, 'Electrical Engineering',           'Dr. A. Krishnan',   'SELECT');
INSERT INTO department VALUES (4, 'Advanced Sciences',                'Dr. L. Bhattachar', 'SAS');
INSERT INTO department VALUES (5, 'Business Studies',                 'Dr. M. Fernandes',  'VITBS');


-- =====================================================================
--  SUBJECT
--  Note which department owns each one -- several tutors below teach
--  subjects owned by a department they do not belong to.
-- =====================================================================
INSERT INTO subject VALUES (101, 'BACSE202', 'Database Systems',                 'CORE',     1);
INSERT INTO subject VALUES (102, 'BACSE203', 'Data Communications and Networking','CORE',     1);
INSERT INTO subject VALUES (103, 'BACSE201', 'Theory of Computation',            'CORE',     1);
INSERT INTO subject VALUES (104, 'BMAT201',  'Probability and Statistics',       'CORE',     4);
INSERT INTO subject VALUES (105, 'BPHY101',  'Engineering Physics',              'CORE',     4);
INSERT INTO subject VALUES (106, 'BMEE201',  'Engineering Thermodynamics',       'CORE',     2);
INSERT INTO subject VALUES (107, 'BEEE202',  'Signals and Systems',              'CORE',     3);
INSERT INTO subject VALUES (108, 'BACSE301', 'Design and Analysis of Algorithms','CORE',     1);
INSERT INTO subject VALUES (109, 'BMGT101',  'Principles of Management',         'ELECTIVE', 5);
INSERT INTO subject VALUES (110, 'BACSE204', 'Operating Systems',                'CORE',     1);


-- =====================================================================
--  STUDENT
--  12 students.  The interesting ones for the ER model:
--    105 Kabir  and  109 Arjun  are BOTH tutor and tutee  -> OVERLAPPING
--    108 Sara   is NEITHER yet (just registered)          -> PARTIAL
-- =====================================================================
INSERT INTO student VALUES (101,'25BCE1001','aarav.sharma@vit.ac.in',  TRUNC(SYSDATE)-400,'ACTIVE','Aarav', 'Sharma', 'A Block','214','Vellore',  DATE '2005-03-14', 1);
INSERT INTO student VALUES (102,'25BCE1002','diya.nair@vit.ac.in',     TRUNC(SYSDATE)-395,'ACTIVE','Diya',  'Nair',   'B Block','118','Kochi',    DATE '2005-07-02', 1);
INSERT INTO student VALUES (103,'25BME2001','rohan.mehta@vit.ac.in',   TRUNC(SYSDATE)-390,'ACTIVE','Rohan', 'Mehta',  'C Block','305','Pune',     DATE '2004-11-23', 2);
INSERT INTO student VALUES (104,'25BAS4001','ishita.rao@vit.ac.in',    TRUNC(SYSDATE)-380,'ACTIVE','Ishita','Rao',    'D Block','402','Bengaluru',DATE '2005-01-09', 4);
INSERT INTO student VALUES (105,'25BCE1003','kabir.singh@vit.ac.in',   TRUNC(SYSDATE)-375,'ACTIVE','Kabir', 'Singh',  'A Block','221','Jaipur',   DATE '2004-09-30', 1);
INSERT INTO student VALUES (106,'25BEE3001','ananya.iyer@vit.ac.in',   TRUNC(SYSDATE)-360,'ACTIVE','Ananya','Iyer',   'E Block','107','Chennai',  DATE '2005-05-17', 3);
INSERT INTO student VALUES (107,'25BCE1004','vivaan.joshi@vit.ac.in',  TRUNC(SYSDATE)-355,'ACTIVE','Vivaan','Joshi',  'B Block','233','Nagpur',   DATE '2004-12-05', 1);
INSERT INTO student VALUES (108,'25BBS5001','sara.khan@vit.ac.in',     TRUNC(SYSDATE)-10, 'ACTIVE','Sara',  'Khan',   'F Block','510','Hyderabad',DATE '2005-08-21', 5);
INSERT INTO student VALUES (109,'25BCE1005','arjun.patel@vit.ac.in',   TRUNC(SYSDATE)-350,'ACTIVE','Arjun', 'Patel',  'A Block','119','Ahmedabad',DATE '2004-06-11', 1);
INSERT INTO student VALUES (110,'25BAS4002','riya.desai@vit.ac.in',    TRUNC(SYSDATE)-340,'ACTIVE','Riya',  'Desai',  'D Block','418','Surat',    DATE '2005-02-28', 4);
INSERT INTO student VALUES (111,'25BME2002','neel.verma@vit.ac.in',    TRUNC(SYSDATE)-330,'ACTIVE','Neel',  'Verma',  'C Block','312','Indore',   DATE '2004-10-08', 2);
INSERT INTO student VALUES (112,'25BEE3002','meera.pillai@vit.ac.in',  TRUNC(SYSDATE)-300,'ACTIVE','Meera', 'Pillai', 'E Block','126','Kollam',   DATE '2005-04-19', 3);


-- =====================================================================
--  STUDENT_PHONE   (the multivalued attribute in action)
--  Several students registered more than one number.
-- =====================================================================
INSERT INTO student_phone VALUES (101, '9840011221');
INSERT INTO student_phone VALUES (101, '9003344556');
-- second number
INSERT INTO student_phone VALUES (102, '9995512340');
INSERT INTO student_phone VALUES (103, '9822114477');
INSERT INTO student_phone VALUES (104, '9880077665');
INSERT INTO student_phone VALUES (105, '9414455667');
INSERT INTO student_phone VALUES (105, '9001122334');
-- second number
INSERT INTO student_phone VALUES (106, '9789011223');
INSERT INTO student_phone VALUES (107, '9765432109');
INSERT INTO student_phone VALUES (108, '9701234567');
INSERT INTO student_phone VALUES (109, '9898776655');
INSERT INTO student_phone VALUES (110, '9924466880');
INSERT INTO student_phone VALUES (111, '9730099881');
INSERT INTO student_phone VALUES (112, '9847755443');


-- =====================================================================
--  TUTOR   (subclass 1 of the overlapping specialization)
-- =====================================================================
INSERT INTO tutor VALUES (101, 'BRONZE', 'VIT-GRD-1001');
INSERT INTO tutor VALUES (103, 'BRONZE', 'VIT-GRD-1002');
INSERT INTO tutor VALUES (105, 'BRONZE', 'VIT-GRD-1003');
INSERT INTO tutor VALUES (107, 'BRONZE', 'VIT-GRD-1004');
INSERT INTO tutor VALUES (109, 'BRONZE', 'VIT-GRD-1005');
INSERT INTO tutor VALUES (111, 'BRONZE', 'VIT-GRD-1006');


-- =====================================================================
--  TUTEE   (subclass 2)
--  105 and 109 appear in BOTH tables -- only possible because the
--  specialization is OVERLAPPING.  Option 8B would have duplicated
--  their name, email and address; option 8A stores each once.
-- =====================================================================
INSERT INTO tutee VALUES (102, 'INTERMEDIATE');
INSERT INTO tutee VALUES (104, 'BASIC');
INSERT INTO tutee VALUES (105, 'ADVANCED');
-- also a tutor
INSERT INTO tutee VALUES (106, 'INTERMEDIATE');
INSERT INTO tutee VALUES (109, 'BASIC');
-- also a tutor
INSERT INTO tutee VALUES (110, 'ADVANCED');
INSERT INTO tutee VALUES (112, 'INTERMEDIATE');
-- Note: 108 Sara is in NEITHER subclass. That is the PARTIAL
-- specialization: a registered student who has not yet taught or booked.


-- =====================================================================
--  TUTEE_PREFTIME   (second multivalued attribute)
-- =====================================================================
INSERT INTO tutee_preftime VALUES (102, 'EVENING');
INSERT INTO tutee_preftime VALUES (102, 'NIGHT');
INSERT INTO tutee_preftime VALUES (104, 'MORNING');
INSERT INTO tutee_preftime VALUES (105, 'AFTERNOON');
INSERT INTO tutee_preftime VALUES (106, 'EVENING');
INSERT INTO tutee_preftime VALUES (109, 'MORNING');
INSERT INTO tutee_preftime VALUES (109, 'AFTERNOON');
INSERT INTO tutee_preftime VALUES (110, 'EVENING');
INSERT INTO tutee_preftime VALUES (112, 'AFTERNOON');


-- =====================================================================
--  TUTOR_SKILL   (the M:N "offers" relationship, with its own attributes)
--
--  CROSS-DEPARTMENT TUTORING -- proof that a student's department does
--  not limit what they may teach:
--    103 Rohan  is Mechanical, teaches Database Systems (a SCOPE subject)
--    109 Arjun  is SCOPE,      teaches Probability (an SAS subject)
--    111 Neel   is Mechanical, teaches Engineering Physics (an SAS subject)
-- =====================================================================
INSERT INTO tutor_skill VALUES (101, 101, 'EXPERT',     'S', TRUNC(SYSDATE)-300);
INSERT INTO tutor_skill VALUES (101, 108, 'PROFICIENT', 'A', TRUNC(SYSDATE)-250);
INSERT INTO tutor_skill VALUES (103, 101, 'PROFICIENT', 'A', TRUNC(SYSDATE)-280);
-- cross-dept
INSERT INTO tutor_skill VALUES (103, 106, 'EXPERT',     'S', TRUNC(SYSDATE)-290);
INSERT INTO tutor_skill VALUES (105, 103, 'EXPERT',     'S', TRUNC(SYSDATE)-270);
INSERT INTO tutor_skill VALUES (105, 110, 'PROFICIENT', 'A', TRUNC(SYSDATE)-260);
INSERT INTO tutor_skill VALUES (107, 102, 'EXPERT',     'S', TRUNC(SYSDATE)-240);
INSERT INTO tutor_skill VALUES (107, 110, 'EXPERT',     'S', TRUNC(SYSDATE)-230);
INSERT INTO tutor_skill VALUES (109, 101, 'EXPERT',     'S', TRUNC(SYSDATE)-220);
INSERT INTO tutor_skill VALUES (109, 104, 'PROFICIENT', 'B', TRUNC(SYSDATE)-210);
-- cross-dept
INSERT INTO tutor_skill VALUES (111, 105, 'PROFICIENT', 'A', TRUNC(SYSDATE)-200);
-- cross-dept
INSERT INTO tutor_skill VALUES (111, 106, 'PROFICIENT', 'B', TRUNC(SYSDATE)-190);
-- Subject 107 (Signals and Systems) and 109 (Management) have NO tutor.
-- That is the partial participation of SUBJECT in "offers", and it is
-- exactly the coverage gap TimeBank is meant to reveal.


-- =====================================================================
--  SLOT   (weak entity -- slot_no restarts at 1 for every tutor)
--  Times are decimal hours on a 24h clock: 16.5 means 16:30.
-- =====================================================================
INSERT INTO slot VALUES (101, 1, 'MON', 16, 18);
INSERT INTO slot VALUES (101, 2, 'WED', 14, 16);
INSERT INTO slot VALUES (103, 1, 'TUE', 10, 12);
INSERT INTO slot VALUES (103, 2, 'THU', 16, 18);
INSERT INTO slot VALUES (105, 1, 'MON', 18, 20);
INSERT INTO slot VALUES (105, 2, 'FRI', 14, 16);
INSERT INTO slot VALUES (107, 1, 'WED', 16, 18);
INSERT INTO slot VALUES (107, 2, 'SAT', 10, 12);
INSERT INTO slot VALUES (109, 1, 'TUE', 14, 16);
INSERT INTO slot VALUES (109, 2, 'THU', 10, 12);
INSERT INTO slot VALUES (111, 1, 'FRI', 16, 18);
INSERT INTO slot VALUES (111, 2, 'SAT', 14, 16);
-- never booked


-- =====================================================================
--  ADMIN
-- =====================================================================
INSERT INTO admin VALUES (seq_admin.NEXTVAL, 'Dr. Kavitha Raman',  'Faculty Coordinator');
INSERT INTO admin VALUES (seq_admin.NEXTVAL, 'Mr. Suresh Babu',    'Student Welfare Officer');

COMMIT;


-- =====================================================================
--  STARTER GRANTS
--  Every student gets 3.0 credits at registration.  This is why "posts"
--  is TOTAL on the Student side: no student can exist with an empty
--  ledger.  balance_snapshot is 3.0 because this is each student's
--  first and only row so far.
-- =====================================================================
INSERT INTO credit_txn (
    txn_id, txn_type, amount, balance_snapshot,
    remarks, student_id, booking_id)
SELECT seq_txn.NEXTVAL, 'GRANT', 3.0, 3.0,
       'Starter grant on registration', student_id, NULL
FROM   student;

COMMIT;


-- =====================================================================
--  TRANSACTIONAL DATA -- all of it through PKG_TIMEBANK
-- =====================================================================
DECLARE
  v_mon_last  DATE := TRUNC (SYSDATE, 'IW') - 7;   -- Monday of last week
  v_mon_next  DATE := TRUNC (SYSDATE, 'IW') + 7;   -- Monday of next week

  v_bk    NUMBER;
  v_code  VARCHAR2(8);
  v_dno   NUMBER;

  -- Book, check in and confirm from both sides in one go.
  PROCEDURE run_completed (
      p_tutee    NUMBER, p_tutor NUMBER, p_subject NUMBER,
      p_slot     NUMBER, p_date  DATE,   p_start   NUMBER,
      p_duration NUMBER, p_mode  VARCHAR2, p_venue VARCHAR2)
  IS
    l_bk    NUMBER;
    l_code  VARCHAR2(8);
  BEGIN
    pkg_timebank.book_session (
        p_tutee, p_tutor, p_subject, p_slot, p_date, p_start,
        p_duration, p_mode, p_venue, l_bk, l_code);
    pkg_timebank.check_in       (l_bk, l_code);
    pkg_timebank.confirm_session(l_bk, 'TUTOR');
    pkg_timebank.confirm_session(l_bk, 'TUTEE');
    DBMS_OUTPUT.PUT_LINE ('  completed booking ' || l_bk ||
                          '  tutee ' || p_tutee || ' <- tutor ' || p_tutor);
  END run_completed;

BEGIN
  DBMS_OUTPUT.PUT_LINE ('Creating sessions...');

  -- ---------- finished sessions (last week) ------------------------
  run_completed (102, 101, 101, 1, v_mon_last + 0, 16,   1.5, 'OFFLINE', 'SJT 512');
  run_completed (104, 109, 104, 2, v_mon_last + 3, 10,   1.0, 'ONLINE',  'Google Meet');
  run_completed (106, 107, 102, 1, v_mon_last + 2, 16,   2.0, 'OFFLINE', 'TT 304');
  run_completed (110, 103, 101, 1, v_mon_last + 1, 10,   1.0, 'OFFLINE', 'SJT 218');  -- cross-dept tutor
  run_completed (112, 105, 103, 1, v_mon_last + 0, 18,   1.5, 'ONLINE',  'MS Teams');
  run_completed (105, 111, 105, 1, v_mon_last + 4, 16,   1.0, 'OFFLINE', 'MB 108');   -- tutee is also a tutor
  run_completed (109, 101, 108, 2, v_mon_last + 2, 14,   1.0, 'ONLINE',  'Google Meet');

  -- ---------- a cancellation --------------------------------------
  -- The tutor pulls out, so the tutee gets every credit back.
  pkg_timebank.book_session (
      102, 105, 110, 2, v_mon_last + 4, 14, 1.0, 'ONLINE', 'MS Teams',
      v_bk, v_code);
  pkg_timebank.cancel_booking (v_bk, 'TUTOR');
  DBMS_OUTPUT.PUT_LINE ('  cancelled booking ' || v_bk || ' (tutor withdrew)');

  -- ---------- a dispute, resolved in the tutee's favour ------------
  -- The tutor never showed up, so the escrow goes back and the tutor
  -- takes a PENALTY -- the only way credits leave the economy.
  pkg_timebank.book_session (
      104, 107, 110, 2, v_mon_last + 5, 10, 1.5, 'OFFLINE', 'TT 115',
      v_bk, v_code);
  pkg_timebank.raise_dispute (
      v_bk, 'TUTEE', 'Tutor did not arrive and did not reply to messages.',
      v_dno);
  pkg_timebank.resolve_dispute (
      v_bk, v_dno, 1, 'TUTEE',
      'Checked the check-in log: no code was ever entered. Escrow returned, tutor penalised.');
  DBMS_OUTPUT.PUT_LINE ('  disputed booking ' || v_bk || ' resolved for the tutee');

  -- ---------- upcoming sessions (next week) ------------------------
  -- These stay CONFIRMED with credits still sitting in escrow, which is
  -- what makes the closed-economy audit interesting.
  pkg_timebank.book_session (
      106, 103, 106, 2, v_mon_next + 3, 16, 1.0, 'OFFLINE', 'MB 204',
      v_bk, v_code);
  DBMS_OUTPUT.PUT_LINE ('  upcoming booking ' || v_bk || '  code ' || v_code);

  pkg_timebank.book_session (
      110, 109, 101, 1, v_mon_next + 1, 14, 2.0, 'ONLINE', 'Google Meet',
      v_bk, v_code);
  DBMS_OUTPUT.PUT_LINE ('  upcoming booking ' || v_bk || '  code ' || v_code);

  pkg_timebank.book_session (
      112, 101, 101, 1, v_mon_next + 0, 16, 1.0, 'OFFLINE', 'SJT 512',
      v_bk, v_code);
  DBMS_OUTPUT.PUT_LINE ('  upcoming booking ' || v_bk || '  code ' || v_code);

  COMMIT;
  DBMS_OUTPUT.PUT_LINE ('Sessions created.');
END;
/


-- =====================================================================
--  FEEDBACK
--  Written against the COMPLETED bookings.  Note that a booking can
--  carry two rows, one per role -- which is why the tutor's rating must
--  average ONLY the rows where reviewer_role = 'TUTEE'.
-- =====================================================================
-- The tutee's review of the tutor.  ROW_NUMBER() turns "the Nth
-- completed booking" into its real booking_id, so this works whatever
-- ids the sequence happened to hand out.
INSERT INTO feedback (booking_id, reviewer_role, rating, comments, feedback_date)
SELECT booking_id,
       'TUTEE',
       CASE rn WHEN 1 THEN 5.0 WHEN 2 THEN 4.0 WHEN 3 THEN 5.0
               WHEN 4 THEN 4.5 WHEN 5 THEN 3.5 WHEN 6 THEN 5.0
               ELSE 4.5 END,
       CASE rn
         WHEN 1 THEN 'Explained normalization with real tables. Very clear.'
         WHEN 2 THEN 'Good on Bayes theorem, but rushed the last example.'
         WHEN 3 THEN 'Sliding window finally makes sense. Great diagrams.'
         WHEN 4 THEN 'Knows databases well even though he is from Mechanical.'
         WHEN 5 THEN 'The pumping lemma section was hard to follow.'
         WHEN 6 THEN 'Worked through three past-paper problems with me.'
         ELSE        'Good coverage of greedy versus dynamic programming.'
       END,
       SYSDATE - 3
FROM   (SELECT booking_id, ROW_NUMBER() OVER (ORDER BY booking_id) AS rn
        FROM   booking
        WHERE  status = 'COMPLETED');

-- The tutor's review of the tutee.  Deliberately NOT written for every
-- session -- people often skip it, which is the partial participation
-- of BOOKING in "receives".
INSERT INTO feedback (booking_id, reviewer_role, rating, comments, feedback_date)
SELECT booking_id,
       'TUTOR',
       CASE rn WHEN 1 THEN 4.5 WHEN 2 THEN 5.0 WHEN 3 THEN 4.0
               WHEN 4 THEN 5.0 WHEN 5 THEN 4.0 ELSE 4.5 END,
       CASE rn
         WHEN 1 THEN 'Came prepared with questions written down.'
         WHEN 2 THEN 'Picked things up very quickly.'
         WHEN 3 THEN 'Joined ten minutes late but worked hard after that.'
         WHEN 4 THEN 'Asked excellent follow-up questions.'
         WHEN 5 THEN 'Patient and polite throughout.'
         ELSE        'Already knew the basics, so we went deeper.'
       END,
       SYSDATE - 3
FROM   (SELECT booking_id, ROW_NUMBER() OVER (ORDER BY booking_id) AS rn
        FROM   booking
        WHERE  status = 'COMPLETED')
WHERE  rn IN (1, 2, 3, 4, 5, 7);
-- booking 6 got no tutor review

COMMIT;


-- =====================================================================
--  VERIFY
-- =====================================================================
SET SERVEROUTPUT ON
EXEC pkg_timebank.audit_economy;

PROMPT
PROMPT ===> Seed complete. Row counts:
SELECT 'DEPARTMENT'     AS table_name, COUNT(*) AS rows_loaded FROM department
UNION ALL SELECT 'STUDENT',        COUNT(*) FROM student
UNION ALL SELECT 'STUDENT_PHONE',  COUNT(*) FROM student_phone
UNION ALL SELECT 'TUTOR',          COUNT(*) FROM tutor
UNION ALL SELECT 'TUTEE',          COUNT(*) FROM tutee
UNION ALL SELECT 'TUTEE_PREFTIME', COUNT(*) FROM tutee_preftime
UNION ALL SELECT 'SUBJECT',        COUNT(*) FROM subject
UNION ALL SELECT 'TUTOR_SKILL',    COUNT(*) FROM tutor_skill
UNION ALL SELECT 'SLOT',           COUNT(*) FROM slot
UNION ALL SELECT 'BOOKING',        COUNT(*) FROM booking
UNION ALL SELECT 'FEEDBACK',       COUNT(*) FROM feedback
UNION ALL SELECT 'ADMIN',          COUNT(*) FROM admin
UNION ALL SELECT 'DISPUTE',        COUNT(*) FROM dispute
UNION ALL SELECT 'CREDIT_TXN',     COUNT(*) FROM credit_txn;
