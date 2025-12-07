trigger ReservationTrigger on Reservation__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            ReservationService.beforeUpsert(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
        }
    }
}
