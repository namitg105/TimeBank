package com.timebank.api.web;

import com.timebank.api.dto.Requests;
import com.timebank.api.dto.Responses;
import com.timebank.dao.StudentDao;
import com.timebank.model.Student;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Member 1's module over HTTP: onboarding and profiles.
 *
 * <p>Every method here is a thin wrapper. The controller's whole job is
 * to translate JSON into arguments, call the DAO, and translate the
 * result back. No SQL and no business rules live at this layer — those
 * stay in the DAO and in the database, so the rules hold whether a
 * request arrives from Flutter, from the console app, or from SQL
 * Developer.
 */
@RestController
@RequestMapping("/api/students")
public class StudentController {

    private final StudentDao dao = new StudentDao();

    /** GET /api/students — everyone, with their derived balance and role. */
    @GetMapping
    public List<Student> list() throws SQLException {
        return dao.listAll();
    }

    /** GET /api/students/search?q=riya — by name or registration number. */
    @GetMapping("/search")
    public List<Student> search(@RequestParam(name = "q", defaultValue = "") String q)
            throws SQLException {
        return dao.search(q);
    }

    /** GET /api/students/102/balance — derived, always summed from the ledger. */
    @GetMapping("/{id}/balance")
    public Map<String, BigDecimal> balance(@PathVariable int id) throws SQLException {
        return Map.of("creditBalance", dao.balanceOf(id));
    }

    /**
     * POST /api/students — register, and grant starter credits.
     *
     * <p>Returns 201 CREATED with the new student. The two writes happen
     * inside one PL/SQL call, so a student can never exist without the
     * opening row in their ledger.
     */
    @PostMapping
    public ResponseEntity<?> register(@RequestBody Requests.RegisterStudent req)
            throws SQLException {

        if (req.regNo() == null || req.regNo().isBlank()) {
            throw new IllegalArgumentException("Registration number is required.");
        }
        if (req.email() == null || !req.email().contains("@")) {
            throw new IllegalArgumentException("A valid email address is required.");
        }

        int id = dao.register(
                req.regNo(), req.firstName(), req.lastName(), req.email(),
                LocalDate.parse(req.dob()), req.deptId(),
                blankToNull(req.block()), blankToNull(req.roomNo()),
                blankToNull(req.city()));

        if (req.phone() != null && !req.phone().isBlank()) {
            dao.addPhone(id, req.phone());
        }

        List<Student> created = dao.search(req.regNo());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(created.isEmpty() ? Map.of("studentId", id) : created.get(0));
    }

    /**
     * DELETE /api/students/105 — closes the account.
     *
     * <p>Despite the HTTP verb this performs an UPDATE, and that is
     * deliberate. A student with bookings or ledger rows can never be
     * physically removed: those foreign keys carry no ON DELETE clause,
     * so Oracle blocks it to keep history intact. Closing an account is
     * a soft delete, and the response says so.
     */
    @DeleteMapping("/{id}")
    public Responses.Ack deactivate(@PathVariable int id) throws SQLException {
        int rows = dao.deactivate(id);
        return new Responses.Ack(
                rows > 0,
                rows > 0
                    ? "Account closed. Their session history and ledger rows are kept."
                    : "No change — unknown id, or the account was already inactive.",
                rows);
    }

    /** DELETE /api/students/101/phones/9003344556 — a genuine row delete. */
    @DeleteMapping("/{id}/phones/{phone}")
    public Responses.Ack removePhone(@PathVariable int id, @PathVariable String phone)
            throws SQLException {
        int rows = dao.removePhone(id, phone);
        return new Responses.Ack(rows > 0,
                rows > 0 ? "Number removed." : "That number was not on record.", rows);
    }

    /** POST /api/students/101/phones — PhoneNo is multivalued, so several are allowed. */
    @PostMapping("/{id}/phones")
    public Responses.Ack addPhone(@PathVariable int id,
                                  @RequestBody Map<String, String> body)
            throws SQLException {
        String phone = body.get("phone");
        if (phone == null || phone.isBlank()) {
            throw new IllegalArgumentException("phone is required");
        }
        dao.addPhone(id, phone);
        return new Responses.Ack(true, "Number added.", 1);
    }

    private static String blankToNull(String s) {
        return (s == null || s.isBlank()) ? null : s;
    }
}
