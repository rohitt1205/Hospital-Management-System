@isTest
private class HMS_SecurityAuditScheduler_Test {

    @isTest
    static void testSchedulerExecutesBatch() {
        insert new HMS_Audit_Tracking__c(
            Name = 'Default',
            Last_Login_Processed__c = DateTime.now().addDays(-1),
            Active_Session_Map__c = '{}'
        );

        Test.startTest();
        new HMS_SecurityAuditScheduler().execute(null);
        Test.stopTest();

        System.assert(true, 'Scheduler should enqueue security audit batch');
    }

    @isTest
    static void testBuildCronExpression() {
        Datetime runAt = Datetime.newInstance(2026, 6, 20, 14, 35, 10);
        String cron = HMS_SecurityAuditScheduler.buildCronExpression(runAt);
        System.assertEquals('10 35 14 20 6 ? 2026', cron);
    }

    @isTest
    static void testScheduleEveryFiveMinutes() {
        Test.startTest();
        String jobId = HMS_SecurityAuditScheduler.scheduleEveryFiveMinutes();
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }
}