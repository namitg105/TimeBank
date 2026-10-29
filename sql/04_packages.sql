-- =====================================================================
--  TimeBank
--  File    : 04_packages.sql
--  Purpose : PKG_TIMEBANK -- every write to the credit economy goes
--            through here.  Nothing else is allowed to post a ledger
--            row, which is what keeps the economy provably closed.
--  Module  : Module 4 (ACID, concurrency control, recovery) and
--            Module 2 (business rules from the requirement analysis).
--
--  WHY A PACKAGE AND NOT TRIGGERS?
--  1. Locking.  Preventing two tutees from grabbing the same hour needs
--     SELECT ... FOR UPDATE on the slot row.  A trigger cannot lock a
--     row before its own statement runs; a procedure can.
--  2. Mutating tables.  The double-booking and collusion checks read
--     BOOKING while BOOKING is being inserted into, which a row trigger
--     may not do (ORA-04091).  In a procedure the read happens before
--     the INSERT starts, so there is no restriction.
--  3. Atomicity.  One session touches BOOKING and CREDIT_TXN together.
--     Wrapping both in one procedure makes the pair all-or-nothing.
-- =====================================================================

SET SERVEROUTPUT ON

CREATE OR REPLACE PACKAGE pkg_timebank AS

  -- ---- derived value helpers -------------------------------------
  FUNCTION  fn_balance       (p_student_id IN NUMBER) RETURN NUMBER;
  FUNCTION  fn_hours_taught  (p_tutor_id   IN NUMBER) RETURN NUMBER;

  -- ---- onboarding -------------------------------------------------
  PROCEDURE enrol_student (
      p_reg_no      IN  VARCHAR2,
      p_first_name  IN  VARCHAR2,
      p_last_name   IN  VARCHAR2,
      p_email       IN  VARCHAR2,
      p_dob         IN  DATE,
      p_dept_id     IN  NUMBER,
      p_block       IN  VARCHAR2 DEFAULT NULL,
      p_room_no     IN  VARCHAR2 DEFAULT NULL,
      p_city        IN  VARCHAR2 DEFAULT NULL,
      p_student_id  OUT NUMBER);

  -- ---- the booking life cycle -------------------------------------
  PROCEDURE book_session (
      p_tutee_id      IN  NUMBER,
      p_tutor_id      IN  NUMBER,
      p_subject_id    IN  NUMBER,
      p_slot_no       IN  NUMBER,
      p_sched_date    IN  DATE,
      p_start_time    IN  NUMBER,
      p_duration      IN  NUMBER,
      p_mode          IN  VARCHAR2,
      p_venue         IN  VARCHAR2,
      p_booking_id    OUT NUMBER,
      p_session_code  OUT VARCHAR2);

  PROCEDURE check_in (
      p_booking_id    IN NUMBER,
      p_session_code  IN VARCHAR2);

  PROCEDURE confirm_session (
      p_booking_id  IN NUMBER,
      p_role        IN VARCHAR2);          -- 'TUTOR' or 'TUTEE'

  PROCEDURE cancel_booking (
      p_booking_id  IN NUMBER,
      p_by_role     IN VARCHAR2);

  -- ---- disputes ---------------------------------------------------
  PROCEDURE raise_dispute (
      p_booking_id  IN  NUMBER,
      p_by_role     IN  VARCHAR2,
      p_reason      IN  VARCHAR2,
      p_dispute_no  OUT NUMBER);

  PROCEDURE resolve_dispute (
      p_booking_id  IN NUMBER,
      p_dispute_no  IN NUMBER,
      p_admin_id    IN NUMBER,
      p_in_favour   IN VARCHAR2,           -- 'TUTOR' or 'TUTEE'
      p_note        IN VARCHAR2);

  -- ---- audit ------------------------------------------------------
  PROCEDURE audit_economy;

END pkg_timebank;
/


CREATE OR REPLACE PACKAGE BODY pkg_timebank AS

  -- =================================================================
  --  PRIVATE : post_txn
  --  The ONLY place a ledger row is ever written.
  --  Computes balance_snapshot as "balance before + this amount", which
  --  is what lets the audit query detect tampering later.
  -- =================================================================
  PROCEDURE post_txn (
      p_student_id  IN NUMBER,
      p_type        IN VARCHAR2,
      p_amount      IN NUMBER,
      p_booking_id  IN NUMBER,
      p_remarks     IN VARCHAR2)
  IS
    v_balance  NUMBER;
  BEGIN
    SELECT NVL (SUM (amount), 0) INTO v_balance
    FROM   credit_txn
    WHERE  student_id = p_student_id;

    INSERT INTO credit_txn (
        txn_id, txn_type, amount, balance_snapshot,
        remarks, student_id, booking_id)
    VALUES (
        seq_txn.NEXTVAL, p_type, p_amount, v_balance + p_amount,
        p_remarks, p_student_id, p_booking_id);
  END post_txn;


  -- =================================================================
  --  fn_balance : CreditBalance is a DERIVED attribute, so it is summed
  --  from the ledger on demand rather than stored in a column.
  -- =================================================================
  FUNCTION fn_balance (p_student_id IN NUMBER) RETURN NUMBER IS
    v_balance  NUMBER;
  BEGIN
    SELECT NVL (SUM (amount), 0) INTO v_balance
    FROM   credit_txn
    WHERE  student_id = p_student_id;
    RETURN v_balance;
  END fn_balance;


  FUNCTION fn_hours_taught (p_tutor_id IN NUMBER) RETURN NUMBER IS
    v_hours  NUMBER;
  BEGIN
    SELECT NVL (SUM (duration_hours), 0) INTO v_hours
    FROM   booking
    WHERE  tutor_id = p_tutor_id
    AND    status   = 'COMPLETED';
    RETURN v_hours;
  END fn_hours_taught;


  -- =================================================================
  --  enrol_student
  --  Creates the student AND the starter grant in one transaction.
  --  This is why "posts" has TOTAL participation on both sides in the
  --  ER diagram: a student can never exist without a ledger row.
  -- =================================================================
  PROCEDURE enrol_student (
      p_reg_no      IN  VARCHAR2,
      p_first_name  IN  VARCHAR2,
      p_last_name   IN  VARCHAR2,
      p_email       IN  VARCHAR2,
      p_dob         IN  DATE,
      p_dept_id     IN  NUMBER,
      p_block       IN  VARCHAR2 DEFAULT NULL,
      p_room_no     IN  VARCHAR2 DEFAULT NULL,
      p_city        IN  VARCHAR2 DEFAULT NULL,
      p_student_id  OUT NUMBER)
  IS
    v_grant  NUMBER;
  BEGIN
    SELECT policy_value INTO v_grant
    FROM   credit_policy
    WHERE  policy_key = 'STARTER_GRANT';

    p_student_id := seq_student.NEXTVAL;

    INSERT INTO student (
        student_id, reg_no, email, first_name, last_name,
        block, room_no, city, dob, dept_id)
    VALUES (
        p_student_id, p_reg_no, p_email, p_first_name, p_last_name,
        p_block, p_room_no, p_city, p_dob, p_dept_id);

    post_txn (p_student_id, 'GRANT', v_grant, NULL,
              'Starter grant on registration');
  END enrol_student;


  -- =================================================================
  --  book_session   -- the concurrency-critical procedure
  --
  --  Step 1 LOCKS the tutor's slot row.  If two tutees run this at the
  --  same moment for the same slot, the second session blocks at the
  --  FOR UPDATE until the first commits, then sees the booking the
  --  first one made and is refused.  Without the lock both would read
  --  "free", both would pass the check, and both would insert -- the
  --  classic lost-update / double-booking anomaly from Module 4.
  --
  --  Oracle uses multiversion read consistency, so an ordinary SELECT
  --  would NOT see the other session's uncommitted booking.  Explicit
  --  row locking is the only way to serialise this.
  -- =================================================================
  PROCEDURE book_session (
      p_tutee_id      IN  NUMBER,
      p_tutor_id      IN  NUMBER,
      p_subject_id    IN  NUMBER,
      p_slot_no       IN  NUMBER,
      p_sched_date    IN  DATE,
      p_start_time    IN  NUMBER,
      p_duration      IN  NUMBER,
      p_mode          IN  VARCHAR2,
      p_venue         IN  VARCHAR2,
      p_booking_id    OUT NUMBER,
      p_session_code  OUT VARCHAR2)
  IS
    v_dummy    NUMBER;
    v_clash    NUMBER;
    v_recent   NUMBER;
    v_cap      NUMBER;
  BEGIN
    IF p_tutor_id = p_tutee_id THEN
      RAISE_APPLICATION_ERROR (-20010,
        'A student cannot book a session with themselves.');
    END IF;

    ---------------------------------------------------------------
    -- 1. Lock this tutor's slot row for the rest of the transaction.
    ---------------------------------------------------------------
    BEGIN
      SELECT tutor_id INTO v_dummy
      FROM   slot
      WHERE  tutor_id = p_tutor_id
      AND    slot_no  = p_slot_no
      FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR (-20011,
          'Tutor ' || p_tutor_id || ' has no slot number ' || p_slot_no || '.');
    END;

    ---------------------------------------------------------------
    -- 2. Is the slot already taken on that date?
    --    (Safe here: we are not inside a BOOKING trigger.)
    ---------------------------------------------------------------
    SELECT COUNT (*) INTO v_clash
    FROM   booking
    WHERE  tutor_id   = p_tutor_id
    AND    slot_no    = p_slot_no
    AND    sched_date = p_sched_date
    AND    status IN ('REQUESTED','CONFIRMED');

    IF v_clash > 0 THEN
      RAISE_APPLICATION_ERROR (-20005,
        'That slot is already booked on ' ||
        TO_CHAR (p_sched_date, 'DD-MON-YYYY') || '.');
    END IF;

    ---------------------------------------------------------------
    -- 3. Collusion cap: the same two people, either direction,
    --    within a rolling week.
    ---------------------------------------------------------------
    SELECT policy_value INTO v_cap
    FROM   credit_policy WHERE policy_key = 'PAIR_WEEKLY_CAP';

    SELECT COUNT (*) INTO v_recent
    FROM   booking
    WHERE  sched_date >= p_sched_date - 7
    AND    status IN ('REQUESTED','CONFIRMED','COMPLETED')
    AND    (   (tutor_id = p_tutor_id AND tutee_id = p_tutee_id)
            OR (tutor_id = p_tutee_id AND tutee_id = p_tutor_id));

    IF v_recent >= v_cap THEN
      RAISE_APPLICATION_ERROR (-20009,
        'This pair has reached the weekly limit of ' || v_cap ||
        ' sessions. Book with a different peer.');
    END IF;

    ---------------------------------------------------------------
    -- 4. Create the booking.  Triggers now check the overdraft floor,
    --    the slot window and the weekday.  The composite foreign keys
    --    check that the slot and the subject both belong to this tutor.
    ---------------------------------------------------------------
    p_booking_id   := seq_booking.NEXTVAL;
    p_session_code := DBMS_RANDOM.STRING ('X', 8);

    INSERT INTO booking (
        booking_id, session_code, sched_date, sched_start_time,
        duration_hours, session_mode, venue, status, credits_held,
        tutee_id, tutor_id, subject_id, slot_no)
    VALUES (
        p_booking_id, p_session_code, p_sched_date, p_start_time,
        p_duration, p_mode, p_venue, 'CONFIRMED', p_duration,
        p_tutee_id, p_tutor_id, p_subject_id, p_slot_no);

    ---------------------------------------------------------------
    -- 5. Move the tutee's credits into escrow.
    --    ONE negative HOLD row -- the tutee is debited now, so there
    --    must be no second debit when the session completes.
    ---------------------------------------------------------------
    post_txn (p_tutee_id, 'HOLD', -p_duration, p_booking_id,
              'Credits held in escrow for booking ' || p_booking_id);
  END book_session;


  -- =================================================================
  --  check_in : the tutor types in the code the tutee was given.
  --  This is what proves the tutee actually turned up, and without it
  --  trg_confirm_after_end refuses to let the session be confirmed.
  -- =================================================================
  PROCEDURE check_in (
      p_booking_id    IN NUMBER,
      p_session_code  IN VARCHAR2)
  IS
    v_code    booking.session_code%TYPE;
    v_status  booking.status%TYPE;
  BEGIN
    SELECT session_code, status INTO v_code, v_status
    FROM   booking
    WHERE  booking_id = p_booking_id
    FOR UPDATE;

    IF v_status <> 'CONFIRMED' THEN
      RAISE_APPLICATION_ERROR (-20012,
        'Only a CONFIRMED booking can be checked in. This one is ' ||
        v_status || '.');
    END IF;

    IF UPPER (p_session_code) <> v_code THEN
      RAISE_APPLICATION_ERROR (-20013,
        'Session code does not match. Ask the tutee to read it again.');
    END IF;

    UPDATE booking
    SET    check_in_at = SYSTIMESTAMP
    WHERE  booking_id  = p_booking_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR (-20014,
        'No booking with id ' || p_booking_id || '.');
  END check_in;


  -- =================================================================
  --  confirm_session
  --  Dual confirmation.  Credits move only when BOTH flags are 'Y'.
  --  Because the tutee was already debited by the HOLD at booking time,
  --  completion writes only ONE row: a positive TRANSFER to the tutor.
  -- =================================================================
  PROCEDURE confirm_session (
      p_booking_id  IN NUMBER,
      p_role        IN VARCHAR2)
  IS
    v_bk  booking%ROWTYPE;
  BEGIN
    SELECT * INTO v_bk
    FROM   booking
    WHERE  booking_id = p_booking_id
    FOR UPDATE;

    IF v_bk.status NOT IN ('CONFIRMED','REQUESTED') THEN
      RAISE_APPLICATION_ERROR (-20015,
        'Booking ' || p_booking_id || ' is ' || v_bk.status ||
        ' and can no longer be confirmed.');
    END IF;

    IF UPPER (p_role) = 'TUTOR' THEN
      UPDATE booking SET confirm_by_tutor = 'Y'
      WHERE  booking_id = p_booking_id;
    ELSIF UPPER (p_role) = 'TUTEE' THEN
      UPDATE booking SET confirm_by_tutee = 'Y'
      WHERE  booking_id = p_booking_id;
    ELSE
      RAISE_APPLICATION_ERROR (-20016,
        'Role must be TUTOR or TUTEE, not ' || p_role || '.');
    END IF;

    -- Re-read: the other side may already have confirmed.
    SELECT * INTO v_bk FROM booking WHERE booking_id = p_booking_id;

    IF v_bk.confirm_by_tutor = 'Y' AND v_bk.confirm_by_tutee = 'Y' THEN

      -- Release escrow to the tutor.
      post_txn (v_bk.tutor_id, 'TRANSFER', v_bk.credits_held,
                p_booking_id,
                'Payment for session ' || p_booking_id);

      -- Closing the booking fires the compound badge trigger.
      UPDATE booking
      SET    status       = 'COMPLETED',
             credits_held = 0
      WHERE  booking_id   = p_booking_id;
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR (-20014,
        'No booking with id ' || p_booking_id || '.');
  END confirm_session;


  -- =================================================================
  --  cancel_booking
  --  Who cancels, and how late, decides where the escrow goes.
  --    tutor cancels, any time        -> tutee gets everything back
  --    tutee cancels early (>24h)     -> tutee gets everything back
  --    tutee cancels late  (<24h)     -> split; the tutor had blocked
  --                                      out that hour already
  -- =================================================================
  PROCEDURE cancel_booking (
      p_booking_id  IN NUMBER,
      p_by_role     IN VARCHAR2)
  IS
    v_bk          booking%ROWTYPE;
    v_window      NUMBER;
    v_share       NUMBER;
    v_hours_left  NUMBER;
    v_to_tutor    NUMBER;
    v_to_tutee    NUMBER;
  BEGIN
    SELECT * INTO v_bk
    FROM   booking
    WHERE  booking_id = p_booking_id
    FOR UPDATE;

    IF v_bk.status NOT IN ('REQUESTED','CONFIRMED') THEN
      RAISE_APPLICATION_ERROR (-20017,
        'Booking ' || p_booking_id || ' is ' || v_bk.status ||
        ' and cannot be cancelled.');
    END IF;

    SELECT policy_value INTO v_window
    FROM   credit_policy WHERE policy_key = 'LATE_CANCEL_HOURS';
    SELECT policy_value INTO v_share
    FROM   credit_policy WHERE policy_key = 'LATE_CANCEL_SHARE';

    v_hours_left := (v_bk.sched_date + v_bk.sched_start_time / 24
                     - SYSDATE) * 24;

    IF UPPER (p_by_role) = 'TUTOR' OR v_hours_left >= v_window THEN
      v_to_tutee := v_bk.credits_held;
      v_to_tutor := 0;
    ELSE
      v_to_tutor := ROUND (v_bk.credits_held * v_share, 1);
      v_to_tutee := v_bk.credits_held - v_to_tutor;
    END IF;

    IF v_to_tutee > 0 THEN
      post_txn (v_bk.tutee_id, 'RELEASE', v_to_tutee, p_booking_id,
                'Escrow returned on cancellation');
    END IF;

    IF v_to_tutor > 0 THEN
      post_txn (v_bk.tutor_id, 'TRANSFER', v_to_tutor, p_booking_id,
                'Late-cancellation compensation');
    END IF;

    UPDATE booking
    SET    status       = 'CANCELLED',
           credits_held = 0
    WHERE  booking_id   = p_booking_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR (-20014,
        'No booking with id ' || p_booking_id || '.');
  END cancel_booking;


  -- =================================================================
  --  raise_dispute
  --  Freezes the escrow: the booking goes to DISPUTED and nothing moves
  --  until an admin decides.
  --  dispute_no is the PARTIAL KEY of this weak entity, so it restarts
  --  at 1 for every booking.
  -- =================================================================
  PROCEDURE raise_dispute (
      p_booking_id  IN  NUMBER,
      p_by_role     IN  VARCHAR2,
      p_reason      IN  VARCHAR2,
      p_dispute_no  OUT NUMBER)
  IS
    v_status  booking.status%TYPE;
  BEGIN
    SELECT status INTO v_status
    FROM   booking
    WHERE  booking_id = p_booking_id
    FOR UPDATE;

    IF v_status = 'CANCELLED' THEN
      RAISE_APPLICATION_ERROR (-20018,
        'A cancelled booking has no escrow left to dispute.');
    END IF;

    SELECT NVL (MAX (dispute_no), 0) + 1 INTO p_dispute_no
    FROM   dispute
    WHERE  booking_id = p_booking_id;

    INSERT INTO dispute (
        booking_id, dispute_no, raised_by_role, reason, status)
    VALUES (
        p_booking_id, p_dispute_no, UPPER (p_by_role), p_reason, 'OPEN');

    UPDATE booking SET status = 'DISPUTED'
    WHERE  booking_id = p_booking_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR (-20014,
        'No booking with id ' || p_booking_id || '.');
  END raise_dispute;


  -- =================================================================
  --  resolve_dispute
  --  Decided for the TUTEE : escrow goes back, tutor takes a penalty.
  --  Decided for the TUTOR : escrow is paid out as a normal session.
  --  The PENALTY row is the only way credits leave the economy.
  -- =================================================================
  PROCEDURE resolve_dispute (
      p_booking_id  IN NUMBER,
      p_dispute_no  IN NUMBER,
      p_admin_id    IN NUMBER,
      p_in_favour   IN VARCHAR2,
      p_note        IN VARCHAR2)
  IS
    v_bk       booking%ROWTYPE;
    v_dstatus  dispute.status%TYPE;
    v_penalty  NUMBER;
  BEGIN
    SELECT status INTO v_dstatus
    FROM   dispute
    WHERE  booking_id = p_booking_id
    AND    dispute_no = p_dispute_no
    FOR UPDATE;

    IF v_dstatus = 'RESOLVED' THEN
      RAISE_APPLICATION_ERROR (-20019, 'That dispute is already resolved.');
    END IF;

    SELECT * INTO v_bk
    FROM   booking WHERE booking_id = p_booking_id FOR UPDATE;

    SELECT policy_value INTO v_penalty
    FROM   credit_policy WHERE policy_key = 'DISPUTE_PENALTY';

    IF UPPER (p_in_favour) = 'TUTEE' THEN
      IF v_bk.credits_held > 0 THEN
        post_txn (v_bk.tutee_id, 'RELEASE', v_bk.credits_held,
                  p_booking_id, 'Dispute resolved for the tutee');
      END IF;
      post_txn (v_bk.tutor_id, 'PENALTY', -v_penalty, NULL,
                'Penalty from dispute on booking ' || p_booking_id);

      UPDATE booking
      SET    status = 'CANCELLED', credits_held = 0
      WHERE  booking_id = p_booking_id;

    ELSIF UPPER (p_in_favour) = 'TUTOR' THEN
      IF v_bk.credits_held > 0 THEN
        post_txn (v_bk.tutor_id, 'TRANSFER', v_bk.credits_held,
                  p_booking_id, 'Dispute resolved for the tutor');
      END IF;

      UPDATE booking
      SET    status = 'COMPLETED', credits_held = 0
      WHERE  booking_id = p_booking_id;
    ELSE
      RAISE_APPLICATION_ERROR (-20020,
        'Decision must be TUTOR or TUTEE, not ' || p_in_favour || '.');
    END IF;

    UPDATE dispute
    SET    status          = 'RESOLVED',
           resolution_note = p_note,
           resolved_by     = p_admin_id
    WHERE  booking_id      = p_booking_id
    AND    dispute_no      = p_dispute_no;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR (-20021,
        'No such dispute on booking ' || p_booking_id || '.');
  END resolve_dispute;


  -- =================================================================
  --  audit_economy
  --  Proves the economy is closed.  At every moment:
  --
  --     sum of all balances + credits sitting in escrow
  --                = total granted - total penalised
  --
  --  If this ever fails, credits were created or destroyed somewhere
  --  outside the ledger.
  -- =================================================================
  PROCEDURE audit_economy IS
    v_balances  NUMBER;
    v_escrow    NUMBER;
    v_grants    NUMBER;
    v_lhs       NUMBER;
    v_drift     NUMBER;
  BEGIN
    SELECT NVL (SUM (amount), 0) INTO v_balances FROM credit_txn;

    SELECT NVL (SUM (credits_held), 0) INTO v_escrow
    FROM   booking
    WHERE  status IN ('REQUESTED','CONFIRMED','DISPUTED');

    SELECT NVL (SUM (amount), 0) INTO v_grants
    FROM   credit_txn
    WHERE  txn_type IN ('GRANT','PENALTY');

    v_lhs   := v_balances + v_escrow;
    v_drift := v_lhs - v_grants;

    DBMS_OUTPUT.PUT_LINE ('--------------------------------------------');
    DBMS_OUTPUT.PUT_LINE ('  CLOSED ECONOMY AUDIT');
    DBMS_OUTPUT.PUT_LINE ('--------------------------------------------');
    DBMS_OUTPUT.PUT_LINE ('  Sum of all balances  : ' || v_balances);
    DBMS_OUTPUT.PUT_LINE ('  Held in escrow       : ' || v_escrow);
    DBMS_OUTPUT.PUT_LINE ('  Grants minus penalty : ' || v_grants);
    DBMS_OUTPUT.PUT_LINE ('  Drift                : ' || v_drift);

    IF v_drift = 0 THEN
      DBMS_OUTPUT.PUT_LINE ('  RESULT: BALANCED - no credits created or lost.');
    ELSE
      DBMS_OUTPUT.PUT_LINE ('  RESULT: *** BROKEN *** investigate the ledger.');
    END IF;
    DBMS_OUTPUT.PUT_LINE ('--------------------------------------------');
  END audit_economy;

END pkg_timebank;
/

SHOW ERRORS

PROMPT ===> PKG_TIMEBANK compiled.
