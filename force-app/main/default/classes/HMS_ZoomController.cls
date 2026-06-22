public with sharing class HMS_ZoomController {

    public class MeetingDetails {
        @AuraEnabled public String appointmentType;
        @AuraEnabled public DateTime appointmentDateTime;
        @AuraEnabled public String joinUrl;
        @AuraEnabled public String startUrl;
        @AuraEnabled public String status;
        @AuraEnabled public String topic;
        @AuraEnabled public String meetingId;
    }

    @AuraEnabled(cacheable=false)
    public static MeetingDetails getMeetingDetails(Id appointmentId) {
        if (appointmentId == null) {
            return null;
        }

        Appointment__c appt = [
            SELECT Id, Appointment_Type__c, Appointment_Date_Time__c
            FROM Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];

        MeetingDetails details = new MeetingDetails();
        details.appointmentType = appt.Appointment_Type__c;
        details.appointmentDateTime = appt.Appointment_Date_Time__c;

        // Query the latest Meeting log record for this appointment
        List<Meeting__c> meetings = [
            SELECT Id, Join_URL__c, Start_URL__c, Status__c, Topic__c, Meeting_ID__c
            FROM Meeting__c
            WHERE Appointment__c = :appointmentId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!meetings.isEmpty()) {
            Meeting__c mtg = meetings[0];
            details.joinUrl = mtg.Join_URL__c;
            details.startUrl = mtg.Start_URL__c;
            details.status = mtg.Status__c;
            details.topic = mtg.Topic__c;
            details.meetingId = mtg.Meeting_ID__c;
        }

        return details;
    }
}
