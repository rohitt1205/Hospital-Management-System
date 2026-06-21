/**
 * RoomCodeGeneratorTest
 * ─────────────────────
 * Test class for RoomCodeGenerator and RoomTrigger.
 * Validates that room codes are auto-generated correctly for every ward type.
 * Tests are resilient to pre-existing Room data in the org.
 */
@IsTest
private class RoomCodeGeneratorTest {

    @TestSetup
    static void setupData() {
        Department__c dept = new Department__c(Name = 'Test Department', Is_Medical_Department__c = true);
        insert dept;

        // Create one ward for each ward type
        List<Ward__c> wards = new List<Ward__c>();
        List<String> wardTypes = new List<String>{
            'ICU', 'OPD', 'General', 'Emergency', 'Private', 'Maternity', 'Pediatric'
        };
        for (String wt : wardTypes) {
            wards.add(new Ward__c(
                Ward_Type__c = wt,
                Capacity__c = 10,
                Status__c = 'Active',
                Department__c = dept.Id
            ));
        }
        insert wards;
    }

    /** Helper: extracts the numeric portion from a room code like GEN001 or GEN-001 */
    private static Integer extractSequence(String roomCode, String prefix) {
        String remainder = roomCode.substring(prefix.length());
        if (remainder.startsWith('-')) {
            remainder = remainder.substring(1);
        }
        return Integer.valueOf(remainder.trim());
    }

    @IsTest
    static void testGeneralWardRoomCode() {
        Ward__c ward = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'General' LIMIT 1];

        Test.startTest();
        Room__c room = new Room__c(Ward__c = ward.Id, Room_Type__c = 'Shared', Capacity__c = 4);
        insert room;
        Test.stopTest();

        room = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room.Id];
        System.assert(room.Name.startsWith('GEN'), 'Name should start with GEN, got: ' + room.Name);
        System.assertEquals(room.Name, room.Room_Code__c, 'Room_Code__c should match Name');
    }

    @IsTest
    static void testICUWardRoomCode() {
        Ward__c ward = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'ICU' LIMIT 1];

        Test.startTest();
        Room__c room = new Room__c(Ward__c = ward.Id, Room_Type__c = 'ICU', Capacity__c = 1);
        insert room;
        Test.stopTest();

        room = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room.Id];
        System.assert(room.Name.startsWith('ICU'), 'Name should start with ICU, got: ' + room.Name);
        System.assertEquals(room.Name, room.Room_Code__c, 'Room_Code__c should match');
    }

    @IsTest
    static void testOPDWardRoomCode() {
        Ward__c ward = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'OPD' LIMIT 1];

        Test.startTest();
        Room__c room = new Room__c(Ward__c = ward.Id, Room_Type__c = 'OPD Cabin', Capacity__c = 2);
        insert room;
        Test.stopTest();

        room = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room.Id];
        System.assert(room.Name.startsWith('OPD'), 'Name should start with OPD, got: ' + room.Name);
    }

    @IsTest
    static void testEmergencyWardRoomCode() {
        Ward__c ward = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'Emergency' LIMIT 1];

        Test.startTest();
        Room__c room = new Room__c(Ward__c = ward.Id, Room_Type__c = 'Shared', Capacity__c = 2);
        insert room;
        Test.stopTest();

        room = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room.Id];
        System.assert(room.Name.startsWith('EMR'), 'Name should start with EMR, got: ' + room.Name);
    }

    @IsTest
    static void testPrivateWardRoomCode() {
        Ward__c ward = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'Private' LIMIT 1];

        Test.startTest();
        Room__c room = new Room__c(Ward__c = ward.Id, Room_Type__c = 'Private', Capacity__c = 1);
        insert room;
        Test.stopTest();

        room = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room.Id];
        System.assert(room.Name.startsWith('PVT'), 'Name should start with PVT, got: ' + room.Name);
    }

    @IsTest
    static void testMaternityWardRoomCode() {
        Ward__c ward = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'Maternity' LIMIT 1];

        Test.startTest();
        Room__c room = new Room__c(Ward__c = ward.Id, Room_Type__c = 'Semi Private', Capacity__c = 3);
        insert room;
        Test.stopTest();

        room = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room.Id];
        System.assert(room.Name.startsWith('MAT'), 'Name should start with MAT, got: ' + room.Name);
    }

    @IsTest
    static void testPediatricWardRoomCode() {
        Ward__c ward = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'Pediatric' LIMIT 1];

        Test.startTest();
        Room__c room = new Room__c(Ward__c = ward.Id, Room_Type__c = 'Shared', Capacity__c = 4);
        insert room;
        Test.stopTest();

        room = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room.Id];
        System.assert(room.Name.startsWith('PED'), 'Name should start with PED, got: ' + room.Name);
    }

    @IsTest
    static void testAutoIncrementSameWardType() {
        Ward__c ward = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'General' LIMIT 1];

        Test.startTest();
        Room__c room1 = new Room__c(Ward__c = ward.Id, Room_Type__c = 'Shared', Capacity__c = 4);
        insert room1;
        Room__c room2 = new Room__c(Ward__c = ward.Id, Room_Type__c = 'Shared', Capacity__c = 4);
        insert room2;
        Room__c room3 = new Room__c(Ward__c = ward.Id, Room_Type__c = 'Shared', Capacity__c = 4);
        insert room3;
        Test.stopTest();

        room1 = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room1.Id];
        room2 = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room2.Id];
        room3 = [SELECT Name, Room_Code__c FROM Room__c WHERE Id = :room3.Id];

        // Verify sequential ordering
        Integer seq1 = extractSequence(room1.Name, 'GEN');
        Integer seq2 = extractSequence(room2.Name, 'GEN');
        Integer seq3 = extractSequence(room3.Name, 'GEN');

        System.assertEquals(seq1 + 1, seq2, 'Second room should be +1 from first');
        System.assertEquals(seq2 + 1, seq3, 'Third room should be +1 from second');
    }

    @IsTest
    static void testBulkInsertSameWardType() {
        Ward__c ward = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'Private' LIMIT 1];

        Test.startTest();
        List<Room__c> rooms = new List<Room__c>();
        for (Integer i = 0; i < 5; i++) {
            rooms.add(new Room__c(Ward__c = ward.Id, Room_Type__c = 'Private', Capacity__c = 1));
        }
        insert rooms;
        Test.stopTest();

        List<Room__c> inserted = [
            SELECT Name, Room_Code__c
            FROM Room__c
            WHERE Id IN :rooms
            ORDER BY Room_Code__c ASC
        ];

        System.assertEquals(5, inserted.size(), 'Should have 5 rooms');
        // Verify all start with PVT and are sequential
        Integer prevSeq = null;
        for (Room__c r : inserted) {
            System.assert(r.Name.startsWith('PVT'), 'Name should start with PVT, got: ' + r.Name);
            Integer seq = extractSequence(r.Name, 'PVT');
            if (prevSeq != null) {
                System.assertEquals(prevSeq + 1, seq, 'Rooms should be sequential');
            }
            prevSeq = seq;
        }
    }

    @IsTest
    static void testMultipleWardTypesInSameBatch() {
        Ward__c genWard = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'General' LIMIT 1];
        Ward__c icuWard = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'ICU' LIMIT 1];

        Test.startTest();
        List<Room__c> rooms = new List<Room__c>{
            new Room__c(Ward__c = genWard.Id, Room_Type__c = 'Shared', Capacity__c = 4),
            new Room__c(Ward__c = icuWard.Id, Room_Type__c = 'ICU', Capacity__c = 1),
            new Room__c(Ward__c = genWard.Id, Room_Type__c = 'Shared', Capacity__c = 4)
        };
        insert rooms;
        Test.stopTest();

        List<Room__c> genRooms = [
            SELECT Name FROM Room__c
            WHERE Id IN :rooms AND Name LIKE 'GEN%' ORDER BY Room_Code__c ASC
        ];
        List<Room__c> icuRooms = [
            SELECT Name FROM Room__c
            WHERE Id IN :rooms AND Name LIKE 'ICU%' ORDER BY Room_Code__c ASC
        ];

        System.assertEquals(2, genRooms.size(), 'Should have 2 GEN rooms');
        System.assertEquals(1, icuRooms.size(), 'Should have 1 ICU room');

        Integer genSeq1 = extractSequence(genRooms[0].Name, 'GEN');
        Integer genSeq2 = extractSequence(genRooms[1].Name, 'GEN');
        System.assert(genSeq2 > genSeq1, 'Second GEN room should have higher sequence than first');
        System.assert(genSeq2 - genSeq1 <= 2, 'GEN room sequences should be close together, got: ' + genSeq1 + ' and ' + genSeq2);
    }

    @IsTest
    static void testIndependentCountersPerWardType() {
        Ward__c genWard = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'General' LIMIT 1];
        Ward__c pvtWard = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'Private' LIMIT 1];
        Ward__c emrWard = [SELECT Id FROM Ward__c WHERE Ward_Type__c = 'Emergency' LIMIT 1];

        Test.startTest();
        Room__c genRoom = new Room__c(Ward__c = genWard.Id, Room_Type__c = 'Shared', Capacity__c = 4);
        Room__c pvtRoom = new Room__c(Ward__c = pvtWard.Id, Room_Type__c = 'Private', Capacity__c = 1);
        Room__c emrRoom = new Room__c(Ward__c = emrWard.Id, Room_Type__c = 'Shared', Capacity__c = 2);
        insert new List<Room__c>{ genRoom, pvtRoom, emrRoom };
        Test.stopTest();

        genRoom = [SELECT Name FROM Room__c WHERE Id = :genRoom.Id];
        pvtRoom = [SELECT Name FROM Room__c WHERE Id = :pvtRoom.Id];
        emrRoom = [SELECT Name FROM Room__c WHERE Id = :emrRoom.Id];

        System.assert(genRoom.Name.startsWith('GEN'), 'General should start with GEN');
        System.assert(pvtRoom.Name.startsWith('PVT'), 'Private should start with PVT');
        System.assert(emrRoom.Name.startsWith('EMR'), 'Emergency should start with EMR');
    }
}