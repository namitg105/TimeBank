package com.timebank.dao;

import com.timebank.db.Database;
import com.timebank.model.LedgerEntry;

import java.math.BigDecimal;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

/**
 * Members 4 and 6: the ledger, the audit, and the fraud report.
 *
 * <p>There is no update or delete method in this class, and that is the
 * point. CREDIT_TXN is append-only and a trigger enforces it, so a
 * mistake is corrected by posting a compensating row rather than by
 * editing history. If the ledger could be edited, the audit below would
 * prove nothing.
 */
public class LedgerDao {

    /** Result of the closed-economy check. */
    public record Audit(BigDecimal balances, BigDecimal escrow,
                        BigDecimal grantsLessPenalties, BigDecimal drift) {
        public boolean balanced() {
            return drift.compareTo(BigDecimal.ZERO) == 0;
        }
    }

    // -----------------------------------------------------------------
    //  INSERT — an administrative adjustment
    // -----------------------------------------------------------------

    /**
     * Posts a manual credit or penalty.
     *
     * <p>{@code balance_snapshot} is computed inside the statement with a
     * scalar subquery rather than being read into Java first. Doing it in
     * two steps would leave a gap in which another session could post a
     * row, and the snapshot would then be wrong — a classic lost update.
     */
    public long postAdjustment(int studentId, String type,
                               BigDecimal amount, String remarks)
            throws SQLException {

        String sql = """
                INSERT INTO credit_txn (
                    txn_id, txn_type, amount, balance_snapshot,
                    remarks, student_id, booking_id)
                VALUES (
                    seq_txn.NEXTVAL, ?, ?,
                    (SELECT NVL(SUM(amount),0) + ? FROM credit_txn
                     WHERE student_id = ?),
                    ?, ?, NULL)""";

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps =
                         c.prepareStatement(sql, new String[]{"TXN_ID"})) {
                ps.setString(1, type);
                ps.setBigDecimal(2, amount);
                ps.setBigDecimal(3, amount);
                ps.setInt(4, studentId);
                ps.setString(5, remarks);
                ps.setInt(6, studentId);
                ps.executeUpdate();

                long id = 0;
                try (ResultSet keys = ps.getGeneratedKeys()) {
                    if (keys.next()) {
                        id = keys.getLong(1);
                    }
                }
                c.commit();
                return id;
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
            throw e;
        } finally {
            if (c != null) c.close();
        }
    }

    // -----------------------------------------------------------------
    //  DISPLAY
    // -----------------------------------------------------------------

    /**
     * One student's passbook, newest first.
     *
     * <p>The LEFT JOIN on booking matters: booking_id is NULL for GRANT
     * and PENALTY rows, so an inner join would quietly drop every
     * starter grant and the running balance would stop making sense.
     */
    public List<LedgerEntry> passbook(int studentId) throws SQLException {
        String sql = """
                SELECT t.txn_id,
                       s.first_name || ' ' || s.last_name AS student_name,
                       t.txn_type, t.amount, t.balance_snapshot,
                       t.txn_timestamp, t.booking_id, t.remarks
                FROM   credit_txn t
                       JOIN      student s ON s.student_id = t.student_id
                       LEFT JOIN booking b ON b.booking_id = t.booking_id
                WHERE  t.student_id = ?
                ORDER  BY t.txn_id DESC""";

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {

            ps.setInt(1, studentId);

            try (ResultSet rs = ps.executeQuery()) {
                List<LedgerEntry> out = new ArrayList<>();
                while (rs.next()) {
                    // getObject, not getInt: getInt turns SQL NULL into 0,
                    // which would silently claim booking #0 caused the row.
                    Integer bookingId = (Integer) rs.getObject("booking_id");

                    out.add(new LedgerEntry(
                            rs.getLong("txn_id"),
                            rs.getString("student_name"),
                            rs.getString("txn_type"),
                            rs.getBigDecimal("amount"),
                            rs.getBigDecimal("balance_snapshot"),
                            rs.getTimestamp("txn_timestamp").toLocalDateTime(),
                            bookingId,
                            rs.getString("remarks")));
                }
                return out;
            }
        }
    }

    /**
     * The closed-economy audit.
     *
     * <pre>
     *   sum of all balances  +  credits held in escrow
     *              =  total granted  -  total penalised
     * </pre>
     *
     * Any drift means credits were created or destroyed outside the
     * ledger, which should be impossible.
     */
    public Audit audit() throws SQLException {
        String sql = """
                SELECT (SELECT NVL(SUM(amount),0) FROM credit_txn) AS balances,
                       (SELECT NVL(SUM(credits_held),0) FROM booking
                        WHERE status IN ('REQUESTED','CONFIRMED','DISPUTED')) AS escrow,
                       (SELECT NVL(SUM(amount),0) FROM credit_txn
                        WHERE txn_type IN ('GRANT','PENALTY')) AS grants
                FROM   dual""";

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            rs.next();
            BigDecimal balances = rs.getBigDecimal("balances");
            BigDecimal escrow   = rs.getBigDecimal("escrow");
            BigDecimal grants   = rs.getBigDecimal("grants");
            BigDecimal drift    = balances.add(escrow).subtract(grants);

            return new Audit(balances, escrow, grants, drift);
        }
    }

    /**
     * Credit-loop collusion: pairs who repeatedly tutor each other.
     *
     * <p>They net out to zero credits but collect a glowing review every
     * time. No database can stop two people who agree to lie, so the aim
     * is to make the pattern visible and not worth the effort.
     */
    public List<String> collusionReport() throws SQLException {
        String sql = """
                SELECT a.first_name || ' ' || a.last_name AS student_a,
                       c.first_name || ' ' || c.last_name AS student_b,
                       COUNT(*) AS a_taught_b,
                       (SELECT COUNT(*) FROM booking b2
                        WHERE  b2.tutor_id = b1.tutee_id
                        AND    b2.tutee_id = b1.tutor_id
                        AND    b2.status   = 'COMPLETED') AS b_taught_a
                FROM   booking b1
                       JOIN student a ON a.student_id = b1.tutor_id
                       JOIN student c ON c.student_id = b1.tutee_id
                WHERE  b1.status   = 'COMPLETED'
                AND    b1.tutor_id < b1.tutee_id
                AND    EXISTS (SELECT 1 FROM booking b4
                               WHERE  b4.tutor_id = b1.tutee_id
                               AND    b4.tutee_id = b1.tutor_id
                               AND    b4.status   = 'COMPLETED')
                GROUP  BY b1.tutor_id, b1.tutee_id,
                          a.first_name, a.last_name, c.first_name, c.last_name
                ORDER  BY a_taught_b DESC""";

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            List<String> out = new ArrayList<>();
            while (rs.next()) {
                out.add(String.format("%s <-> %s : %d and %d sessions",
                        rs.getString("student_a"), rs.getString("student_b"),
                        rs.getInt("a_taught_b"), rs.getInt("b_taught_a")));
            }
            return out;
        }
    }

    /** Top tutors by hours taught, with the rating their tutees gave them. */
    public List<String> leaderboard() throws SQLException {
        String sql = """
                WITH tutor_stats AS (
                    SELECT b.tutor_id,
                           COUNT(*) AS sessions,
                           SUM(b.duration_hours) AS hours,
                           (SELECT ROUND(AVG(f.rating),2)
                            FROM   feedback f
                                   JOIN booking b2 ON b2.booking_id = f.booking_id
                            WHERE  b2.tutor_id     = b.tutor_id
                            AND    f.reviewer_role = 'TUTEE') AS avg_rating
                    FROM   booking b
                    WHERE  b.status = 'COMPLETED'
                    GROUP  BY b.tutor_id)
                SELECT DENSE_RANK() OVER (ORDER BY ts.hours DESC) AS rnk,
                       s.first_name || ' ' || s.last_name AS tutor_name,
                       t.badge_level, ts.sessions, ts.hours,
                       NVL(ts.avg_rating, 0) AS rating
                FROM   tutor_stats ts
                       JOIN tutor   t ON t.student_id = ts.tutor_id
                       JOIN student s ON s.student_id = ts.tutor_id
                ORDER  BY ts.hours DESC""";

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            List<String> out = new ArrayList<>();
            while (rs.next()) {
                out.add(String.format("%2d. %-22s %-7s %2d sessions  %4sh  rating %s",
                        rs.getInt("rnk"), rs.getString("tutor_name"),
                        rs.getString("badge_level"), rs.getInt("sessions"),
                        rs.getBigDecimal("hours"), rs.getBigDecimal("rating")));
            }
            return out;
        }
    }
}
