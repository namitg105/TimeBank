package com.timebank.api.web;

import java.time.LocalDate;
import java.util.Map;

/**
 * The when, how long and where of a session, read and checked once for
 * both booking endpoints.
 *
 * <p>The date window matches the app's date picker: up to 30 days back
 * (so a session that already happened can be recorded and finished) and
 * up to 60 days ahead. The remaining rules — free hour, weekday, credits,
 * clashes — stay in PKG_TIMEBANK and its triggers, under a row lock.
 */
record SessionDetails(int subjectId, int slotNo, LocalDate date,
                      double startTime, double durationHours,
                      String mode, String venue) {

    static final int DAYS_BACK = 30;
    static final int DAYS_AHEAD = 60;

    static SessionDetails from(Map<String, Object> body) {
        int subjectId = Input.integer(body.get("subjectId"), "Pick a subject.");
        int slotNo    = Input.integer(body.get("slotNo"), "Pick one of the free hours.");

        LocalDate date = Input.date(body.get("schedDate"), "Pick a date for the session.");
        LocalDate today = LocalDate.now();
        if (date.isBefore(today.minusDays(DAYS_BACK))) {
            throw new IllegalArgumentException(
                    "Sessions can be recorded up to " + DAYS_BACK + " days back.");
        }
        if (date.isAfter(today.plusDays(DAYS_AHEAD))) {
            throw new IllegalArgumentException(
                    "Sessions can be booked up to " + DAYS_AHEAD + " days ahead.");
        }

        double start = Input.decimal(body.get("startTime"), "Pick a start time.");
        if (start < 0 || start >= 24) {
            throw new IllegalArgumentException("Pick a start time within the day.");
        }

        double hours = Input.decimal(body.get("durationHours"), "Pick how long the session lasts.");
        if (hours != 0.5 && hours != 1.0 && hours != 1.5 && hours != 2.0) {
            throw new IllegalArgumentException("A session can last 0.5, 1, 1.5 or 2 hours.");
        }

        String mode = Input.text(body.get("mode")) == null ? "ONLINE"
                : Input.oneOf(body.get("mode"), "Choose in person or online.",
                              "ONLINE", "OFFLINE");

        String venue = Input.maxLength(Input.text(body.get("venue")), 60,
                "Room or meeting link");

        return new SessionDetails(subjectId, slotNo, date, start, hours, mode, venue);
    }
}
