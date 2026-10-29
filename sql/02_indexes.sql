-- =====================================================================
--  TimeBank
--  File    : 02_indexes.sql
--  Purpose : Secondary indexes for the query workload.
--  Module  : Module 3 -- single-level and multi-level (B+ tree) indexing.
--
--  Oracle builds a B+ tree index by default for CREATE INDEX.  There is
--  no "clustered B+ tree" in Oracle; the nearest equivalent is an
--  index-organised table, demonstrated at the bottom of this file.
--
--  Note on what NOT to index: avg_rating_as_tutor is a DERIVED value
--  that changes after every session, so indexing it would mean constant
--  index maintenance.  We index the stable search keys instead.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tutor search:  "find tutors who teach subject X"
--    Composite (subject_id, tutor_id) lets Oracle answer the lookup
--    entirely from the index -- it never touches the table.  This is an
--    index-only scan, the cheapest possible access path.
-- ---------------------------------------------------------------------
CREATE INDEX idx_skill_subject ON tutor_skill (subject_id, tutor_id);


-- ---------------------------------------------------------------------
-- 2. Ledger statement:  "show this student's transactions, newest first"
--    Leading column student_id narrows to one student; the second column
--    delivers the rows already sorted, so the ORDER BY needs no sort.
-- ---------------------------------------------------------------------
CREATE INDEX idx_txn_student_time ON credit_txn (student_id, txn_timestamp DESC);


-- ---------------------------------------------------------------------
-- 3. Booking lookups by either participant.  Two separate indexes are
--    needed because an index can only be used when the query filters on
--    its LEADING column.
-- ---------------------------------------------------------------------
CREATE INDEX idx_booking_tutor ON booking (tutor_id, status);
CREATE INDEX idx_booking_tutee ON booking (tutee_id, status);


-- ---------------------------------------------------------------------
-- 4. Schedule conflict detection:  "is this tutor busy that day?"
-- ---------------------------------------------------------------------
CREATE INDEX idx_booking_sched ON booking (sched_date, tutor_id);


-- ---------------------------------------------------------------------
-- 5. Open-dispute queue for the admin dashboard.
--    A FUNCTION-BASED index: rows where status = 'RESOLVED' are stored
--    as NULL, and Oracle does not index all-NULL keys.  The index
--    therefore contains ONLY the open disputes, so it stays tiny no
--    matter how large the dispute table grows.
-- ---------------------------------------------------------------------
CREATE INDEX idx_dispute_open ON dispute (
  CASE WHEN status <> 'RESOLVED' THEN status END);


-- ---------------------------------------------------------------------
-- 6. Index-organised table demo (Oracle's answer to a clustered index).
--    In an IOT the table data lives INSIDE the B+ tree leaf blocks, so
--    there is no separate table segment and no ROWID lookup at all.
--    Used here for a small, read-mostly lookup table.
-- ---------------------------------------------------------------------
CREATE TABLE credit_policy (
  policy_key    VARCHAR2(30)  NOT NULL,
  policy_value  NUMBER(6,2)   NOT NULL,
  description   VARCHAR2(120) NOT NULL,
  CONSTRAINT pk_credit_policy PRIMARY KEY (policy_key)
) ORGANIZATION INDEX;

INSERT INTO credit_policy VALUES
  ('STARTER_GRANT',      3.0,  'Credits given to every new student at registration');
INSERT INTO credit_policy VALUES
  ('OVERDRAFT_FLOOR',   -5.0,  'A balance may never fall below this value');
INSERT INTO credit_policy VALUES
  ('LATE_CANCEL_HOURS', 24.0,  'Cancelling inside this window forfeits half the credits');
INSERT INTO credit_policy VALUES
  ('LATE_CANCEL_SHARE',  0.5,  'Fraction of held credits paid to the tutor on a late cancel');
INSERT INTO credit_policy VALUES
  ('DISPUTE_PENALTY',    1.0,  'Credits deducted from the party at fault');
INSERT INTO credit_policy VALUES
  ('PAIR_WEEKLY_CAP',    2.0,  'Max completed sessions per tutor-tutee pair per week');
COMMIT;


-- ---------------------------------------------------------------------
-- 7. Gather statistics so the optimiser costs these plans correctly.
--    Without stats Oracle guesses, and EXPLAIN PLAN output is meaningless.
-- ---------------------------------------------------------------------
BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS (ownname => USER, cascade => TRUE);
END;
/

PROMPT ===> Indexes, policy IOT and optimiser statistics created.
