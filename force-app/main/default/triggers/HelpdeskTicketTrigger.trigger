trigger HelpdeskTicketTrigger on Helpdesk_Ticket__c (before update) {
    StatusTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap, 'Helpdesk_Ticket__c', 'Status__c');
}