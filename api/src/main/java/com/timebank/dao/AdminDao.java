package com.timebank.dao;

import com.timebank.db.Database;
import com.timebank.db.SqlLog;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

/**
 * The admin side: who the moderators are, and the dispute queue.
 *
 * <p>ADMIN is a separate entity, not a flag on STUDENT, and that is a
 * modelling decision worth defending. A moderator is not a kind of
 * student — they have a designation rather than a department, no credit
 * balance, and no participation in any session. Folding them into
 * STUDENT would mean a column that is NULL for almost every row.
 *
 * <p>DISPUTE is a WEAK ENTITY of BOOKING: {@code dispute_no} is only a
 * partial key, numbered within one booking, so the primary key is the
 * pair (booking_id, dispute_no). A dispute cannot exist without the
 * session it is about.
 */
public class AdminDao {

    public record Admin(int adminId, String name, String designation) { }

    public record Dispute(int bookingId, int disputeNo, String raisedByRole,
                          String reason, String raisedOn, String status,
                          String tutorName, String tuteeName,
                          String subjectCode, String resolutionNote,
                          Integer resolvedBy) { }

    // -----------------------------------------------------------------
    //  Who can moderate
    // -----------------------------------------------------------------

    /** Every moderator, for the admin sign-in picker. */
    public List<Admin> all() throws SQLException {
        String sql = """
                SELECT admin_id, admin_name, designation
                FROM   admin
                ORDER  BY admin_id""";

        long t0 = SqlLog.q("AdminDao.all  (ADMIN is its own entity, not a flag"
                         + " on STUDENT -- a moderator has no department, no"
                         + " credit balance and no sessions)", sql);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            List<Admin> out = new ArrayList<>();
            while (rs.next()) {
                out.add(new Admin(rs.getInt("admin_id"),
                                  rs.getString("admin_name"),
                                  rs.getString("designation")));
            }
            SqlLog.rows(out.size(), t0);
            return out;
        }
    }

    // -----------------------------------------------------------------
    //  The dispute queue
    // -----------------------------------------------------------------

    /**
     * Disputes, newest first, with the people and subject joined back in.
     *
     * <p>Five tables. In the ER diagram all of this lived in the
     * relationship diamonds around BOOKING; in the relational model
     * those survive only as foreign keys, so a join is the only way to
     * get the context back.
     */
    public List<Dispute> disputes(String status) throws SQLException {
        String sql = """
                SELECT d.booking_id, d.dispute_no, d.raised_by_role,
                       d.reason,
                       TO_CHAR(d.raised_on, 'DD-MON-YYYY') AS raised_on,
                       d.status, d.resolution_note, d.resolved_by,
                       tr.first_name || ' ' || tr.last_name AS tutor_name,
                       te.first_name || ' ' || te.last_name AS tutee_name,
                       sub.subject_code
                FROM   dispute d
                       JOIN booking b   ON b.booking_id  = d.booking_id
                       JOIN student tr  ON tr.student_id = b.tutor_id
                       JOIN student te  ON te.student_id = b.tutee_id
                       JOIN subject sub ON sub.subject_id = b.subject_id
                WHERE  (? IS NULL OR d.status = ?)
                ORDER  BY CASE d.status WHEN 'OPEN'         THEN 1
                                        WHEN 'UNDER_REVIEW' THEN 2
                                        ELSE 3 END,
                          d.booking_id DESC""";

        long t0 = SqlLog.q("AdminDao.disputes  (five-table join; DISPUTE is a"
                         + " WEAK ENTITY of BOOKING, keyed on the pair"
                         + " (booking_id, dispute_no))", sql, status, status);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {

            ps.setString(1, status);
            ps.setString(2, status);

            try (ResultSet rs = ps.executeQuery()) {
                List<Dispute> out = new ArrayList<>();
                while (rs.next()) {
                    // Read as Number: Oracle returns NUMBER as BigDecimal,
                    // so casting straight to Integer throws.
                    Number by = (Number) rs.getObject("resolved_by");

                    out.add(new Dispute(
                            rs.getInt("booking_id"),
                            rs.getInt("dispute_no"),
                            rs.getString("raised_by_role"),
                            rs.getString("reason"),
                            rs.getString("raised_on"),
                            rs.getString("status"),
                            rs.getString("tutor_name"),
                            rs.getString("tutee_name"),
                            rs.getString("subject_code"),
                            rs.getString("resolution_note"),
                            by == null ? null : by.intValue()));
                }
                SqlLog.rows(out.size(), t0);
                return out;
            }
        }
    }

    /** Moves a dispute to UNDER_REVIEW so the queue shows it is being worked on. */
    public int triage(int bookingId, int disputeNo) throws SQLException {
        String sql = """
                UPDATE dispute
                SET    status = 'UNDER_REVIEW'
                WHERE  booking_id = ?
                AND    dispute_no = ?
                AND    status     = 'OPEN'""";

        long t0 = SqlLog.q("AdminDao.triage  (the status guard makes this"
                         + " idempotent -- running it twice changes 0 rows)",
                sql, bookingId, disputeNo);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setInt(1, bookingId);
                ps.setInt(2, disputeNo);
                int n = ps.executeUpdate();
                c.commit();
                SqlLog.changed(n, t0);

                Database.showAfter(
                    "DISPUTE now reads:",
                    "SELECT booking_id, dispute_no, status, resolved_by "
                  + "FROM dispute WHERE booking_id = ? AND dispute_no = ?",
                    bookingId, disputeNo);

                return n;
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
     * Rules on a dispute.
     *
     * <p>Delegates to PKG_TIMEBANK because ruling is not one write: the
     * escrow has to go back to one party, a PENALTY may be posted
     * against the other, and the dispute row has to close — all or
     * nothing. A PENALTY is the only way credits ever leave the economy,
     * which is why the audit still balances afterwards.
     */
    public void resolve(int bookingId, int disputeNo, int adminId,
                        String inFavour, String note) throws SQLException {

        String plsql = """
                BEGIN
                  pkg_timebank.resolve_dispute(
                      p_booking_id => ?, p_dispute_no => ?, p_admin_id => ?,
                      p_in_favour  => ?, p_note       => ?);
                END;""";

        long t0 = SqlLog.q("AdminDao.resolve  ->  PKG_TIMEBANK.RESOLVE_DISPUTE"
                         + "   (returns escrow, may post a PENALTY, closes the"
                         + " dispute -- one transaction)",
                plsql, bookingId, disputeNo, adminId, inFavour, note);

        Connection c = null;
        try {
            c = Database.get();
            try (CallableStatement cs = c.prepareCall(plsql)) {
                cs.setInt(1, bookingId);
                cs.setInt(2, disputeNo);
                cs.setInt(3, adminId);
                cs.setString(4, inFavour);
                cs.setString(5, note);
                cs.execute();
                c.commit();
                SqlLog.called("resolved in favour of " + inFavour + ", COMMIT", t0);

                Database.showAfter(
                    "DISPUTE is now closed, and names who closed it -- "
                  + "CHK_DP_RESOLVED would refuse the row otherwise:",
                    "SELECT booking_id, dispute_no, status, resolved_by, "
                  + "resolution_note FROM dispute "
                  + "WHERE booking_id = ? AND dispute_no = ?",
                    bookingId, disputeNo);

                Database.showAfter(
                    "CREDIT_TXN rows this ruling wrote (a PENALTY is the only "
                  + "way credits ever LEAVE the economy):",
                    "SELECT txn_id, student_id, txn_type, amount, remarks "
                  + "FROM credit_txn WHERE booking_id = ? ORDER BY txn_id",
                    bookingId);
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
     * Proves the ledger really is append-only.
     *
     * <p>Deliberately attempts an UPDATE that TRG_TXN_IMMUTABLE will
     * refuse, and reports the refusal. Nothing changes; the error IS the
     * result. Even an administrator cannot edit credit history — a
     * mistake is corrected by posting a compensating row.
     */
    public String proveLedgerImmutable() throws SQLException {
        String sql = """
                UPDATE credit_txn
                SET    amount = amount + 999
                WHERE  txn_id = (SELECT MIN(txn_id) FROM credit_txn)""";

        long t0 = SqlLog.q("AdminDao.proveLedgerImmutable  (THIS IS MEANT TO"
                         + " FAIL -- TRG_TXN_IMMUTABLE should refuse it)", sql);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.executeUpdate();
                Database.silentRollback(c);
                SqlLog.called("NO ERROR RAISED -- the trigger is missing!", t0);
                return "PROBLEM: the update was allowed. "
                     + "TRG_TXN_IMMUTABLE is not in place.";
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
            String msg = Database.explain(e);
            SqlLog.failed(msg, t0);
            return "Blocked as designed -> " + msg;
        } finally {
            if (c != null) c.close();
        }
    }
}
