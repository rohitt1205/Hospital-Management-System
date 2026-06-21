@isTest
global class HMS_GeolocationMock_Success implements HttpCalloutMock {
    global HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(
            '{"status":"success","country":"India","city":"Bengaluru","regionName":"Karnataka",'
            + '"lat":12.97,"lon":77.59,"isp":"Example ISP","query":"8.8.8.8"}'
        );
        return res;
    }
}