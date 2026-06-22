@isTest
public class HMS_ZoomServiceTest {

    private class ZoomMockHttpResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            if (req.getEndpoint().contains('zoom.us/oauth/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token": "mock_access_token_12345"}');
            } else if (req.getEndpoint().contains('api.zoom.us/v2/users/')) {
                res.setStatusCode(201);
                res.setBody('{"id": 987654321, "topic": "Test Meeting", "start_time": "2026-06-22T10:00:00Z", "duration": 30, "join_url": "https://zoom.us/j/987654321", "start_url": "https://zoom.us/s/987654321", "status": "waiting"}');
            } else {
                res.setStatusCode(400);
                res.setBody('{"error": "Unknown endpoint"}');
            }
            return res;
        }
    }

    @testSetup
    static void setup() {
        // Setup Zoom Custom Settings
        Zoom_Setting__c settings = new Zoom_Setting__c();
        settings.Account_ID__c = 'test_acc_id';
        settings.Client_ID__c = 'test_client_id';
        settings.Client_Secret__c = 'test_secret';
        settings.Default_Host_Email__c = 'imrohitkumar387@gmail.com';
        insert settings;

        // Create test department
        Department__c dept = new Department__c(Name = 'Test Department', Is_Medical_Department__c = true);
        insert dept;

        // Create test doctor
        Doctor__c doc = new Doctor__c();
        doc.Email__c = 'imrohitkumar387@gmail.com';
        doc.Registration_Number__c = 'DOC123';
        doc.Active__c = true;
        doc.Department__c = dept.Id;
        insert doc;


        // Create test patient
        Patient__c pat = new Patient__c();
        pat.Name = 'John Doe';
        pat.Email__c = 'informrohit1@gmail.com';
        insert pat;


        // Create test online appointment
        Appointment__c app = new Appointment__c();
        app.Patient__c = pat.Id;
        app.Doctor__c = doc.Id;
        app.Appointment_Date_Time__c = DateTime.now().addDays(1);
        app.Appointment_Type__c = 'OPD';
        app.Status__c = 'Confirmed';
        insert app;
    }

    @isTest
    static void testZoomCallouts() {
        Test.setMock(HttpCalloutMock.class, new ZoomMockHttpResponse());

        Test.startTest();
        String token = HMS_ZoomService.getAccessToken();
        System.assertEquals('mock_access_token_12345', token, 'Access token should match mock');

        Map<String, Object> meeting = HMS_ZoomService.createMeeting('imrohitkumar387@gmail.com', 'Test Meeting', DateTime.now(), 30);
        System.assertEquals(987654321, meeting.get('id'), 'Meeting ID should match mock');
        Test.stopTest();
    }

    @isTest
    static void testTriggerAndQueueable() {
        // Retrieve the appointment and verify meeting log has been created via trigger/queueable
        Appointment__c app = [SELECT Id, Appointment_Type__c FROM Appointment__c LIMIT 1];
        app.Appointment_Type__c = 'Teleconsultation';

        Test.setMock(HttpCalloutMock.class, new ZoomMockHttpResponse());

        Test.startTest();
        update app;
        Test.stopTest();


        // Query created meeting log record
        List<Meeting__c> logs = [SELECT Id, Meeting_ID__c, Join_URL__c, Start_URL__c, Status__c FROM Meeting__c WHERE Appointment__c = :app.Id];
        System.assert(!logs.isEmpty(), 'Meeting log should be created');
        System.assertEquals('987654321', logs[0].Meeting_ID__c, 'Meeting ID should be populated');
        System.assertEquals('https://zoom.us/j/987654321', logs[0].Join_URL__c, 'Join URL should be populated');
    }

    @isTest
    static void testControllerDetails() {
        Appointment__c app = [SELECT Id, Appointment_Type__c FROM Appointment__c LIMIT 1];
        app.Appointment_Type__c = 'Teleconsultation';
        update app;

        // Create mock meeting log manually

        Meeting__c mtg = new Meeting__c();
        mtg.Appointment__c = app.Id;
        mtg.Topic__c = 'Teleconsultation';
        mtg.Meeting_ID__c = '987654321';
        mtg.Join_URL__c = 'https://zoom.us/j/987654321';
        mtg.Start_URL__c = 'https://zoom.us/s/987654321';
        mtg.Status__c = 'waiting';
        insert mtg;

        Test.startTest();
        HMS_ZoomController.MeetingDetails details = HMS_ZoomController.getMeetingDetails(app.Id);
        Test.stopTest();

        System.assertNotEquals(null, details, 'Details wrapper should be returned');
        System.assertEquals('Teleconsultation', details.appointmentType, 'Appointment type should match');
        System.assertEquals('https://zoom.us/j/987654321', details.joinUrl, 'Join URL should match');
    }
}
