public with sharing class HMS_ZoomInvocable {
    
    @InvocableMethod(label='Create Zoom Meeting' description='Enqueues a queueable job to request a Zoom meeting and log details.')
    public static void createZoomMeeting(List<Id> appointmentIds) {
        if (appointmentIds != null && !appointmentIds.isEmpty()) {
            System.enqueueJob(new HMS_ZoomMeetingQueueable(appointmentIds));
        }
    }
}
