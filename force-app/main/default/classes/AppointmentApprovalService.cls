/**
 * Doctor approval workflow for agent-submitted appointment requests.
 * Doctors are resolved via Doctor__c.Staff__c → Staff__c.Salesforce_User__c.
 */
public without sharing class AppointmentApprovalService {

    public class PendingRequest {
        public Id appointmentId;
        public String confirmationNumber;
        public String patientName;
        public String departmentName;
        public Datetime appointmentDateTime;
        public String appointmentTypeLabel;
        public String symptoms;
        public String selectedSlot;
    }

    public static Id resolveDoctorIdForUser(Id userId) {
        if (userId == null) {
            userId = UserInfo.getUserId();
        }
        List<Doctor__c> doctors = [
            SELECT Id
            FROM Doctor__c
            WHERE Active__c = true
              AND Staff__r.Salesforce_User__c = :userId
            LIMIT 1
        ];
        if (doctors.isEmpty()) {
            throw new AppointmentBookingException(
                'No active doctor profile is linked to your Salesforce user. Contact your administrator.'
            );
        }
        return doctors[0].Id;
    }

    public static List<PendingRequest> listPendingRequestsForCurrentDoctor() {
        Id doctorId = resolveDoctorIdForUser(UserInfo.getUserId());
        List<PendingRequest> requests = new List<PendingRequest>();
        for (Appointment__c appt : [
            SELECT Id, Name, Appointment_Date_Time__c, Appointment_Type__c,
                   Symptoms__c, Selected_Slot__c,
                   Patient__r.Name, Department__r.Name
            FROM Appointment__c
            WHERE Doctor__c = :doctorId
              AND Status__c = 'Requested'
            ORDER BY Appointment_Date_Time__c ASC
            LIMIT 100
        ]) {
            PendingRequest request = new PendingRequest();
            request.appointmentId = appt.Id;
            request.confirmationNumber = appt.Name;
            request.patientName = appt.Patient__r != null ? appt.Patient__r.Name : 'Unknown';
            request.departmentName = appt.Department__r != null ? appt.Department__r.Name : '';
            request.appointmentDateTime = appt.Appointment_Date_Time__c;
            request.appointmentTypeLabel = appointmentTypeLabel(appt.Appointment_Type__c);
            request.symptoms = appt.Symptoms__c;
            request.selectedSlot = appt.Selected_Slot__c;
            requests.add(request);
        }
        return requests;
    }

    public static Appointment__c approveRequest(Id appointmentId) {
        Appointment__c appt = loadManagedRequest(appointmentId);
        appt.Status__c = 'Confirmed';
        appt.Rejection_Reason__c = null;
        try {
            update appt;
        } catch (DmlException ex) {
            throw new AppointmentBookingException(formatDmlFailure('approve', ex));
        }
        Appointment__c refreshed = reloadWithPatient(appt.Id);
        AppointmentNotificationHandler.sendApprovalNotification(refreshed);
        return refreshed;
    }

    public static Appointment__c rejectRequest(Id appointmentId, String rejectionReason) {
        Appointment__c appt = loadManagedRequest(appointmentId);
        appt.Status__c = 'Rejected';
        appt.Rejection_Reason__c = String.isBlank(rejectionReason)
            ? 'The doctor is unavailable at the requested time.'
            : rejectionReason.trim();
        try {
            update appt;
        } catch (DmlException ex) {
            throw new AppointmentBookingException(formatDmlFailure('reject', ex));
        }
        Appointment__c refreshed = reloadWithPatient(appt.Id);
        AppointmentNotificationHandler.sendRejectionNotification(refreshed, appt.Rejection_Reason__c);
        return refreshed;
    }

    private static Appointment__c loadManagedRequest(Id appointmentId) {
        if (appointmentId == null) {
            throw new AppointmentBookingException('Please select an appointment request.');
        }
        List<Appointment__c> appointments = [
            SELECT Id, Status__c, Doctor__c
            FROM Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];
        if (appointments.isEmpty()) {
            throw new AppointmentBookingException('The appointment request could not be found.');
        }
        Appointment__c appt = appointments[0];
        if (!HMSPortalContextService.canManageAnyAppointmentRequest()) {
            Id doctorId = resolveDoctorIdForUser(UserInfo.getUserId());
            if (appt.Doctor__c != doctorId) {
                throw new AppointmentBookingException('You can only manage appointment requests assigned to you.');
            }
        }
        if (appt.Status__c != 'Requested') {
            throw new AppointmentBookingException(
                'Only pending requests can be approved or rejected. Current status: ' + appt.Status__c + '.'
            );
        }
        return appt;
    }

    private static Appointment__c reloadWithPatient(Id appointmentId) {
        return [
            SELECT Id, Name, Status__c, Appointment_Date_Time__c, Rejection_Reason__c,
                   Patient__r.Name, Patient__r.Email__c,
                   Doctor__r.Name, Department__r.Name
            FROM Appointment__c
            WHERE Id = :appointmentId
            LIMIT 1
        ];
    }

    private static String formatDmlFailure(String action, DmlException ex) {
        String detail = ex.getNumDml() > 0 ? ex.getDmlMessage(0) : ex.getMessage();
        if (String.isBlank(detail)) {
            return 'Could not ' + action + ' the appointment request. Please try again.';
        }
        return 'Could not ' + action + ' the appointment request: ' + detail;
    }

    private static String appointmentTypeLabel(String apiValue) {
        if (String.isBlank(apiValue)) {
            return 'OPD';
        }
        for (Schema.PicklistEntry entry : Appointment__c.Appointment_Type__c.getDescribe().getPicklistValues()) {
            if (entry.getValue() == apiValue) {
                return entry.getLabel();
            }
        }
        return apiValue;
    }
}