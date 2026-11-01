package com.timebank.api.web;

import com.timebank.dao.AuthDao;
import com.timebank.dao.StudentDao;
import com.timebank.model.Student;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Signing up and signing in.
 *
 * <p>MEMBER 1 — Onboarding and profiles.
 *
 * <p>Three ways in, and they are deliberately different:
 *
 * <ul>
 *   <li>{@code /signup} creates a row. It is the same PL/SQL call the
 *       directory screen uses, because registering is registering
 *       whoever asks for it.</li>
 *   <li>{@code /login} reads a row. A registration number identifies a
 *       student; there is no password column on STUDENT.</li>
 *   <li>{@code /admin} checks one credential held in configuration, not
 *       in the schema.</li>
 * </ul>
 *
 * <p>WHY THERE ARE NO PASSWORDS IN THE DATABASE, SAID PLAINLY
 * Credentials are not a data-modelling problem. Storing them properly
 * means salting, hashing, rotation and an identity service — none of
 * which demonstrates anything about schema design, and all of which
 * would be wrong if done casually. What this project does demonstrate
 * is the part that IS the database's job: UQ_STUDENT_REG guaranteeing
 * one row per registration number, and ACCOUNT_STATUS being what a soft
 * delete leaves behind so a closed account can be refused rather than
 * erased.
 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthDao    auth     = new AuthDao();
    private final StudentDao students = new StudentDao();

    /** The single administrator, from application.properties. */
    @Value("${admin.username:namit}")
    private String adminUsername;

    @Value("${admin.password:timebank@2026}")
    private String adminPassword;

    @Value("${admin.displayName:Namit Gupta}")
    private String adminDisplayName;

    // -----------------------------------------------------------------
    //  STUDENT SIGN IN
    // -----------------------------------------------------------------

    /**
     * POST /api/auth/login  with  {"regNo": "25BCE1001"}
     *
     * <p>A closed account is refused here rather than deleted, which is
     * the whole point of the soft delete: their sessions and ledger rows
     * are still referenced by foreign keys and must not disappear.
     */
    @PostMapping("/login")
    public ResponseEntity<Map<String, Object>> login(
            @RequestBody Map<String, String> body) throws SQLException {

        String regNo = trim(body.get("regNo"));
        if (regNo == null) {
            throw new IllegalArgumentException(
                    "Enter your registration number.");
        }

        AuthDao.Session s = auth.signIn(regNo);

        if (s == null) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of(
                    "ok", false,
                    "message", "No student is registered as " + regNo
                             + ". Sign up instead?"));
        }

        if (!"ACTIVE".equals(s.accountStatus())) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of(
                    "ok", false,
                    "message", "That account is " + s.accountStatus()
                             + ". It still exists — closing an account is an "
                             + "UPDATE, not a DELETE — but it cannot sign in."));
        }

        return ResponseEntity.ok(session(s));
    }

    // -----------------------------------------------------------------
    //  STUDENT SIGN UP
    // -----------------------------------------------------------------

    /**
     * POST /api/auth/signup
     *
     * <p>Exactly the same PL/SQL call the directory screen makes. One
     * transaction writes the STUDENT row AND the opening ledger row,
     * because STUDENT has total participation in <i>posts</i> — a
     * student with no credits is an impossible state, and keeping both
     * writes inside the package makes it impossible to reach.
     */
    @PostMapping("/signup")
    public ResponseEntity<Map<String, Object>> signup(
            @RequestBody Map<String, Object> body) throws SQLException {

        String regNo     = trim(body.get("regNo"));
        String firstName = trim(body.get("firstName"));
        String lastName  = trim(body.get("lastName"));
        String email     = trim(body.get("email"));
        String dob       = trim(body.get("dob"));

        if (regNo == null || firstName == null || lastName == null) {
            throw new IllegalArgumentException(
                    "Registration number and both names are required.");
        }
        if (email == null || !email.contains("@")) {
            throw new IllegalArgumentException(
                    "A valid email address is required.");
        }
        if (dob == null) {
            throw new IllegalArgumentException("Date of birth is required.");
        }

        if (auth.regNoExists(regNo)) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                    "ok", false,
                    "message", regNo + " is already registered. Sign in "
                             + "instead — UQ_STUDENT_REG allows only one "
                             + "student per registration number."));
        }

        int deptId = intOr(body.get("deptId"), 1);

        int id = students.register(
                regNo, firstName, lastName, email,
                LocalDate.parse(dob), deptId,
                trim(body.get("block")),
                trim(body.get("roomNo")),
                trim(body.get("city")));

        String phone = trim(body.get("phone"));
        if (phone != null) {
            students.addPhone(id, phone);
        }

        AuthDao.Session s = auth.signIn(regNo);

        Map<String, Object> out = session(s);
        out.put("created", true);
        out.put("message", "Welcome. You start with 3.0 credits — that row "
                         + "was written in the same transaction as your "
                         + "student record.");

        return ResponseEntity.status(HttpStatus.CREATED).body(out);
    }

    // -----------------------------------------------------------------
    //  ADMIN SIGN IN
    // -----------------------------------------------------------------

    /**
     * POST /api/auth/admin  with  {"username": "...", "password": "..."}
     *
     * <p>One credential, read from configuration. There is one
     * administrator on this deployment, and the ADMIN table carries who
     * they are rather than how they prove it.
     */
    @PostMapping("/admin")
    public ResponseEntity<Map<String, Object>> adminLogin(
            @RequestBody Map<String, String> body) {

        String u = trim(body.get("username"));
        String p = trim(body.get("password"));

        if (!adminUsername.equalsIgnoreCase(u == null ? "" : u)
                || !adminPassword.equals(p == null ? "" : p)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of(
                    "ok", false,
                    "message", "Those administrator details are not right."));
        }

        return ResponseEntity.ok(Map.of(
                "ok", true,
                "kind", "ADMIN",
                "username", adminUsername,
                "displayName", adminDisplayName,
                "message", "Signed in as the administrator."));
    }

    /** GET /api/auth/departments — for the sign-up form's picker. */
    @GetMapping("/departments")
    public List<Map<String, Object>> departments() throws SQLException {
        return students.departments();
    }

    // -----------------------------------------------------------------

    private static Map<String, Object> session(AuthDao.Session s) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ok", true);
        out.put("kind", "STUDENT");
        out.put("studentId", s.studentId());
        out.put("regNo", s.regNo());
        out.put("fullName", s.fullName());
        out.put("email", s.email());
        out.put("age", s.age());
        out.put("school", s.school());
        out.put("accountStatus", s.accountStatus());
        out.put("role", s.role());
        out.put("badgeLevel", s.badgeLevel() == null ? "" : s.badgeLevel());
        out.put("needTier", s.needTier() == null ? "" : s.needTier());
        return out;
    }

    private static String trim(Object o) {
        if (o == null) {
            return null;
        }
        String s = String.valueOf(o).trim();
        return s.isEmpty() ? null : s;
    }

    private static int intOr(Object o, int fallback) {
        if (o instanceof Number n) {
            return n.intValue();
        }
        try {
            return Integer.parseInt(String.valueOf(o).trim());
        } catch (Exception e) {
            return fallback;
        }
    }
}
