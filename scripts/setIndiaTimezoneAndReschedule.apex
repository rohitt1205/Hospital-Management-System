List<User> usersToUpdate = [
    SELECT Id, TimeZoneSidKey
    FROM User
    WHERE Id IN (
        '005g5000008OL8LAAW',
        '005g5000008TopeAAC',
        '005g5000008QriPAAS',
        '005g5000008Qs1lAAC',
        '005g5000008R8WLAA0'
    )
];
for (User userRecord : usersToUpdate) {
    userRecord.TimeZoneSidKey = 'Asia/Kolkata';
}
update usersToUpdate;

for (CronTrigger existingJob : [
    SELECT Id
    FROM CronTrigger
    WHERE CronJobDetail.Name LIKE 'HMS Emergency Admission SLA%'
]) {
    System.abortJob(existingJob.Id);
}

for (Integer minute = 0; minute < 60; minute += 5) {
    String minuteText = minute < 10 ? '0' + String.valueOf(minute) : String.valueOf(minute);
    System.schedule(
        'HMS Emergency Admission SLA ' + minuteText,
        '0 ' + String.valueOf(minute) + ' * * * ?',
        new EmergencyAdmissionSlaScheduler()
    );
}
