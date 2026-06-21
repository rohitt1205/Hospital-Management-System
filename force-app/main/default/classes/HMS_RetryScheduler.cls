/**
 * HMS_RetryScheduler
 * ─────────────────────────────────────────────────────────────────────────────
 * Schedulable class that kicks off HMS_RetryBatch every 15 minutes.
 *
 * To schedule, run in Developer Console > Anonymous Apex:
 *
 *   System.schedule(
 *       'HMS Datadog Retry',
 *       '0 15 * * * ?',
 *       new HMS_RetryScheduler()
 *   );
 *
 * To verify the scheduled job:
 *   SELECT Id, JobType, CronExpression, State, NextFireTime
 *   FROM CronTrigger
 *   WHERE CronJobDetail.Name = 'HMS Datadog Retry'
 *
 * To abort the job:
 *   System.abortJob('<jobId from query above>');
 * ─────────────────────────────────────────────────────────────────────────────
 */
global class HMS_RetryScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new HMS_RetryBatch(), 50);
    }
}