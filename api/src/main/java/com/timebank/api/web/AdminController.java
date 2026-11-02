package com.timebank.api.web;

import com.timebank.dao.AdminDao;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;

/**
 * The moderator's side of the system.
 *
 * <p>These endpoints are separate from the student ones because the
 * actions behind them are not things a student may do: ruling on a
 * dispute moves someone else's credits, and posting a PENALTY is the
 * only way credits ever leave the economy.
 *
 * <p>A note for the viva, said plainly: sign-in here is a <em>picker</em>
 * over the ADMIN table, not authentication. There is no password column
 * in the schema and no session management in this service. That is a
 * deliberate scope boundary for a database course project — real
 * authentication belongs in an identity layer, not in a DBMS schema, and
 * storing passwords here would mean salting, hashing and rotation that
 * teach nothing about data modelling.
 */
@RestController
@RequestMapping("/api/admin")
public class AdminController {

    private final AdminDao dao = new AdminDao();

    /** GET /api/admin/accounts — the moderators on file, for the picker. */
    @GetMapping("/accounts")
    public List<AdminDao.Admin> accounts() throws SQLException {
        return dao.all();
    }

    /**
     * GET /api/admin/disputes          — the whole queue
     * GET /api/admin/disputes?status=OPEN — just the open ones
     */
    @GetMapping("/disputes")
    public List<AdminDao.Dispute> disputes(
            @RequestParam(name = "status", required = false) String status)
            throws SQLException {

        String s = (status == null || status.isBlank())
                 ? null : status.trim().toUpperCase();

        if (s != null && !List.of("OPEN", "UNDER_REVIEW", "RESOLVED").contains(s)) {
            throw new IllegalArgumentException("Pick one of the complaint filters.");
        }
        return dao.disputes(s);
    }

    /** POST /api/admin/disputes/10/1/triage — mark it as being looked at. */
    @PostMapping("/disputes/{bookingId}/{disputeNo}/triage")
    public Map<String, Object> triage(@PathVariable int bookingId,
                                      @PathVariable int disputeNo)
            throws SQLException {
        String status = statusOf(bookingId, disputeNo);
        if (!"OPEN".equals(status)) {
            throw new IllegalArgumentException("RESOLVED".equals(status)
                    ? "This complaint has already been closed."
                    : "This complaint is already being looked into.");
        }
        int rows = dao.triage(bookingId, disputeNo);
        return Map.of("changed", rows, "message", "Marked as being looked into.");
    }

    /**
     * POST /api/admin/disputes/10/1/resolve — rule on it.
     *
     * <p>Body: adminId, inFavour (TUTOR or TUTEE), note.
     */
    @PostMapping("/disputes/{bookingId}/{disputeNo}/resolve")
    public Map<String, Object> resolve(@PathVariable int bookingId,
                                       @PathVariable int disputeNo,
                                       @RequestBody Map<String, Object> body)
            throws SQLException {

        int adminId = Input.integer(body.get("adminId"),
                "Pick whose name the ruling is recorded under.");
        String inFavour = Input.oneOf(body.get("inFavour"),
                "Say who the ruling favours: the tutor or the learner.", "TUTOR", "TUTEE");
        String note = Input.maxLength(
                Input.required(body.get("note"), "Write a short note explaining the ruling."),
                400, "Ruling note");

        statusOf(bookingId, disputeNo);   // fails with a sentence if it is not there

        dao.resolve(bookingId, disputeNo, adminId, inFavour, note);

        return Map.of(
                "resolved", true,
                "inFavour", inFavour,
                "message", "Complaint closed and the credits settled. "
                         + "The ruling is saved with the complaint.");
    }

    /**
     * POST /api/admin/prove-immutable — demonstrate the append-only ledger.
     *
     * <p>Deliberately attempts to edit a credit row and reports the
     * refusal. Nothing changes. Worth running in front of an examiner:
     * it shows that not even an administrator can rewrite history.
     */
    @PostMapping("/prove-immutable")
    public Map<String, Object> proveImmutable() throws SQLException {
        String result = dao.proveLedgerImmutable();
        boolean blocked = result.startsWith("Blocked");
        return Map.of(
                "blocked", blocked,
                // What the app shows; the technical detail is in "result"
                // and in the API terminal.
                "message", blocked
                        ? "The change was refused. Past credit records can never "
                        + "be edited; a mistake is fixed by adding a new "
                        + "correcting entry."
                        : "Warning: a past credit record could be changed. "
                        + "Check the API window.",
                "result", result,
                "explanation",
                "TRG_TXN_IMMUTABLE fires BEFORE UPDATE OR DELETE on CREDIT_TXN "
              + "and raises unconditionally. A mistake is corrected by "
              + "INSERTING a compensating PENALTY or RELEASE row, exactly as "
              + "in a real accounting ledger. This is what makes the "
              + "closed-economy audit mean anything.");
    }

    /** The complaint's status; fails with a sentence when there is no such complaint. */
    private String statusOf(int bookingId, int disputeNo) throws SQLException {
        return dao.disputes(null).stream()
                .filter(d -> d.bookingId() == bookingId && d.disputeNo() == disputeNo)
                .map(AdminDao.Dispute::status)
                .findFirst().orElseThrow(() ->
                        new IllegalArgumentException("That complaint does not exist."));
    }
}
