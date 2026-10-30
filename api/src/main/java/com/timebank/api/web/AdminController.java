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
            throw new IllegalArgumentException(
                    "status must be OPEN, UNDER_REVIEW or RESOLVED.");
        }
        return dao.disputes(s);
    }

    /** POST /api/admin/disputes/10/1/triage — mark it as being looked at. */
    @PostMapping("/disputes/{bookingId}/{disputeNo}/triage")
    public Map<String, Object> triage(@PathVariable int bookingId,
                                      @PathVariable int disputeNo)
            throws SQLException {
        int rows = dao.triage(bookingId, disputeNo);
        return Map.of(
                "changed", rows,
                "message", rows > 0
                    ? "Moved to UNDER_REVIEW."
                    : "No change -- it was not OPEN. The status guard in the "
                    + "WHERE clause makes this safe to run twice.");
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

        Integer adminId = intOrNull(body.get("adminId"));
        if (adminId == null) {
            throw new IllegalArgumentException(
                    "adminId is required -- a resolved dispute must name who ruled on it.");
        }

        String inFavour = String.valueOf(body.getOrDefault("inFavour", ""))
                                .trim().toUpperCase();
        if (!inFavour.equals("TUTOR") && !inFavour.equals("TUTEE")) {
            throw new IllegalArgumentException("inFavour must be TUTOR or TUTEE.");
        }

        String note = String.valueOf(body.getOrDefault("note", "")).trim();
        if (note.isEmpty()) {
            throw new IllegalArgumentException(
                    "A resolution note is required -- the CHECK constraint on "
                  + "DISPUTE refuses a RESOLVED row without one.");
        }

        dao.resolve(bookingId, disputeNo, adminId, inFavour, note);

        return Map.of(
                "resolved", true,
                "inFavour", inFavour,
                "message", "Escrow returned and the dispute closed. If a "
                         + "PENALTY was posted, that is the only way credits "
                         + "leave the economy -- the audit still balances.");
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
        return Map.of(
                "blocked", result.startsWith("Blocked"),
                "result", result,
                "explanation",
                "TRG_TXN_IMMUTABLE fires BEFORE UPDATE OR DELETE on CREDIT_TXN "
              + "and raises unconditionally. A mistake is corrected by "
              + "INSERTING a compensating PENALTY or RELEASE row, exactly as "
              + "in a real accounting ledger. This is what makes the "
              + "closed-economy audit mean anything.");
    }

    private static Integer intOrNull(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Number n) {
            return n.intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(o).trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
