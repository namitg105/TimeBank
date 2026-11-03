package com.timebank.api.web;

import com.timebank.api.dto.Responses;
import com.timebank.dao.AuthDao;
import com.timebank.dao.StudentDao;
import com.timebank.dao.StudentLookup;
import com.timebank.model.Student;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;

/**
 * Member 1's module over HTTP: onboarding and profiles.
 *
 * <p>Every method here is a thin wrapper. The controller's whole job is
 * to check the input, call the DAO, and translate the result back. No
 * SQL lives at this layer — it stays in the DAO and in the database, so
 * the rules hold whether a request arrives from Flutter, from the
 * console app, or from SQL Developer.
 */
@RestController
@RequestMapping("/api/students")
public class StudentController {

    private final StudentDao dao  = new StudentDao();
    private final AuthDao    auth = new AuthDao();

    /** GET /api/students — everyone, with their derived balance and role. */
    @GetMapping
    public List<Student> list() throws SQLException {
        return dao.listAll();
    }

    /**
     * GET /api/students/views/low-balance — and the three below it.
     *
     * <p>Four questions an administrator asks about the directory, each
     * answered by a different kind of SELECT. They return rows of plain
     * text rather than Students, because none of them is a student
     * record: one is per department, one is a ranking.
     */
    @GetMapping("/views/low-balance")
    public List<Map<String, Object>> lowBalance() throws SQLException {
        return dao.belowAverage();
    }

    /** GET /api/students/views/never-booked */
    @GetMapping("/views/never-booked")
    public List<Map<String, Object>> neverBooked() throws SQLException {
        return dao.neverBooked();
    }

    /** GET /api/students/views/by-department */
    @GetMapping("/views/by-department")
    public List<Map<String, Object>> byDepartment() throws SQLException {
        return dao.departmentScoreboard();
    }

    /** GET /api/students/views/ranking */
    @GetMapping("/views/ranking")
    public List<Map<String, Object>> ranking() throws SQLException {
        return dao.balanceRanking();
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
        StudentLookup.requireExists(id);
        return Map.of("creditBalance", dao.balanceOf(id));
    }

    /**
     * POST /api/students — the administrator registers a student and
     * grants starter credits.
     *
     * <p>The same checks as sign-up (Input.newStudent), all made before
     * the first INSERT. The student row and the opening ledger row are
     * written inside one PL/SQL call, so a student can never exist
     * without their credits.
     */
    @PostMapping
    public ResponseEntity<?> register(@RequestBody Map<String, Object> body)
            throws SQLException {

        Input.NewStudent in = Input.newStudent(body);

        if (auth.regNoExists(in.regNo())) {
            throw new IllegalArgumentException(
                    in.regNo() + " is already registered.");
        }

        int id = dao.register(
                in.regNo(), in.firstName(), in.lastName(), in.email(),
                in.dob(), in.deptId(), in.block(), in.roomNo(), in.city());

        if (in.phone() != null) {
            dao.addPhone(id, in.phone());
        }

        List<Student> created = dao.search(in.regNo());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(created.isEmpty() ? Map.of("studentId", id) : created.get(0));
    }

    /**
     * DELETE /api/students/105 — deactivates the account.
     *
     * <p>Despite the HTTP verb this performs an UPDATE, and that is
     * deliberate. A student with bookings or ledger rows can never be
     * physically removed: those foreign keys carry no ON DELETE clause,
     * so Oracle blocks it to keep history intact. It is a soft delete.
     */
    @DeleteMapping("/{id}")
    public Responses.Ack deactivate(@PathVariable int id) throws SQLException {
        StudentLookup.requireExists(id);
        int rows = dao.deactivate(id);
        return new Responses.Ack(
                rows > 0,
                rows > 0
                    ? "Account deactivated. Their past sessions and credits stay on record."
                    : "That account was already deactivated.",
                rows);
    }

    /** POST /api/students/105/reactivate — the undo of a deactivation. */
    @PostMapping("/{id}/reactivate")
    public Responses.Ack reactivate(@PathVariable int id) throws SQLException {
        StudentLookup.requireExists(id);
        int rows = dao.reactivate(id);
        return new Responses.Ack(
                rows > 0,
                rows > 0
                    ? "Account reactivated. They can sign in again."
                    : "That account is already active.",
                rows);
    }

    /** GET /api/students/101/phones — the multivalued attribute. */
    @GetMapping("/{id}/phones")
    public List<String> phones(@PathVariable int id) throws SQLException {
        StudentLookup.requireExists(id);
        return dao.phonesOf(id);
    }

    /** DELETE /api/students/101/phones/9003344556 — a genuine row delete. */
    @DeleteMapping("/{id}/phones/{phone}")
    public Responses.Ack removePhone(@PathVariable int id, @PathVariable String phone)
            throws SQLException {
        StudentLookup.requireExists(id);
        int rows = dao.removePhone(id, phone);
        return new Responses.Ack(rows > 0,
                rows > 0 ? "Number removed." : "That number is not on your list.", rows);
    }

    /** POST /api/students/101/phones — PhoneNo is multivalued, so several are allowed. */
    @PostMapping("/{id}/phones")
    public Responses.Ack addPhone(@PathVariable int id,
                                  @RequestBody Map<String, Object> body)
            throws SQLException {
        StudentLookup.requireExists(id);
        dao.addPhone(id, Input.phone(body.get("phone")));
        return new Responses.Ack(true, "Number added.", 1);
    }
}
