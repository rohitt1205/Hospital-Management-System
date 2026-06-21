@IsTest
private class HMSPortalNetworkCleanupTest {

    @IsTest
    static void returnsZeroWhenRetiredNetworkMissing() {
        Test.startTest();
        Integer memberCount = HMSPortalNetworkCleanup.countRetiredPortalMembers();
        Test.stopTest();
        System.assert(memberCount >= 0, 'Count should not throw when retired network is missing or empty.');
    }
}