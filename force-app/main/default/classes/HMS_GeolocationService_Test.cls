@isTest
private class HMS_GeolocationService_Test {

    @isTest
    static void testLookupIpSuccess() {
        HMS_GeolocationService.clearCacheForTest();
        Test.setMock(HttpCalloutMock.class, new HMS_GeolocationMock_Success());

        Test.startTest();
        Map<String, String> geo = HMS_GeolocationService.lookupIp('8.8.8.8');
        Test.stopTest();

        System.assertEquals('India', geo.get('country'));
        System.assertEquals('Bengaluru', geo.get('city'));
    }

    @isTest
    static void testPrivateIpSkipped() {
        Map<String, String> geo = HMS_GeolocationService.lookupIp('127.0.0.1');
        System.assertEquals('', geo.get('country'));
    }
}