package com.timebank.api.dto;

import java.math.BigDecimal;

/**
 * Request bodies, grouped in one file because each is only a handful of
 * fields. Records give immutability and JSON binding for free.
 */
public final class Requests {

    private Requests() { }

    public record RegisterStudent(
            String regNo, String firstName, String lastName, String email,
            String dob,          // yyyy-MM-dd
            int    deptId,
            String block, String roomNo, String city, String phone) { }

    public record BookSession(
            int    tuteeId, int tutorId, int subjectId, int slotNo,
            String schedDate,    // yyyy-MM-dd
            double startTime,    // decimal hour: 16.5 is 16:30
            double durationHours,
            String mode, String venue) { }

    public record CheckIn(String sessionCode) { }

    public record Confirm(String role) { }        // TUTOR or TUTEE

    public record Cancel(String byRole) { }

    public record Adjustment(
            int studentId, String type, BigDecimal amount, String remarks) { }
}
