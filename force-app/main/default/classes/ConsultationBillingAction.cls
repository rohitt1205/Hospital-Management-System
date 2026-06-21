public with sharing class ConsultationBillingAction {
    public class Request {
        @InvocableVariable(label='Appointment Record Id' required=true)
        public Id recordId;
    }

    @InvocableMethod(label='Create Consultation Billing Charge' category='Billing')
    public static void createCharge(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.recordId != null) {
                ids.add(request.recordId);
            }
        }
        ConsultationChargeService.createCharges(ids);
    }
}