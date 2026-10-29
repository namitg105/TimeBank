-- =====================================================================
--  TimeBank : A Peer Tutoring Credit Exchange Management System
--  File    : 01_ddl.sql
--  Purpose : Create all 14 relations, every integrity constraint,
--            the sequences, and the derived-value views.
--  Module  : Maps to Module 1 (relational model constraints: domain,
--            key, entity integrity, referential integrity, nulls)
--            and Module 2 (the ER-to-relational mapping result).
-- =====================================================================

SET SERVEROUTPUT ON
SET DEFINE OFF


-- =====================================================================
--  SEQUENCES
--  Master data (departments, students, subjects) is seeded with small
--  readable IDs, so those sequences start at 1000 to avoid collisions.
--  Transactional data is created only by the application / package, so
--  those sequences start at 1.
-- =====================================================================

CREATE SEQUENCE seq_dept       START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_student    START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_subject    START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_booking    START WITH 1    INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_txn        START WITH 1    INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_admin      START WITH 1    INCREMENT BY 1 NOCACHE;


-- =====================================================================
--  RELATION 1 : DEPARTMENT
--  Mapping step 1 (strong entity).  Referenced by STUDENT and SUBJECT.
-- =====================================================================
CREATE TABLE department (
  dept_id     NUMBER(6)        NOT NULL,
  dept_name   VARCHAR2(60)     NOT NULL,
  dept_head   VARCHAR2(60),
  school      VARCHAR2(60)     NOT NULL,
  --
  CONSTRAINT pk_department   PRIMARY KEY (dept_id),
  CONSTRAINT uq_dept_name    UNIQUE (dept_name)
);

COMMENT ON TABLE department IS
  'Academic department. Owns subjects and enrols students. Note: a department never restricts which subjects a student may tutor.';


-- =====================================================================
--  RELATION 2 : STUDENT   (superclass of the ISA specialization)
--  Mapping step 1 + step 4 (FK dept_id from the "belongs to" 1:N).
--  Composite attributes Name and Address are flattened here, which is
--  mapping rule 3: only the leaf components become columns.
--  CREDIT_BALANCE is NOT a column -- it is derived (see v_student_balance).
-- =====================================================================
CREATE TABLE student (
  student_id      NUMBER(8)     NOT NULL,
  reg_no          VARCHAR2(15)  NOT NULL,
  email           VARCHAR2(80)  NOT NULL,
  join_date       DATE          DEFAULT SYSDATE NOT NULL,
  account_status  VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL,
  first_name      VARCHAR2(40)  NOT NULL,   -- Name (composite) -> leaf
  last_name       VARCHAR2(40)  NOT NULL,   -- Name (composite) -> leaf
  block           VARCHAR2(20),             -- Address (composite) -> leaf
  room_no         VARCHAR2(10),             -- Address (composite) -> leaf
  city            VARCHAR2(40),             -- Address (composite) -> leaf
  dob             DATE          NOT NULL,
  dept_id         NUMBER(6)     NOT NULL,
  --
  CONSTRAINT pk_student        PRIMARY KEY (student_id),
  CONSTRAINT uq_student_reg    UNIQUE (reg_no),
  CONSTRAINT uq_student_email  UNIQUE (email),
  CONSTRAINT fk_student_dept   FOREIGN KEY (dept_id)
                               REFERENCES department (dept_id),
  CONSTRAINT chk_stu_status    CHECK (account_status IN
                                 ('ACTIVE','SUSPENDED','INACTIVE')),
  CONSTRAINT chk_stu_email     CHECK (email LIKE '%@%.%')
);

COMMENT ON COLUMN student.dept_id IS
  'Informational only. Does NOT limit which subjects this student may tutor.';


-- =====================================================================
--  RELATION 3 : STUDENT_PHONE
--  Mapping step 6 (multivalued attribute PhoneNo).
--  PK = {owner key + the value itself}.
-- =====================================================================
CREATE TABLE student_phone (
  student_id  NUMBER(8)     NOT NULL,
  phone_no    VARCHAR2(15)  NOT NULL,
  --
  CONSTRAINT pk_student_phone PRIMARY KEY (student_id, phone_no),
  CONSTRAINT fk_phone_student FOREIGN KEY (student_id)
                              REFERENCES student (student_id)
                              ON DELETE CASCADE,
  CONSTRAINT chk_phone_digits CHECK (REGEXP_LIKE (phone_no, '^[0-9]{10}$'))
);


-- =====================================================================
--  RELATION 4 : TUTOR   (subclass -- mapping option 8A)
--  Option 8A is required because the specialization is OVERLAPPING and
--  PARTIAL: one student can be both tutor and tutee, and a new student
--  is neither.  student_id is simultaneously PK and FK.
--  TOTAL_HOURS_TAUGHT and AVG_RATING_AS_TUTOR are derived -> not stored.
-- =====================================================================
CREATE TABLE tutor (
  student_id           NUMBER(8)     NOT NULL,
  badge_level          VARCHAR2(10)  DEFAULT 'BRONZE' NOT NULL,
  verification_doc_no  VARCHAR2(30)  NOT NULL,
  --
  CONSTRAINT pk_tutor        PRIMARY KEY (student_id),
  CONSTRAINT fk_tutor_student FOREIGN KEY (student_id)
                              REFERENCES student (student_id)
                              ON DELETE CASCADE,
  CONSTRAINT chk_badge       CHECK (badge_level IN ('BRONZE','SILVER','GOLD'))
);


-- =====================================================================
--  RELATION 5 : TUTEE   (subclass -- mapping option 8A)
-- =====================================================================
CREATE TABLE tutee (
  student_id          NUMBER(8)     NOT NULL,
  academic_need_tier  VARCHAR2(15)  DEFAULT 'BASIC' NOT NULL,
  --
  CONSTRAINT pk_tutee         PRIMARY KEY (student_id),
  CONSTRAINT fk_tutee_student FOREIGN KEY (student_id)
                              REFERENCES student (student_id)
                              ON DELETE CASCADE,
  CONSTRAINT chk_need_tier    CHECK (academic_need_tier IN
                                ('BASIC','INTERMEDIATE','ADVANCED'))
);


-- =====================================================================
--  RELATION 6 : TUTEE_PREFTIME
--  Mapping step 6 (multivalued attribute PreferredTimeBand).
-- =====================================================================
CREATE TABLE tutee_preftime (
  student_id          NUMBER(8)     NOT NULL,
  preferred_timeband  VARCHAR2(10)  NOT NULL,
  --
  CONSTRAINT pk_tutee_pref  PRIMARY KEY (student_id, preferred_timeband),
  CONSTRAINT fk_pref_tutee  FOREIGN KEY (student_id)
                            REFERENCES tutee (student_id)
                            ON DELETE CASCADE,
  CONSTRAINT chk_timeband   CHECK (preferred_timeband IN
                              ('MORNING','AFTERNOON','EVENING','NIGHT'))
);


-- =====================================================================
--  RELATION 7 : SUBJECT
--  Mapping step 1 + step 4 (FK dept_id from "offered by").
-- =====================================================================
CREATE TABLE subject (
  subject_id    NUMBER(6)     NOT NULL,
  subject_code  VARCHAR2(12)  NOT NULL,
  subject_name  VARCHAR2(70)  NOT NULL,
  category      VARCHAR2(12)  NOT NULL,
  dept_id       NUMBER(6)     NOT NULL,
  --
  CONSTRAINT pk_subject      PRIMARY KEY (subject_id),
  CONSTRAINT uq_subject_code UNIQUE (subject_code),
  CONSTRAINT fk_subject_dept FOREIGN KEY (dept_id)
                             REFERENCES department (dept_id),
  CONSTRAINT chk_sub_cat     CHECK (category IN ('CORE','ELECTIVE','LAB'))
);


-- =====================================================================
--  RELATION 8 : TUTOR_SKILL
--  Mapping step 5 (M:N relationship "offers").  The three descriptive
--  attributes of the relationship diamond live here, NOT on TUTOR or
--  SUBJECT, because they describe one tutor's skill in one subject.
--  This table is also the referenced parent of a composite FK from
--  BOOKING, which is what guarantees a tutor can only be booked for a
--  subject they actually offer.
-- =====================================================================
CREATE TABLE tutor_skill (
  tutor_id          NUMBER(8)     NOT NULL,
  subject_id        NUMBER(6)     NOT NULL,
  competency_level  VARCHAR2(12)  NOT NULL,
  grade_proof       VARCHAR2(2)   NOT NULL,
  certified_on      DATE          DEFAULT SYSDATE NOT NULL,
  --
  CONSTRAINT pk_tutor_skill   PRIMARY KEY (tutor_id, subject_id),
  CONSTRAINT fk_skill_tutor   FOREIGN KEY (tutor_id)
                              REFERENCES tutor (student_id)
                              ON DELETE CASCADE,
  CONSTRAINT fk_skill_subject FOREIGN KEY (subject_id)
                              REFERENCES subject (subject_id),
  CONSTRAINT chk_competency   CHECK (competency_level IN
                                ('BEGINNER','PROFICIENT','EXPERT')),
  CONSTRAINT chk_grade_proof  CHECK (grade_proof IN ('S','A','B','C'))
);


-- =====================================================================
--  RELATION 9 : SLOT   (WEAK ENTITY, owner = TUTOR)
--  Mapping step 2.  PK = {owner PK + partial key slot_no}.
--  ON DELETE CASCADE because a weak entity cannot outlive its owner.
--  DURATION is derived (end - start) -> not stored.
-- =====================================================================
CREATE TABLE slot (
  tutor_id     NUMBER(8)     NOT NULL,
  slot_no      NUMBER(3)     NOT NULL,   -- partial key: restarts per tutor
  day_of_week  VARCHAR2(3)   NOT NULL,
  start_time   NUMBER(4,2)   NOT NULL,   -- 24h clock, e.g. 16.5 = 16:30
  end_time     NUMBER(4,2)   NOT NULL,
  --
  CONSTRAINT pk_slot       PRIMARY KEY (tutor_id, slot_no),
  CONSTRAINT fk_slot_tutor FOREIGN KEY (tutor_id)
                           REFERENCES tutor (student_id)
                           ON DELETE CASCADE,
  CONSTRAINT chk_slot_day  CHECK (day_of_week IN
                             ('MON','TUE','WED','THU','FRI','SAT','SUN')),
  CONSTRAINT chk_slot_hrs  CHECK (start_time >= 0 AND end_time <= 24),
  CONSTRAINT chk_slot_order CHECK (end_time > start_time)
);


-- =====================================================================
--  RELATION 10 : BOOKING   (the central entity)
--  Mapping step 1 + step 4 x 4.
--
--  TWO COMPOSITE FOREIGN KEYS share the tutor_id column:
--    (tutor_id, slot_no)    -> SLOT        : the slot must be THIS tutor's
--    (tutor_id, subject_id) -> TUTOR_SKILL : the tutor must offer it
--  Sharing one column is what makes both facts agree automatically,
--  with no trigger required.
--
--  Composite attributes from the ER diagram flattened here:
--    Schedule     -> sched_date, sched_start_time, duration_hours
--    Confirmation -> confirm_by_tutor, confirm_by_tutee
-- =====================================================================
CREATE TABLE booking (
  booking_id        NUMBER(10)    NOT NULL,
  session_code      VARCHAR2(8)   NOT NULL,  -- shown ONLY to the tutee
  request_date      DATE          DEFAULT SYSDATE NOT NULL,
  sched_date        DATE          NOT NULL,
  sched_start_time  NUMBER(4,2)   NOT NULL,
  duration_hours    NUMBER(3,1)   NOT NULL,
  session_mode      VARCHAR2(7)   NOT NULL,  -- "MODE" is an Oracle keyword
  venue             VARCHAR2(60),
  status            VARCHAR2(10)  DEFAULT 'REQUESTED' NOT NULL,
  credits_held      NUMBER(4,1)   DEFAULT 0 NOT NULL,
  confirm_by_tutor  CHAR(1)       DEFAULT 'N' NOT NULL,
  confirm_by_tutee  CHAR(1)       DEFAULT 'N' NOT NULL,
  check_in_at       TIMESTAMP,               -- set when SessionCode entered
  tutee_id          NUMBER(8)     NOT NULL,
  tutor_id          NUMBER(8)     NOT NULL,
  subject_id        NUMBER(6)     NOT NULL,
  slot_no           NUMBER(3)     NOT NULL,
  --
  CONSTRAINT pk_booking      PRIMARY KEY (booking_id),
  CONSTRAINT uq_session_code UNIQUE (session_code),
  CONSTRAINT fk_bk_tutee     FOREIGN KEY (tutee_id)
                             REFERENCES tutee (student_id),
  CONSTRAINT fk_bk_skill     FOREIGN KEY (tutor_id, subject_id)
                             REFERENCES tutor_skill (tutor_id, subject_id),
  CONSTRAINT fk_bk_slot      FOREIGN KEY (tutor_id, slot_no)
                             REFERENCES slot (tutor_id, slot_no),
  CONSTRAINT chk_bk_status   CHECK (status IN
                               ('REQUESTED','CONFIRMED','COMPLETED',
                                'CANCELLED','DISPUTED')),
  CONSTRAINT chk_bk_mode     CHECK (session_mode IN ('ONLINE','OFFLINE')),
  CONSTRAINT chk_bk_duration CHECK (duration_hours IN (0.5, 1.0, 1.5, 2.0)),
  CONSTRAINT chk_bk_held     CHECK (credits_held >= 0),
  CONSTRAINT chk_bk_conf_t   CHECK (confirm_by_tutor IN ('Y','N')),
  CONSTRAINT chk_bk_conf_e   CHECK (confirm_by_tutee IN ('Y','N')),
  CONSTRAINT chk_bk_not_self CHECK (tutor_id <> tutee_id)
);

COMMENT ON COLUMN booking.session_code IS
  'One-time code issued to the tutee. The tutor types it in to check in, which proves the tutee actually attended.';


-- =====================================================================
--  RELATION 11 : FEEDBACK   (WEAK ENTITY, owner = BOOKING)
--  Mapping step 2.  PK = {booking_id + reviewer_role}.
--  Using the role as the partial key means one booking holds at most two
--  reviews (one per participant) and nobody can review twice -- the
--  primary key enforces that business rule for free.
-- =====================================================================
CREATE TABLE feedback (
  booking_id     NUMBER(10)    NOT NULL,
  reviewer_role  VARCHAR2(5)   NOT NULL,   -- partial key
  rating         NUMBER(2,1)   NOT NULL,
  comments       VARCHAR2(400),
  feedback_date  DATE          DEFAULT SYSDATE NOT NULL,
  --
  CONSTRAINT pk_feedback      PRIMARY KEY (booking_id, reviewer_role),
  CONSTRAINT fk_fb_booking    FOREIGN KEY (booking_id)
                              REFERENCES booking (booking_id)
                              ON DELETE CASCADE,
  CONSTRAINT chk_fb_role      CHECK (reviewer_role IN ('TUTOR','TUTEE')),
  CONSTRAINT chk_fb_rating    CHECK (rating BETWEEN 1.0 AND 5.0)
);


-- =====================================================================
--  RELATION 12 : ADMIN
--  Resolves disputes.  Partial participation on both sides of "resolves".
-- =====================================================================
CREATE TABLE admin (
  admin_id     NUMBER(6)     NOT NULL,
  admin_name   VARCHAR2(60)  NOT NULL,
  designation  VARCHAR2(40)  NOT NULL,
  --
  CONSTRAINT pk_admin PRIMARY KEY (admin_id)
);


-- =====================================================================
--  RELATION 13 : DISPUTE   (WEAK ENTITY, owner = BOOKING)
--  Mapping step 2 + step 4 (resolved_by from "resolves").
--  resolved_by is NULLABLE: an open dispute has no resolver yet, which
--  is the partial participation shown by a single line in the ER diagram.
-- =====================================================================
CREATE TABLE dispute (
  booking_id       NUMBER(10)    NOT NULL,
  dispute_no       NUMBER(3)     NOT NULL,   -- partial key
  raised_by_role   VARCHAR2(5)   NOT NULL,
  reason           VARCHAR2(400) NOT NULL,
  raised_on        DATE          DEFAULT SYSDATE NOT NULL,
  status           VARCHAR2(12)  DEFAULT 'OPEN' NOT NULL,
  resolution_note  VARCHAR2(400),
  resolved_by      NUMBER(6),                -- NULL while unresolved
  --
  CONSTRAINT pk_dispute      PRIMARY KEY (booking_id, dispute_no),
  CONSTRAINT fk_dp_booking   FOREIGN KEY (booking_id)
                             REFERENCES booking (booking_id)
                             ON DELETE CASCADE,
  CONSTRAINT fk_dp_admin     FOREIGN KEY (resolved_by)
                             REFERENCES admin (admin_id),
  CONSTRAINT chk_dp_role     CHECK (raised_by_role IN ('TUTOR','TUTEE')),
  CONSTRAINT chk_dp_status   CHECK (status IN
                               ('OPEN','UNDER_REVIEW','RESOLVED')),
  -- A resolved dispute must name its resolver and carry a note.
  CONSTRAINT chk_dp_resolved CHECK (
       (status = 'RESOLVED' AND resolved_by IS NOT NULL
                            AND resolution_note IS NOT NULL)
    OR (status <> 'RESOLVED'))
);


-- =====================================================================
--  RELATION 14 : CREDIT_TXN   (the immutable ledger)
--  Mapping step 1 + step 4 x 2.
--    student_id  (from "posts")     : NOT NULL -- total participation
--    booking_id  (from "generates") : NULL     -- partial participation
--  booking_id is the ONLY nullable foreign key in the whole database,
--  because starter grants and penalties have no originating session.
-- =====================================================================
CREATE TABLE credit_txn (
  txn_id            NUMBER(12)    NOT NULL,
  txn_type          VARCHAR2(9)   NOT NULL,
  amount            NUMBER(4,1)   NOT NULL,   -- signed: + in, - out
  txn_timestamp     TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  balance_snapshot  NUMBER(6,1)   NOT NULL,   -- balance AFTER this row
  remarks           VARCHAR2(200),
  student_id        NUMBER(8)     NOT NULL,
  booking_id        NUMBER(10),               -- NULL for GRANT / PENALTY
  --
  CONSTRAINT pk_credit_txn   PRIMARY KEY (txn_id),
  CONSTRAINT fk_txn_student  FOREIGN KEY (student_id)
                             REFERENCES student (student_id),
  CONSTRAINT fk_txn_booking  FOREIGN KEY (booking_id)
                             REFERENCES booking (booking_id),
  CONSTRAINT chk_txn_type    CHECK (txn_type IN
                               ('GRANT','HOLD','RELEASE','TRANSFER','PENALTY')),
  CONSTRAINT chk_txn_nonzero CHECK (amount <> 0),
  -- The sign of the amount must agree with the kind of transaction.
  -- Without this, a PENALTY of +5.0 would invent credits from nothing.
  CONSTRAINT chk_txn_sign    CHECK (
       (txn_type IN ('GRANT','RELEASE','TRANSFER') AND amount > 0)
    OR (txn_type IN ('HOLD','PENALTY')            AND amount < 0)),
  -- A session-driven movement must name its booking; a grant must not.
  CONSTRAINT chk_txn_booking CHECK (
       (txn_type IN ('HOLD','RELEASE','TRANSFER') AND booking_id IS NOT NULL)
    OR (txn_type IN ('GRANT','PENALTY')))
);

COMMENT ON TABLE credit_txn IS
  'Append-only ledger. Rows are never updated or deleted; corrections are made by inserting a new PENALTY or RELEASE row.';
COMMENT ON COLUMN credit_txn.balance_snapshot IS
  'Controlled redundancy kept for auditability. Must equal the previous snapshot + this amount. Never updated.';


-- =====================================================================
--  DERIVED-VALUE VIEWS
--  The ER diagram marks these as derived attributes (dashed ovals), so
--  mapping rule 6 says they must NOT be stored as columns.  Exposing
--  them as views keeps the schema normalised while still making them
--  easy to query from the Java application.
-- =====================================================================

-- CreditBalance  =  SUM(amount) over that student's ledger rows.
CREATE OR REPLACE VIEW v_student_balance AS
SELECT s.student_id,
       s.first_name || ' ' || s.last_name           AS student_name,
       s.reg_no,
       s.dept_id,
       NVL (SUM (t.amount), 0)                      AS credit_balance,
       NVL (SUM (CASE WHEN t.txn_type = 'TRANSFER'
                      THEN t.amount END), 0)        AS credits_earned,
       COUNT (t.txn_id)                             AS ledger_rows
FROM   student s
       LEFT JOIN credit_txn t ON t.student_id = s.student_id
GROUP  BY s.student_id, s.first_name, s.last_name, s.reg_no, s.dept_id;


-- Age  =  derived from DOB.
-- TotalHoursTaught, AvgRatingAsTutor  =  derived from BOOKING / FEEDBACK.
-- Note the rating restriction: a booking holds TWO feedback rows, so a
-- tutor's rating must average only the ones written by the TUTEE.
CREATE OR REPLACE VIEW v_tutor_profile AS
SELECT t.student_id                                   AS tutor_id,
       s.first_name || ' ' || s.last_name             AS tutor_name,
       s.dept_id,
       t.badge_level,
       FLOOR (MONTHS_BETWEEN (SYSDATE, s.dob) / 12)   AS age,
       NVL ((SELECT SUM (b.duration_hours)
             FROM   booking b
             WHERE  b.tutor_id = t.student_id
             AND    b.status   = 'COMPLETED'), 0)     AS total_hours_taught,
       (SELECT ROUND (AVG (f.rating), 2)
        FROM   feedback f
               JOIN booking b2 ON b2.booking_id = f.booking_id
        WHERE  b2.tutor_id      = t.student_id
        AND    f.reviewer_role  = 'TUTEE')            AS avg_rating_as_tutor,
       (SELECT COUNT (*)
        FROM   tutor_skill ts
        WHERE  ts.tutor_id = t.student_id)            AS subjects_offered
FROM   tutor t
       JOIN student s ON s.student_id = t.student_id;


-- Slot duration, plus whether the slot is currently taken.
CREATE OR REPLACE VIEW v_slot_detail AS
SELECT sl.tutor_id,
       sl.slot_no,
       sl.day_of_week,
       sl.start_time,
       sl.end_time,
       sl.end_time - sl.start_time                    AS duration,
       (SELECT COUNT (*)
        FROM   booking b
        WHERE  b.tutor_id = sl.tutor_id
        AND    b.slot_no  = sl.slot_no
        AND    b.status IN ('REQUESTED','CONFIRMED')) AS active_bookings
FROM   slot sl;


PROMPT ===> 14 tables, 6 sequences and 3 views created.
