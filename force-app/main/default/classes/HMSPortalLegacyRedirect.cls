/**
 * Server-side redirects from the retired HMS Patient Portal sites to the live /s/ portal.
 */
public with sharing class HMSPortalLegacyRedirect {

    public static final String LIVE_LOGIN_URL =
        'https://orgfarm-721f288b1d-dev-ed.develop.my.site.com/s/login/';
    public static final String LIVE_HOME_URL =
        'https://orgfarm-721f288b1d-dev-ed.develop.my.site.com/s/';

    public static Boolean isRetiredPortalSite() {
        String prefix = Site.getPathPrefix();
        if (String.isNotBlank(prefix) && prefix.contains('hmspatient')) {
            return true;
        }

        PageReference current = ApexPages.currentPage();
        if (current != null) {
            String url = current.getUrl();
            if (String.isNotBlank(url) && url.contains('hmspatient')) {
                return true;
            }
            Map<String, String> params = current.getParameters();
            if (params != null) {
                for (String value : params.values()) {
                    if (String.isNotBlank(value) && value.contains('hmspatient')) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    public static PageReference liveLoginRedirect() {
        PageReference ref = new PageReference(LIVE_LOGIN_URL);
        ref.setRedirect(true);
        return ref;
    }

    public static PageReference liveHomeRedirect() {
        PageReference ref = new PageReference(LIVE_HOME_URL);
        ref.setRedirect(true);
        return ref;
    }
}