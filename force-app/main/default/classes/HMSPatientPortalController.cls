/**
 * LWC entry point for the Hospital Patient Portal dashboard.
 * Data loading is delegated to PatientPortalDataService (without sharing) because
 * @AuraEnabled methods invoked from LWC run with sharing at API 67+.
 */
public with sharing class HMSPatientPortalController {

    @AuraEnabled
    public static String getPortalSummary() {
        Map<String, Object> summary = PatientPortalDataService.baseSummary();

        summary.put('loggedInUserId', UserInfo.getUserId());
        summary.put('loggedInEmail', UserInfo.getUserEmail());
        summary.put('serverTime', String.valueOf(Datetime.now()));

        Patient__c patient = PatientPortalLinkService.resolveForRunningUser();

        if (patient == null) {
            summary.put('linked', false);
            summary.put('status', 'No linked patient record');
            return JSON.serialize(summary);
        }

        summary.put('linked', true);
        PatientPortalDataService.enrichSummary(summary, patient);
        return JSON.serialize(summary);
    }

    @AuraEnabled
    public static String getPortalSummaryJson() {
        return getPortalSummary();
    }

    @AuraEnabled
    public static Boolean ensureMyPatientLink() {
        return PatientPortalLinkService.resolveForRunningUser() != null;
    }

    /**
     * Returns bootstrap parameters for the Hospital Patient Portal embedded
     * messaging deployment so the dashboard can launch Agentforce chat.
     */
    @AuraEnabled(cacheable=true)
    public static String getEmbeddedChatConfig() {
        final String deploymentName = 'Hospital_Patient_Portal_Deployment';
        final String eswSiteName = 'ESW_Hospital_Patient_Porta_17818759301761';

        List<Site> eswSites = [
            SELECT UrlPathPrefix
            FROM Site
            WHERE Name = :eswSiteName
            LIMIT 1
        ];
        if (eswSites.isEmpty()) {
            throw new AuraHandledException('Embedded chat is not configured for this portal.');
        }

        String siteRoot = Site.getBaseUrl();
        if (String.isBlank(siteRoot)) {
            String orgHost = URL.getOrgDomainUrl().getHost();
            siteRoot = 'https://' + orgHost.replace('.my.salesforce.com', '.my.site.com') + '/s';
        }
        if (siteRoot.endsWith('/s')) {
            siteRoot = siteRoot.substring(0, siteRoot.length() - 2);
        } else if (siteRoot.endsWith('/s/')) {
            siteRoot = siteRoot.substring(0, siteRoot.length() - 3);
        } else if (siteRoot.endsWith('/')) {
            siteRoot = siteRoot.substring(0, siteRoot.length() - 1);
        }

        String pathPrefix = eswSites[0].UrlPathPrefix;
        String eswBaseUrl = siteRoot + '/' + pathPrefix;
        String orgHost = URL.getOrgDomainUrl().getHost();
        String scrt2Host = orgHost.replace('.my.salesforce.com', '.my.salesforce-scrt.com');

        Map<String, String> config = new Map<String, String>{
            'orgId' => UserInfo.getOrganizationId(),
            'deploymentName' => deploymentName,
            'eswBaseUrl' => eswBaseUrl,
            'bootstrapUrl' => eswBaseUrl + '/assets/js/bootstrap.min.js',
            'scrt2Url' => 'https://' + scrt2Host
        };
        return JSON.serialize(config);
    }
}