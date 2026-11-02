package com.timebank.api.web;

import com.timebank.dao.AuthDao;
import com.timebank.dao.StudentDao;
import com.timebank.model.Student;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
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

        String regNo = Input.text(body.get("regNo"));
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
                    "message", "This account has been deactivated, so it cannot "
                             + "sign in. Ask the administrator to reactivate it."));
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

        // Everything is checked before the first INSERT, so a bad phone
        // can no longer leave a half-created account behind.
        Input.NewStudent in = Input.newStudent(body);

        if (auth.regNoExists(in.regNo())) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                    "ok", false,
                    "message", in.regNo() + " is already registered. "
                             + "Sign in instead."));
        }

        int id = students.register(
                in.regNo(), in.firstName(), in.lastName(), in.email(),
                in.dob(), in.deptId(), in.block(), in.roomNo(), in.city());

        if (in.phone() != null) {
            students.addPhone(id, in.phone());
        }

        AuthDao.Session s = auth.signIn(in.regNo());

        Map<String, Object> out = session(s);
        out.put("created", true);
        out.put("message", "Welcome. You start with 3.0 credits.");

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

        String u = Input.text(body.get("username"));
        String p = Input.text(body.get("password"));

        if (u == null || p == null) {
            throw new IllegalArgumentException("Enter the username and the password.");
        }

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
}
