@IsTest
private class ReservationServiceTest {

    private static Id hotelId;
    private static Id roomStdId;
    private static Id roomSuiteId;
    private static Id guestAId;
    private static Id guestBId;

    @TestSetup
    static void setupData() {
        Hotel__c h = new Hotel__c(Name = 'A4D Hotel', Phone__c = '1234567890', Rating__c = 4);
        insert h;
        hotelId = h.Id;

        Room__c r1 = new Room__c(Name = '101', Hotel__c = hotelId, RoomNumber__c = '101', RoomType__c = 'Standard', Capacity__c = 2, PricePerNight__c = 100);
        Room__c r2 = new Room__c(Name = '501', Hotel__c = hotelId, RoomNumber__c = '501', RoomType__c = 'Suite', Capacity__c = 4, PricePerNight__c = 250);
        insert new List<Room__c>{ r1, r2 };
        roomStdId = r1.Id;
        roomSuiteId = r2.Id;

        Guest__c g1 = new Guest__c(Name = 'John Doe', Email__c = 'john@example.com');
        Guest__c g2 = new Guest__c(Name = 'Jane Smith', Email__c = 'jane@example.com');
        insert new List<Guest__c>{ g1, g2 };
        guestAId = g1.Id;
        guestBId = g2.Id;
    }

    @IsTest
    static void testValidation_CheckoutAfterCheckin() {
        Reservation__c res = new Reservation__c(
            Guest__c = guestAId,
            Room__c = roomStdId,
            Status__c = 'Booked',
            CheckInDate__c = Date.newInstance(2025,1,10),
            CheckOutDate__c = Date.newInstance(2025,1,9)
        );
        Test.startTest();
        try {
            insert res;
            System.assert(false, 'Expected validation error for invalid date range');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Check-Out Date must be after Check-In Date'), 'Expected message not found: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testNoOverlapAcrossDifferentRooms() {
        Reservation__c res1 = new Reservation__c(
            Guest__c = guestAId,
            Room__c = roomStdId,
            Status__c = 'Booked',
            CheckInDate__c = Date.newInstance(2025,1,10),
            CheckOutDate__c = Date.newInstance(2025,1,12)
        );
        Reservation__c res2 = new Reservation__c(
            Guest__c = guestBId,
            Room__c = roomSuiteId,
            Status__c = 'Booked',
            CheckInDate__c = Date.newInstance(2025,1,11),
            CheckOutDate__c = Date.newInstance(2025,1,13)
        );
        Test.startTest();
        insert new List<Reservation__c>{ res1, res2 };
        Test.stopTest();
        System.assertNotEquals(null, res1.Id);
        System.assertNotEquals(null, res2.Id);
    }

    @IsTest
    static void testOverlapBlockedSameRoom() {
        Reservation__c existingRes = new Reservation__c(
            Guest__c = guestAId,
            Room__c = roomStdId,
            Status__c = 'Booked',
            CheckInDate__c = Date.newInstance(2025,2,1),
            CheckOutDate__c = Date.newInstance(2025,2,5)
        );
        insert existingRes;

        // Overlapping request in the middle
        Reservation__c overlapping = new Reservation__c(
            Guest__c = guestBId,
            Room__c = roomStdId,
            Status__c = 'Booked',
            CheckInDate__c = Date.newInstance(2025,2,3),
            CheckOutDate__c = Date.newInstance(2025,2,6)
        );
        Test.startTest();
        try {
            insert overlapping;
            System.assert(false, 'Expected overlap error');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('overlapping'), 'Expected overlap error message, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testTotalsCalculatedByNights() {
        Reservation__c res = new Reservation__c(
            Guest__c = guestAId,
            Room__c = roomSuiteId,
            Status__c = 'Booked',
            CheckInDate__c = Date.newInstance(2025,3,10),
            CheckOutDate__c = Date.newInstance(2025,3,13) // 3 nights
        );
        Test.startTest();
        insert res;
        Test.stopTest();

        res = [SELECT TotalAmount__c FROM Reservation__c WHERE Id = :res.Id];
        Decimal expected = 3 * 250;
        System.assertEquals(expected, res.TotalAmount__c, 'Total amount should equal nights * price per night');
    }

    @IsTest
    static void testActiveStatusesOnly() {
        // Existing active booking
        Reservation__c active = new Reservation__c(
            Guest__c = guestAId,
            Room__c = roomStdId,
            Status__c = 'Booked',
            CheckInDate__c = Date.newInstance(2025,4,1),
            CheckOutDate__c = Date.newInstance(2025,4,3)
        );
        insert active;

        // Overlap with Cancelled should be allowed
        Reservation__c cancelled = new Reservation__c(
            Guest__c = guestBId,
            Room__c = roomStdId,
            Status__c = 'Cancelled',
            CheckInDate__c = Date.newInstance(2025,4,2),
            CheckOutDate__c = Date.newInstance(2025,4,4)
        );
        Test.startTest();
        insert cancelled;
        Test.stopTest();
        System.assertNotEquals(null, cancelled.Id);
    }
}
