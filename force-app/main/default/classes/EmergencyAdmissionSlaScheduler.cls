public without sharing class EmergencyAdmissionSlaScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        EmergencyAdmissionSlaService.escalateOverdueAdmissions();
    }
}