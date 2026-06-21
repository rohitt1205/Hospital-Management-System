trigger NotificationLogTrigger on Notification_Log__c (before update) {
    StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Notification_Log__c', 'Status__c');
}