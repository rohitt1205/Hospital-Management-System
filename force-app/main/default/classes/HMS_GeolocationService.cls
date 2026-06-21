/**
 * Resolves approximate geolocation from a public IP address for audit enrichment.
 */
public without sharing class HMS_GeolocationService {

    private static Map<String, Map<String, String>> cache = new Map<String, Map<String, String>>();

    public static Boolean isEnabled() {
        AuditLog_Config__mdt cfg = getConfig();
        return cfg.Is_Geolocation_Enabled__c != false;
    }

    public static Map<String, String> lookupIp(String ipAddress) {
        Map<String, String> empty = emptyResult();
        if (!isEnabled() || String.isBlank(ipAddress) || isPrivateOrLocalIp(ipAddress)) {
            return empty;
        }
        if (cache.containsKey(ipAddress)) {
            return cache.get(ipAddress);
        }

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://ip-api.com/json/' + EncodingUtil.urlEncode(ipAddress, 'UTF-8')
                + '?fields=status,country,city,regionName,lat,lon,isp,query');
            req.setMethod('GET');
            req.setTimeout(5000);

            HttpResponse resp = new Http().send(req);
            if (resp.getStatusCode() != 200) {
                cache.put(ipAddress, empty);
                return empty;
            }

            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
            if (payload.get('status') != 'success') {
                cache.put(ipAddress, empty);
                return empty;
            }

            Map<String, String> result = new Map<String, String>{
                'ip'       => stringValue(payload.get('query')),
                'country'  => stringValue(payload.get('country')),
                'region'   => stringValue(payload.get('regionName')),
                'city'     => stringValue(payload.get('city')),
                'latitude' => stringValue(payload.get('lat')),
                'longitude'=> stringValue(payload.get('lon')),
                'isp'      => stringValue(payload.get('isp'))
            };
            cache.put(ipAddress, result);
            return result;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'HMS_GeolocationService.lookupIp failed for ' + ipAddress + ' — ' + ex.getMessage());
            cache.put(ipAddress, empty);
            return empty;
        }
    }

    @TestVisible
    static void clearCacheForTest() {
        cache.clear();
    }

    private static Boolean isPrivateOrLocalIp(String ipAddress) {
        if (ipAddress == '127.0.0.1' || ipAddress.startsWith('10.')
            || ipAddress.startsWith('192.168.') || ipAddress.startsWith('169.254.')) {
            return true;
        }
        if (ipAddress.startsWith('172.')) {
            List<String> parts = ipAddress.split('\\.');
            if (parts.size() > 1) {
                Integer second = Integer.valueOf(parts[1]);
                return second >= 16 && second <= 31;
            }
        }
        return false;
    }

    private static Map<String, String> emptyResult() {
        return new Map<String, String>{
            'ip' => '', 'country' => '', 'region' => '', 'city' => '',
            'latitude' => '', 'longitude' => '', 'isp' => ''
        };
    }

    private static String stringValue(Object value) {
        return value == null ? '' : String.valueOf(value);
    }

    private static AuditLog_Config__mdt getConfig() {
        List<AuditLog_Config__mdt> configs = [
            SELECT Is_Geolocation_Enabled__c
            FROM AuditLog_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        return configs.isEmpty()
            ? new AuditLog_Config__mdt(Is_Geolocation_Enabled__c = true)
            : configs[0];
    }
}