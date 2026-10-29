-- =====================================================================
--  TimeBank
--  File    : 03_triggers.sql
--  Purpose : Business rules that a CHECK constraint cannot express.
--  Module  : Module 1 (constraint enforcement) + Module 4 (transaction
--            integrity).
--
--  WHY TRIGGERS AND NOT CHECK CONSTRAINTS?
--  An Oracle CHECK constraint may only look at the columns of the row
--  being changed.  It cannot call SYSDATE, cannot run a sub-query, and
--  cannot compare one row with another.  Every rule below needs at
--  least one of those, so each one has to be a trigger.
--
--  THE MUTATING-TABLE RESTRICTION  (important -- likely viva question)
--  A FOR EACH ROW trigger may NOT query the table its own statement is
--  changing; Oracle raises ORA-04091 "table is mutating".  The reason is
--  that half-finished statements would give the trigger an inconsistent
--  view of the data.
--
--  That rules out the obvious design for three of our rules:
--    * double-booking check   -- reads BOOKING while inserting BOOKING
--    * pair collusion cap     -- reads BOOKING while inserting BOOKING
--    * badge promotion        -- reads BOOKING while updating BOOKING
--
--  How each one is solved instead:
--    * double-booking + pair cap -> moved into PKG_TIMEBANK, where the
--      slot row can also be locked with SELECT ... FOR UPDATE.  A
--      trigger could never do that, so the package is the better home
--      anyway (see 04_packages.sql).
--    * badge promotion -> a COMPOUND TRIGGER.  Row ids are collected in
--      the AFTER EACH ROW section and processed in AFTER STATEMENT,
--      by which time the table is no longer mutating.
--
--  Every trigger kept below reads a DIFFERENT table from the one it
--  fires on, so none of them can mutate.
-- =====================================================================

SET SERVEROUTPUT ON


-- =====================================================================
--  TRIGGER 1 : The ledger is append-only.
--  Fires on   : CREDIT_TXN     Reads: nothing  -> safe
--
--  Credits must never be edited or erased.  A mistake is corrected by
--  INSERTING a compensating row, exactly like a real accounting ledger.
--  This is what makes the closed-economy audit meaningful: if rows could
--  be edited, SUM(amount) would prove nothing.
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_txn_immutable
BEFORE UPDATE OR DELETE ON credit_txn
FOR EACH ROW
BEGIN
  RAISE_APPLICATION_ERROR (-20001,
    'CREDIT_TXN is append-only. Insert a correcting PENALTY or RELEASE row instead of changing history.');
END;
/


-- =====================================================================
--  TRIGGER 2 : Overdraft floor.
--  Fires on   : BOOKING        Reads: CREDIT_TXN  -> safe
--
--  CreditBalance is a DERIVED attribute, so there is no column to hang a
--  CHECK on -- the balance must be summed from the ledger first.
--  Rule: a tutee may borrow down to -5.0 credits and no further.
--
--  Note this fires on BOOKING, not on CREDIT_TXN.  Putting it on the
--  ledger would read the very table being inserted into (ORA-04091),
--  and booking time is the right moment to refuse anyway -- before the
--  tutor's slot is taken.
--  Admin PENALTY rows are deliberately exempt: a penalty is allowed to
--  push a cheat below the floor.
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_credit_floor
BEFORE INSERT ON booking
FOR EACH ROW
DECLARE
  v_balance  NUMBER;
  v_floor    NUMBER;
BEGIN
  SELECT policy_value INTO v_floor
  FROM   credit_policy
  WHERE  policy_key = 'OVERDRAFT_FLOOR';

  SELECT NVL (SUM (amount), 0) INTO v_balance
  FROM   credit_txn
  WHERE  student_id = :NEW.tutee_id;

  IF v_balance - :NEW.duration_hours < v_floor THEN
    RAISE_APPLICATION_ERROR (-20002,
      'Overdraft limit reached. Balance is ' || v_balance ||
      ', this booking costs ' || :NEW.duration_hours ||
      ', floor is ' || v_floor || '. Teach a session to earn credits.');
  END IF;
END;
/


-- =====================================================================
--  TRIGGER 3 : Nobody may confirm a session that has not finished.
--  Fires on   : BOOKING        Reads: only :NEW   -> safe
--
--  Needs SYSDATE, so it cannot be a CHECK constraint.
--  sched_start_time is a decimal hour (16.5 = 16:30), so it is divided
--  by 24 to become a fraction of a day before being added to the date.
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_confirm_after_end
BEFORE UPDATE OF confirm_by_tutor, confirm_by_tutee ON booking
FOR EACH ROW
DECLARE
  v_session_end  DATE;
BEGIN
  IF (:NEW.confirm_by_tutor = 'Y' AND :OLD.confirm_by_tutor = 'N')
  OR (:NEW.confirm_by_tutee = 'Y' AND :OLD.confirm_by_tutee = 'N') THEN

    v_session_end := :NEW.sched_date
                   + (:NEW.sched_start_time + :NEW.duration_hours) / 24;

    IF SYSDATE < v_session_end THEN
      RAISE_APPLICATION_ERROR (-20003,
        'This session ends at ' ||
        TO_CHAR (v_session_end, 'DD-MON-YYYY HH24:MI') ||
        '. It cannot be confirmed before then.');
    END IF;

    -- A session can only be confirmed if the tutee actually turned up,
    -- which entering the session code proves.
    IF :NEW.check_in_at IS NULL THEN
      RAISE_APPLICATION_ERROR (-20004,
        'No check-in recorded. The tutor must enter the tutee''s session code before this session can be confirmed.');
    END IF;
  END IF;
END;
/


-- =====================================================================
--  TRIGGER 4 : The booking must fit inside the tutor's declared slot.
--  Fires on   : BOOKING        Reads: SLOT        -> safe
--
--  The composite foreign key already guarantees the slot BELONGS to this
--  tutor.  This trigger adds the part a foreign key cannot check: that
--  the requested hours fall inside the slot's window, and that the date
--  falls on the slot's weekday.
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_booking_fits_slot
BEFORE INSERT ON booking
FOR EACH ROW
DECLARE
  v_start   slot.start_time%TYPE;
  v_end     slot.end_time%TYPE;
  v_day     slot.day_of_week%TYPE;
  v_bk_day  VARCHAR2(3);
BEGIN
  SELECT start_time, end_time, day_of_week
  INTO   v_start, v_end, v_day
  FROM   slot
  WHERE  tutor_id = :NEW.tutor_id
  AND    slot_no  = :NEW.slot_no;

  IF :NEW.sched_start_time < v_start
  OR :NEW.sched_start_time + :NEW.duration_hours > v_end THEN
    RAISE_APPLICATION_ERROR (-20006,
      'Requested time falls outside slot ' || :NEW.slot_no ||
      ' (' || v_start || ' to ' || v_end || ').');
  END IF;

  -- NLS_DATE_LANGUAGE pins the weekday name so this behaves identically
  -- on every machine, whatever language the session is running in.
  v_bk_day := UPPER (TO_CHAR (:NEW.sched_date, 'DY',
                              'NLS_DATE_LANGUAGE=ENGLISH'));

  IF v_bk_day <> v_day THEN
    RAISE_APPLICATION_ERROR (-20007,
      'Slot ' || :NEW.slot_no || ' is a ' || v_day ||
      ' slot, but the chosen date is a ' || v_bk_day || '.');
  END IF;
END;
/


-- =====================================================================
--  TRIGGER 5 : Feedback only on a finished session.
--  Fires on   : FEEDBACK       Reads: BOOKING     -> safe
--
--  The primary key (booking_id, reviewer_role) already stops anyone
--  reviewing the same session twice.  This adds the timing rule.
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_feedback_valid
BEFORE INSERT ON feedback
FOR EACH ROW
DECLARE
  v_status  booking.status%TYPE;
BEGIN
  SELECT status INTO v_status
  FROM   booking
  WHERE  booking_id = :NEW.booking_id;

  IF v_status <> 'COMPLETED' THEN
    RAISE_APPLICATION_ERROR (-20008,
      'Feedback can only be left on a COMPLETED session. This booking is ' ||
      v_status || '.');
  END IF;
END;
/


-- =====================================================================
--  TRIGGER 6 : Badge promotion  -- COMPOUND TRIGGER
--  Fires on   : BOOKING        Reads: BOOKING     -> would mutate!
--
--  BadgeLevel is a STORED attribute (unlike TotalHoursTaught, which is
--  derived), so it has to be kept in step with the hours actually
--  taught.  Computing it needs SUM over BOOKING -- the very table being
--  updated -- so a plain FOR EACH ROW trigger would raise ORA-04091.
--
--  A compound trigger solves this by splitting the work across two
--  timing points:
--    AFTER EACH ROW  -- only remember WHICH tutors were affected
--    AFTER STATEMENT -- now the statement is finished and BOOKING is no
--                       longer mutating, so the SUM is legal
--
--  Thresholds:  BRONZE  <10h  |  SILVER  10-25h  |  GOLD  25h+
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_badge_promote
FOR UPDATE OF status ON booking
COMPOUND TRIGGER

  TYPE t_id_list IS TABLE OF booking.tutor_id%TYPE INDEX BY PLS_INTEGER;
  g_tutors  t_id_list;
  g_count   PLS_INTEGER := 0;

  ------------------------------------------------------------------
  AFTER EACH ROW IS
  BEGIN
    IF :NEW.status = 'COMPLETED' AND :OLD.status <> 'COMPLETED' THEN
      g_count            := g_count + 1;
      g_tutors (g_count) := :NEW.tutor_id;
    END IF;
  END AFTER EACH ROW;

  ------------------------------------------------------------------
  AFTER STATEMENT IS
    v_hours  NUMBER;
    v_badge  tutor.badge_level%TYPE;
  BEGIN
    FOR i IN 1 .. g_count LOOP
      SELECT NVL (SUM (duration_hours), 0) INTO v_hours
      FROM   booking
      WHERE  tutor_id = g_tutors (i)
      AND    status   = 'COMPLETED';

      v_badge := CASE
                   WHEN v_hours >= 25 THEN 'GOLD'
                   WHEN v_hours >= 10 THEN 'SILVER'
                   ELSE                    'BRONZE'
                 END;

      UPDATE tutor
      SET    badge_level  = v_badge
      WHERE  student_id   = g_tutors (i)
      AND    badge_level <> v_badge;       -- skip pointless writes
    END LOOP;

    g_count := 0;        -- reset state for the next statement
    g_tutors.DELETE;
  END AFTER STATEMENT;

END trg_badge_promote;
/

PROMPT ===> 6 triggers compiled (5 simple + 1 compound).
