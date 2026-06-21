/**
 * Runs HMS_SecurityAuditBatch and reschedules itself every 5 minutes.
 * Salesforce cron does not support sub-hourly recurring expressions, so each
 * run schedules the next one-time job dynamically.
 */
public class HMS_SecurityAuditScheduler implements Schedulable {

    public static final String JOB_NAME = 'HMS Security Audit';

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new HMS_SecurityAuditBatch(), 200);
        reschedule(sc);
    }

    public static String scheduleEveryFiveMinutes() {
        abortExisting();
        return scheduleAt(Datetime.now().addMinutes(5));
    }

    @TestVisible
    private static void reschedule(SchedulableContext sc) {
        if (sc != null) {
            try {
                System.abortJob(sc.getTriggerId());
            } catch (Exception ex) { /* prior job may already be gone */ }
        }
        scheduleAt(Datetime.now().addMinutes(5));
    }

    @TestVisible
    private static String scheduleAt(Datetime runAt) {
        String cron = buildCronExpression(runAt);
        return System.schedule(JOB_NAME, cron, new HMS_SecurityAuditScheduler());
    }

    @TestVisible
    private static String buildCronExpression(Datetime runAt) {
        return String.format(
            '{0} {1} {2} {3} {4} ? {5}',
            new List<String>{
                String.valueOf(runAt.second()),
                String.valueOf(runAt.minute()),
                String.valueOf(runAt.hour()),
                String.valueOf(runAt.day()),
                String.valueOf(runAt.month()),
                String.valueOf(runAt.year())
            }
        );
    }

    private static void abortExisting() {
        for (CronTrigger job : [
            SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :JOB_NAME
        ]) {
            System.abortJob(job.Id);
        }
    }
}