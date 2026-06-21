for (CronTrigger existingJob : [
    SELECT Id
    FROM CronTrigger
    WHERE CronJobDetail.Name LIKE 'HMS Emergency Admission SLA%'
]) {
    System.abortJob(existingJob.Id);
}

System.schedule('HMS Emergency Admission SLA 00', '0 0 * * * ?', new EmergencyAdmissionSlaScheduler());
System.schedule('HMS Emergency Admission SLA 15', '0 15 * * * ?', new EmergencyAdmissionSlaScheduler());
System.schedule('HMS Emergency Admission SLA 30', '0 30 * * * ?', new EmergencyAdmissionSlaScheduler());
System.schedule('HMS Emergency Admission SLA 45', '0 45 * * * ?', new EmergencyAdmissionSlaScheduler());
