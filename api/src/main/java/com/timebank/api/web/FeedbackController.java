package com.timebank.api.web;

import com.timebank.dao.FeedbackDao;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;

/**
 * Feedback, disputes and fraud, over HTTP.
 *
 * <p>MEMBER 5 — FEEDBACK, DISPUTE, ADMIN.
 */
@RestController
@RequestMapping("/api/feedback")
public class FeedbackController {

    private final FeedbackDao dao = new FeedbackDao();

    /** GET /api/feedback — every review and dispute written so far. */
    @GetMapping
    public List<Map<String, Object>> all() throws SQLException {
        return dao.reviewsAndDisputes();
    }

    /** GET /api/feedback/both-sides — the self join. */
    @GetMapping("/both-sides")
    public List<Map<String, Object>> bothSides() throws SQLException {
        return dao.bothSides();
    }

    /** GET /api/feedback/top-tutors — rated above the campus average. */
    @GetMapping("/top-tutors")
    public List<Map<String, Object>> topTutors() throws SQLException {
        return dao.aboveAverage();
    }

    /** GET /api/feedback/collusion — pairs who keep tutoring each other. */
    @GetMapping("/collusion")
    public List<Map<String, Object>> collusion() throws SQLException {
        return dao.collusion();
    }

    /** GET /api/feedback/by-subject — rating spread, with a total row. */
    @GetMapping("/by-subject")
    public List<Map<String, Object>> bySubject() throws SQLException {
        return dao.ratingBySubject();
    }

    /** GET /api/feedback/trend — is each tutor improving or slipping? */
    @GetMapping("/trend")
    public List<Map<String, Object>> trend() throws SQLException {
        return dao.ratingTrend();
    }

    /** GET /api/feedback/reviewable — finished sessions awaiting a review. */
    @GetMapping("/reviewable")
    public List<Map<String, Object>> reviewable() throws SQLException {
        return dao.reviewable();
    }

    /**
     * POST /api/feedback — leave a review.
     *
     * <p>Body: bookingId, reviewerRole (TUTOR or TUTEE), rating, comments.
     */
    @PostMapping
    public ResponseEntity<Map<String, Object>> leave(
            @RequestBody Map<String, Object> body) throws SQLException {

        int bookingId = intOf(body.get("bookingId"), "bookingId");

        String role = String.valueOf(body.getOrDefault("reviewerRole", ""))
                            .trim().toUpperCase();
        if (!role.equals("TUTOR") && !role.equals("TUTEE")) {
            throw new IllegalArgumentException(
                    "reviewerRole must be TUTOR or TUTEE.");
        }

        BigDecimal rating;
        try {
            rating = new BigDecimal(String.valueOf(body.get("rating")));
        } catch (Exception e) {
            throw new IllegalArgumentException("A rating is required.");
        }
        if (rating.compareTo(BigDecimal.ONE) < 0
                || rating.compareTo(new BigDecimal("5")) > 0) {
            throw new IllegalArgumentException(
                    "The rating has to be between 1 and 5.");
        }

        String comments = String.valueOf(
                body.getOrDefault("comments", "")).trim();

        dao.leaveReview(bookingId, role, rating,
                        comments.isEmpty() ? null : comments);

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "saved", true,
                "bookingId", bookingId,
                "reviewerRole", role,
                "message", "Review saved."));
    }

    /** DELETE /api/feedback/4/TUTEE — retract one review. */
    @DeleteMapping("/{bookingId}/{role}")
    public Map<String, Object> retract(@PathVariable int bookingId,
                                       @PathVariable String role)
            throws SQLException {

        String r = role.trim().toUpperCase();
        if (!r.equals("TUTOR") && !r.equals("TUTEE")) {
            throw new IllegalArgumentException("role must be TUTOR or TUTEE.");
        }

        int n = dao.retractReview(bookingId, r);
        return Map.of(
                "removed", n,
                "message", n > 0 ? "Review removed."
                                 : "There was no review from that side.");
    }

    private static int intOf(Object o, String field) {
        if (o instanceof Number n) {
            return n.intValue();
        }
        try {
            return Integer.parseInt(String.valueOf(o).trim());
        } catch (Exception e) {
            throw new IllegalArgumentException(field + " is required.");
        }
    }
}
