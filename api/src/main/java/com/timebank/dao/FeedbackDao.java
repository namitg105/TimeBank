package com.timebank.dao;

import com.timebank.db.Database;
import com.timebank.db.SqlLog;

import java.math.BigDecimal;
import java.sql.*;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Member 5's module: reviews.
 *
 * <p>FEEDBACK is a WEAK ENTITY owned by BOOKING. Its key is the pair
 * {@code (booking_id, reviewer_role)}, and the role being part of that
 * key is what makes the rest of this class possible: one session can
 * hold exactly two reviews, one per side, and nobody can review the same
 * session twice — the primary key does the work a trigger would
 * otherwise have to do.
 *
 * <p>It also dies with its owner. FK_FB_BOOKING carries ON DELETE
 * CASCADE, which is what "existence dependent" means in practice.
 */
public class FeedbackDao {

    // -----------------------------------------------------------------
    //  INSERT
    // -----------------------------------------------------------------

    /**
     * Leaves a review on a finished session.
     *
     * <p>Almost nothing is checked here on purpose. TRG_FEEDBACK_VALID
     * refuses a review on a session that has not finished, CHK_FB_RATING
     * refuses anything outside 1 to 5, and the primary key refuses a
     * second review from the same side. Re-checking those in Java would
     * duplicate them and still not cover a different client.
     */
    public void leaveReview(int bookingId, String role,
                            BigDecimal rating, String comments)
            throws SQLException {
        String sql = """
                INSERT INTO feedback (
                    booking_id, reviewer_role, rating, comments, feedback_date)
                VALUES (?, ?, ?, ?, SYSDATE)""";

        long t0 = SqlLog.q("MEMBER 5  .  Leave a review",
                sql, bookingId, role, rating, comments);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setInt(1, bookingId);
                ps.setString(2, role);
                ps.setBigDecimal(3, rating);
                ps.setString(4, comments);
                int n = ps.executeUpdate();
                c.commit();
                SqlLog.changed(n, t0);

                Database.showAfter(
                    "FEEDBACK for session " + bookingId + ":",
                    "SELECT booking_id, reviewer_role, rating, "
                  + "TO_CHAR(feedback_date,'DD-MON-YYYY') AS left_on "
                  + "FROM feedback WHERE booking_id = ? ORDER BY reviewer_role",
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

    // -----------------------------------------------------------------
    //  DELETE
    // -----------------------------------------------------------------

    /**
     * Retracts a review.
     *
     * <p>Both key columns are in the WHERE because the primary key is
     * the composite {@code (booking_id, reviewer_role)} — the booking
     * alone would delete the other side's review too.
     *
     * <p>Safe as a real delete, unlike closing an account: nothing
     * references FEEDBACK, so removing a row orphans nothing. A rating
     * is an opinion, not a financial record.
     */
    public int retractReview(int bookingId, String role) throws SQLException {
        String sql = "DELETE FROM feedback WHERE booking_id = ? AND reviewer_role = ?";

        long t0 = SqlLog.q("MEMBER 5  .  Retract a review", sql, bookingId, role);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setInt(1, bookingId);
                ps.setString(2, role);
                int n = ps.executeUpdate();
                c.commit();
                SqlLog.changed(n, t0);

                Database.showAfter(
                    "FEEDBACK for session " + bookingId + ":",
                    "SELECT booking_id, reviewer_role, rating "
                  + "FROM feedback WHERE booking_id = ? ORDER BY reviewer_role",
                    bookingId);
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

    /** Which sides have already reviewed this session. */
    public List<String> reviewersOf(int bookingId) throws SQLException {
        String sql = """
                SELECT reviewer_role
                FROM   feedback
                WHERE  booking_id = ?
                ORDER  BY reviewer_role""";

        long t0 = SqlLog.q("MEMBER 5  .  Who has reviewed this session?",
                sql, bookingId);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, bookingId);
            try (ResultSet rs = ps.executeQuery()) {
                List<String> out = new ArrayList<>();
                while (rs.next()) {
                    out.add(rs.getString(1));
                }
                SqlLog.rows(out.size(), t0);
                return out;
            }
        }
    }

    // -----------------------------------------------------------------
    //  The four views on reviews
    // -----------------------------------------------------------------

    /**
     * SELF JOIN — both sides of every session.
     *
     * <p>Both halves of the review come from the SAME table, so FEEDBACK
     * is joined to itself and the two copies are told apart by
     * reviewer_role. That is only possible because the role is part of
     * the key.
     *
     * <p>Both feedback joins are OUTER, because many sessions get only
     * one review or none — the partial participation of BOOKING in
     * "receives". An inner join would quietly hide every one-sided
     * session, which is exactly the set worth chasing.
     */
    public List<Map<String, Object>> bothSides() throws SQLException {
        String sql = """
                SELECT b.booking_id,
                       sub.subject_code,
                       tr.first_name                   AS tutor,
                       te.first_name                   AS learner,
                       ft.rating                       AS learner_rated_tutor,
                       fe.rating                       AS tutor_rated_learner,
                       NVL (d.status, '-')             AS complaint,
                       CASE
                         WHEN ft.rating IS NULL AND fe.rating IS NULL THEN 'no reviews'
                         WHEN ft.rating IS NULL OR  fe.rating IS NULL THEN 'one-sided'
                         WHEN ABS (ft.rating - fe.rating) >= 1.5      THEN 'DISAGREEMENT'
                         ELSE                                              'both agree'
                       END                             AS review_state
                FROM   booking b
                       JOIN      subject  sub ON sub.subject_id   = b.subject_id
                       JOIN      student  tr  ON tr.student_id    = b.tutor_id
                       JOIN      student  te  ON te.student_id    = b.tutee_id
                       LEFT JOIN feedback ft  ON ft.booking_id    = b.booking_id
                                             AND ft.reviewer_role = 'TUTEE'
                       LEFT JOIN feedback fe  ON fe.booking_id    = b.booking_id
                                             AND fe.reviewer_role = 'TUTOR'
                       LEFT JOIN dispute  d   ON d.booking_id     = b.booking_id
                ORDER  BY b.booking_id""";

        return rowsOf("MEMBER 5  .  Both sides of every session", sql);
    }

    /**
     * NESTED subquery, three levels deep — tutors above the campus average.
     *
     * <p>Innermost: average each tutor's ratings. Middle: average those
     * averages. Outer: keep the tutors above it.
     *
     * <p>It is the average OF the per-tutor averages, not the average of
     * all ratings. Averaging every row would let a tutor with 20
     * sessions drown out one with 2, and the "campus average" would
     * really be the busiest tutor's average.
     */
    public List<Map<String, Object>> aboveAverage() throws SQLException {
        String sql = """
                SELECT s.first_name || ' ' || s.last_name            AS tutor_name,
                       t.badge_level,
                       ROUND (AVG (f.rating), 2)                     AS their_average,
                       COUNT (f.booking_id)                          AS reviews,
                       (SELECT ROUND (AVG (per_tutor), 2)
                        FROM  (SELECT AVG (f2.rating) AS per_tutor
                               FROM   feedback f2
                                      JOIN booking b2 ON b2.booking_id = f2.booking_id
                               WHERE  f2.reviewer_role = 'TUTEE'
                               GROUP  BY b2.tutor_id))               AS campus_average
                FROM   feedback f
                       JOIN booking b ON b.booking_id = f.booking_id
                       JOIN tutor   t ON t.student_id = b.tutor_id
                       JOIN student s ON s.student_id = t.student_id
                WHERE  f.reviewer_role = 'TUTEE'
                GROUP  BY s.first_name, s.last_name, t.badge_level
                HAVING AVG (f.rating) > (SELECT AVG (per_tutor)
                                         FROM  (SELECT AVG (f3.rating) AS per_tutor
                                                FROM   feedback f3
                                                       JOIN booking b3
                                                         ON b3.booking_id = f3.booking_id
                                                WHERE  f3.reviewer_role = 'TUTEE'
                                                GROUP  BY b3.tutor_id))
                ORDER  BY their_average DESC""";

        return rowsOf("MEMBER 5  .  Tutors rated above the campus average", sql);
    }

    /**
     * AGGREGATE with ROLLUP — the rating spread per subject.
     *
     * <p>STDDEV matters more than it looks: a 4.0 built from 4, 4, 4 is
     * a very different tutor from a 4.0 built from 5, 5, 2 — same mean,
     * completely different experience.
     *
     * <p>ROLLUP adds the all-subjects row in the same pass instead of a
     * second query joined with UNION ALL, and GROUPING() tells that
     * subtotal apart from a real NULL.
     */
    public List<Map<String, Object>> ratingSpread() throws SQLException {
        String sql = """
                SELECT CASE WHEN GROUPING (sub.subject_code) = 1
                            THEN '** ALL SUBJECTS **'
                            ELSE sub.subject_code END                         AS subject,
                       COUNT (*)                                              AS reviews,
                       ROUND (AVG (f.rating), 2)                              AS avg_rating,
                       ROUND (NVL (STDDEV (f.rating), 0), 2)                  AS spread,
                       MIN (f.rating)                                         AS worst,
                       MAX (f.rating)                                         AS best,
                       SUM (CASE WHEN f.rating >= 4.5 THEN 1 ELSE 0 END)      AS excellent,
                       SUM (CASE WHEN f.rating <  3.5 THEN 1 ELSE 0 END)      AS poor
                FROM   feedback f
                       JOIN booking b   ON b.booking_id  = f.booking_id
                       JOIN subject sub ON sub.subject_id = b.subject_id
                WHERE  f.reviewer_role = 'TUTEE'
                GROUP  BY ROLLUP (sub.subject_code)
                HAVING COUNT (*) >= 1
                ORDER  BY GROUPING (sub.subject_code), avg_rating DESC""";

        return rowsOf("MEMBER 5  .  Rating spread by subject", sql);
    }

    /**
     * ANALYTIC (WINDOW) — is each tutor improving or slipping?
     *
     * <p>LAG gives the rating they got on the session before, and the
     * moving average smooths the last three. A plain GROUP BY could
     * never show this: it collapses the history into one number, and the
     * trend — which is the entire question — is exactly what gets lost.
     * A tutor averaging 4.0 while improving is a very different
     * proposition from one averaging 4.0 while sliding.
     */
    public List<Map<String, Object>> ratingTrend() throws SQLException {
        String sql = """
                SELECT s.first_name                                     AS tutor,
                       b.booking_id,
                       TO_CHAR (b.sched_date, 'DD-MON')                 AS session_date,
                       f.rating,
                       LAG (f.rating) OVER (PARTITION BY b.tutor_id
                                            ORDER BY b.sched_date)      AS previous_rating,
                       ROUND (AVG (f.rating) OVER (
                                PARTITION BY b.tutor_id
                                ORDER BY b.sched_date
                                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)
                                                                        AS moving_avg_3,
                       CASE
                         WHEN LAG (f.rating) OVER (PARTITION BY b.tutor_id
                                                   ORDER BY b.sched_date) IS NULL
                              THEN 'first review'
                         WHEN f.rating > LAG (f.rating) OVER (PARTITION BY b.tutor_id
                                                              ORDER BY b.sched_date)
                              THEN 'improving'
                         WHEN f.rating < LAG (f.rating) OVER (PARTITION BY b.tutor_id
                                                              ORDER BY b.sched_date)
                              THEN 'slipping'
                         ELSE 'steady'
                       END                                              AS trend,
                       DENSE_RANK () OVER (ORDER BY f.rating DESC)      AS campus_rank
                FROM   feedback f
                       JOIN booking b ON b.booking_id = f.booking_id
                       JOIN student s ON s.student_id = b.tutor_id
                WHERE  f.reviewer_role = 'TUTEE'
                ORDER  BY tutor, b.sched_date""";

        return rowsOf("MEMBER 5  .  Is each tutor improving or slipping?", sql);
    }

    /**
     * Runs one of the views above and returns its rows as text.
     *
     * <p>They have different columns and none is a row of one table, so
     * they share this rather than four near-identical mappers. Nothing
     * is bound: each statement is fixed text chosen by the caller.
     */
    private List<Map<String, Object>> rowsOf(String label, String sql)
            throws SQLException {
        long t0 = SqlLog.q(label, sql);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            ResultSetMetaData meta = rs.getMetaData();
            List<Map<String, Object>> out = new ArrayList<>();

            while (rs.next()) {
                Map<String, Object> row = new LinkedHashMap<>();
                for (int i = 1; i <= meta.getColumnCount(); i++) {
                    String name = meta.getColumnLabel(i).toLowerCase().replace('_', ' ');
                    String v = rs.getString(i);
                    row.put(name, v == null ? "—" : v);
                }
                out.add(row);
            }

            SqlLog.rows(out.size(), t0);
            return out;
        }
    }
}
