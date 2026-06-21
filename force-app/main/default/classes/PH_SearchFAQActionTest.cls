@isTest
private class PH_SearchFAQActionTest {
    @isTest
    static void testSearchFAQs() {
        // Seed the database
        HMS_FAQDataSeeder.seedFAQs();
        
        // Assert items were seeded
        System.assert([SELECT Count() FROM FAQ__c] > 0, 'FAQ records should be seeded');

        // Test running seeder again (should skip/not insert duplicates)
        Test.startTest();
        HMS_FAQDataSeeder.seedFAQs();
        Test.stopTest();

        // 1. Test empty search term (should return default list)
        PH_SearchFAQAction.Request reqEmpty = new PH_SearchFAQAction.Request();
        reqEmpty.searchTerm = '';
        List<PH_SearchFAQAction.Response> resEmptyList = PH_SearchFAQAction.searchFAQs(new List<PH_SearchFAQAction.Request>{ reqEmpty });
        System.assertEquals(1, resEmptyList.size(), 'Should return one response');
        System.assertEquals(true, resEmptyList[0].found, 'Should find general FAQs');
        System.assert(resEmptyList[0].faqText.contains('Category:'), 'FAQ text should contain category details');

        // 2. Test specific category matching
        PH_SearchFAQAction.Request reqCategory = new PH_SearchFAQAction.Request();
        reqCategory.searchTerm = 'Admissions';
        List<PH_SearchFAQAction.Response> resCategoryList = PH_SearchFAQAction.searchFAQs(new List<PH_SearchFAQAction.Request>{ reqCategory });
        System.assertEquals(1, resCategoryList.size());
        System.assertEquals(true, resCategoryList[0].found);
        System.assert(resCategoryList[0].faqText.contains('Admissions'), 'Should return Admissions FAQs');

        // 3. Test question keyword matching
        PH_SearchFAQAction.Request reqKeyword = new PH_SearchFAQAction.Request();
        reqKeyword.searchTerm = 'visiting hours';
        List<PH_SearchFAQAction.Response> resKeywordList = PH_SearchFAQAction.searchFAQs(new List<PH_SearchFAQAction.Request>{ reqKeyword });
        System.assertEquals(1, resKeywordList.size());
        System.assertEquals(true, resKeywordList[0].found);
        System.assert(resKeywordList[0].faqText.contains('visiting hours') || resKeywordList[0].faqText.contains('visitor'), 'Should return visiting hours FAQ');

        // 4. Test no results matching
        PH_SearchFAQAction.Request reqNone = new PH_SearchFAQAction.Request();
        reqNone.searchTerm = 'NonexistentKeywordXYZ';
        List<PH_SearchFAQAction.Response> resNoneList = PH_SearchFAQAction.searchFAQs(new List<PH_SearchFAQAction.Request>{ reqNone });
        System.assertEquals(1, resNoneList.size());
        System.assertEquals(false, resNoneList[0].found);
        System.assert(resNoneList[0].faqText.contains('No matching FAQs found'), 'Should indicate no results found');

        // 5. Test matching many results (should trigger size > 5 limit logic)
        PH_SearchFAQAction.Request reqMany = new PH_SearchFAQAction.Request();
        reqMany.searchTerm = 'e';
        List<PH_SearchFAQAction.Response> resManyList = PH_SearchFAQAction.searchFAQs(new List<PH_SearchFAQAction.Request>{ reqMany });
        System.assertEquals(1, resManyList.size());
        System.assertEquals(true, resManyList[0].found);
    }
}
