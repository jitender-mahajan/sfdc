public with sharing class ReservationService {
    public class ReservationRequest {
        @AuraEnabled public Id reservationId;
        @AuraEnabled public Id roomId;
        @AuraEnabled public Date checkInDate;
        @AuraEnabled public Date checkOutDate;
        @AuraEnabled public Id statusRecordTypeId;
        @AuraEnabled public String status; // Booked, Checked-In, etc.
    }

    public static void beforeUpsert(List<Reservation__c> newList, Map<Id, Reservation__c> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        // Basic validation: Checkout must be after Checkin
        for (Reservation__c r : newList) {
            if (r.CheckInDate__c != null && r.CheckOutDate__c != null && r.CheckOutDate__c <= r.CheckInDate__c) {
                r.addError('Check-Out Date must be after Check-In Date.');
            }
        }

        // Prevent overlaps for active statuses
        preventOverlappingReservations(newList);

        // Calculate TotalAmount__c = nights * room.PricePerNight__c
        calculateTotals(newList);
    }

    private static void preventOverlappingReservations(List<Reservation__c> newList) {
        Set<Id> roomIds = new Set<Id>();
        for (Reservation__c r : newList) {
            if (r.Room__c != null) roomIds.add(r.Room__c);
        }
        if (roomIds.isEmpty()) return;

        // Consider overlapping only for Booked and Checked-In
        Set<String> activeStatuses = new Set<String>{'Booked', 'Checked-In'};

        // Index incoming by Room
        Map<Id, List<Reservation__c>> byRoom = new Map<Id, List<Reservation__c>>();
        for (Reservation__c r : newList) {
            if (r.Room__c == null) continue;
            if (!byRoom.containsKey(r.Room__c)) byRoom.put(r.Room__c, new List<Reservation__c>());
            byRoom.get(r.Room__c).add(r);
        }

        // Query existing reservations for these rooms that could overlap
        List<Reservation__c> existing = [
            SELECT Id, Room__c, CheckInDate__c, CheckOutDate__c, Status__c
            FROM Reservation__c
            WHERE Room__c IN :roomIds
            AND Status__c IN :activeStatuses
        ];

        // Build per-room existing lists for faster checks
        Map<Id, List<Reservation__c>> existingByRoom = new Map<Id, List<Reservation__c>>();
        for (Reservation__c e : existing) {
            List<Reservation__c> bucket = existingByRoom.get(e.Room__c);
            if (bucket == null) {
                bucket = new List<Reservation__c>();
                existingByRoom.put(e.Room__c, bucket);
            }
            bucket.add(e);
        }

        for (Id roomId : byRoom.keySet()) {
            List<Reservation__c> incoming = byRoom.get(roomId);
            List<Reservation__c> current = existingByRoom.containsKey(roomId) ? existingByRoom.get(roomId) : new List<Reservation__c>();

            for (Reservation__c n : incoming) {
                if (n.CheckInDate__c == null || n.CheckOutDate__c == null) continue;
                if (!activeStatuses.contains(n.Status__c)) continue;

                // Check against existing reservations (exclude self on update)
                for (Reservation__c e : current) {
                    if (n.Id != null && n.Id == e.Id) continue;
                    if (datesOverlap(n.CheckInDate__c, n.CheckOutDate__c, e.CheckInDate__c, e.CheckOutDate__c)) {
                        n.addError('This room already has an active reservation overlapping the selected dates.');
                        break;
                    }
                }

                // Also check against other new records in the same transaction for same room
                for (Reservation__c m : incoming) {
                    if (m == n) continue;
                    if (m.CheckInDate__c == null || m.CheckOutDate__c == null) continue;
                    if (!activeStatuses.contains(m.Status__c)) continue;
                    if (datesOverlap(n.CheckInDate__c, n.CheckOutDate__c, m.CheckInDate__c, m.CheckOutDate__c)) {
                        n.addError('Another reservation in this save overlaps the selected dates for the same room.');
                        break;
                    }
                }
            }
        }
    }

    @TestVisible
    private static Boolean datesOverlap(Date aStart, Date aEnd, Date bStart, Date bEnd) {
        // Overlap if aStart <= bEnd AND aEnd >= bStart
        // Treat touching boundaries (where check-out == other check-in) as overlapping
        return (aStart <= bEnd && aEnd >= bStart);
    }

    private static void calculateTotals(List<Reservation__c> newList) {
        Set<Id> roomIds = new Set<Id>();
        for (Reservation__c r : newList) {
            if (r.Room__c != null) roomIds.add(r.Room__c);
        }
        if (roomIds.isEmpty()) return;

        Map<Id, Room__c> rooms = new Map<Id, Room__c>([
            SELECT Id, PricePerNight__c FROM Room__c WHERE Id IN :roomIds
        ]);

        for (Reservation__c r : newList) {
            if (r.CheckInDate__c == null || r.CheckOutDate__c == null || r.Room__c == null) continue;
            Room__c room = rooms.get(r.Room__c);
            if (room == null || room.PricePerNight__c == null) continue;
            Integer nights = r.CheckInDate__c.daysBetween(r.CheckOutDate__c);
            if (nights != null && nights > 0) {
                r.TotalAmount__c = Decimal.valueOf(nights) * room.PricePerNight__c;
            }
        }
    }
}
