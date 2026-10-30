package com.timebank.dao;

import com.timebank.db.Database;
import com.timebank.db.SqlLog;
import com.timebank.model.Student;

import java.math.BigDecimal;
import java.sql.*;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * Member 1's module: onboarding and profiles.
 *
 * <p>EVERY statement here uses {@code ?} placeholders and a
 * {@link PreparedStatement}. Two reasons, both worth knowing:
 *
 * <ol>
 *   <li><b>SQL injection.</b> A bind variable is never parsed as SQL. If
 *       someone types {@code '; DROP TABLE student; --} as a name, it is
 *       stored as that literal text. String concatenation would have
 *       executed it.</li>
 *   <li><b>Speed.</b> Oracle parses {@code WHERE id = ?} once and reuses
 *       the plan for every value. Concatenating the value produces a
 *       brand-new statement each time, so the shared pool fills with
 *       thousands of one-shot plans.</li>
 * </ol>
 */
public class StudentDao {

    // -----------------------------------------------------------------
    //  INSERT — register a student
    // -----------------------------------------------------------------

    /**
     * Registers a student and grants their starter credits.
     *
     * <p>This calls the stored procedure rather than running an INSERT,
     * because registering is really two writes that must not come apart:
     * the STUDENT row and its opening GRANT in the ledger. Keeping them
     * inside PL/SQL means a single round trip to the database and no way
     * for the application to do only half of it.
     *
     * @return the generated student id
     */
    public int register(String regNo, String firstName, String lastName,
                        String email, LocalDate dob, int deptId,
                        String block, String roomNo, String city)
            throws SQLException {

        String plsql = """
                BEGIN
                  pkg_timebank.enrol_student(
                      p_reg_no => ?, p_first_name => ?, p_last_name => ?,
                      p_email  => ?, p_dob        => ?, p_dept_id    => ?,
                      p_block  => ?, p_room_no    => ?, p_city       => ?,
                      p_student_id => ?);
                END;""";

        long t0 = SqlLog.q("StudentDao.register  ->  PKG_TIMEBANK.ENROL_STUDENT"
                         + "   (writes STUDENT + the opening GRANT in one transaction)",
                plsql, regNo, firstName, lastName, email, dob, deptId,
                block, roomNo, city);

        Connection c = null;
        try {
            c = Database.get();
            try (CallableStatement cs = c.prepareCall(plsql)) {
                cs.setString(1, regNo);
                cs.setString(2, firstName);
                cs.setString(3, lastName);
                cs.setString(4, email);
                cs.setDate(5, Date.valueOf(dob));
                cs.setInt(6, deptId);
                cs.setString(7, block);
                cs.setString(8, roomNo);
                cs.setString(9, city);
                cs.registerOutParameter(10, Types.INTEGER);   // OUT param
                cs.execute();

                int newId = cs.getInt(10);
                c.commit();
                SqlLog.called("student " + newId
                            + " created, starter credits posted, COMMIT", t0);
                return newId;
            }
        } catch (SQLException e) {
            Database.silentRollback(c);
            SqlLog.failed(Database.explain(e), t0);
            throw e;
        } finally {
            if (c != null) c.close();          // returns it to the pool
        }
    }

    /** Adds one phone number. PhoneNo is a multivalued attribute, so a student may have several. */
    public void addPhone(int studentId, String phone) throws SQLException {
        String sql = "INSERT INTO student_phone (student_id, phone_no) VALUES (?, ?)";

        long t0 = SqlLog.q("StudentDao.addPhone  (PhoneNo is multivalued,"
                         + " so it has its own table)", sql, studentId, phone);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setInt(1, studentId);
                ps.setString(2, phone);
                int n = ps.executeUpdate();
                c.commit();
                SqlLog.changed(n, t0);
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
    //  UPDATE
    // -----------------------------------------------------------------

    /**
     * Closes an account.
     *
     * <p>Note this is an UPDATE, not a DELETE. A student with bookings or
     * ledger rows can never be physically removed: those foreign keys
     * carry no ON DELETE clause, so Oracle blocks it on purpose to keep
     * session history and the ledger intact. "Deleting a user" in this
     * system means flipping a status — a soft delete.
     *
     * @return the number of rows changed, so the caller can tell whether
     *         the id actually existed
     */
    public int deactivate(int studentId) throws SQLException {
        String sql = """
                UPDATE student
                SET    account_status = 'INACTIVE'
                WHERE  student_id     = ?
                AND    account_status <> 'INACTIVE'""";

        long t0 = SqlLog.q("StudentDao.deactivate  (SOFT DELETE -- the foreign"
                         + " keys from BOOKING and CREDIT_TXN forbid a real one)",
                sql, studentId);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setInt(1, studentId);
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
    //  DELETE
    // -----------------------------------------------------------------

    /**
     * Removes one phone number — a genuine row delete, because
     * STUDENT_PHONE came from a multivalued attribute and nothing
     * references it.
     */
    public int removePhone(int studentId, String phone) throws SQLException {
        String sql = "DELETE FROM student_phone WHERE student_id = ? AND phone_no = ?";

        long t0 = SqlLog.q("StudentDao.removePhone  (a REAL delete -- nothing"
                         + " downstream references STUDENT_PHONE)",
                sql, studentId, phone);

        Connection c = null;
        try {
            c = Database.get();
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setInt(1, studentId);
                ps.setString(2, phone);
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
    //  SEARCH
    // -----------------------------------------------------------------

    /**
     * Searches by name or registration number.
     *
     * <p>The wildcards go in the <em>value</em>, never in the SQL text:
     * {@code LIKE ?} with {@code "%" + term + "%"} bound to it. Building
     * {@code LIKE '%" + term + "%'} by concatenation is the classic
     * injection hole.
     *
     * <p>UPPER() on both sides makes the search case-insensitive. On a
     * large table this would defeat an ordinary index, and the fix is a
     * function-based index on UPPER(last_name).
     */
    public List<Student> search(String term) throws SQLException {
        String sql = """
                SELECT s.student_id, s.reg_no,
                       s.first_name || ' ' || s.last_name  AS full_name,
                       s.email, s.dob,
                       FLOOR(MONTHS_BETWEEN(SYSDATE, s.dob)/12) AS age,
                       s.city, s.account_status, d.school,
                       v.credit_balance,
                       CASE
                         WHEN t.student_id IS NOT NULL
                          AND e.student_id IS NOT NULL THEN 'BOTH'
                         WHEN t.student_id IS NOT NULL THEN 'TUTOR ONLY'
                         WHEN e.student_id IS NOT NULL THEN 'TUTEE ONLY'
                         ELSE 'NEITHER YET'
                       END AS role_in_system
                FROM   student s
                       JOIN      department        d ON d.dept_id    = s.dept_id
                       JOIN      v_student_balance v ON v.student_id = s.student_id
                       LEFT JOIN tutor             t ON t.student_id = s.student_id
                       LEFT JOIN tutee             e ON e.student_id = s.student_id
                WHERE  UPPER(s.first_name || ' ' || s.last_name) LIKE UPPER(?)
                   OR  UPPER(s.reg_no)                           LIKE UPPER(?)
                ORDER  BY s.student_id""";

        String pattern = "%" + term + "%";

        long t0 = SqlLog.q("StudentDao.search  (Member 1 Q1 + Q2: derived age,"
                         + " and TUTOR/TUTEE/BOTH/NEITHER from two LEFT JOINs)",
                sql, pattern, pattern);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {

            ps.setString(1, pattern);
            ps.setString(2, pattern);

            try (ResultSet rs = ps.executeQuery()) {
                List<Student> out = mapAll(rs);
                SqlLog.rows(out.size(), t0);
                return out;
            }
        }
    }

    // -----------------------------------------------------------------
    //  DISPLAY
    // -----------------------------------------------------------------

    /** Every active student, with their derived balance and role. */
    public List<Student> listAll() throws SQLException {
        return search("");          // an empty pattern matches everyone
    }

    /** Current balance — derived, so it is always summed from the ledger. */
    public BigDecimal balanceOf(int studentId) throws SQLException {
        String sql = "SELECT pkg_timebank.fn_balance(?) FROM dual";

        long t0 = SqlLog.q("StudentDao.balanceOf  (CreditBalance is DERIVED --"
                         + " nothing stores it, it is summed from the ledger)",
                sql, studentId);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, studentId);
            try (ResultSet rs = ps.executeQuery()) {
                BigDecimal bal = rs.next() ? rs.getBigDecimal(1) : BigDecimal.ZERO;
                SqlLog.called("balance = " + bal, t0);
                return bal;
            }
        }
    }

    // -----------------------------------------------------------------

    private List<Student> mapAll(ResultSet rs) throws SQLException {
        List<Student> out = new ArrayList<>();
        while (rs.next()) {
            out.add(new Student(
                    rs.getInt("student_id"),
                    rs.getString("reg_no"),
                    rs.getString("full_name"),
                    rs.getString("email"),
                    rs.getDate("dob").toLocalDate(),
                    rs.getInt("age"),
                    rs.getString("city"),
                    rs.getString("account_status"),
                    rs.getString("school"),
                    rs.getBigDecimal("credit_balance"),
                    rs.getString("role_in_system")));
        }
        return out;
    }
}
