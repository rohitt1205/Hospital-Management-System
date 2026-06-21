public with sharing class MedicineBillingAction {
    public class Request {
        @InvocableVariable(label='Prescription Line Item Record Id' required=true)
        public Id recordId;
    }

    @InvocableMethod(label='Create Medicine Billing Charge' category='Billing')
    public static void createCharge(List<Request> requests) {
        Set<Id> ids = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.recordId != null) {
                ids.add(request.recordId);
            }
        }
        MedicineChargeService.createCharges(ids);
    }
}