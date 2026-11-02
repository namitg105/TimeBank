package com.timebank.api.web;

import com.timebank.api.dto.Responses;
import com.timebank.dao.BookingDao;
import com.timebank.model.Booking;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;

/**
 * Members 2 and 3 over HTTP: the booking engine and escrow.
 *
 * <p>Note what is NOT here: no slot-availability check, no overdraft
 * check, no collusion cap. All of those live inside PKG_TIMEBANK, where
 * they run under a row lock. Re-implementing them in Java would be both
 * duplicated and weaker — the app could not hold a database lock across
 * an HTTP request anyway.
 */
@RestController
@RequestMapping("/api/bookings")
public class BookingController {

    private final BookingDao dao = new BookingDao();

    /** GET /api/bookings — everything, or ?status=CONFIRMED to filter. */
    @GetMapping
    public List<Booking> list(@RequestParam(required = false) String status)
            throws SQLException {
        return (status == null || status.isBlank())
                ? dao.listAll()
                : dao.byStatus(status.toUpperCase());
    }

    /**
     * GET /api/bookings/student/105 — every session for one person.
     *
     * <p>Returns sessions where they were the tutor AND where they were
     * the tutee, in one list. A student can legitimately be both, which
     * is the overlapping specialization reaching all the way up into the
     * API surface.
     */
    @GetMapping("/student/{id}")
    public List<Booking> forStudent(@PathVariable int id) throws SQLException {
        return dao.forStudent(id);
    }

    /**
     * POST /api/bookings — book a session by ids.
     *
     * <p>The code is never returned from this generic endpoint. The
     * learner retrieves it from their own session list, while the tutor
     * sees only the check-in prompt. That keeps this lower-level endpoint
     * consistent with the guided booking flow as well.
     */
    @PostMapping
    public ResponseEntity<Responses.BookingCreated> book(
            @RequestBody Map<String, Object> body) throws SQLException {

        int tuteeId = Input.integer(body.get("tuteeId"), "Pick the learner.");
        int tutorId = Input.integer(body.get("tutorId"), "Pick the tutor.");
        SessionDetails d = SessionDetails.from(body);

        var result = dao.book(tuteeId, tutorId, d.subjectId(), d.slotNo(),
                d.date(), d.startTime(), d.durationHours(), d.mode(), d.venue());

        return ResponseEntity.status(HttpStatus.CREATED).body(
                new Responses.BookingCreated(
                        result.bookingId(),
                        null,
                        d.durationHours(),
                        "Booked. The learner can find the session code in their "
                      + "Sessions list."));
    }

    /** POST /api/bookings/12/checkin — the tutor enters the learner's code. */
    @PostMapping("/{id}/checkin")
    public Responses.Ack checkIn(@PathVariable int id,
                                 @RequestBody Map<String, Object> body)
            throws SQLException {
        String code = Input.required(body.get("sessionCode"),
                "Enter the session code.").toUpperCase();
        dao.checkIn(id, code);
        return new Responses.Ack(true,
                "Checked in. The session can now be confirmed.", 1);
    }

    /**
     * POST /api/bookings/12/confirm — one side says it happened.
     *
     * <p>Credits move only once BOTH sides have confirmed. The learner was
     * already debited by the HOLD at booking time, so completion writes
     * a single positive TRANSFER to the tutor — never a second debit.
     */
    @PostMapping("/{id}/confirm")
    public Responses.Ack confirm(@PathVariable int id,
                                @RequestBody Map<String, Object> body)
            throws SQLException {
        String role = Input.oneOf(body.get("role"),
                "Say who is confirming: the tutor or the learner.", "TUTOR", "TUTEE");
        dao.confirm(id, role);
        boolean done = "COMPLETED".equals(dao.statusOf(id));
        return new Responses.Ack(true, done
                ? "Both sides confirmed. The credits have been paid to the tutor."
                : "Confirmation recorded. Credits move once the other side confirms.", 1);
    }

    /**
     * POST /api/bookings/12/cancel — who cancels, and how late, decides
     * the split. The reply says what actually happened to the credits.
     */
    @PostMapping("/{id}/cancel")
    public Responses.Ack cancel(@PathVariable int id,
                                @RequestBody Map<String, Object> body)
            throws SQLException {
        String byRole = Input.oneOf(body.get("byRole"),
                "Say who is cancelling: the tutor or the learner.", "TUTOR", "TUTEE");
        dao.cancel(id, byRole);

        BookingDao.CancelOutcome out = dao.cancelOutcome(id);
        String message = out.paidToTutor() > 0
                ? "Session cancelled. " + credits(out.returnedToLearner())
                  + " returned to the learner and " + credits(out.paidToTutor())
                  + " paid to the tutor, because it was cancelled less than "
                  + "a day before."
                : "Session cancelled. " + credits(out.returnedToLearner())
                  + " returned to the learner.";
        return new Responses.Ack(true, message, 1);
    }

    private static String credits(double n) {
        return String.format("%.1f credit%s", n, n == 1.0 ? "" : "s");
    }

    /**
     * DELETE /api/bookings/abandoned — purge stale requests.
     *
     * <p>Only REQUESTED rows can go: they never reached escrow, so no
     * ledger row points at them. Anything further along is referenced by
     * CREDIT_TXN and Oracle refuses, deliberately — deleting it would
     * orphan money.
     */
    @DeleteMapping("/abandoned")
    public Responses.Ack purge() throws SQLException {
        int rows = dao.purgeAbandoned();
        return new Responses.Ack(true, rows + " abandoned request(s) deleted.", rows);
    }
}
