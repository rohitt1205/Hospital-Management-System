public with sharing class AdmissionBillingAction {
    public class Request {
        @InvocableVariable(label='Admission Record Id' required=true)
        public Id recordId;
    }

    @InvocableMethod(label='Create Admission Billing Charge' category='Billing')
    public static void createCharge(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.recordId != null) {
                ids.add(request.recordId);
            }
        }
        AdmissionChargeService.createCharges(ids);
    }
}