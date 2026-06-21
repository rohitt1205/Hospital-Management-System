@isTest
private class StatusTransitionValidatorTest {

    @isTest
    static void testValidDonationTransition() {
        // Pledged (1) -> Received (2) should be allowed (forward)
        Donation__c donation = new Donation__c(
            Donor_Name__c = 'John Doe',
            Status__c = 'Pledged'
        );
        insert donation;

        donation.Status__c = 'Received';
        
        Test.startTest();
        Database.SaveResult result = Database.update(donation, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Forward transition from Pledged to Received should be allowed.');
    }

    @isTest
    static void testInvalidDonationTransition() {
        // Received (2) -> Pledged (1) should be blocked (backward)
        Donation__c donation = new Donation__c(
            Donor_Name__c = 'Jane Doe',
            Status__c = 'Received'
        );
        // Bypassing trigger on insert since insert starts at Received
        insert donation;

        donation.Status__c = 'Pledged';
        
        Test.startTest();
        Database.SaveResult result = Database.update(donation, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Backward transition from Received to Pledged should be blocked.');
        System.assert(result.getErrors()[0].getMessage().contains('Status cannot be reverted'), 
            'Expected validation error message, got: ' + result.getErrors()[0].getMessage());
    }

    @isTest
    static void testValidHelpdeskTicketTransition() {
        // New -> In Progress -> Resolved -> Closed
        Helpdesk_Ticket__c ticket = new Helpdesk_Ticket__c(
            Priority__c = 'Medium',
            Status__c = 'New'
        );
        insert ticket;

        ticket.Status__c = 'In Progress';
        update ticket;

        ticket.Status__c = 'Resolved';
        update ticket;

        ticket.Status__c = 'Closed';
        
        Test.startTest();
        Database.SaveResult result = Database.update(ticket, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Linear forward transitions should be allowed.');
    }

    @isTest
    static void testInvalidHelpdeskTicketTransition() {
        Helpdesk_Ticket__c ticket = new Helpdesk_Ticket__c(
            Priority__c = 'High',
            Status__c = 'Resolved'
        );
        insert ticket;

        ticket.Status__c = 'In Progress';
        
        Test.startTest();
        Database.SaveResult result = Database.update(ticket, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Backward transition from Resolved to In Progress should be blocked.');
    }

    @isTest
    static void testCyclicalStatusUnconstrained() {
        // Room status is cyclical (Occupied -> Available) and should NOT be validated
        Ward__c ward = new Ward__c(
            Status__c = 'Active'
        );
        insert ward;

        Room__c room = new Room__c(
            Name = 'Room 999',
            Ward__c = ward.Id,
            Room_Type__c = 'shared non ac room without extra bed',
            Status__c = 'Occupied'
        );
        insert room;

        room.Status__c = 'Available';
        
        Test.startTest();
        Database.SaveResult result = Database.update(room, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Cyclical fields (like Room Status) should not have transition constraints.');
    }

    @isTest
    static void testUnchangedOrBlankStatusAndUnmonitoredField() {
        Helpdesk_Ticket__c ticket = new Helpdesk_Ticket__c(
            Priority__c = 'Medium',
            Status__c = 'New'
        );
        insert ticket;

        // Cover unchanged status scenario (line 53 continue)
        ticket.Description__c = 'Updated Description';
        update ticket;

        // Cover unmonitored field scenario (line 36 return)
        StatusTransitionValidator.validateTransitions(
            new List<Room__c>{new Room__c()},
            new Map<Id, Room__c>(),
            'Room__c',
            'Room_Code__c'
        );
    }
}