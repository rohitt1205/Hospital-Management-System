/**
 * Reports community memberships on the retired HMS Patient Portal network.
 * NetworkMember records must be removed in Setup or via Data API (Apex DML is blocked).
 */
public without sharing class HMSPortalNetworkCleanup {

    public static final String RETIRED_NETWORK_NAME = 'HMS Patient Portal';

    public static Integer countRetiredPortalMembers() {
        List<Network> retiredNetworks = [
            SELECT Id
            FROM Network
            WHERE Name = :RETIRED_NETWORK_NAME
            LIMIT 1
        ];
        if (retiredNetworks.isEmpty()) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM NetworkMember
            WHERE NetworkId = :retiredNetworks[0].Id
        ];
    }
}