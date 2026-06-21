public without sharing class TakeAdmissionPageController {
    private final Id appointmentId;

    public TakeAdmissionPageController(ApexPages.StandardController controller) {
        appointmentId = controller.getId();
    }

    public PageReference takeAdmission() {
        Id admissionId = TakeAdmissionController.createAdmission(appointmentId);
        PageReference target = new PageReference('/lightning/r/Admission__c/' + admissionId + '/view');
        target.setRedirect(true);
        return target;
    }
}