@IsTest
private class PatientRazorpayCheckoutControllerTest {
    @IsTest
    static void testCheckoutPageRequiresParams() {
        PageReference pageRef = Page.PatientRazorpayCheckout;
        Test.setCurrentPage(pageRef);
        PatientRazorpayCheckoutController controller = new PatientRazorpayCheckoutController();
        System.assertEquals(false, controller.ready);
        System.assertNotEquals(null, controller.errorMessage);
    }
}