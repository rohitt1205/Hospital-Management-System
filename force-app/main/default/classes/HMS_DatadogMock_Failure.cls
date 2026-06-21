/**
 * HMS_DatadogMock_Failure
 * HttpCalloutMock returning HTTP 503 (Datadog server error).
 */
@isTest
global class HMS_DatadogMock_Failure implements HttpCalloutMock {
    global HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(503);
        res.setBody('{"errors":["Service Unavailable"]}');
        res.setHeader('Content-Type', 'application/json');
        return res;
    }
}