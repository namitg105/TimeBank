package com.timebank.api.web;

import com.timebank.db.Database;
import com.timebank.db.SqlLog;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.sql.SQLException;
import java.time.format.DateTimeParseException;

/**
 * Turns every failure into an HTTP status plus one sentence for the app.
 *
 * <p>The mapping matters. A broken business rule — "that slot is already
 * booked", "not enough credits" — is something the user can fix, so it
 * returns 409 CONFLICT and the app shows the sentence. Bad input returns
 * 400. A genuine fault returns 500 with a generic sentence: Java and
 * Oracle internals are printed in the API window, never sent to the app.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(SQLException.class)
    public ResponseEntity<ApiError> onSql(SQLException e) {
        int code = e.getErrorCode();
        String message = Database.explain(e);

        // The raw error, for whoever is watching the API window.
        SqlLog.note("Oracle said: " + firstLine(e.getMessage()));

        // -20000 to -20999 are OUR errors, raised by the triggers and the
        // package with RAISE_APPLICATION_ERROR. They are business rules.
        boolean businessRule = code >= 20000 && code <= 20999;

        // Constraint and size violations are also the caller's to fix.
        boolean badInput = code == 1       // unique key
                        || code == 1400    // NOT NULL
                        || code == 1438    // number too large
                        || code == 2290    // CHECK
                        || code == 2291    // FK parent missing
                        || code == 2292    // FK child exists
                        || code == 12899;  // value too long

        HttpStatus status = (businessRule || badInput)
                ? HttpStatus.CONFLICT
                : HttpStatus.INTERNAL_SERVER_ERROR;

        String kind = businessRule ? "RULE_VIOLATION"
                    : badInput     ? "CONSTRAINT_VIOLATION"
                    : "DATABASE_ERROR";

        return ResponseEntity.status(status).body(new ApiError(kind, message, code));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiError> onBadInput(IllegalArgumentException e) {
        return bad(e.getMessage());
    }

    /** A body that is missing or is not JSON, or a field of the wrong type. */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiError> onUnreadable(HttpMessageNotReadableException e) {
        SqlLog.note("Unreadable request: " + firstLine(e.getMessage()));
        return bad("Some details were missing or in the wrong format. "
                 + "Check the form and try again.");
    }

    /** /api/students/abc/balance — a path or query value of the wrong type. */
    @ExceptionHandler({MethodArgumentTypeMismatchException.class,
                       MissingServletRequestParameterException.class})
    public ResponseEntity<ApiError> onBadParameter(Exception e) {
        SqlLog.note("Bad parameter: " + firstLine(e.getMessage()));
        return bad("That link is not valid.");
    }

    @ExceptionHandler(DateTimeParseException.class)
    public ResponseEntity<ApiError> onBadDate(DateTimeParseException e) {
        return bad("That date is not valid.");
    }

    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<ApiError> onNotFound(NoResourceFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(new ApiError("NOT_FOUND", "That page does not exist.", 0));
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ApiError> onWrongMethod(HttpRequestMethodNotSupportedException e) {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED)
                .body(new ApiError("NOT_ALLOWED", "That action is not available here.", 0));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> onAnythingElse(Exception e) {
        SqlLog.note("Unexpected error: " + e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ApiError("SERVER_ERROR",
                        "Something went wrong on the server. Please try again.", 0));
    }

    private static ResponseEntity<ApiError> bad(String message) {
        return ResponseEntity.badRequest().body(new ApiError("BAD_REQUEST", message, 0));
    }

    private static String firstLine(String s) {
        if (s == null) return "";
        int nl = s.indexOf('\n');
        return nl > 0 ? s.substring(0, nl) : s;
    }
}
