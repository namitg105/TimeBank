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
 * Feedback, disputes and fraud.
 *
 * <p>MEMBER 5 — FEEDBACK, DISPUTE, ADMIN.
 *
 * <p>THE THREE IDEAS THIS MODULE OWNS
 *
 * <ul>
 *   <li><b>Two weak entities with different kinds of partial key.</b>
 *       FEEDBACK is keyed on (booking_id, reviewer_role): one session
 *       carries two reviews, one from each side, so the ROLE is what
 *       tells them apart. DISPUTE is keyed on (booking_id, dispute_no):
 *       a session can be disputed more than once, so a COUNTER is what
 *       tells those apart. Same shape, different partial key, for
 *       different reasons.</li>
 *
 *   <li><b>The self join.</b> Q2 joins FEEDBACK to itself twice, the
 *       two copies told apart by reviewer_role. That is only possible
 *       because the role is part of the key. Both joins are OUTER,
 *       because many sessions get only one review — the partial
 *       participation of BOOKING in <i>receives</i>.</li>
 *
 *   <li><b>Collusion detection.</b> Two students who repeatedly tutor
 *       each other net out to zero credits and collect a five-star
 *       review every time. In graph terms it is a 2-cycle.</li>
 * </ul>
 *
 * <p>THE CONSEQUENCE OF THE ROLE BEING IN THE KEY, which every query
 * here respects: a tutor's rating must average only the rows where
 * {@code reviewer_role = 'TUTEE'}. Averaging both directions would mix
 * in that tutor's own opinions of their students, which measures
 * nothing at all.
 */
public class FeedbackDao {

    // -----------------------------------------------------------------
    //  Q1 — everything written about a session
    // -----------------------------------------------------------------

    public List<Map<String, Object>> reviewsAndDisputes() throws SQLException {
        String sql = """
                SELECT 'REVIEW'  AS record_type,
                       f.booking_id,
                       f.reviewer_role          AS written_by,
                       TO_CHAR(f.rating)        AS detail,
                       TO_CHAR(f.feedback_date, 'DD-MON-YYYY') AS on_date,
                       f.comments               AS note
                FROM   feedback f
                UNION ALL
                SELECT 'DISPUTE',
                       d.booking_id,
                       d.raised_by_role,
                       d.status,
                       TO_CHAR(d.raised_on, 'DD-MON-YYYY'),
                       d.reason
                FROM   dispute d
                ORDER  BY record_type, booking_id""";

        long t0 = SqlLog.q("MEMBER 5  .  Reviews and disputes", sql);
        return read(sql, t0);
    }

    // -----------------------------------------------------------------
    //  Q2 — both sides of each session   (SELF JOIN)
    // -----------------------------------------------------------------

    /**
     * FEEDBACK joined to itself, the two copies told apart by role.
     *
     * <p>Both joins must be OUTER. Many sessions get a review from only
     * one side, and an inner join would drop them — along with every
     * session that got no review at all, which is exactly the set worth
     * chasing.
     */
    public List<Map<String, Object>> bothSides() throws SQLException {
        String sql = """
                SELECT b.booking_id,
                       sub.subject_code,
                       tr.first_name            AS tutor,
                       te.first_name            AS tutee,
                       ft.rating                AS tutee_rated_tutor,
                       fe.rating                AS tutor_rated_tutee,
                       NVL(d.status, '-')       AS dispute_status,
                       CASE
                         WHEN ft.rating IS NULL AND fe.rating IS NULL
                              THEN 'no reviews'
                         WHEN ft.rating IS NULL OR  fe.rating IS NULL
                              THEN 'one-sided'
                         WHEN ABS(ft.rating - fe.rating) >= 1.5
                              THEN 'DISAGREEMENT'
                         ELSE 'both agree'
                       END                      AS review_state
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

        long t0 = SqlLog.q("MEMBER 5  .  Both sides of each session", sql);
        return read(sql, t0);
    }

    // -----------------------------------------------------------------
    //  Q3 — tutors above the campus average   (NESTED)
    // -----------------------------------------------------------------

    public List<Map<String, Object>> aboveAverage() throws SQLException {
        String sql = """
                SELECT s.first_name || ' ' || s.last_name  AS tutor_name,
                       t.badge_level,
                       ROUND(AVG(f.rating), 2)             AS their_average,
                       COUNT(f.booking_id)                 AS reviews,
                       (SELECT ROUND(AVG(per_tutor), 2)
                        FROM  (SELECT AVG(f2.rating) AS per_tutor
                               FROM   feedback f2
                                      JOIN booking b2
                                        ON b2.booking_id = f2.booking_id
                               WHERE  f2.reviewer_role = 'TUTEE'
                               GROUP  BY b2.tutor_id))     AS campus_average
                FROM   feedback f
                       JOIN booking b ON b.booking_id = f.booking_id
                       JOIN tutor   t ON t.student_id = b.tutor_id
                       JOIN student s ON s.student_id = t.student_id
                WHERE  f.reviewer_role = 'TUTEE'
                GROUP  BY s.first_name, s.last_name, t.badge_level
                HAVING AVG(f.rating) > (SELECT AVG(per_tutor)
                                        FROM  (SELECT AVG(f3.rating) AS per_tutor
                                               FROM   feedback f3
                                                      JOIN booking b3
                                                        ON b3.booking_id = f3.booking_id
                                               WHERE  f3.reviewer_role = 'TUTEE'
                                               GROUP  BY b3.tutor_id))
                ORDER  BY their_average DESC""";

        long t0 = SqlLog.q("MEMBER 5  .  Tutors above the campus average", sql);
        return read(sql, t0);
    }

    // -----------------------------------------------------------------
    //  Q4 — the credit-loop collusion detector   (CORRELATED)
    // -----------------------------------------------------------------

    /**
     * Pairs who repeatedly tutor each other.
     *
     * <p>They net out to zero credits and collect a glowing review every
     * time. {@code b1.tutor_id < b1.tutee_id} reports each pair once;
     * without it A–B and B–A would come back as two separate findings.
     *
     * <p>No database can stop two people who agree to lie. What it can
     * do is make the pattern cheap to see and not worth the effort.
     */
    public List<Map<String, Object>> collusion() throws SQLException {
        String sql = """
                SELECT a.first_name || ' ' || a.last_name  AS student_a,
                       c.first_name || ' ' || c.last_name  AS student_b,
                       COUNT(*)                            AS a_taught_b,
                       (SELECT COUNT(*)
                        FROM   booking b2
                        WHERE  b2.tutor_id = b1.tutee_id
                        AND    b2.tutee_id = b1.tutor_id
                        AND    b2.status   = 'COMPLETED')  AS b_taught_a,
                       (SELECT ROUND(AVG(f.rating), 2)
                        FROM   feedback f
                               JOIN booking b3 ON b3.booking_id = f.booking_id
                        WHERE  ((b3.tutor_id = b1.tutor_id
                                 AND b3.tutee_id = b1.tutee_id)
                             OR (b3.tutor_id = b1.tutee_id
                                 AND b3.tutee_id = b1.tutor_id)))
                                                           AS avg_between_them,
                       'REVIEW MANUALLY'                   AS recommended_action
                FROM   booking b1
                       JOIN student a ON a.student_id = b1.tutor_id
                       JOIN student c ON c.student_id = b1.tutee_id
                WHERE  b1.status   = 'COMPLETED'
                AND    b1.tutor_id < b1.tutee_id
                AND    EXISTS (SELECT 1
                               FROM   booking b4
                               WHERE  b4.tutor_id = b1.tutee_id
                               AND    b4.tutee_id = b1.tutor_id
                               AND    b4.status   = 'COMPLETED')
                GROUP  BY b1.tutor_id, b1.tutee_id,
                          a.first_name, a.last_name,
                          c.first_name, c.last_name
                ORDER  BY a_taught_b DESC""";

        long t0 = SqlLog.q("MEMBER 5  .  Collusion detector", sql);
        return read(sql, t0);
    }

    // -----------------------------------------------------------------
    //  Q5 — rating distribution by subject   (AGGREGATE)
    // -----------------------------------------------------------------

    public List<Map<String, Object>> ratingBySubject() throws SQLException {
        String sql = """
                SELECT CASE WHEN GROUPING(sub.subject_code) = 1
                            THEN '** ALL SUBJECTS **'
                            ELSE sub.subject_code END      AS subject,
                       COUNT(*)                            AS reviews,
                       ROUND(AVG(f.rating), 2)             AS avg_rating,
                       ROUND(NVL(STDDEV(f.rating), 0), 2)  AS spread,
                       MIN(f.rating)                       AS worst,
                       MAX(f.rating)                       AS best,
                       SUM(CASE WHEN f.rating >= 4.5 THEN 1 ELSE 0 END)
                                                           AS excellent,
                       SUM(CASE WHEN f.rating >= 3 AND f.rating < 4.5
                                THEN 1 ELSE 0 END)         AS good,
                       SUM(CASE WHEN f.rating < 3 THEN 1 ELSE 0 END)
                                                           AS poor
                FROM   feedback f
                       JOIN booking b   ON b.booking_id  = f.booking_id
                       JOIN subject sub ON sub.subject_id = b.subject_id
                WHERE  f.reviewer_role = 'TUTEE'
                GROUP  BY ROLLUP(sub.subject_code)
                ORDER  BY GROUPING(sub.subject_code), avg_rating DESC""";

        long t0 = SqlLog.q("MEMBER 5  .  Rating spread by subject", sql);
        return read(sql, t0);
    }

    // -----------------------------------------------------------------
    //  Q6 — how each tutor is trending   (ANALYTIC)
    // -----------------------------------------------------------------

    public List<Map<String, Object>> ratingTrend() throws SQLException {
        String sql = """
                SELECT s.first_name                        AS tutor,
                       b.booking_id,
                       TO_CHAR(b.sched_date, 'DD-MON')     AS session_date,
                       f.rating,
                       LAG(f.rating) OVER (PARTITION BY b.tutor_id
                                           ORDER BY b.sched_date)
                                                           AS previous_rating,
                       ROUND(AVG(f.rating) OVER (PARTITION BY b.tutor_id
                                                 ORDER BY b.sched_date
                                                 ROWS BETWEEN 2 PRECEDING
                                                          AND CURRENT ROW), 2)
                                                           AS moving_avg_3,
                       CASE
                         WHEN LAG(f.rating) OVER (PARTITION BY b.tutor_id
                                                  ORDER BY b.sched_date) IS NULL
                              THEN 'first review'
                         WHEN f.rating > LAG(f.rating) OVER (
                                  PARTITION BY b.tutor_id
                                  ORDER BY b.sched_date) THEN 'improving'
                         WHEN f.rating < LAG(f.rating) OVER (
                                  PARTITION BY b.tutor_id
                                  ORDER BY b.sched_date) THEN 'slipping'
                         ELSE 'steady'
                       END                                 AS trend
                FROM   feedback f
                       JOIN booking b ON b.booking_id = f.booking_id
                       JOIN student s ON s.student_id = b.tutor_id
                WHERE  f.reviewer_role = 'TUTEE'
                ORDER  BY s.first_name, b.sched_date""";

        long t0 = SqlLog.q("MEMBER 5  .  Rating trend per tutor", sql);
        return read(sql, t0);
    }

    // -----------------------------------------------------------------
    //  INSERT — leave a review
    // -----------------------------------------------------------------

    /**
     * One review, from one side of one session.
     *
     * <p>No "has this person already reviewed?" check is needed. The
     * primary key (booking_id, reviewer_role) refuses a second review
     * from the same side, which is work a trigger would otherwise have
     * to do. TRG_FEEDBACK_VALID adds the part a key cannot express:
     * the session must have reached COMPLETED.
     */
    public int leaveReview(int bookingId, String role,
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
                    "FEEDBACK for booking " + bookingId + ":",
                    "SELECT booking_id, reviewer_role, rating, comments "
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

    // -----------------------------------------------------------------
    //  DELETE — retract a review
    // -----------------------------------------------------------------

    /**
     * Removes one review.
     *
     * <p>Both key columns are in the WHERE, because one of them alone
     * identifies nothing: booking 4 has two reviews and the role is
     * what tells them apart.
     */
    public int retractReview(int bookingId, String role) throws SQLException {
        String sql = """
                DELETE FROM feedback
                WHERE  booking_id    = ?
                AND    reviewer_role = ?""";

        long t0 = SqlLog.q("MEMBER 5  .  Retract a review",
                sql, bookingId, role);

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
                    "FEEDBACK for booking " + bookingId + ":",
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

    /** Sessions that are COMPLETED and still missing a review from one side. */
    public List<Map<String, Object>> reviewable() throws SQLException {
        String sql = """
                SELECT b.booking_id,
                       sub.subject_code,
                       tr.first_name || ' ' || tr.last_name AS tutor,
                       te.first_name || ' ' || te.last_name AS tutee,
                       TO_CHAR(b.sched_date, 'DD-MON-YYYY') AS session_date,
                       CASE WHEN EXISTS (SELECT 1 FROM feedback f
                                         WHERE  f.booking_id = b.booking_id
                                         AND    f.reviewer_role = 'TUTEE')
                            THEN 'done' ELSE 'missing' END  AS tutee_review,
                       CASE WHEN EXISTS (SELECT 1 FROM feedback f
                                         WHERE  f.booking_id = b.booking_id
                                         AND    f.reviewer_role = 'TUTOR')
                            THEN 'done' ELSE 'missing' END  AS tutor_review
                FROM   booking b
                       JOIN subject sub ON sub.subject_id = b.subject_id
                       JOIN student tr  ON tr.student_id  = b.tutor_id
                       JOIN student te  ON te.student_id  = b.tutee_id
                WHERE  b.status = 'COMPLETED'
                ORDER  BY b.booking_id""";

        long t0 = SqlLog.q("MEMBER 5  .  Sessions that can be reviewed", sql);
        return read(sql, t0);
    }

    // -----------------------------------------------------------------

    private List<Map<String, Object>> read(String sql, long t0)
            throws SQLException {
        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            ResultSetMetaData meta = rs.getMetaData();
            int cols = meta.getColumnCount();

            List<Map<String, Object>> out = new ArrayList<>();
            while (rs.next()) {
                Map<String, Object> row = new LinkedHashMap<>();
                for (int i = 1; i <= cols; i++) {
                    Object v = rs.getObject(i);
                    row.put(camel(meta.getColumnLabel(i)),
                            v instanceof BigDecimal b ? (Object) b.doubleValue()
                                                      : v == null ? null
                                                      : String.valueOf(v));
                }
                out.add(row);
            }
            SqlLog.rows(out.size(), t0);
            return out;
        }
    }

    private static String camel(String column) {
        String[] parts = column.toLowerCase().split("_");
        StringBuilder sb = new StringBuilder(parts[0]);
        for (int i = 1; i < parts.length; i++) {
            if (parts[i].isEmpty()) {
                continue;
            }
            sb.append(Character.toUpperCase(parts[i].charAt(0)))
              .append(parts[i].substring(1));
        }
        return sb.toString();
    }
}
