/**
 * AdmissionEmailHandler
 * Invocable Apex called by the "Admission Confirmation Email" Record-Triggered Flow.
 * Sends ward staff alert emails when a new admission is created.
 */
public with sharing class AdmissionEmailHandler {

    public class AdmissionRequest {
        @InvocableVariable(label='Admission Record Id' required=true)
        public Id admissionId;
    }

    @InvocableMethod(
        label       = 'Send Ward Staff Admission Alert'
        description = 'Sends email alerts to ward staff when a new admission is created.'
        category    = 'Admission'
    )
    public static void sendWardStaffAlert(List<AdmissionRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> admissionIds = new Set<Id>();
        for (AdmissionRequest req : requests) {
            if (req.admissionId != null) {
                admissionIds.add(req.admissionId);
            }
        }

        if (admissionIds.isEmpty()) {
            return;
        }

        List<Admission__c> admissions = [
            SELECT  Id,
                    Name,
                    Admission_Type__c,
                    Admission_Date_Time__c,
                    Status__c,
                    Doctor__r.Name,
                    Room__r.Name,
                    Ward__c,
                    Ward__r.Name,
                    Patient__r.Name
            FROM    Admission__c
            WHERE   Id IN :admissionIds
            LIMIT   200
        ];

        if (admissions.isEmpty()) {
            return;
        }

        Set<Id> wardIds = new Set<Id>();
        for (Admission__c adm : admissions) {
            if (adm.Ward__c != null) {
                wardIds.add(adm.Ward__c);
            }
        }

        if (wardIds.isEmpty()) {
            return;
        }

        List<Staff__c> wardStaff = [
            SELECT  Id,
                    Name,
                    Email__c,
                    Department__c
            FROM    Staff__c
            WHERE   Status__c       = 'Active'
            AND     Email__c        != null
            AND     Department__c   IN (
                        SELECT Department__c
                        FROM   Ward__c
                        WHERE  Id IN :wardIds
                    )
            LIMIT   200
        ];

        if (wardStaff.isEmpty()) {
            return;
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Admission__c adm : admissions) {
            for (Staff__c staff : wardStaff) {
                String doctorName  = (adm.Doctor__r != null) ? adm.Doctor__r.Name : 'Not assigned';
                String roomName    = (adm.Room__r   != null) ? adm.Room__r.Name   : 'Not assigned';
                String wardName    = (adm.Ward__r   != null) ? adm.Ward__r.Name   : 'Not specified';
                String patientName = (adm.Patient__r != null) ? adm.Patient__r.Name : 'Unknown';

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ staff.Email__c });
                mail.setSubject('New Admission Alert — ' + adm.Name);
                mail.setHtmlBody(
                    '<html><body style="font-family: Arial, sans-serif;">' +
                    '<h2>New Admission Alert</h2>' +
                    '<p>A new patient admission has been created in your ward.</p>' +
                    '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
                        '<tr><th>Field</th><th>Value</th></tr>' +
                        '<tr><td><strong>Admission #</strong></td><td>' + adm.Name + '</td></tr>' +
                        '<tr><td><strong>Patient</strong></td><td>' + patientName + '</td></tr>' +
                        '<tr><td><strong>Type</strong></td><td>' + adm.Admission_Type__c + '</td></tr>' +
                        '<tr><td><strong>Ward</strong></td><td>' + wardName + '</td></tr>' +
                        '<tr><td><strong>Room</strong></td><td>' + roomName + '</td></tr>' +
                        '<tr><td><strong>Doctor</strong></td><td>' + doctorName + '</td></tr>' +
                        '<tr><td><strong>Date &amp; Time</strong></td><td>' + String.valueOf(adm.Admission_Date_Time__c) + '</td></tr>' +
                    '</table>' +
                    '<p style="color:#666; font-size:0.85em;">Hospital Management System</p>' +
                    '</body></html>'
                );
                mail.setSaveAsActivity(false);
                emails.add(mail);
            }
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR,
                    'AdmissionEmailHandler: Failed to send emails — ' + ex.getMessage());
            }
        }
    }
}