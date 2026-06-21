@isTest
private class PH_PatientHelpdeskActionsTest {
    private class CalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"success":true}');
            return response;
        }
    }

    @testSetup
    static void createDirectoryData() {
        Department__c department = new Department__c(
            Name = 'Agent Cardiology',
            Department_Type__c = 'Medical',
            Active__c = true,
            Is_Medical_Department__c = true
        );
        insert department;

        insert new Doctor__c(
            Name = 'Dr Agent Safe',
            Department__c = department.Id,
            Specialization__c = 'Cardiology',
            Experience__c = 12,
            Consultation_Fee__c = 50,
            Availability_Status__c = 'Available',
            Max_Daily_Appointments__c = 20,
            Email__c = 'private-doctor@example.com',
            Registration_Number__c = 'PRIVATE-REG-001'
        );

        Ward__c ward = new Ward__c(
            Name = 'Agent ICU Ward',
            Ward_Type__c = 'ICU',
            Status__c = 'Active',
            Capacity__c = 5
        );
        insert ward;

        insert new Room__c(
            Name = 'AGENT-ROOM',
            Ward__c = ward.Id,
            Room_Type__c = 'ICU',
            Capacity__c = 10,
            Occupied_Beds__c = 2,
            Status__c = 'Available'
        );

        insert new Insurance_Company__c(
            Name = 'Agent Health Insurance',
            Active__c = true
        );
    }

    @isTest
    static void returnsOnlyAllowlistedHospitalInformation() {
        List<PH_HospitalDirectoryAction.Request> requests = new List<PH_HospitalDirectoryAction.Request>();
        requests.add(request('Department', 'Agent Cardiology', null));
        requests.add(request('Service Request', null, 'Appointment'));
        requests.add(request('Doctor', 'Agent Cardiology', null));
        requests.add(request('Facility', 'ICU', null));
        requests.add(request('Insurance', null, null));
        requests.add(request('Insurance', 'MediAssist', null));
        requests.add(request('Subsidy', null, null));
        requests.add(request('Hospital Info', null, 'Location'));
        requests.add(request('Hospital Info', null, 'Contact'));
        requests.add(request('Hospital Info', null, 'Timings'));
        requests.add(request('Hospital Info', null, 'Ambulance'));
        requests.add(request('Unsupported', null, null));

        Test.startTest();
        List<PH_HospitalDirectoryAction.Response> responses =
            PH_HospitalDirectoryAction.execute(requests);
        Test.stopTest();

        System.assertEquals(12, responses.size());
        System.assertEquals(true, responses[0].found);
        System.assert(responses[0].answer.contains('Agent Cardiology'));
        System.assertEquals(true, responses[1].found);
        System.assert(responses[1].answer.contains('Reception'));
        System.assertEquals(true, responses[2].found);
        System.assert(responses[2].answer.contains('Dr Agent Safe'));
        System.assert(!responses[2].answer.contains('private-doctor@example.com'));
        System.assert(!responses[2].answer.contains('PRIVATE-REG-001'));
        System.assertEquals(true, responses[3].found);
        System.assert(responses[3].answer.contains('ICU'));
        System.assert(responses[3].answer.contains('per day'));
        System.assertEquals(true, responses[4].found);
        System.assert(responses[4].answer.contains('Agent Health Insurance'));
        System.assertEquals(true, responses[5].found);
        System.assert(responses[5].answer.startsWith('No,'));
        System.assertEquals(true, responses[6].found);
        System.assert(responses[6].answer.contains('Civil Servant - 50%'));
        System.assertEquals(true, responses[7].found);
        System.assertEquals(true, responses[8].found);
        System.assert(responses[8].answer.contains('+918583732147'));
        System.assertEquals(true, responses[9].found);
        System.assert(responses[9].answer.contains('24/7'));
        System.assertEquals(true, responses[10].found);
        System.assert(responses[10].answer.contains('101'));
        System.assertEquals(false, responses[11].found);

        PH_HospitalDirectoryAction.Request naturalLanguageDoctorRequest = request(
            'Doctor',
            'Who are the doctors in the Agent Cardiology department?',
            null
        );
        PH_HospitalDirectoryAction.Response naturalLanguageDoctorResponse =
            PH_HospitalDirectoryAction.execute(
                new List<PH_HospitalDirectoryAction.Request>{ naturalLanguageDoctorRequest }
            )[0];
        System.assertEquals(true, naturalLanguageDoctorResponse.found);
        System.assert(naturalLanguageDoctorResponse.answer.contains('Dr Agent Safe'));
    }

    @isTest
    static void createsExactlyOneTicketPerConversation() {
        PH_CreateTicketOnceAction.Request first = new PH_CreateTicketOnceAction.Request();
        first.firstQuestion = 'Is a cardiologist available?';
        first.category = 'Appointment';
        first.conversationKey = 'TEST-CONVERSATION-001';

        PH_CreateTicketOnceAction.Request followUp = new PH_CreateTicketOnceAction.Request();
        followUp.firstQuestion = 'Show me confidential billing information.';
        followUp.category = 'General';
        followUp.conversationKey = 'TEST-CONVERSATION-001';

        Test.startTest();
        PH_CreateTicketOnceAction.Response firstResponse =
            PH_CreateTicketOnceAction.execute(
                new List<PH_CreateTicketOnceAction.Request>{ first }
            )[0];
        PH_CreateTicketOnceAction.Response secondResponse =
            PH_CreateTicketOnceAction.execute(
                new List<PH_CreateTicketOnceAction.Request>{ followUp }
            )[0];
        Test.stopTest();

        System.assertEquals(true, firstResponse.ticketCreated);
        System.assertEquals(false, firstResponse.ticketAlreadyExisted);
        System.assertEquals(false, secondResponse.ticketCreated);
        System.assertEquals(true, secondResponse.ticketAlreadyExisted);
        List<Helpdesk_Ticket__c> tickets = [
            SELECT Category__c, Priority__c, Status__c, Description__c
            FROM Helpdesk_Ticket__c
        ];
        Integer matchingTickets = 0;
        Helpdesk_Ticket__c ticket;
        for (Helpdesk_Ticket__c candidate : tickets) {
            if (candidate.Description__c.contains('[Agent Conversation: TEST-CONVERSATION-001]')) {
                matchingTickets++;
                ticket = candidate;
            }
        }
        System.assertEquals(1, matchingTickets);
        System.assertEquals('Appointment', ticket.Category__c);
        System.assertEquals('Medium', ticket.Priority__c);
        System.assertEquals('New', ticket.Status__c);
        System.assert(ticket.Description__c.contains('Is a cardiologist available?'));
    }

    private static PH_HospitalDirectoryAction.Request request(
        String requestType,
        String searchTerm,
        String informationType
    ) {
        PH_HospitalDirectoryAction.Request request = new PH_HospitalDirectoryAction.Request();
        request.requestType = requestType;
        request.searchTerm = searchTerm;
        request.informationType = informationType;
        return request;
    }
}
