package com.timebank.api.web;

import com.timebank.db.Database;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.sql.SQLException;

/**
 * Turns database errors into sensible HTTP responses.
 *
 * <p>The mapping matters. A broken business rule — "that slot is already
 * booked", "overdraft limit reached" — is the user's problem, so it
 * returns 409 CONFLICT and the app shows the message. A genuine fault,
 * such as Oracle being down, returns 500 and the app shows a retry.
 * Returning 500 for everything would make the app unable to tell the two
 * apart.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(SQLException.class)
    public ResponseEntity<ApiError> onSql(SQLException e) {
        int code = e.getErrorCode();
        String message = Database.explain(e);

        // 20001-20021 are OUR errors, raised by the triggers and package
        // with RAISE_APPLICATION_ERROR. They are business rules, not bugs.
        boolean businessRule = code >= 20001 && code <= 20021;

        // Constraint violations are also the caller's fault.
        boolean constraint = code == 1       // unique key
                          || code == 1400    // NOT NULL
                          || code == 2290    // CHECK
                          || code == 2291    // FK parent missing
                          || code == 2292;   // FK child exists

        HttpStatus status = (businessRule || constraint)
                ? HttpStatus.CONFLICT
                : HttpStatus.INTERNAL_SERVER_ERROR;

        String kind = businessRule ? "RULE_VIOLATION"
                    : constraint   ? "CONSTRAINT_VIOLATION"
                    : "DATABASE_ERROR";

        return ResponseEntity.status(status).body(new ApiError(kind, message, code));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiError> onBadInput(IllegalArgumentException e) {
        return ResponseEntity.badRequest()
                .body(new ApiError("BAD_REQUEST", e.getMessage(), 0));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> onAnythingElse(Exception e) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ApiError("SERVER_ERROR", e.getMessage(), 0));
    }
}
