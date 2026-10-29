package com.timebank.api.web;

import com.timebank.api.dto.Requests;
import com.timebank.api.dto.Responses;
import com.timebank.dao.BookingDao;
import com.timebank.model.Booking;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.sql.SQLException;
import java.time.LocalDate;
import java.util.List;

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
     * POST /api/bookings — book a session.
     *
     * <p>The response carries the session code. That code goes to the
     * TUTEE only: the tutor types it in at the start of the session,
     * which is what proves the tutee actually turned up. Without a
     * check-in the confirmation trigger refuses to complete the session,
     * so a tutor cannot claim credits for a no-show.
     */
    @PostMapping
    public ResponseEntity<Responses.BookingCreated> book(
            @RequestBody Requests.BookSession req) throws SQLException {

        if (req.tuteeId() == req.tutorId()) {
            throw new IllegalArgumentException(
                    "A student cannot book a session with themselves.");
        }

        var result = dao.book(
                req.tuteeId(), req.tutorId(), req.subjectId(), req.slotNo(),
                LocalDate.parse(req.schedDate()), req.startTime(),
                req.durationHours(),
                req.mode() == null ? "ONLINE" : req.mode().toUpperCase(),
                req.venue());

        return ResponseEntity.status(HttpStatus.CREATED).body(
                new Responses.BookingCreated(
                        result.bookingId(),
                        result.sessionCode(),
                        req.durationHours(),
                        "Give this code to the tutee only. "
                      + req.durationHours() + " credits are now held in escrow "
                      + "and reach the tutor only when both sides confirm."));
    }

    /** POST /api/bookings/12/checkin — the tutor enters the tutee's code. */
    @PostMapping("/{id}/checkin")
    public Responses.Ack checkIn(@PathVariable int id,
                                 @RequestBody Requests.CheckIn req)
            throws SQLException {
        dao.checkIn(id, req.sessionCode().trim().toUpperCase());
        return new Responses.Ack(true,
                "Checked in. The session can now be confirmed.", 1);
    }

    /**
     * POST /api/bookings/12/confirm — one side says it happened.
     *
     * <p>Credits move only once BOTH sides have confirmed. The tutee was
     * already debited by the HOLD at booking time, so completion writes
     * a single positive TRANSFER to the tutor — never a second debit.
     */
    @PostMapping("/{id}/confirm")
    public Responses.Ack confirm(@PathVariable int id,
                                 @RequestBody Requests.Confirm req)
            throws SQLException {
        String role = req.role().trim().toUpperCase();
        if (!role.equals("TUTOR") && !role.equals("TUTEE")) {
            throw new IllegalArgumentException("role must be TUTOR or TUTEE");
        }
        dao.confirm(id, role);
        return new Responses.Ack(true,
                "Confirmation recorded. Credits move once both sides confirm.", 1);
    }

    /** POST /api/bookings/12/cancel — who cancels, and how late, decides the split. */
    @PostMapping("/{id}/cancel")
    public Responses.Ack cancel(@PathVariable int id,
                                @RequestBody Requests.Cancel req)
            throws SQLException {
        dao.cancel(id, req.byRole().trim().toUpperCase());
        return new Responses.Ack(true,
                "Cancelled. Tutor cancels or tutee cancels early: all credits "
              + "returned. Tutee cancels inside 24 hours: split with the tutor.", 1);
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
