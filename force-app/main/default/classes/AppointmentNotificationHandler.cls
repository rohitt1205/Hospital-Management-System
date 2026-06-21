/**
 * Sends patient email notifications when appointment requests are approved or rejected.
 */
public without sharing class AppointmentNotificationHandler {

    public static void sendApprovalNotification(Appointment__c appt) {
        sendPatientEmail(
            appt,
            'Your appointment request has been confirmed',
            buildApprovalBody(appt)
        );
    }

    public static void sendRejectionNotification(Appointment__c appt, String rejectionReason) {
        sendPatientEmail(
            appt,
            'Update on your appointment request',
            buildRejectionBody(appt, rejectionReason)
        );
    }

    private static void sendPatientEmail(Appointment__c appt, String subject, String htmlBody) {
        if (appt == null || appt.Patient__r == null || String.isBlank(appt.Patient__r.Email__c)) {
            return;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ appt.Patient__r.Email__c });
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setSaveAsActivity(false);

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'AppointmentNotificationHandler: Failed to send email — ' + ex.getMessage());
        }
    }

    private static String buildApprovalBody(Appointment__c appt) {
        String doctorName = appt.Doctor__r != null ? appt.Doctor__r.Name : 'your doctor';
        String departmentName = appt.Department__r != null ? appt.Department__r.Name : 'the hospital';
        return '<html><body style="font-family: Arial, sans-serif;">' +
            '<h2>Appointment Confirmed</h2>' +
            '<p>Your appointment request has been approved.</p>' +
            '<p><strong>Reference:</strong> ' + appt.Name + '<br/>' +
            '<strong>Date &amp; time:</strong> ' + formatDateTime(appt.Appointment_Date_Time__c) + '<br/>' +
            '<strong>Doctor:</strong> Dr. ' + doctorName + '<br/>' +
            '<strong>Department:</strong> ' + departmentName + '</p>' +
            '<p style="color:#666; font-size:0.85em;">Hospital Management System</p>' +
            '</body></html>';
    }

    private static String buildRejectionBody(Appointment__c appt, String rejectionReason) {
        String doctorName = appt.Doctor__r != null ? appt.Doctor__r.Name : 'the requested doctor';
        return '<html><body style="font-family: Arial, sans-serif;">' +
            '<h2>Appointment Request Update</h2>' +
            '<p>Unfortunately, your appointment request (' + appt.Name + ') with Dr. ' +
            doctorName + ' could not be confirmed.</p>' +
            (String.isBlank(rejectionReason)
                ? ''
                : '<p><strong>Reason:</strong> ' + rejectionReason.escapeHtml4() + '</p>') +
            '<p>Please contact the hospital reception to book another time.</p>' +
            '<p style="color:#666; font-size:0.85em;">Hospital Management System</p>' +
            '</body></html>';
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? '' : value.format('dd MMM yyyy, hh:mm a');
    }
}