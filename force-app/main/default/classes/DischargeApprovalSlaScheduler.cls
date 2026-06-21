public without sharing class DischargeApprovalSlaScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        DischargeApprovalSlaService.escalateOverdueDischarges();
        
        if (!Test.isRunningTest()) {
            if (context != null) {
                try {
                    System.abortJob(context.getTriggerId());
                } catch (Exception e) {
                    System.debug('Error aborting job: ' + e.getMessage());
                }
            }
            reschedule();
        }
    }

    public static void reschedule() {
        Datetime nextRun = System.now().addMinutes(5);
        String cronStr = nextRun.second() + ' ' + 
                         nextRun.minute() + ' ' + 
                         nextRun.hour() + ' ' + 
                         nextRun.day() + ' ' + 
                         nextRun.month() + ' ? ' + 
                         nextRun.year();
        System.schedule('Discharge SLA Escalate - ' + nextRun.getTime(), cronStr, new DischargeApprovalSlaScheduler());
    }
}