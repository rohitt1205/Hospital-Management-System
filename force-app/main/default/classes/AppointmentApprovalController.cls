public with sharing class AppointmentApprovalController {

    @AuraEnabled(cacheable=true)
    public static List<AppointmentApprovalService.PendingRequest> getPendingRequests() {
        return AppointmentApprovalService.listPendingRequestsForCurrentDoctor();
    }

    @AuraEnabled
    public static String approveRequest(Id appointmentId) {
        Appointment__c appt = AppointmentApprovalService.approveRequest(appointmentId);
        return appt.Name + ' has been confirmed.';
    }

    @AuraEnabled
    public static String rejectRequest(Id appointmentId, String rejectionReason) {
        Appointment__c appt = AppointmentApprovalService.rejectRequest(appointmentId, rejectionReason);
        return appt.Name + ' has been rejected.';
    }
}