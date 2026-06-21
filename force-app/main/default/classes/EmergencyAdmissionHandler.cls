/**
 * EmergencyAdmissionHandler
 * ─────────────────────────────────────────────────────────────────────────────
 * Invocable Apex called by the "Emergency Admission Processing" Record-Triggered
 * Flow (After Create on Admission__c).
 *
 * Responsibility:
 *   Send an email notification to all active ward staff members associated with
 *   the ward on the newly created Emergency Admission record.
 *
 * Called from Flow element: "Notify Ward Staff via Email"
 * Action API Name         : EmergencyAdmissionHandler
 * ─────────────────────────────────────────────────────────────────────────────
 */
public with sharing class EmergencyAdmissionHandler {

    // ─── Inner class used by the Flow to pass input ───────────────────────────
    public class AdmissionRequest {
        @InvocableVariable(label='Admission Record Id' required=true)
        public Id admissionId;
    }

    // ─── Invocable method: called by Flow ─────────────────────────────────────
    @InvocableMethod(
        label       = 'Send Emergency Admission Notification'
        description = 'Sends email alerts to all ward staff when an Emergency admission is created.'
        category    = 'Admission'
    )
    public static void sendWardNotification(List<AdmissionRequest> requests) {
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

        // ── 1. Fetch the Admission records with related data ───────────────────
        List<Admission__c> admissions = [
            SELECT  Id,
                    Name,
                    Admission_Type__c,
                    Priority__c,
                    Doctor__r.Name,
                    Room__r.Name,
                    Ward__c,
                    Ward__r.Name,
                    Patient__r.Name,
                    Admission_Date_Time__c
            FROM    Admission__c
            WHERE   Id IN :admissionIds
            LIMIT   200
        ];

        if (admissions.isEmpty()) {
            return;
        }

        // ── 2. Collect all Ward Ids for staff query ────────────────────────────
        Set<Id> wardIds = new Set<Id>();
        for (Admission__c adm : admissions) {
            if (adm.Ward__c != null) {
                wardIds.add(adm.Ward__c);
            }
        }

        // ── 3. Query active Staff members in those wards who have an email ─────
        //      Staff__c.Department__c is a Lookup to Department__c.
        //      We match by the Ward on the Admission (via Department link).
        //      Adjust the filter if Staff__c has a direct Ward__c lookup.
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
            return; // No staff to notify
        }

        // ── 4. Build email list ────────────────────────────────────────────────
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Admission__c adm : admissions) {
            for (Staff__c staff : wardStaff) {

                String doctorName = (adm.Doctor__r != null) ? adm.Doctor__r.Name : 'Not yet assigned';
                String roomName   = (adm.Room__r   != null) ? adm.Room__r.Name   : 'Not yet assigned';
                String wardName   = (adm.Ward__r   != null) ? adm.Ward__r.Name   : 'Not specified';
                String patientName= (adm.Patient__r!= null) ? adm.Patient__r.Name: 'Unknown';

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ staff.Email__c });
                mail.setSubject('🚨 EMERGENCY ADMISSION — Immediate Attention Required');
                mail.setHtmlBody(
                    '<html><body style="font-family: Arial, sans-serif;">' +
                    '<h2 style="color:#cc0000;">⚠️ Emergency Admission Alert</h2>' +
                    '<p>An emergency admission has been created and requires your immediate attention.</p>' +
                    '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
                        '<tr><th>Field</th><th>Value</th></tr>' +
                        '<tr><td><strong>Admission #</strong></td><td>' + adm.Name + '</td></tr>' +
                        '<tr><td><strong>Patient</strong></td><td>' + patientName + '</td></tr>' +
                        '<tr><td><strong>Priority</strong></td><td><strong style="color:#cc0000;">CRITICAL</strong></td></tr>' +
                        '<tr><td><strong>Ward</strong></td><td>' + wardName + '</td></tr>' +
                        '<tr><td><strong>Room</strong></td><td>' + roomName + '</td></tr>' +
                        '<tr><td><strong>Assigned Doctor</strong></td><td>' + doctorName + '</td></tr>' +
                        '<tr><td><strong>Date &amp; Time</strong></td><td>' + String.valueOf(adm.Admission_Date_Time__c) + '</td></tr>' +
                    '</table>' +
                    '<br/><p>Please report to the ward immediately.</p>' +
                    '<p style="color:#666; font-size:0.85em;">This is an automated notification from the Hospital Management System.</p>' +
                    '</body></html>'
                );
                mail.setSaveAsActivity(false);
                emails.add(mail);
            }
        }

        // ── 5. Send emails (respect org limits) ───────────────────────────────
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false); // false = partial success allowed
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR,
                    'EmergencyAdmissionHandler: Failed to send emails — ' + ex.getMessage());
            }
        }
    }
}