public with sharing class LabBillingAction {
    public class Request {
        @InvocableVariable(label='Lab Result Record Id' required=true)
        public Id recordId;
    }

    @InvocableMethod(label='Create Lab Billing Charge' category='Billing')
    public static void createCharge(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.recordId != null) {
                ids.add(request.recordId);
            }
        }
        LabChargeService.createCharges(ids);
    }
}