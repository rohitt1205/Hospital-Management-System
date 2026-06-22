public with sharing class HMS_ZoomService {

    public class ZoomException extends Exception {}

    /**
     * Gets the OAuth access token from Zoom using Server-to-Server OAuth credentials.
     */
    public static String getAccessToken() {
        Zoom_Setting__c settings = Zoom_Setting__c.getOrgDefaults();
        if (settings == null || String.isBlank(settings.Client_ID__c) || String.isBlank(settings.Client_Secret__c) || String.isBlank(settings.Account_ID__c)) {
            throw new ZoomException('Zoom settings are not configured. Please populate Zoom_Setting__c credentials.');
        }

        String tokenUrl = 'https://zoom.us/oauth/token?grant_type=account_credentials&account_id=' + EncodingUtil.urlEncode(settings.Account_ID__c, 'UTF-8');
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(tokenUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        Blob headerValue = Blob.valueOf(settings.Client_ID__c + ':' + settings.Client_Secret__c);
        String authorizationHeader = 'Basic ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
        req.setTimeout(60000);

        Http h = new Http();
        HttpResponse res = h.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) jsonMap.get('access_token');
        } else {
            throw new ZoomException('Failed to retrieve access token from Zoom. Status: ' + res.getStatus() + ', Response: ' + res.getBody());
        }
    }

    /**
     * Creates a scheduled Zoom meeting under a host user email.
     */
    public static Map<String, Object> createMeeting(String hostEmail, String topic, DateTime startTime, Integer durationMinutes) {
        String accessToken = getAccessToken();
        
        // Ensure we have a valid host email, default if blank
        Zoom_Setting__c settings = Zoom_Setting__c.getOrgDefaults();
        String activeHost = String.isNotBlank(hostEmail) ? hostEmail : (settings != null ? settings.Default_Host_Email__c : null);
        if (String.isBlank(activeHost)) {
            activeHost = 'imrohitkumar387@gmail.com'; // Absolute fallback
        }

        String meetingUrl = 'https://api.zoom.us/v2/users/' + EncodingUtil.urlEncode(activeHost, 'UTF-8') + '/meetings';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(meetingUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setTimeout(60000);

        // Format start time as ISO-8601 string (UTC)
        String formattedStartTime = startTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

        Map<String, Object> bodyMap = new Map<String, Object>();
        bodyMap.put('topic', topic);
        bodyMap.put('type', 2); // Scheduled meeting
        bodyMap.put('start_time', formattedStartTime);
        bodyMap.put('duration', durationMinutes);
        bodyMap.put('timezone', 'UTC');

        // Settings to make meeting joinable without registration etc.
        Map<String, Object> settingsMap = new Map<String, Object>();
        settingsMap.put('join_before_host', true);
        settingsMap.put('jbh_time', 0); // join at scheduled time or any time
        settingsMap.put('waiting_room', false);
        bodyMap.put('settings', settingsMap);

        req.setBody(JSON.serialize(bodyMap));

        Http h = new Http();
        HttpResponse res = h.send(req);

        if (res.getStatusCode() == 201 || res.getStatusCode() == 200) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } else {
            throw new ZoomException('Failed to create Zoom meeting. Status: ' + res.getStatus() + ', Response: ' + res.getBody());
        }
    }
}
