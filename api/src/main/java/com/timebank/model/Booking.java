package com.timebank.model;

import java.math.BigDecimal;
import java.time.LocalDate;

/** One session, joined up with the names behind its four foreign keys. */
public record Booking(
        int        bookingId,
        String     tuteeName,
        String     tutorName,
        String     subjectCode,
        LocalDate  schedDate,
        BigDecimal startTime,
        BigDecimal durationHours,
        String     mode,
        String     venue,
        String     status,
        BigDecimal creditsHeld,
        String     confirmations,   // e.g. "Y/N"
        boolean    checkedIn
) {
    /** 16.5 -> "16:30". The column stores a decimal hour, not a timestamp. */
    public String clockTime() {
        int hour    = startTime.intValue();
        int minutes = startTime.subtract(BigDecimal.valueOf(hour))
                               .multiply(BigDecimal.valueOf(60)).intValue();
        return String.format("%02d:%02d", hour, minutes);
    }

    @Override
    public String toString() {
        return String.format("#%-4d %-10s %-5s %-9s %-9s -> %-9s %5sh  %-10s %s",
                bookingId, schedDate, clockTime(), subjectCode,
                tuteeName, tutorName, durationHours, status,
                checkedIn ? "checked-in" : "");
    }
}
