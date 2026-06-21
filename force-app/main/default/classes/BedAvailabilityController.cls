public without sharing class BedAvailabilityController {
    public class BedOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public BedOption(String bedNumber) {
            label = 'Bed ' + bedNumber;
            value = bedNumber;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<BedOption> getAvailableBeds(Id roomId, Integer capacity) {
        Integer resolvedCapacity = capacity == null ? 0 : capacity;
        Set<String> unavailableBedNumbers = new Set<String>();

        if (roomId != null) {
            Room__c room = [
                SELECT Capacity__c
                FROM Room__c
                WHERE Id = :roomId
                LIMIT 1
            ];
            resolvedCapacity = room.Capacity__c == null ? 0 : Integer.valueOf(room.Capacity__c);

            for (Bed_Allocation__c allocation : [
                SELECT Bed_Number__c
                FROM Bed_Allocation__c
                WHERE Room__c = :roomId
                AND Status__c IN ('Reserved', 'Occupied')
            ]) {
                if (!String.isBlank(allocation.Bed_Number__c)) {
                    unavailableBedNumbers.add(allocation.Bed_Number__c.trim());
                }
            }
        }

        List<BedOption> options = new List<BedOption>();
        for (Integer bedNumber = 1; bedNumber <= resolvedCapacity; bedNumber++) {
            String value = String.valueOf(bedNumber);
            if (!unavailableBedNumbers.contains(value)) {
                options.add(new BedOption(value));
            }
        }
        return options;
    }
}