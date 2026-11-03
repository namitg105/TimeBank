package com.timebank.api.web;

import com.timebank.api.dto.Responses;
import com.timebank.dao.FeedbackDao;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;

/**
 * Member 5's module over HTTP: reviews.
 *
 * <p>The four GETs are the ways of reading what has been written — each
 * a different shape of query, and each answering a question somebody
 * actually asks about a tutoring scheme. The POST and DELETE are how a
 * review gets there and how it is taken back.
 */
@RestController
@RequestMapping("/api/feedback")
public class FeedbackController {

    private final FeedbackDao dao = new FeedbackDao();

    /** GET /api/feedback/sessions — both sides of every session. */
    @GetMapping("/sessions")
    public List<Map<String, Object>> bothSides() throws SQLException {
        return dao.bothSides();
    }

    /** GET /api/feedback/top-rated — tutors above the campus average. */
    @GetMapping("/top-rated")
    public List<Map<String, Object>> topRated() throws SQLException {
        return dao.aboveAverage();
    }

    /** GET /api/feedback/by-subject — rating spread, with a grand total. */
    @GetMapping("/by-subject")
    public List<Map<String, Object>> bySubject() throws SQLException {
        return dao.ratingSpread();
    }

    /** GET /api/feedback/trend — improving or slipping, per tutor. */
    @GetMapping("/trend")
    public List<Map<String, Object>> trend() throws SQLException {
        return dao.ratingTrend();
    }

    /** GET /api/feedback/12 — which sides have reviewed session 12. */
    @GetMapping("/{bookingId}")
    public List<String> reviewers(@PathVariable int bookingId) throws SQLException {
        return dao.reviewersOf(bookingId);
    }

    /**
     * POST /api/feedback/12 — leave a review.
     *
     * <p>Body: role (TUTOR or TUTEE), rating 1 to 5, and a comment.
     */
    @PostMapping("/{bookingId}")
    public ResponseEntity<Responses.Ack> leave(@PathVariable int bookingId,
                                               @RequestBody Map<String, Object> body)
            throws SQLException {

        String role = Input.oneOf(body.get("role"),
                "Say who is reviewing: the tutor or the learner.", "TUTOR", "TUTEE");

        double rating = Input.decimal(body.get("rating"), "Choose a rating.");
        if (rating < 1 || rating > 5
                || Math.abs(rating * 2 - Math.rint(rating * 2)) > 1e-9) {
            throw new IllegalArgumentException(
                    "A rating is between 1 and 5, in halves.");
        }

        String comments = Input.maxLength(Input.text(body.get("comments")), 400,
                "Comment");

        dao.leaveReview(bookingId, role, BigDecimal.valueOf(rating), comments);

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(new Responses.Ack(true, "Review saved.", 1));
    }

    /** DELETE /api/feedback/12/TUTEE — take a review back. */
    @DeleteMapping("/{bookingId}/{role}")
    public Responses.Ack retract(@PathVariable int bookingId,
                                 @PathVariable String role) throws SQLException {
        String side = Input.oneOf(role,
                "Say whose review to remove: the tutor's or the learner's.",
                "TUTOR", "TUTEE");
        int rows = dao.retractReview(bookingId, side);
        return new Responses.Ack(rows > 0,
                rows > 0 ? "Review removed." : "There was no review to remove.",
                rows);
    }
}
