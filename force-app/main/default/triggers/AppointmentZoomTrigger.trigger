trigger AppointmentZoomTrigger on Appointment__c (after insert, after update) {
    List<Id> idsToProcess = new List<Id>();
    
    for (Appointment__c app : Trigger.new) {
        Boolean isOnline = (app.Appointment_Type__c == 'Teleconsultation' || app.Appointment_Type__c == 'Online');
        // Let's check status. If scheduled or normal active status, trigger Zoom creation.
        Boolean isScheduled = (app.Status__c == 'Scheduled' || app.Status__c == 'Confirmed');
        
        Boolean shouldTrigger = false;
        if (Trigger.isInsert) {
            if (isOnline && isScheduled) {
                shouldTrigger = true;
            }
        } else if (Trigger.isUpdate) {
            Appointment__c oldApp = Trigger.oldMap.get(app.Id);
            Boolean wasOnline = (oldApp.Appointment_Type__c == 'Teleconsultation' || oldApp.Appointment_Type__c == 'Online');
            Boolean wasScheduled = (oldApp.Status__c == 'Scheduled' || oldApp.Status__c == 'Confirmed');
            
            // Trigger if newly changed to online or newly confirmed/scheduled
            if (isOnline && isScheduled && (!wasOnline || !wasScheduled)) {
                shouldTrigger = true;
            }
        }
        
        if (shouldTrigger) {
            idsToProcess.add(app.Id);
        }
    }
    
    if (!idsToProcess.isEmpty()) {
        System.enqueueJob(new HMS_ZoomMeetingQueueable(idsToProcess));
    }
}
