/**
 * Asynchronous email notifications for doctors and ward managers.
 * Sends after DML commits via Queueable to avoid trigger governor-limit issues.
 */
public without sharing class HMSNotificationService {

    @TestVisible
    private static final String DEFAULT_WARD_MANAGER_EMAIL = 'prasantnov9@gmail.com';

    /**
     * Org-wide Gmail sender(s) in priority order. Configure in Setup:
     * Organization-Wide Email Addresses → add address → verify via inbox link.
     * Do NOT use Deliverability domain verification for gmail.com.
     */
    @TestVisible
    private static final List<String> SENDER_EMAIL_PRIORITY = new List<String>{
        'prasantnov9@gmail.com',
        'joshiprashant.0911@gmail.com'
    };

    @TestVisible
    private static Id testSenderOrgWideEmailId;

    private static Id cachedSenderOrgWideEmailId;
    private static Boolean senderLookupAttempted = false;

    private static final Set<String> PENDING_APPOINTMENT_STATUSES = new Set<String>{
        'Requested'
    };
    private static final Set<String> PENDING_ADMISSION_STATUSES = new Set<String>{
        'Draft'
    };

    public static void enqueueDoctorAppointmentNotifications(Set<Id> appointmentIds) {
        enqueue(HMSNotificationQueueable.NotificationType.DOCTOR_APPOINTMENT, appointmentIds);
    }

    public static void enqueueDoctorAdmissionNotifications(Set<Id> admissionIds) {
        enqueue(HMSNotificationQueueable.NotificationType.DOCTOR_ADMISSION, admissionIds);
    }

    public static void enqueueWardManagerBedNotifications(Set<Id> bedAllocationIds) {
        enqueue(HMSNotificationQueueable.NotificationType.WARD_BED_ALLOCATION, bedAllocationIds);
    }

    public static void enqueueWardManagerAdmissionBedNotifications(Set<Id> admissionIds) {
        enqueue(HMSNotificationQueueable.NotificationType.WARD_ADMISSION_BED, admissionIds);
    }

    public static void enqueueWardManagerBedNotificationsFromChange(
        List<Bed_Allocation__c> newAllocations,
        Map<Id, Bed_Allocation__c> oldById
    ) {
        if (newAllocations == null || newAllocations.isEmpty()) {
            return;
        }
        Map<Id, Bed_Allocation__c> priorById = oldById == null
            ? new Map<Id, Bed_Allocation__c>()
            : oldById;

        Set<Id> allocationIds = new Set<Id>();
        for (Bed_Allocation__c allocation : newAllocations) {
            if (allocation.Id == null || !isActiveBedAllocation(allocation)) {
                continue;
            }
            Bed_Allocation__c prior = priorById.get(allocation.Id);
            if (prior == null || !isActiveBedAllocation(prior)) {
                allocationIds.add(allocation.Id);
            }
        }
        enqueueWardManagerBedNotifications(allocationIds);
    }

    private static Boolean isActiveBedAllocation(Bed_Allocation__c allocation) {
        if (allocation == null || String.isBlank(allocation.Status__c)) {
            return false;
        }
        String status = allocation.Status__c.trim();
        return status == 'Reserved' || status == 'Occupied' || status == 'Active';
    }

    private static void enqueue(HMSNotificationQueueable.NotificationType type, Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return;
        }
        if (System.isBatch() || System.isFuture()) {
            dispatch(type, recordIds);
            return;
        }
        System.enqueueJob(new HMSNotificationQueueable(type, new List<Id>(recordIds)));
    }

    public static void dispatch(HMSNotificationQueueable.NotificationType type, Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            return;
        }
        switch on type {
            when DOCTOR_APPOINTMENT {
                sendDoctorAppointmentEmails(recordIds);
            }
            when DOCTOR_ADMISSION {
                sendDoctorAdmissionEmails(recordIds);
            }
            when WARD_BED_ALLOCATION {
                sendWardManagerBedEmails(recordIds);
            }
            when WARD_ADMISSION_BED {
                sendWardManagerAdmissionBedEmails(recordIds);
            }
        }
    }

    @TestVisible
    private static Integer testEmailsSentCount = 0;

    public static void sendDoctorAppointmentEmails(Set<Id> appointmentIds) {
        List<Appointment__c> appointments = [
            SELECT Id,
                   Name,
                   Status__c,
                   Doctor__c,
                   Appointment_Date_Time__c,
                   Appointment_Date__c,
                   Appointment_Time__c,
                   Patient__r.Name,
                   Department__r.Name
            FROM Appointment__c
            WHERE Id IN :appointmentIds
              AND Doctor__c != null
            WITH SYSTEM_MODE
        ];
        Map<Id, Doctor__c> doctorsById = loadDoctorsForAppointments(appointments);
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Appointment__c appt : appointments) {
            Doctor__c doctor = doctorsById.get(appt.Doctor__c);
            Messaging.SingleEmailMessage mail = buildDoctorAppointmentEmail(appt, doctor);
            if (mail != null) {
                emails.add(mail);
            }
        }
        sendEmails(emails);
    }

    public static void sendDoctorAdmissionEmails(Set<Id> admissionIds) {
        List<Admission__c> admissions = [
            SELECT Id,
                   Name,
                   Status__c,
                   Doctor__c,
                   Admission_Date_Time__c,
                   Patient__r.Name,
                   Patient_Name__c,
                   Department__r.Name,
                   Ward__r.Name
            FROM Admission__c
            WHERE Id IN :admissionIds
              AND Doctor__c != null
            WITH SYSTEM_MODE
        ];
        Map<Id, Doctor__c> doctorsById = loadDoctorsForAdmissions(admissions);
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Admission__c admission : admissions) {
            Doctor__c doctor = doctorsById.get(admission.Doctor__c);
            Messaging.SingleEmailMessage mail = buildDoctorAdmissionEmail(admission, doctor);
            if (mail != null) {
                emails.add(mail);
            }
        }
        sendEmails(emails);
    }

    public static void sendWardManagerBedEmails(Set<Id> bedAllocationIds) {
        List<Bed_Allocation__c> allocations = [
            SELECT Id,
                   Bed_Number__c,
                   Start_Date_Time__c,
                   Patient__r.Name,
                   Room__r.Name,
                   Room__r.Ward__r.Name,
                   Room__r.Ward__c
            FROM Bed_Allocation__c
            WHERE Id IN :bedAllocationIds
            WITH SYSTEM_MODE
        ];
        if (allocations.isEmpty()) {
            return;
        }

        Set<Id> wardIds = new Set<Id>();
        for (Bed_Allocation__c allocation : allocations) {
            if (allocation.Room__r != null && allocation.Room__r.Ward__c != null) {
                wardIds.add(allocation.Room__r.Ward__c);
            }
        }

        Map<Id, Ward__c> wardsById = wardIds.isEmpty()
            ? new Map<Id, Ward__c>()
            : new Map<Id, Ward__c>([
                SELECT Id, Name
                FROM Ward__c
                WHERE Id IN :wardIds
                WITH SYSTEM_MODE
            ]);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Bed_Allocation__c allocation : allocations) {
            Messaging.SingleEmailMessage mail = buildWardManagerBedEmail(allocation, wardsById);
            if (mail != null) {
                emails.add(mail);
            }
        }
        sendEmails(emails);
    }

    public static void sendWardManagerAdmissionBedEmails(Set<Id> admissionIds) {
        List<Admission__c> admissions = [
            SELECT Id,
                   Name,
                   Admission_Date_Time__c,
                   Patient__r.Name,
                   Ward__c,
                   Ward__r.Name,
                   Bed__r.Name,
                   Room__r.Name,
                   Room__r.Ward__c,
                   Room__r.Ward__r.Name
            FROM Admission__c
            WHERE Id IN :admissionIds
              AND Bed__c != null
            WITH SYSTEM_MODE
        ];
        if (admissions.isEmpty()) {
            return;
        }

        Set<Id> wardIds = new Set<Id>();
        for (Admission__c admission : admissions) {
            if (admission.Ward__c != null) {
                wardIds.add(admission.Ward__c);
            } else if (admission.Room__r != null && admission.Room__r.Ward__c != null) {
                wardIds.add(admission.Room__r.Ward__c);
            }
        }

        Map<Id, Ward__c> wardsById = wardIds.isEmpty()
            ? new Map<Id, Ward__c>()
            : new Map<Id, Ward__c>([
                SELECT Id, Name
                FROM Ward__c
                WHERE Id IN :wardIds
                WITH SYSTEM_MODE
            ]);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Admission__c admission : admissions) {
            Messaging.SingleEmailMessage mail = buildWardManagerAdmissionBedEmail(admission, wardsById);
            if (mail != null) {
                emails.add(mail);
            }
        }
        sendEmails(emails);
    }

    @TestVisible
    private static Map<Id, Doctor__c> loadDoctorsForAppointments(List<Appointment__c> appointments) {
        Set<Id> doctorIds = new Set<Id>();
        for (Appointment__c appt : appointments) {
            if (appt.Doctor__c != null) {
                doctorIds.add(appt.Doctor__c);
            }
        }
        return loadDoctorsById(doctorIds);
    }

    @TestVisible
    private static Map<Id, Doctor__c> loadDoctorsForAdmissions(List<Admission__c> admissions) {
        Set<Id> doctorIds = new Set<Id>();
        for (Admission__c admission : admissions) {
            if (admission.Doctor__c != null) {
                doctorIds.add(admission.Doctor__c);
            }
        }
        return loadDoctorsById(doctorIds);
    }

    private static Map<Id, Doctor__c> loadDoctorsById(Set<Id> doctorIds) {
        if (doctorIds.isEmpty()) {
            return new Map<Id, Doctor__c>();
        }
        return new Map<Id, Doctor__c>([
            SELECT Id, Name, Email__c
            FROM Doctor__c
            WHERE Id IN :doctorIds
            WITH SYSTEM_MODE
        ]);
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildDoctorAppointmentEmail(
        Appointment__c appt,
        Doctor__c doctor
    ) {
        if (appt == null || doctor == null || String.isBlank(doctor.Email__c)) {
            return null;
        }

        String doctorName = nullSafe(doctor.Name);
        String patientName = appt.Patient__r != null ? nullSafe(appt.Patient__r.Name) : 'Unknown';
        String departmentName = appt.Department__r != null ? nullSafe(appt.Department__r.Name) : 'Not specified';
        String whenLabel = formatAppointmentWhen(appt);
        String approvalLine = PENDING_APPOINTMENT_STATUSES.contains(appt.Status__c)
            ? '<p><strong>Action required:</strong> Please review this appointment for approval.</p>'
            : '';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ doctor.Email__c });
        mail.setSubject('New Appointment Assigned — ' + appt.Name);
        mail.setHtmlBody(
            '<html><body style="font-family: Arial, sans-serif;">' +
            '<h2>New Appointment Notification</h2>' +
            '<p>Dear Dr. ' + doctorName.escapeHtml4() + ',</p>' +
            '<p>A new appointment has been scheduled with you.</p>' +
            '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
            '<tr><th align="left">Reference</th><td>' + appt.Name.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Patient</th><td>' + patientName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Date &amp; Time</th><td>' + whenLabel.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Department</th><td>' + departmentName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Status</th><td>' + nullSafe(appt.Status__c).escapeHtml4() + '</td></tr>' +
            '</table>' +
            approvalLine +
            '<p style="color:#666; font-size:0.85em;">Hospital Management System</p>' +
            '</body></html>'
        );
        mail.setSaveAsActivity(false);
        return mail;
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildDoctorAdmissionEmail(
        Admission__c admission,
        Doctor__c doctor
    ) {
        if (admission == null || doctor == null || String.isBlank(doctor.Email__c)) {
            return null;
        }

        String doctorName = nullSafe(doctor.Name);
        String patientName = admission.Patient__r != null
            ? nullSafe(admission.Patient__r.Name)
            : nullSafe(admission.Patient_Name__c);
        String departmentName = admission.Department__r != null
            ? nullSafe(admission.Department__r.Name)
            : 'Not specified';
        String wardName = admission.Ward__r != null ? nullSafe(admission.Ward__r.Name) : 'Not assigned';
        String whenLabel = formatDateTime(admission.Admission_Date_Time__c);
        String approvalLine = PENDING_ADMISSION_STATUSES.contains(admission.Status__c)
            ? '<p><strong>Action required:</strong> Please review this admission for approval.</p>'
            : '';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ doctor.Email__c });
        mail.setSubject('New Admission Assigned — ' + admission.Name);
        mail.setHtmlBody(
            '<html><body style="font-family: Arial, sans-serif;">' +
            '<h2>New Admission Notification</h2>' +
            '<p>Dear Dr. ' + doctorName.escapeHtml4() + ',</p>' +
            '<p>A patient has been admitted under your care.</p>' +
            '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
            '<tr><th align="left">Reference</th><td>' + admission.Name.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Patient</th><td>' + patientName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Admission Date &amp; Time</th><td>' + whenLabel.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Department</th><td>' + departmentName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Ward</th><td>' + wardName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Status</th><td>' + nullSafe(admission.Status__c).escapeHtml4() + '</td></tr>' +
            '</table>' +
            approvalLine +
            '<p style="color:#666; font-size:0.85em;">Hospital Management System</p>' +
            '</body></html>'
        );
        mail.setSaveAsActivity(false);
        return mail;
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildWardManagerBedEmail(
        Bed_Allocation__c allocation,
        Map<Id, Ward__c> wardsById
    ) {
        if (allocation == null) {
            return null;
        }

        Id wardId = allocation.Room__r != null ? allocation.Room__r.Ward__c : null;
        Ward__c ward = wardId != null ? wardsById.get(wardId) : null;
        String wardName = ward != null
            ? nullSafe(ward.Name)
            : (allocation.Room__r != null && allocation.Room__r.Ward__r != null
                ? nullSafe(allocation.Room__r.Ward__r.Name)
                : 'Not specified');
        String wardManagerEmail = resolveWardManagerEmail(ward);
        if (String.isBlank(wardManagerEmail)) {
            return null;
        }

        String patientName = allocation.Patient__r != null ? nullSafe(allocation.Patient__r.Name) : 'Unknown';
        String bedNumber = String.isBlank(allocation.Bed_Number__c) ? 'Not specified' : allocation.Bed_Number__c;
        String whenLabel = formatDateTime(allocation.Start_Date_Time__c);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ wardManagerEmail });
        mail.setSubject('Bed Allocated — Ward ' + wardName);
        mail.setHtmlBody(
            '<html><body style="font-family: Arial, sans-serif;">' +
            '<h2>Bed Allocation Alert</h2>' +
            '<p>A bed has been allocated in your ward.</p>' +
            '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
            '<tr><th align="left">Ward</th><td>' + wardName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Bed Number</th><td>' + bedNumber.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Patient</th><td>' + patientName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Allocation Date &amp; Time</th><td>' + whenLabel.escapeHtml4() + '</td></tr>' +
            '</table>' +
            '<p style="color:#666; font-size:0.85em;">Hospital Management System</p>' +
            '</body></html>'
        );
        mail.setSaveAsActivity(false);
        return mail;
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildWardManagerAdmissionBedEmail(
        Admission__c admission,
        Map<Id, Ward__c> wardsById
    ) {
        if (admission == null) {
            return null;
        }

        Id wardId = admission.Ward__c;
        if (wardId == null && admission.Room__r != null) {
            wardId = admission.Room__r.Ward__c;
        }
        Ward__c ward = wardId != null ? wardsById.get(wardId) : null;
        String wardName = ward != null
            ? nullSafe(ward.Name)
            : (admission.Ward__r != null
                ? nullSafe(admission.Ward__r.Name)
                : (admission.Room__r != null && admission.Room__r.Ward__r != null
                    ? nullSafe(admission.Room__r.Ward__r.Name)
                    : 'Not specified'));
        String wardManagerEmail = resolveWardManagerEmail(ward);
        if (String.isBlank(wardManagerEmail)) {
            return null;
        }

        String patientName = admission.Patient__r != null ? nullSafe(admission.Patient__r.Name) : 'Unknown';
        String bedName = admission.Bed__r != null ? nullSafe(admission.Bed__r.Name) : 'Not specified';
        String whenLabel = formatDateTime(admission.Admission_Date_Time__c);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ wardManagerEmail });
        mail.setSubject('Bed Assigned — Ward ' + wardName);
        mail.setHtmlBody(
            '<html><body style="font-family: Arial, sans-serif;">' +
            '<h2>Bed Assignment Alert</h2>' +
            '<p>A bed has been assigned to a patient in your ward.</p>' +
            '<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;">' +
            '<tr><th align="left">Admission</th><td>' + admission.Name.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Ward</th><td>' + wardName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Bed</th><td>' + bedName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Patient</th><td>' + patientName.escapeHtml4() + '</td></tr>' +
            '<tr><th align="left">Assignment Date &amp; Time</th><td>' + whenLabel.escapeHtml4() + '</td></tr>' +
            '</table>' +
            '<p style="color:#666; font-size:0.85em;">Hospital Management System</p>' +
            '</body></html>'
        );
        mail.setSaveAsActivity(false);
        return mail;
    }

    @TestVisible
    private static String resolveWardManagerEmail(Ward__c ward) {
        if (ward != null) {
            String configuredEmail = readWardManagerEmailField(ward);
            if (String.isNotBlank(configuredEmail)) {
                return configuredEmail;
            }
        }
        return DEFAULT_WARD_MANAGER_EMAIL;
    }

    private static String readWardManagerEmailField(Ward__c ward) {
        if (ward == null) {
            return null;
        }
        Map<String, Schema.SObjectField> wardFields = Ward__c.SObjectType.getDescribe().fields.getMap();
        if (!wardFields.containsKey('ward_manager_email__c')) {
            return null;
        }
        Object configuredEmail = ward.get('Ward_Manager_Email__c');
        return configuredEmail == null ? null : String.valueOf(configuredEmail);
    }

    private static void sendEmails(List<Messaging.SingleEmailMessage> emails) {
        if (emails == null || emails.isEmpty()) {
            return;
        }
        Id senderId = resolveSenderOrgWideEmailId();
        try {
            if (!attemptSend(emails, senderId) && senderId != null) {
                attemptSend(emails, null);
            }
            testEmailsSentCount += emails.size();
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'HMSNotificationService: Failed to send email — ' + ex.getMessage());
        }
    }

    private static Boolean attemptSend(List<Messaging.SingleEmailMessage> emails, Id senderId) {
        for (Messaging.SingleEmailMessage mail : emails) {
            mail.setOrgWideEmailAddressId(null);
            if (senderId != null) {
                mail.setOrgWideEmailAddressId(senderId);
            }
        }
        Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);
        for (Messaging.SendEmailResult result : results) {
            if (!result.isSuccess()) {
                return false;
            }
        }
        return true;
    }

    @TestVisible
    private static Id resolveSenderOrgWideEmailId() {
        if (Test.isRunningTest()) {
            return testSenderOrgWideEmailId;
        }
        if (senderLookupAttempted) {
            return cachedSenderOrgWideEmailId;
        }
        senderLookupAttempted = true;

        Map<String, Id> orgWideByAddress = new Map<String, Id>();
        for (OrgWideEmailAddress orgWideEmail : [
            SELECT Id, Address
            FROM OrgWideEmailAddress
            WHERE Address IN :SENDER_EMAIL_PRIORITY
        ]) {
            orgWideByAddress.put(orgWideEmail.Address.toLowerCase(), orgWideEmail.Id);
        }

        for (String senderEmail : SENDER_EMAIL_PRIORITY) {
            Id orgWideId = orgWideByAddress.get(senderEmail.toLowerCase());
            if (orgWideId != null) {
                cachedSenderOrgWideEmailId = orgWideId;
                return cachedSenderOrgWideEmailId;
            }
        }
        return null;
    }

    private static String formatAppointmentWhen(Appointment__c appt) {
        if (appt.Appointment_Date_Time__c != null) {
            return formatDateTime(appt.Appointment_Date_Time__c);
        }
        if (appt.Appointment_Date__c != null) {
            String datePart = appt.Appointment_Date__c.format();
            if (String.isNotBlank(appt.Appointment_Time__c)) {
                return datePart + ' ' + appt.Appointment_Time__c;
            }
            return datePart;
        }
        return 'Not specified';
    }

    private static String formatDateTime(Datetime value) {
        return value == null ? 'Not specified' : value.format('dd MMM yyyy, hh:mm a');
    }

    private static String nullSafe(String value) {
        return String.isBlank(value) ? 'N/A' : value;
    }
}