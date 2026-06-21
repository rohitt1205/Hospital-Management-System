for (CronTrigger existingJob : [
    SELECT Id
    FROM CronTrigger
    WHERE CronJobDetail.Name LIKE 'HMS Emergency Admission SLA%'
]) {
    System.abortJob(existingJob.Id);
}
