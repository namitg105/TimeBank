package com.timebank.dao;

import com.timebank.db.Database;
import com.timebank.db.SqlLog;

import java.sql.*;

/**
 * Turns whatever a person typed into a student id.
 *
 * <p>WHY THIS EXISTS
 * {@code STUDENT_ID} is a surrogate key from a sequence. It identifies a
 * row perfectly and means nothing to anybody — no student knows theirs.
 * What they know is their registration number, which is the natural key:
 * UQ_STUDENT_REG guarantees one row per registration number, so it
 * identifies a person just as reliably.
 *
 * <p>A form should ask for the key people actually know. This class is
 * the translation, so every screen can accept either and nothing above
 * it has to care which was typed.
 */
public final class StudentLookup {

    private StudentLookup() { }

    /**
     * Resolves a registration number, or a bare id, to a student id.
     *
     * @param ref  "25BDE0068", or "1003", in any case
     * @return the student id
     * @throws IllegalArgumentException if nobody matches
     */
    public static int resolve(String ref) throws SQLException {
        if (ref == null || ref.isBlank()) {
            throw new IllegalArgumentException(
                    "Enter a registration number.");
        }

        String s = ref.trim();

        // All digits: already an id. Still check it exists, so a typo
        // fails here with a sentence rather than later with ORA-02291.
        if (s.matches("\\d+")) {
            int id = Integer.parseInt(s);
            if (exists(id)) {
                return id;
            }
            throw new IllegalArgumentException(
                    "There is no student " + s + ".");
        }

        String sql = """
                SELECT student_id,
                       first_name || ' ' || last_name AS full_name
                FROM   student
                WHERE  UPPER(reg_no) = UPPER(?)""";

        long t0 = SqlLog.q("Look up a student by registration number",
                sql, s);

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {

            ps.setString(1, s);

            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    SqlLog.rows(0, t0);
                    throw new IllegalArgumentException(
                            "No student is registered as " + s + ".");
                }
                int id = rs.getInt("student_id");
                SqlLog.called(s + " is " + rs.getString("full_name")
                            + ", student " + id, t0);
                return id;
            }
        }
    }

    private static boolean exists(int studentId) throws SQLException {
        String sql = "SELECT COUNT(*) FROM student WHERE student_id = ?";

        try (Connection c = Database.get();
             PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, studentId);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                return rs.getInt(1) > 0;
            }
        }
    }
}
