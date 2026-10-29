package com.timebank.api.web;

import com.timebank.api.dto.Requests;
import com.timebank.api.dto.Responses;
import com.timebank.dao.LedgerDao;
import com.timebank.model.LedgerEntry;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;

/**
 * Members 4 and 6 over HTTP: the ledger, the audit and the reports.
 *
 * <p>There is no PUT and no DELETE on a transaction, and that is the
 * point. CREDIT_TXN is append-only and a database trigger enforces it,
 * so a mistake is corrected by posting a compensating row rather than by
 * editing history. If the API offered an edit endpoint, the audit below
 * would prove nothing.
 */
@RestController
@RequestMapping("/api/ledger")
public class LedgerController {

    private final LedgerDao dao = new LedgerDao();

    /**
     * GET /api/ledger/student/102 — one student's passbook.
     *
     * <p>Each row carries the balance as it stood immediately after that
     * transaction, frozen and never updated. Two independent ways of
     * arriving at the same number — summing the amounts, and reading the
     * snapshot — are what make the trail trustworthy.
     */
    @GetMapping("/student/{id}")
    public List<LedgerEntry> passbook(@PathVariable int id) throws SQLException {
        return dao.passbook(id);
    }

    /**
     * GET /api/ledger/audit — the closed-economy check.
     *
     * <pre>
     *   sum of all balances  +  credits held in escrow
     *              =  total granted  -  total penalised
     * </pre>
     *
     * <p>Every session writes one HOLD and one TRANSFER that cancel out,
     * so the only things that can change the total are a new grant or a
     * penalty. Any drift means credits appeared from nowhere.
     */
    @GetMapping("/audit")
    public Responses.Audit audit() throws SQLException {
        LedgerDao.Audit a = dao.audit();
        return new Responses.Audit(
                a.balances(), a.escrow(), a.grantsLessPenalties(),
                a.drift(), a.balanced());
    }

    /**
     * POST /api/ledger/adjustments — an administrative credit or penalty.
     *
     * <p>A PENALTY is the only way credits ever leave the economy.
     */
    @PostMapping("/adjustments")
    public ResponseEntity<Map<String, Object>> adjust(
            @RequestBody Requests.Adjustment req) throws SQLException {

        String type = req.type().trim().toUpperCase();
        if (!type.equals("GRANT") && !type.equals("PENALTY")) {
            throw new IllegalArgumentException("type must be GRANT or PENALTY");
        }

        long txnId = dao.postAdjustment(
                req.studentId(), type, req.amount(), req.remarks());

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(Map.of("txnId", txnId, "posted", true));
    }

    /** GET /api/ledger/leaderboard — top tutors by hours taught. */
    @GetMapping("/leaderboard")
    public List<String> leaderboard() throws SQLException {
        return dao.leaderboard();
    }

    /**
     * GET /api/ledger/collusion — pairs who repeatedly tutor each other.
     *
     * <p>They net out to zero credits but collect a glowing review every
     * time. No database can stop two people who agree to lie; the aim is
     * to make the pattern visible and not worth the effort.
     */
    @GetMapping("/collusion")
    public List<String> collusion() throws SQLException {
        return dao.collusionReport();
    }
}
