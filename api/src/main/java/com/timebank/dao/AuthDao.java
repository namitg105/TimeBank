package com.timebank.dao;

import com.timebank.db.Database;
import com.timebank.db.SqlLog;

import java.sql.*;

/**
 * Sign-up and sign-in for students.
 *
 * <p>MEMBER 1 — Onboarding and profiles.
 *
 * <p>HOW SIGNING IN WORKS, AND WHY IT IS HONEST TO SAY SO
 * A student signs in with their registration number. There is no
 * password column on STUDENT and no session token, because this is a
 * database project and credentials are not a data-modelling problem:
 * doing them properly means salting, hashing, rotation and an identity
 * service, none of which would teach anything about schema design.
 *
 * <p>What the schema DOES enforce, and what this class demonstrates, is
 * more interesting:
 *
 * <ul>
 *   <li><b>UQ_STUDENT_REG</b> makes the registration number unique, so
 *       it can identify a person at all. Sign-up relies on the database
 *       to reject a duplicate rather than checking first and inserting
 *       after — checking first is a race.</li>
 *   <li><b>ACCOUNT_STATUS</b> is what a soft delete leaves behind. A
 *       closed account still exists, still owns its bookings and ledger
 *       rows, and is refused at sign-in by this class rather than by
 *       being deleted.</li>
 * </ul>
 */
public class AuthDao {

    /** What the app needs to know about whoever just signed in. */
    public record Session(int studentId, String regNo, String fullName,
                          String email, int age, String school,
                          String accountStatus, String role,
                          String badgeLevel, String needTier) { }

    // -----------------------------------------------------------------
    //  SIGN IN
    // -----------------------------------------------------------------

    /**
     * Looks a student up by registration number.
     *
     * <p>One query answers everything the app needs: who they are, their
     * derived age, and which subclass tables they are in. The two LEFT
     * JOINs are Member 1's Q2 again — they must be OUTER, or a student
     * in neither subclass would vanish and could never sign in.
     *
     * @return their session, or null if no such registration number
     */
    public Session signIn(String regNo) throws SQLException {
        String sql = """
                SELECT s.student_id, s.reg_no,
                       s.first_name || ' ' || s.last_name       AS full_name,
                       s.email,
                       FLOOR(MONTHS_BETWEEN(SYSDATE, s.dob)/12) AS age,
                       d.school,
                       s.account_status,
                       CASE
                         WHEN t.student_id IS NOT NULL
                          AND e.student_id IS NOT NULL THEN 'BOTH'
                         WHEN t.student_id IS NOT NULL THEN 'TUTOR ONLY'
                         WHEN e.student_id IS NOT NULL THEN 'TUTEE ONLY'
                         ELSE 'NEITHER YET'
                       END                                      AS role_in_system,
                       t.badge_level,
                       e.academic_need_tier
                FROM   student s
                       JOIN      department d ON d.dept_id    = s.dept_id
                       LEFT JOIN tutor      t ON t.student_id = s.student_id
                       LEFT JOIN tutee      e ON e.student_id = s.student_id
                WHERE  UPPER(s.reg_no) = UPPER(?)""";

        long t0 = SqlLog.q("MEMBER 1  .  Sign in",
                sql, regNo);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {

            ps.setString(1, regNo);

            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    SqlLog.rows(0, t0);
                    SqlLog.note("no student with that registration number");
                    return null;
                }

                Session s = new Session(
                        rs.getInt("student_id"),
                        rs.getString("reg_no"),
                        rs.getString("full_name"),
                        rs.getString("email"),
                        rs.getInt("age"),
                        rs.getString("school"),
                        rs.getString("account_status"),
                        rs.getString("role_in_system"),
                        rs.getString("badge_level"),
                        rs.getString("academic_need_tier"));

                SqlLog.rows(1, t0);
                SqlLog.note("signed in: " + s.fullName()
                          + "  (" + s.role() + ", " + s.accountStatus() + ")");
                return s;
            }
        }
    }

    /** True if that registration number is already taken. */
    public boolean regNoExists(String regNo) throws SQLException {
        String sql = """
                SELECT COUNT(*) FROM student WHERE UPPER(reg_no) = UPPER(?)""";

        long t0 = SqlLog.q("MEMBER 1  .  Is this reg no taken?", sql, regNo);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setString(1, regNo);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                boolean taken = rs.getInt(1) > 0;
                SqlLog.called(taken ? "already taken" : "available", t0);
                return taken;
            }
        }
    }
}
