trigger RoomTrigger on Room__c (before insert, before update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        RoomCodeGenerator.generateRoomCodes(Trigger.new);
    }
    FacilityAutomationHandler.beforeRoomSave(Trigger.new);
}