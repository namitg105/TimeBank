package com.timebank.dao;

import com.timebank.db.Database;
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
                return r;
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
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
        callOneArg("BEGIN pkg_timebank.check_in(?, ?); END;", bookingId, sessionCode);
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
        callOneArg("BEGIN pkg_timebank.confirm_session(?, ?); END;", bookingId, role);
    }

    /** Cancels. Who cancels, and how late, decides where the escrow goes. */
    public void cancel(int bookingId, String byRole) throws SQLException {
        callOneArg("BEGIN pkg_timebank.cancel_booking(?, ?); END;", bookingId, byRole);
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
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                int rows = ps.executeUpdate();
                c.commit();
                return rows;
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
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
        return query(BASE_SELECT + """
                WHERE  b.tutor_id = ? OR b.tutee_id = ?
                ORDER  BY b.sched_date DESC""",
                ps -> {
                    ps.setInt(1, studentId);
                    ps.setInt(2, studentId);
                });
    }

    /** Filter by status, e.g. CONFIRMED or COMPLETED. */
    public List<Booking> byStatus(String status) throws SQLException {
        return query(BASE_SELECT + """
                WHERE  b.status = ?
                ORDER  BY b.sched_date DESC""",
                ps -> ps.setString(1, status));
    }

    /** Everything, newest first. */
    public List<Booking> listAll() throws SQLException {
        return query(BASE_SELECT + " ORDER BY b.booking_id", ps -> { });
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

    private List<Booking> query(String sql, Binder binder) throws SQLException {
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
                return out;
            }
        }
    }

    private void callOneArg(String plsql, int id, String arg) throws SQLException {
        Connection c = null;
        try {
            c = Database.get();
            try (CallableStatement cs = c.prepareCall(plsql)) {
                cs.setInt(1, id);
                cs.setString(2, arg);
                cs.execute();
                c.commit();
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
            throw e;
        } finally {
            if (c != null) c.close();
        }
    }
}
