/**
 * Staff/admin operations for the Hospital Patient Portal Experience Cloud site.
 */
public without sharing class HMSPortalAdminController {

    @AuraEnabled
    public static Map<String, Integer> getAdminDashboardSummary() {
        HMSPortalContextService.assertStaffAccess();
        Map<String, Integer> summary = new Map<String, Integer>();
        summary.put('totalPatients', [SELECT COUNT() FROM Patient__c]);
        summary.put('pendingRequests', [
            SELECT COUNT() FROM Appointment__c WHERE Status__c = 'Requested'
        ]);
        summary.put('appointmentsToday', [
            SELECT COUNT() FROM Appointment__c
            WHERE DAY_ONLY(Appointment_Date_Time__c) = TODAY
        ]);
        summary.put('unpaidInvoices', [
            SELECT COUNT() FROM Invoice__c
            WHERE Payment_Status__c IN ('Unpaid', 'Partially Paid', 'Draft')
        ]);
        summary.put('availableBeds', [
            SELECT COUNT() FROM Bed__c WHERE Status__c = 'Available'
        ]);
        summary.put('activeAdmissions', [
            SELECT COUNT() FROM Admission__c WHERE Status__c = 'Admitted'
        ]);
        return summary;
    }

    // ── Patients ──────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<PatientRow> searchPatients(String searchTerm) {
        HMSPortalContextService.assertStaffAccess();
        String term = String.isBlank(searchTerm) ? null : ('%' + String.escapeSingleQuotes(searchTerm.trim()) + '%');

        List<Patient__c> rows;
        if (term == null) {
            rows = [
                SELECT Id, Name, Email__c, Phone__c, Status__c, Gender__c,
                       Blood_Group__c, Date_of_Birth__c, Portal_User__c,
                       Patient_Approval_Status__c, CreatedDate
                FROM Patient__c
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
        } else {
            rows = [
                SELECT Id, Name, Email__c, Phone__c, Status__c, Gender__c,
                       Blood_Group__c, Date_of_Birth__c, Portal_User__c,
                       Patient_Approval_Status__c, CreatedDate
                FROM Patient__c
                WHERE Name LIKE :term
                   OR Email__c LIKE :term
                   OR Phone__c LIKE :term
                ORDER BY Name ASC
                LIMIT 50
            ];
        }
        return wrapPatients(rows);
    }

    @AuraEnabled
    public static PatientRow savePatient(String patientJson) {
        HMSPortalContextService.assertStaffAccess();
        if (String.isBlank(patientJson)) {
            throw new AuraHandledException('Patient details are required.');
        }

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(patientJson);
        Patient__c patient = new Patient__c();
        if (data.containsKey('id') && data.get('id') != null) {
            patient.Id = (Id) String.valueOf(data.get('id'));
        }

        patient.Name       = stringValue(data, 'name');
        patient.Email__c     = stringValue(data, 'email');
        patient.Phone__c     = stringValue(data, 'phone');
        patient.Status__c    = stringValue(data, 'status', 'Active');
        patient.Gender__c    = stringValue(data, 'gender');
        patient.Blood_Group__c = stringValue(data, 'bloodGroup');
        patient.Address__c   = stringValue(data, 'address');
        patient.Aadhaar_Last_4__c = stringValue(data, 'aadhaarLast4');
        patient.Patient_Approval_Status__c = stringValue(data, 'approvalStatus', 'Approved');

        if (String.isBlank(patient.Name)) {
            throw new AuraHandledException('Patient name is required.');
        }

        if (patient.Id == null) {
            insert patient;
        } else {
            update patient;
        }

        patient = [
            SELECT Id, Name, Email__c, Phone__c, Status__c, Gender__c,
                   Blood_Group__c, Date_of_Birth__c, Portal_User__c,
                   Patient_Approval_Status__c, CreatedDate
            FROM Patient__c
            WHERE Id = :patient.Id
            LIMIT 1
        ];
        return new PatientRow(patient);
    }

    // ── Appointments ──────────────────────────────────────────────────────────

    @AuraEnabled
    public static List<AppointmentRow> listAppointments(String statusFilter) {
        HMSPortalContextService.assertStaffAccess();
        String soql = 'SELECT Id, Name, Status__c, Appointment_Date_Time__c, Appointment_Type__c,' +
            ' Patient__r.Name, Doctor__r.Name, Department__r.Name, Priority__c, Symptoms__c' +
            ' FROM Appointment__c';
        if (String.isBlank(statusFilter) || statusFilter == 'All') {
            soql += ' WHERE Status__c != \'Requested\'';
        } else {
            soql += ' WHERE Status__c = :statusFilter';
        }
        soql += ' ORDER BY Appointment_Date_Time__c DESC NULLS LAST LIMIT 100';

        List<AppointmentRow> result = new List<AppointmentRow>();
        for (Appointment__c appt : Database.query(soql)) {
            result.add(new AppointmentRow(appt));
        }
        return result;
    }

    @AuraEnabled
    public static String updateAppointmentStatus(Id appointmentId, String newStatus) {
        HMSPortalContextService.assertStaffAccess();
        if (appointmentId == null || String.isBlank(newStatus)) {
            throw new AuraHandledException('Appointment and status are required.');
        }
        Appointment__c appt = [
            SELECT Id, Name, Status__c
            FROM Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];
        appt.Status__c = newStatus;
        update appt;
        return appt.Name + ' updated to ' + newStatus + '.';
    }

    @AuraEnabled
    public static List<PendingRequestRow> listPendingAppointmentRequests() {
        HMSPortalContextService.assertStaffAccess();
        List<PendingRequestRow> result = new List<PendingRequestRow>();
        for (Appointment__c appt : [
            SELECT Id, Name, Appointment_Date_Time__c, Appointment_Type__c,
                   Symptoms__c,
                   Patient__r.Name, Department__r.Name, Doctor__r.Name
            FROM Appointment__c
            WHERE Status__c = 'Requested'
            ORDER BY Appointment_Date_Time__c ASC
            LIMIT 100
        ]) {
            result.add(new PendingRequestRow(appt));
        }
        return result;
    }

    @AuraEnabled
    public static String approveAppointmentRequest(Id appointmentId) {
        HMSPortalContextService.assertStaffAccess();
        Appointment__c appt = AppointmentApprovalService.approveRequest(appointmentId);
        return appt.Name + ' has been confirmed.';
    }

    @AuraEnabled
    public static String rejectAppointmentRequest(Id appointmentId, String rejectionReason) {
        HMSPortalContextService.assertStaffAccess();
        Appointment__c appt = AppointmentApprovalService.rejectRequest(appointmentId, rejectionReason);
        return appt.Name + ' has been rejected.';
    }

    // ── Billing ───────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<InvoiceRow> listRecentInvoices() {
        HMSPortalContextService.assertStaffAccess();
        List<InvoiceRow> result = new List<InvoiceRow>();
        for (Invoice__c inv : [
            SELECT Id, Name, Net_Payable__c, Payment_Status__c, Invoice_Date__c,
                   Patient__r.Name, Admission__r.Name
            FROM Invoice__c
            ORDER BY Invoice_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 50
        ]) {
            result.add(new InvoiceRow(inv));
        }
        return result;
    }

    @AuraEnabled
    public static String updateInvoicePaymentStatus(Id invoiceId, String paymentStatus) {
        HMSPortalContextService.assertStaffAccess();
        Invoice__c inv = [
            SELECT Id, Name, Payment_Status__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];
        inv.Payment_Status__c = paymentStatus;
        update inv;
        return inv.Name + ' marked as ' + paymentStatus + '.';
    }

    // ── Wrappers ──────────────────────────────────────────────────────────────

    public class PatientRow {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String status;
        @AuraEnabled public String gender;
        @AuraEnabled public String bloodGroup;
        @AuraEnabled public String portalUserId;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public Datetime createdDate;

        public PatientRow(Patient__c p) {
            id             = p.Id;
            name           = p.Name;
            email          = p.Email__c;
            phone          = p.Phone__c;
            status         = p.Status__c;
            gender         = p.Gender__c;
            bloodGroup     = p.Blood_Group__c;
            portalUserId   = p.Portal_User__c;
            approvalStatus = p.Patient_Approval_Status__c;
            createdDate    = p.CreatedDate;
        }
    }

    public class AppointmentRow {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime appointmentDateTime;
        @AuraEnabled public String appointmentType;
        @AuraEnabled public String patientName;
        @AuraEnabled public String doctorName;
        @AuraEnabled public String departmentName;
        @AuraEnabled public String priority;
        @AuraEnabled public String symptoms;

        public AppointmentRow(Appointment__c a) {
            id                  = a.Id;
            name                = a.Name;
            status              = a.Status__c;
            appointmentDateTime = a.Appointment_Date_Time__c;
            appointmentType     = a.Appointment_Type__c;
            patientName         = a.Patient__r != null ? a.Patient__r.Name : '—';
            doctorName          = a.Doctor__r  != null ? a.Doctor__r.Name  : '—';
            departmentName      = a.Department__r != null ? a.Department__r.Name : '—';
            priority            = a.Priority__c;
            symptoms            = a.Symptoms__c;
        }
    }

    public class PendingRequestRow {
        @AuraEnabled public String appointmentId;
        @AuraEnabled public String confirmationNumber;
        @AuraEnabled public String patientName;
        @AuraEnabled public String departmentName;
        @AuraEnabled public String doctorName;
        @AuraEnabled public Datetime appointmentDateTime;
        @AuraEnabled public String appointmentType;
        @AuraEnabled public String symptoms;

        public PendingRequestRow(Appointment__c a) {
            appointmentId       = a.Id;
            confirmationNumber  = a.Name;
            patientName         = a.Patient__r != null ? a.Patient__r.Name : 'Unknown';
            departmentName      = a.Department__r != null ? a.Department__r.Name : '';
            doctorName          = a.Doctor__r != null ? a.Doctor__r.Name : '';
            appointmentDateTime = a.Appointment_Date_Time__c;
            appointmentType     = a.Appointment_Type__c;
            symptoms            = a.Symptoms__c;
        }
    }

    public class InvoiceRow {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal netPayable;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public Date invoiceDate;
        @AuraEnabled public String patientName;
        @AuraEnabled public String admissionName;

        public InvoiceRow(Invoice__c inv) {
            id            = inv.Id;
            name          = inv.Name;
            netPayable    = inv.Net_Payable__c;
            paymentStatus = inv.Payment_Status__c;
            invoiceDate   = inv.Invoice_Date__c;
            patientName   = inv.Patient__r != null ? inv.Patient__r.Name : '—';
            admissionName = inv.Admission__r != null ? inv.Admission__r.Name : '—';
        }
    }

    private static List<PatientRow> wrapPatients(List<Patient__c> rows) {
        List<PatientRow> result = new List<PatientRow>();
        for (Patient__c p : rows) {
            result.add(new PatientRow(p));
        }
        return result;
    }

    private static String stringValue(Map<String, Object> data, String key) {
        return stringValue(data, key, null);
    }

    private static String stringValue(Map<String, Object> data, String key, String defaultValue) {
        if (!data.containsKey(key) || data.get(key) == null) {
            return defaultValue;
        }
        String value = String.valueOf(data.get(key)).trim();
        return String.isBlank(value) ? defaultValue : value;
    }
}