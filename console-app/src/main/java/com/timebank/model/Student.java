package com.timebank.model;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * One row of the STUDENT relation, plus the two values the ER diagram
 * marks as DERIVED (dashed ovals) and therefore does not store as
 * columns: age and credit balance. Both arrive from v_student_balance.
 *
 * <p>A record is used rather than a class with getters because this is
 * pure data with no behaviour — exactly what records are for.
 */
public record Student(
        int        studentId,
        String     regNo,
        String     fullName,
        String     email,
        LocalDate  dob,
        int        age,              // derived from dob
        String     city,
        String     accountStatus,
        String     school,
        BigDecimal creditBalance,    // derived: SUM(amount) over the ledger
        String     roleInSystem      // TUTOR ONLY / TUTEE ONLY / BOTH / NEITHER
) {
    @Override
    public String toString() {
        return String.format("%-5d %-12s %-22s %-10s %6s cr  %s",
                studentId, regNo, fullName, school, creditBalance, roleInSystem);
    }
}
