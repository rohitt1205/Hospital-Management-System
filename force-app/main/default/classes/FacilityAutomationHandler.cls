public without sharing class FacilityAutomationHandler {
    public static void beforeRoomSave(List<Room__c> rooms) {
        for (Room__c room : rooms) {
            if (room.Capacity__c == null) {
                room.Capacity__c = 20;
            }
            if (room.Occupied_Beds__c == null) {
                room.Occupied_Beds__c = 0;
            }
            room.Price__c = roomPrice(room.Room_Type__c);
        }
    }

    public static void beforeBedSave(List<Bed__c> beds) {
        Set<Id> roomIds = new Set<Id>();
        for (Bed__c bed : beds) {
            if (bed.Room__c != null) {
                roomIds.add(bed.Room__c);
            }
        }

        Map<Id, Room__c> rooms = roomIds.isEmpty()
            ? new Map<Id, Room__c>()
            : new Map<Id, Room__c>([
                SELECT Id, Name, Room_Type__c, Price__c
                FROM Room__c
                WHERE Id IN :roomIds
            ]);

        for (Bed__c bed : beds) {
            Room__c room = rooms.get(bed.Room__c);
            if (room != null) {
                bed.Daily_Rate__c = room.Price__c == null ? roomPrice(room.Room_Type__c) : room.Price__c;
                if (String.isBlank(bed.Name)) {
                    bed.Name = room.Name + '-BED';
                }
            }
            if (String.isBlank(bed.Status__c)) {
                bed.Status__c = 'Available';
            }
        }
    }

    public static void afterBedAllocationSave(List<Bed_Allocation__c> allocations) {
        Set<Id> bedIds = new Set<Id>();
        for (Bed_Allocation__c allocation : allocations) {
            if (allocation.Bed__c != null) {
                bedIds.add(allocation.Bed__c);
            }
        }
        if (bedIds.isEmpty()) {
            return;
        }

        Map<Id, Bed__c> beds = new Map<Id, Bed__c>([
            SELECT Id, Room__c
            FROM Bed__c
            WHERE Id IN :bedIds
        ]);

        List<Bed__c> bedsToUpdate = new List<Bed__c>();
        for (Bed_Allocation__c allocation : allocations) {
            if (allocation.Bed__c == null) {
                continue;
            }
            String status = allocation.Status__c == 'Active' ? 'Occupied' : 'Available';
            bedsToUpdate.add(new Bed__c(Id = allocation.Bed__c, Status__c = status));
        }
        if (!bedsToUpdate.isEmpty()) {
            update bedsToUpdate;
        }

        Set<Id> roomIds = new Set<Id>();
        for (Bed__c bed : beds.values()) {
            if (bed.Room__c != null) {
                roomIds.add(bed.Room__c);
            }
        }
        refreshRoomOccupancy(roomIds);
    }

    public static void beforeBedAllocationSave(List<Bed_Allocation__c> allocations, Map<Id, Bed_Allocation__c> oldMap) {
        Set<Id> roomIds = new Set<Id>();
        Set<Id> admissionIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        Set<String> requestedRoomTypes = new Set<String>();
        for (Bed_Allocation__c allocation : allocations) {
            if (allocation.Admission__c != null) {
                admissionIds.add(allocation.Admission__c);
            }
            if (allocation.Patient__c != null) {
                patientIds.add(allocation.Patient__c);
            }
            if (allocation.Room__c != null) {
                roomIds.add(allocation.Room__c);
            } else if (!String.isBlank(allocation.Room_Type__c)) {
                requestedRoomTypes.add(allocation.Room_Type__c);
            }
        }
        if (roomIds.isEmpty() && requestedRoomTypes.isEmpty()) {
            return;
        }

        Set<Id> currentIds = new Set<Id>();
        for (Bed_Allocation__c allocation : allocations) {
            if (allocation.Id != null) {
                currentIds.add(allocation.Id);
            }
        }

        Map<Id, Room__c> rooms = new Map<Id, Room__c>();
        if (!roomIds.isEmpty()) {
            rooms.putAll(new Map<Id, Room__c>([
                SELECT Id, Capacity__c, Occupied_Beds__c, Price__c, Room_Type__c
                FROM Room__c
                WHERE Id IN :roomIds
                FOR UPDATE
            ]));
        }

        Map<String, List<Room__c>> availableRoomsByType = new Map<String, List<Room__c>>();
        if (!requestedRoomTypes.isEmpty()) {
            for (Room__c room : [
                SELECT Id, Capacity__c, Occupied_Beds__c, Price__c, Room_Type__c
                FROM Room__c
                WHERE Room_Type__c IN :requestedRoomTypes
                ORDER BY Occupied_Beds__c ASC, CreatedDate ASC
            ]) {
                rooms.put(room.Id, room);
                String key = normalize(room.Room_Type__c);
                if (!availableRoomsByType.containsKey(key)) {
                    availableRoomsByType.put(key, new List<Room__c>());
                }
                availableRoomsByType.get(key).add(room);
            }
        }

        Map<Id, Admission__c> admissionsById = new Map<Id, Admission__c>();
        Map<Id, Admission__c> latestAdmissionByPatient = new Map<Id, Admission__c>();
        if (!admissionIds.isEmpty()) {
            admissionsById.putAll(new Map<Id, Admission__c>([
                SELECT Id, Patient__c, Admission_Date_Time__c
                FROM Admission__c
                WHERE Id IN :admissionIds
            ]));
        }
        if (!patientIds.isEmpty()) {
            for (Admission__c admission : [
                SELECT Id, Patient__c, Admission_Date_Time__c, CreatedDate
                FROM Admission__c
                WHERE Patient__c IN :patientIds
                ORDER BY Admission_Date_Time__c DESC NULLS LAST, CreatedDate DESC
            ]) {
                if (admission.Patient__c != null && !latestAdmissionByPatient.containsKey(admission.Patient__c)) {
                    latestAdmissionByPatient.put(admission.Patient__c, admission);
                }
                admissionsById.put(admission.Id, admission);
            }
        }

        // Resolve the patient from an explicitly selected admission before
        // enforcing the one-active-bed-per-patient rule.
        for (Bed_Allocation__c allocation : allocations) {
            if (allocation.Patient__c == null && allocation.Admission__c != null) {
                Admission__c admission = admissionsById.get(allocation.Admission__c);
                if (admission != null && admission.Patient__c != null) {
                    allocation.Patient__c = admission.Patient__c;
                    patientIds.add(admission.Patient__c);
                }
            }
        }

        Set<Id> patientsWithActiveAllocations = new Set<Id>();
        if (!patientIds.isEmpty()) {
            // Lock patient rows so concurrent allocations in different rooms
            // cannot both pass validation for the same patient.
            List<Patient__c> lockedPatients = [
                SELECT Id FROM Patient__c WHERE Id IN :patientIds FOR UPDATE
            ];
            for (Bed_Allocation__c existing : [
                SELECT Id, Patient__c
                FROM Bed_Allocation__c
                WHERE Patient__c IN :patientIds
                AND Status__c IN ('Reserved', 'Occupied')
            ]) {
                if (!currentIds.contains(existing.Id) && existing.Patient__c != null) {
                    patientsWithActiveAllocations.add(existing.Patient__c);
                }
            }
        }

        Map<String, Id> activeBedKeys = new Map<String, Id>();
        if (!rooms.isEmpty()) {
            Set<Id> allocationRoomIds = new Set<Id>();
            allocationRoomIds.addAll(rooms.keySet());
            for (Bed_Allocation__c existing : [
                SELECT Id, Room__c, Bed_Number__c
                FROM Bed_Allocation__c
                WHERE Room__c IN :allocationRoomIds
                AND Status__c IN ('Reserved', 'Occupied')
            ]) {
                if (!currentIds.contains(existing.Id) && existing.Room__c != null && !String.isBlank(existing.Bed_Number__c)) {
                    activeBedKeys.put(allocationKey(existing.Room__c, existing.Bed_Number__c), existing.Id);
                }
            }
        }

        Map<Id, Integer> incomingCapacityDemandByRoom = new Map<Id, Integer>();
        Set<String> incomingKeys = new Set<String>();
        Set<Id> incomingPatientIds = new Set<Id>();
        for (Bed_Allocation__c allocation : allocations) {
            if (allocation.Room__c == null) {
                assignRoomFromType(allocation, availableRoomsByType, incomingCapacityDemandByRoom, activeBedKeys, incomingKeys);
            }

            if (allocation.Room__c == null) {
                allocation.addError('Select a room type with available capacity before allocating a bed.');
                continue;
            }

            Room__c room = rooms.get(allocation.Room__c);
            if (room == null) {
                allocation.addError('Selected room is not available.');
                continue;
            }

            if (String.isBlank(allocation.Status__c)) {
                allocation.Status__c = 'Reserved';
            }
            if (allocation.Start_Date_Time__c == null) {
                allocation.Start_Date_Time__c = System.now();
            }
            validateBedAllocationSchedule(allocation, admissionsById, latestAdmissionByPatient);
            allocation.Daily_Rate__c = room.Price__c == null ? roomPrice(room.Room_Type__c) : room.Price__c;
            if (allocation.Room__c != null) {
                allocation.Room_Type__c = null;
            }

            if (!isActiveAllocation(allocation)) {
                continue;
            }

            if (allocation.Patient__c != null) {
                if (patientsWithActiveAllocations.contains(allocation.Patient__c)
                    || incomingPatientIds.contains(allocation.Patient__c)) {
                    allocation.addError('This patient already has an active bed allocation. Release or cancel it before assigning another bed.');
                }
                incomingPatientIds.add(allocation.Patient__c);
            }

            if (requiresAvailableCapacity(allocation, oldMap)) {
                Integer activeCount = incomingCapacityDemandByRoom.containsKey(allocation.Room__c)
                    ? incomingCapacityDemandByRoom.get(allocation.Room__c)
                    : 0;
                incomingCapacityDemandByRoom.put(allocation.Room__c, activeCount + 1);
            }

            if (!String.isBlank(allocation.Bed_Number__c)) {
                Integer bedNumber = parseBedNumber(allocation.Bed_Number__c);
                Integer roomCapacity = room.Capacity__c == null ? 0 : Integer.valueOf(room.Capacity__c);
                if (bedNumber == null || bedNumber < 1) {
                    allocation.addError('Enter a valid numeric bed number.');
                } else if (roomCapacity > 0 && bedNumber > roomCapacity) {
                    allocation.addError('Bed number cannot be greater than the room bed capacity.');
                }

                String key = allocationKey(allocation.Room__c, allocation.Bed_Number__c);
                if (incomingKeys.contains(key) || activeBedKeys.containsKey(key)) {
                    allocation.addError('This bed number is already allocated for the selected room.');
                }
                incomingKeys.add(key);
            }
        }

        for (Id roomId : incomingCapacityDemandByRoom.keySet()) {
            Room__c room = rooms.get(roomId);
            Integer incomingCount = incomingCapacityDemandByRoom.get(roomId);
            Integer capacity = room.Capacity__c == null ? 0 : Integer.valueOf(room.Capacity__c);
            Integer occupied = room.Occupied_Beds__c == null ? 0 : Integer.valueOf(room.Occupied_Beds__c);
            if (capacity > 0 && occupied + incomingCount > capacity) {
                for (Bed_Allocation__c allocation : allocations) {
                    if (allocation.Room__c == roomId && isActiveAllocation(allocation) && requiresAvailableCapacity(allocation, oldMap)) {
                        allocation.addError('Room capacity is full. Select another room or release an existing allocation.');
                    }
                }
            }
        }
    }

    private static void validateBedAllocationSchedule(
        Bed_Allocation__c allocation,
        Map<Id, Admission__c> admissionsById,
        Map<Id, Admission__c> latestAdmissionByPatient
    ) {
        if (!isActiveAllocation(allocation)) {
            return;
        }

        if (allocation.Start_Date_Time__c != null && allocation.Start_Date_Time__c > System.now().addDays(30)) {
            allocation.Start_Date_Time__c.addError('Bed allocation start date and time cannot be more than 30 days from today.');
        }

        Admission__c admission;
        if (allocation.Admission__c != null) {
            admission = admissionsById.get(allocation.Admission__c);
        } else if (allocation.Patient__c != null) {
            admission = latestAdmissionByPatient.get(allocation.Patient__c);
            if (admission != null) {
                allocation.Admission__c = admission.Id;
            }
        }

        if (admission == null) {
            if (allocation.Patient__c != null || allocation.Admission__c != null) {
                allocation.Start_Date_Time__c.addError('Create or select an admission before allocating a bed.');
            }
            return;
        }

        if (allocation.Patient__c == null && admission.Patient__c != null) {
            allocation.Patient__c = admission.Patient__c;
        }

        if (admission.Admission_Date_Time__c != null
            && allocation.Start_Date_Time__c != null
            && allocation.Start_Date_Time__c < admission.Admission_Date_Time__c) {
            allocation.Start_Date_Time__c.addError('Bed allocation start date and time cannot be before the patient admission date and time.');
        }
    }

    public static void afterBedAllocationChange(List<Bed_Allocation__c> newAllocations, List<Bed_Allocation__c> oldAllocations) {
        Map<Id, Integer> occupiedDeltaByRoom = new Map<Id, Integer>();
        Map<Id, Bed_Allocation__c> oldById = new Map<Id, Bed_Allocation__c>();
        if (oldAllocations != null) {
            for (Bed_Allocation__c oldAllocation : oldAllocations) {
                if (oldAllocation.Id != null) {
                    oldById.put(oldAllocation.Id, oldAllocation);
                }
            }
        }

        if (newAllocations != null) {
            for (Bed_Allocation__c allocation : newAllocations) {
                Bed_Allocation__c oldAllocation = oldById.get(allocation.Id);
                if (oldAllocation != null && isActiveAllocation(oldAllocation)
                    && (!isActiveAllocation(allocation) || oldAllocation.Room__c != allocation.Room__c)) {
                    addRoomDelta(occupiedDeltaByRoom, oldAllocation.Room__c, -1);
                }
                if (isActiveAllocation(allocation)
                    && (oldAllocation == null || !isActiveAllocation(oldAllocation) || oldAllocation.Room__c != allocation.Room__c)) {
                    addRoomDelta(occupiedDeltaByRoom, allocation.Room__c, 1);
                }
            }
        }
        if (oldAllocations != null) {
            for (Bed_Allocation__c allocation : oldAllocations) {
                if ((newAllocations == null || !oldById.isEmpty()) && newAllocations == null && isActiveAllocation(allocation)) {
                    addRoomDelta(occupiedDeltaByRoom, allocation.Room__c, -1);
                }
            }
        }

        applyRoomDeltas(occupiedDeltaByRoom);
    }

    public static void refreshRoomOccupancy(Set<Id> roomIds) {
        if (roomIds == null || roomIds.isEmpty()) {
            return;
        }
        Map<Id, Integer> occupiedByRoom = new Map<Id, Integer>();
        for (AggregateResult result : [
            SELECT Room__c roomId, COUNT(Id) total
            FROM Bed_Allocation__c
            WHERE Room__c IN :roomIds
            AND Status__c IN ('Reserved', 'Occupied')
            GROUP BY Room__c
        ]) {
            occupiedByRoom.put((Id) result.get('roomId'), (Integer) result.get('total'));
        }

        List<Room__c> roomsToUpdate = new List<Room__c>();
        for (Id roomId : roomIds) {
            Integer occupied = occupiedByRoom.containsKey(roomId) ? occupiedByRoom.get(roomId) : 0;
            roomsToUpdate.add(new Room__c(Id = roomId, Occupied_Beds__c = occupied));
        }
        if (!roomsToUpdate.isEmpty()) {
            update roomsToUpdate;
        }
    }

    private static Map<Id, Integer> activeAllocationCounts(Set<Id> roomIds, Set<Id> excludedAllocationIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult result : [
            SELECT Room__c roomId, COUNT(Id) total
            FROM Bed_Allocation__c
            WHERE Room__c IN :roomIds
            AND Status__c IN ('Reserved', 'Occupied')
            AND Id NOT IN :excludedAllocationIds
            GROUP BY Room__c
        ]) {
            counts.put((Id) result.get('roomId'), (Integer) result.get('total'));
        }
        return counts;
    }

    private static Boolean isActiveAllocation(Bed_Allocation__c allocation) {
        return allocation != null
            && allocation.Room__c != null
            && (allocation.Status__c == 'Reserved' || allocation.Status__c == 'Occupied');
    }

    private static Boolean requiresAvailableCapacity(Bed_Allocation__c allocation, Map<Id, Bed_Allocation__c> oldMap) {
        if (!isActiveAllocation(allocation)) {
            return false;
        }
        if (oldMap == null || allocation.Id == null || !oldMap.containsKey(allocation.Id)) {
            return true;
        }

        Bed_Allocation__c oldAllocation = oldMap.get(allocation.Id);
        return !isActiveAllocation(oldAllocation) || oldAllocation.Room__c != allocation.Room__c;
    }

    private static void addRoomDelta(Map<Id, Integer> deltas, Id roomId, Integer delta) {
        if (roomId == null || delta == null || delta == 0) {
            return;
        }
        Integer current = deltas.containsKey(roomId) ? deltas.get(roomId) : 0;
        deltas.put(roomId, current + delta);
    }

    private static void applyRoomDeltas(Map<Id, Integer> occupiedDeltaByRoom) {
        Set<Id> roomIds = new Set<Id>();
        roomIds.addAll(occupiedDeltaByRoom.keySet());
        if (roomIds.isEmpty()) {
            return;
        }

        List<Room__c> roomsToUpdate = new List<Room__c>();
        for (Room__c room : [
            SELECT Id, Capacity__c, Occupied_Beds__c
            FROM Room__c
            WHERE Id IN :roomIds
            FOR UPDATE
        ]) {
            Integer occupiedDelta = occupiedDeltaByRoom.containsKey(room.Id) ? occupiedDeltaByRoom.get(room.Id) : 0;
            Decimal occupied = room.Occupied_Beds__c == null ? 0 : room.Occupied_Beds__c;
            Decimal newOccupied = occupied + occupiedDelta;
            if (newOccupied < 0) {
                newOccupied = 0;
            }
            roomsToUpdate.add(new Room__c(
                Id = room.Id,
                Occupied_Beds__c = newOccupied
            ));
        }

        if (!roomsToUpdate.isEmpty()) {
            update roomsToUpdate;
        }
    }

    private static String allocationKey(Id roomId, String bedNumber) {
        return String.valueOf(roomId) + ':' + bedNumber.trim().toLowerCase();
    }

    private static void assignRoomFromType(
        Bed_Allocation__c allocation,
        Map<String, List<Room__c>> availableRoomsByType,
        Map<Id, Integer> incomingCapacityDemandByRoom,
        Map<String, Id> activeBedKeys,
        Set<String> incomingKeys
    ) {
        if (String.isBlank(allocation.Room_Type__c)) {
            return;
        }

        List<Room__c> candidateRooms = availableRoomsByType.get(normalize(allocation.Room_Type__c));
        if (candidateRooms == null || candidateRooms.isEmpty()) {
            return;
        }

        for (Room__c room : candidateRooms) {
            Integer capacity = room.Capacity__c == null ? 0 : Integer.valueOf(room.Capacity__c);
            Integer occupied = room.Occupied_Beds__c == null ? 0 : Integer.valueOf(room.Occupied_Beds__c);
            Integer incoming = incomingCapacityDemandByRoom.containsKey(room.Id) ? incomingCapacityDemandByRoom.get(room.Id) : 0;
            if (capacity > 0 && occupied + incoming >= capacity) {
                continue;
            }

            Integer bedNumber = parseBedNumber(allocation.Bed_Number__c);
            if (bedNumber != null && capacity > 0 && bedNumber > capacity) {
                continue;
            }
            if (!String.isBlank(allocation.Bed_Number__c)) {
                String bedKey = allocationKey(room.Id, allocation.Bed_Number__c);
                if (incomingKeys.contains(bedKey) || activeBedKeys.containsKey(bedKey)) {
                    continue;
                }
            }

            allocation.Room__c = room.Id;
            return;
        }
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? null : value.trim().toLowerCase();
    }

    private static Integer parseBedNumber(String bedNumber) {
        if (String.isBlank(bedNumber)) {
            return null;
        }
        String normalizedBedNumber = bedNumber.trim();
        if (!Pattern.matches('^[0-9]+$', normalizedBedNumber)) {
            return null;
        }
        return Integer.valueOf(normalizedBedNumber);
    }

    private static Decimal roomPrice(String roomType) {
        if (String.isBlank(roomType)) {
            return 0;
        }

        String normalizedRoomType = roomType.trim().toLowerCase();
        if (normalizedRoomType == 'shared non ac room without extra bed') {
            return 50;
        }
        if (normalizedRoomType == 'shared non ac room with extra bed') {
            return 75;
        }
        if (normalizedRoomType == 'shared ac room without extra bed') {
            return 100;
        }
        if (normalizedRoomType == 'shared ac room with extra bed') {
            return 125;
        }
        if (normalizedRoomType == 'private non ac room without extra bed') {
            return 100;
        }
        if (normalizedRoomType == 'private ac room without extra bed') {
            return 125;
        }
        if (normalizedRoomType == 'private non ac room with extra bed') {
            return 125;
        }
        if (normalizedRoomType == 'private ac room with extra bed') {
            return 150;
        }
        return 0;
    }
}