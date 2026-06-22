public with sharing class HMS_ZoomMeetingQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> appointmentIds;

    public HMS_ZoomMeetingQueueable(List<Id> ids) {
        this.appointmentIds = ids;
    }

    public void execute(QueueableContext context) {
        if (appointmentIds == null || appointmentIds.isEmpty()) {
            return;
        }

        List<Appointment__c> appointments = [
            SELECT Id, Name, Patient__r.Name, Doctor__r.Email__c, Appointment_Date_Time__c
            FROM Appointment__c
            WHERE Id IN :appointmentIds
        ];

        List<Meeting__c> meetingsToInsert = new List<Meeting__c>();

        for (Appointment__c app : appointments) {
            try {
                String hostEmail = app.Doctor__r.Email__c;
                String topic = 'Consultation: ' + (app.Patient__r.Name != null ? app.Patient__r.Name : 'Patient') + ' (' + app.Name + ')';
                DateTime startTime = app.Appointment_Date_Time__c != null ? app.Appointment_Date_Time__c : System.now();
                Integer duration = 30; // Default consultation duration

                Map<String, Object> meetingResult = HMS_ZoomService.createMeeting(hostEmail, topic, startTime, duration);

                Meeting__c mtg = new Meeting__c();
                mtg.Appointment__c = app.Id;
                mtg.Topic__c = topic;
                
                if (meetingResult.containsKey('id')) {
                    mtg.Meeting_ID__c = String.valueOf(meetingResult.get('id'));
                }
                mtg.Start_Time__c = startTime;
                
                if (meetingResult.containsKey('duration')) {
                    mtg.Duration__c = Decimal.valueOf(String.valueOf(meetingResult.get('duration')));
                }
                if (meetingResult.containsKey('join_url')) {
                    mtg.Join_URL__c = (String) meetingResult.get('join_url');
                }
                if (meetingResult.containsKey('start_url')) {
                    mtg.Start_URL__c = (String) meetingResult.get('start_url');
                }
                if (meetingResult.containsKey('status')) {
                    mtg.Status__c = (String) meetingResult.get('status');
                } else {
                    mtg.Status__c = 'Created';
                }

                meetingsToInsert.add(mtg);

            } catch (Exception ex) {
                // If it fails, log the failure by creating a Meeting__c record with status 'Failed' 
                // so we can display it on the LWC and log the error.
                System.debug('Error creating Zoom meeting: ' + ex.getMessage());
                Meeting__c mtg = new Meeting__c();
                mtg.Appointment__c = app.Id;
                mtg.Topic__c = 'Failed Zoom Meeting Generation';
                mtg.Status__c = 'Failed';
                mtg.Join_URL__c = null;
                mtg.Start_URL__c = null;
                mtg.Start_Time__c = app.Appointment_Date_Time__c != null ? app.Appointment_Date_Time__c : System.now();
                meetingsToInsert.add(mtg);
            }
        }

        if (!meetingsToInsert.isEmpty()) {
            // Using system mode bypass to insert logging details securely
            Database.insert(meetingsToInsert, AccessLevel.SYSTEM_MODE);
        }
    }
}
