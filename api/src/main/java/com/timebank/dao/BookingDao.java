package com.timebank.dao;

import com.timebank.db.Database;
import com.timebank.db.SqlLog;
import com.timebank.model.Booking;

import java.sql.*;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * Members 2 and 3: the booking engine and escrow.
 *
 * <p>The write operations all delegate to {@code PKG_TIMEBANK}. That is a
 * deliberate design choice, not laziness:
 *
 * <ul>
 *   <li><b>Atomicity.</b> Booking a session is five steps (lock the slot,
 *       check it is free, check the collusion cap, insert, move credits
 *       into escrow). Done from Java they would be five round trips, and
 *       a crash in the middle would leave credits stranded.</li>
 *   <li><b>Locking.</b> Preventing two tutees from grabbing the same hour
 *       needs {@code SELECT ... FOR UPDATE} held for the whole
 *       transaction. Issuing that from Java works, but every future
 *       caller would have to remember to do it.</li>
 *   <li><b>One gatekeeper.</b> If a mobile app or a report is added
 *       later, the rules stay in one place instead of being copied.</li>
 * </ul>
 */
public class BookingDao {

    /** Carries back the two OUT parameters of book_session. */
    public record BookingResult(int bookingId, String sessionCode) { }

    // -----------------------------------------------------------------
    //  INSERT — book a session
    // -----------------------------------------------------------------

    public BookingResult book(int tuteeId, int tutorId, int subjectId,
                              int slotNo, LocalDate when, double startTime,
                              double hours, String mode, String venue)
            throws SQLException {

        String plsql = """
                BEGIN
                  pkg_timebank.book_session(
                      p_tutee_id   => ?, p_tutor_id   => ?, p_subject_id => ?,
                      p_slot_no    => ?, p_sched_date => ?, p_start_time => ?,
                      p_duration   => ?, p_mode       => ?, p_venue      => ?,
                      p_booking_id => ?, p_session_code => ?);
                END;""";

        long t0 = SqlLog.q("BookingDao.book  ->  PKG_TIMEBANK.BOOK_SESSION"
                         + "   (locks the slot FOR UPDATE, checks the collusion"
                         + " cap, inserts, moves credits into escrow)",
                plsql, tuteeId, tutorId, subjectId, slotNo, when,
                startTime, hours, mode, venue);

        Connection c = null;
        try {
            c = Database.get();
            try (CallableStatement cs = c.prepareCall(plsql)) {
                cs.setInt(1, tuteeId);
                cs.setInt(2, tutorId);
                cs.setInt(3, subjectId);
                cs.setInt(4, slotNo);
                cs.setDate(5, Date.valueOf(when));
                cs.setDouble(6, startTime);
                cs.setDouble(7, hours);
                cs.setString(8, mode);
                cs.setString(9, venue);
                cs.registerOutParameter(10, Types.INTEGER);
                cs.registerOutParameter(11, Types.VARCHAR);
                cs.execute();

                BookingResult r = new BookingResult(cs.getInt(10), cs.getString(11));
                c.commit();
                SqlLog.called("booking " + r.bookingId()
                            + " created, session code " + r.sessionCode()
                            + ", credits now in escrow, COMMIT", t0);

                SqlLog.inside("PKG_TIMEBANK.BOOK_SESSION", """
                        -- 1. lock the slot so two tutees cannot take it
                        SELECT tutor_id INTO v_x FROM slot
                        WHERE  tutor_id = p_tutor_id AND slot_no = p_slot_no
                        FOR UPDATE;

                        -- 2. is that hour already taken?
                        SELECT COUNT(*) INTO v_clash FROM booking
                        WHERE  tutor_id = p_tutor_id
                        AND    sched_date = p_sched_date
                        AND    status IN ('REQUESTED','CONFIRMED')
                        AND    p_start_time < sched_start_time + duration_hours
                        AND    sched_start_time < p_start_time + p_duration;

                        -- 3. weekly cap for this pair (anti-collusion)
                        SELECT COUNT(*) INTO v_pair FROM booking ...

                        -- 4. the booking itself
                        INSERT INTO booking (...) VALUES (seq_booking.NEXTVAL, ...);

                        -- 5. move the credits into escrow: ONE negative row
                        --    against the TUTEE. The tutor is paid only when
                        --    both sides confirm.
                        post_txn (p_tutee_id, 'HOLD', -p_duration, ...);
                        """);

                Database.showAfter(
                    "INSERTED into BOOKING:",
                    "SELECT booking_id, status, sched_date, sched_start_time, "
                  + "duration_hours, credits_held, tutee_id, tutor_id "
                  + "FROM booking WHERE booking_id = ?",
                    r.bookingId());

                Database.showAfter(
                    "INSERTED into CREDIT_TXN -- the escrow HOLD. Negative, "
                  + "against the TUTEE. The tutor is paid only on completion:",
                    "SELECT txn_id, student_id, txn_type, amount, "
                  + "balance_snapshot, remarks FROM credit_txn "
                  + "WHERE booking_id = ? ORDER BY txn_id",
                    r.bookingId());

                return r;
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
            SqlLog.failed(Database.explain(e), t0);
            throw e;
        } finally {
            if (c != null) c.close();
        }
    }

    /**
     * The tutor types in the code the tutee was given.
     *
     * <p>This is what proves the tutee actually turned up. Without a
     * check-in the confirmation trigger refuses to let the session be
     * completed, so a tutor cannot claim credits for a no-show.
     */
    public void checkIn(int bookingId, String sessionCode) throws SQLException {
        callOneArg("BookingDao.checkIn  (the session code proves the tutee"
                 + " turned up -- without it the confirm trigger refuses)",
                "BEGIN pkg_timebank.check_in(?, ?); END;", bookingId, sessionCode);
    }

    // -----------------------------------------------------------------
    //  UPDATE — confirm or cancel
    // -----------------------------------------------------------------

    /**
     * One side confirms the session happened.
     *
     * <p>Credits move only when BOTH sides have confirmed. Because the
     * tutee was already debited by the HOLD at booking time, completion
     * writes a single positive TRANSFER to the tutor — not a second
     * debit. Getting that wrong would charge the tutee twice.
     */
    public void confirm(int bookingId, String role) throws SQLException {
        callOneArg("BookingDao.confirm  (credits move only when BOTH sides have"
                 + " confirmed; completion writes ONE positive TRANSFER, because"
                 + " the tutee was already debited by the HOLD at booking time)",
                "BEGIN pkg_timebank.confirm_session(?, ?); END;", bookingId, role);
    }

    /** Cancels. Who cancels, and how late, decides where the escrow goes. */
    public void cancel(int bookingId, String byRole) throws SQLException {
        callOneArg("BookingDao.cancel  (who cancels, and how late, decides"
                 + " where the escrow goes)",
                "BEGIN pkg_timebank.cancel_booking(?, ?); END;", bookingId, byRole);
    }

    // -----------------------------------------------------------------
    //  DELETE
    // -----------------------------------------------------------------

    /**
     * Purges abandoned requests.
     *
     * <p>Only REQUESTED rows can go: they never reached escrow, so no
     * ledger row points at them. A CONFIRMED or COMPLETED booking is
     * referenced by CREDIT_TXN and Oracle will refuse — deliberately,
     * because deleting it would orphan money.
     */
    public int purgeAbandoned() throws SQLException {
        String sql = """
                DELETE FROM booking b
                WHERE  b.status     = 'REQUESTED'
                AND    b.sched_date < TRUNC(SYSDATE)
                AND    NOT EXISTS (SELECT 1 FROM credit_txn t
                                   WHERE  t.booking_id = b.booking_id)""";

        Connection c = null;
        long t0 = SqlLog.q("BookingDao.purgeAbandoned  (only REQUESTED rows may"
                         + " really be deleted -- anything in escrow is"
                         + " referenced by CREDIT_TXN and Oracle refuses)", sql);

        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                int rows = ps.executeUpdate();
                c.commit();
                SqlLog.changed(rows, t0);
                return rows;
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
            SqlLog.failed(Database.explain(e), t0);
            throw e;
        } finally {
            if (c != null) c.close();
        }
    }

    // -----------------------------------------------------------------
    //  SEARCH / DISPLAY
    // -----------------------------------------------------------------

    /**
     * Every session for one person, in either role.
     *
     * <p>The same id is bound twice — once against tutor_id and once
     * against tutee_id — which is the overlapping specialization showing
     * up in the application layer. A student can legitimately appear on
     * both sides of the platform.
     */
    public List<Booking> forStudent(int studentId) throws SQLException {
        return query("BookingDao.forStudent  (the SAME id is bound twice, once"
                   + " per role -- that is the overlapping specialization"
                   + " surfacing in the application layer)",
                BASE_SELECT + """
                WHERE  b.tutor_id = ? OR b.tutee_id = ?
                ORDER  BY b.sched_date DESC""",
                ps -> {
                    ps.setInt(1, studentId);
                    ps.setInt(2, studentId);
                },
                studentId, studentId);
    }

    /** Filter by status, e.g. CONFIRMED or COMPLETED. */
    public List<Booking> byStatus(String status) throws SQLException {
        return query("BookingDao.byStatus  (six-table join)",
                BASE_SELECT + """
                WHERE  b.status = ?
                ORDER  BY b.sched_date DESC""",
                ps -> ps.setString(1, status),
                status);
    }

    /** Everything, newest first. */
    public List<Booking> listAll() throws SQLException {
        return query("BookingDao.listAll  (Member 3 Q2: the six-table join that"
                   + " rebuilds each session from its foreign keys)",
                BASE_SELECT + " ORDER BY b.booking_id", ps -> { });
    }

    // -----------------------------------------------------------------
    //  internals
    // -----------------------------------------------------------------

    /**
     * The six-table join that rebuilds a session from its foreign keys.
     * In the ER diagram this information lived in the relationship
     * diamonds; in the relational model those survive only as foreign
     * keys, so a join is the only way to get it back.
     */
    private static final String BASE_SELECT = """
            SELECT b.booking_id,
                   te.first_name || ' ' || te.last_name AS tutee_name,
                   tr.first_name || ' ' || tr.last_name AS tutor_name,
                   sub.subject_code,
                   b.sched_date, b.sched_start_time, b.duration_hours,
                   b.session_mode, b.venue, b.status, b.credits_held,
                   b.confirm_by_tutor || '/' || b.confirm_by_tutee AS confirms,
                   b.check_in_at
            FROM   booking b
                   JOIN student tr  ON tr.student_id  = b.tutor_id
                   JOIN student te  ON te.student_id  = b.tutee_id
                   JOIN subject sub ON sub.subject_id = b.subject_id
            """;

    /** Lets each query supply its own bind values without repeating the plumbing. */
    @FunctionalInterface
    private interface Binder {
        void bind(PreparedStatement ps) throws SQLException;
    }

    private List<Booking> query(String label, String sql, Binder binder,
                                Object... binds) throws SQLException {
        long t0 = SqlLog.q(label, sql, binds);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {

            binder.bind(ps);

            try (ResultSet rs = ps.executeQuery()) {
                List<Booking> out = new ArrayList<>();
                while (rs.next()) {
                    out.add(new Booking(
                            rs.getInt("booking_id"),
                            rs.getString("tutee_name"),
                            rs.getString("tutor_name"),
                            rs.getString("subject_code"),
                            rs.getDate("sched_date").toLocalDate(),
                            rs.getBigDecimal("sched_start_time"),
                            rs.getBigDecimal("duration_hours"),
                            rs.getString("session_mode"),
                            rs.getString("venue"),
                            rs.getString("status"),
                            rs.getBigDecimal("credits_held"),
                            rs.getString("confirms"),
                            rs.getTimestamp("check_in_at") != null));
                }
                SqlLog.rows(out.size(), t0);
                return out;
            }
        }
    }

    private void callOneArg(String label, String plsql, int id, String arg)
            throws SQLException {

        long t0 = SqlLog.q(label, plsql, id, arg);

        Connection c = null;
        try {
            c = Database.get();
            try (CallableStatement cs = c.prepareCall(plsql)) {
                cs.setInt(1, id);
                cs.setString(2, arg);
                cs.execute();
                c.commit();
                SqlLog.called("accepted, COMMIT", t0);

                Database.showAfter(
                    "BOOKING " + id + " now reads:",
                    "SELECT booking_id, status, confirm_by_tutor, "
                  + "confirm_by_tutee, check_in_at, credits_held "
                  + "FROM booking WHERE booking_id = ?",
                    id);

                Database.showAfter(
                    "CREDIT_TXN rows for this session:",
                    "SELECT txn_id, student_id, txn_type, amount, "
                  + "balance_snapshot FROM credit_txn "
                  + "WHERE booking_id = ? ORDER BY txn_id",
                    id);
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
            SqlLog.failed(Database.explain(e), t0);
            throw e;
        } finally {
            if (c != null) c.close();
        }
    }
}
