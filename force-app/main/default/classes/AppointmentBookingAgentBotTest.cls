@IsTest(SeeAllData=true)
private class AppointmentBookingAgentBotTest {

    @IsTest
    static void testInvocableBookAsAgentBotUser() {
        Test.setMock(HttpCalloutMock.class, new WhatsAppCalloutMock());

        List<User> botUsers = [
            SELECT Id
            FROM User
            WHERE Username LIKE 'hms_patient_assistant%'
            LIMIT 1
        ];
        if (botUsers.isEmpty()) {
            return;
        }

        AppointmentBookingInvocableBook.Request bookReq = new AppointmentBookingInvocableBook.Request();
        bookReq.departmentName = 'Cardiology';
        bookReq.appointmentDate = '2026-08-10';
        bookReq.appointmentTime = 'morning';

        Test.startTest();
        System.runAs(botUsers[0]) {
            List<AppointmentBookingInvocableBook.Response> responses =
                AppointmentBookingInvocableBook.book(
                    new List<AppointmentBookingInvocableBook.Request>{ bookReq }
                );
            System.assertEquals(1, responses.size());
            System.assert(
                responses[0].isSuccess == true,
                'Agent bot booking failed: ' + String.valueOf(responses[0].errorMessage)
            );
            System.assertNotEquals(null, responses[0].appointmentId);
        }
        Test.stopTest();
    }
}