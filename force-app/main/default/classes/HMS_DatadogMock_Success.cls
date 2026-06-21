/**
 * HMS_DatadogMock_Success
 * HttpCalloutMock returning HTTP 202 (Datadog accepted).
 */
@isTest
global class HMS_DatadogMock_Success implements HttpCalloutMock {
    global HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(202);
        res.setBody('{"status":"ok"}');
        res.setHeader('Content-Type', 'application/json');
        return res;
    }
}