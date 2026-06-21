/**
 * RoomCodeGenerator
 * ─────────────────
 * Generates auto-incrementing Room Numbers (Name field) and Room_Code__c
 * based on the Ward Type of the parent Ward__c record.
 *
 * Prefix mapping:
 *   ICU        → ICU001, ICU002, …
 *   OPD        → OPD001, OPD002, …
 *   General    → GEN001, GEN002, …
 *   Emergency  → EMR001, EMR002, …
 *   Private    → PVT001, PVT002, …
 *   Maternity  → MAT001, MAT002, …
 *   Pediatric  → PED001, PED002, …
 *
 * The sequence is determined by counting existing Room__c records whose
 * Room_Code__c starts with the same prefix, so each ward type has its own
 * independent auto-increment counter.
 *
 * Called from RoomTrigger (before insert).
 */
public with sharing class RoomCodeGenerator {

    // Map Ward_Type__c picklist values → 3-character prefixes
    private static final Map<String, String> WARD_TYPE_PREFIX = new Map<String, String>{
        'ICU'       => 'ICU',
        'OPD'       => 'OPD',
        'General'   => 'GEN',
        'Emergency' => 'EMR',
        'Private'   => 'PVT',
        'Maternity' => 'MAT',
        'Pediatric' => 'PED'
    };

    /**
     * Main entry point – called from before-insert trigger context.
     * Populates Name and Room_Code__c on each new Room__c record.
     */
    public static void generateRoomCodes(List<Room__c> newRooms) {
        // 1. Collect all Ward Ids referenced by the incoming rooms
        Set<Id> wardIds = new Set<Id>();
        for (Room__c room : newRooms) {
            if (room.Ward__c != null) {
                wardIds.add(room.Ward__c);
            }
        }

        if (wardIds.isEmpty()) {
            return;
        }

        // 2. Query the Ward records to get their Ward_Type__c and Capacity__c
        Map<Id, Ward__c> wardsById = new Map<Id, Ward__c>(
            [SELECT Id, Ward_Type__c, Capacity__c FROM Ward__c WHERE Id IN :wardIds]
        );

        // 3. Determine which prefixes we need to query counts for
        Set<String> prefixesNeeded = new Set<String>();
        for (Room__c room : newRooms) {
            if (room.Ward__c != null) {
                Ward__c ward = wardsById.get(room.Ward__c);
                if (ward != null && ward.Ward_Type__c != null) {
                    String prefix = WARD_TYPE_PREFIX.get(ward.Ward_Type__c);
                    if (prefix != null) {
                        prefixesNeeded.add(prefix);
                    }
                }
            }
        }

        // 4. Query existing rooms to find the max sequence per prefix.
        //    We look for Room_Code__c that starts with the prefix
        //    (handles both old format like "GEN-001" and new format "GEN001").
        Map<String, Integer> prefixMaxSeq = new Map<String, Integer>();
        for (String prefix : prefixesNeeded) {
            String likePattern = prefix + '%';
            List<Room__c> existing = [
                SELECT Room_Code__c
                FROM Room__c
                WHERE Room_Code__c LIKE :likePattern
                ORDER BY CreatedDate DESC
            ];
            Integer maxSeq = 0;
            for (Room__c r : existing) {
                if (r.Room_Code__c != null) {
                    // Strip the prefix and any trailing dash/separator to get numeric part
                    String remainder = r.Room_Code__c.substring(prefix.length());
                    // Remove leading dash or hyphen if present (legacy format e.g. "GEN-001")
                    if (remainder.startsWith('-')) {
                        remainder = remainder.substring(1);
                    }
                    try {
                        Integer seq = Integer.valueOf(remainder.trim());
                        if (seq > maxSeq) {
                            maxSeq = seq;
                        }
                    } catch (Exception e) {
                        // Skip non-numeric suffixes
                    }
                }
            }
            prefixMaxSeq.put(prefix, maxSeq);
        }

        // 5. Assign room codes – handle multiple rooms in the same batch
        //    that share the same prefix by incrementing a running counter.
        Map<String, Integer> runningCounter = new Map<String, Integer>(prefixMaxSeq);

        for (Room__c room : newRooms) {
            if (room.Ward__c == null) {
                continue;
            }
            Ward__c ward = wardsById.get(room.Ward__c);
            if (ward == null || ward.Ward_Type__c == null) {
                continue;
            }
            String prefix = WARD_TYPE_PREFIX.get(ward.Ward_Type__c);
            if (prefix == null) {
                continue; // Unsupported ward type – leave blank
            }

            Integer nextSeq = (runningCounter.get(prefix) != null ? runningCounter.get(prefix) : 0) + 1;
            runningCounter.put(prefix, nextSeq);

            // Check if the user manually entered a numeric Room Number (Name)
            Boolean isNumericName = String.isNotBlank(room.Name) && Pattern.matches('^[0-9]+$', room.Name.trim());
            Integer seq = nextSeq;

            if (isNumericName) {
                seq = Integer.valueOf(room.Name.trim());
                if (ward.Capacity__c != null && seq > ward.Capacity__c) {
                    room.Name.addError('Room number cannot exceed the room capacity of the assigned ward.');
                    continue;
                }
            } else {
                if (ward.Capacity__c != null && seq > ward.Capacity__c) {
                    room.addError('Room number cannot exceed the room capacity of the assigned ward.');
                    continue;
                }
            }

            // Format as PREFIX + zero-padded 3-digit number (e.g. GEN001)
            String seqStr = String.valueOf(seq).leftPad(3, '0');
            String roomCode = prefix + seqStr;

            room.Name = roomCode;
            room.Room_Code__c = roomCode;
        }
    }
}