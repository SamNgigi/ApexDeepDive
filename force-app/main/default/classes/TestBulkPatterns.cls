@isTest
public class TestBulkPatterns {

    static testMethod void bulkOpportunityTest(){
        /**
         * Test that ensures that a primary contact exists for opportunities that
         * were already associated with contacts
         */
        List<Opportunity> ops = new List<Opportunity>();


        // Note, you may need to adjust these numbers
        initTestObjects(ops, 100, 15, 15, 40);

        Test.startTest();
        for(Opportunity op: ops) op.StageName = 'Qualification';
        update ops;
        Test.stopTest();

        validateOCRs(ops);


    }

    static testMethod void createTaskTest(){
        /**
         * Testing wether an opportunity has been associated with a contact
         */
        Integer numberOfOpportunities = 100;
        List<Opportunity> ops = new List<Opportunity>();
        for(Integer x = 0; x<numberOfOpportunities; x++){
            ops.add(new Opportunity(CloseDate = Date.today().addDays(5),
                                    Name = 'TestOp_' + String.valueOf(x),
                                    StageName = 'Prospecting'));
        }

        insert ops;

        Test.startTest();
        for(Opportunity op: ops) op.StageName = 'Qualification';
        update ops;
        Test.stopTest();

        List<Task> tasks = [SELECT ID, OwnerID, WhatID, Status, Subject, Type
                            FROM Task
                            WHERE OwnerID = :UserInfo.getUserID()
                            AND Type = 'Other'AND IsClosed=False
                            AND Subject = 'Assign Primary Contact' ];
        /**
         * Unit Test by default only see data that was created during the unit test.
         * A few exceptions include Static Resources & User Objects(User data)
         * 
         * A test can access existing organization data by using the SeeAllData=true attribute 
         * on the isTest annotation params
         * 
         * Be carefull to differentiate in the test between test data and existing data. One way
         * is by maintaining a list of IDS for created test data and using it in queries to 
         * validate created test record
         * 
         * Good thing is that even when the SeeAllData=true any modification made to the db
         * during a test are discarded when test is complete
         */
        System.assertEquals(NumberOfOpportunities, tasks.size());

    }

    
    public static void initTestObjects(
        List<Opportunity> newOpportunities, // List to be populated with opportunites
        Integer numberOfOpportunities, // Specifies number of new opportunites to create
        Integer numberOfOtherOpportunities, // Specifies additional opportunities to be created, associated with contacts
        Integer contactRolesPerOp, //specifies number of contacts to be associated with each opportunity
        Integer numberOfContacts // specifies number of contacts to distribute amongs opportunities and should be larger than contactRolesPerOp
    ){
    /**
     * Method prepares the specified number of opportunities,
     * with contact roles on each
     * The contact roles are distributed evenly among the number
     * of contacts specified
     */
        if(numberOfContacts < contactRolesPerOp)
            numberOfContacts = contactRolesPerOp;
        
        List<Contact> cts = new List<Contact>();
        for(Integer x=0; x<numberOfContacts; x++)
            cts.add(new Contact(LastName='TestContact_' + String.valueOf(x)));
        //Insert new contacts
        insert cts;

        newOpportunities.clear();
        for(Integer x=0; x<numberOfOpportunities; x++){
            newOpportunities.add(
                new Opportunity(CloseDate=Date.Today().addDays(5),
                                Name = 'NewOppTest_' + String.valueOf(x),
                                StageName = 'Prospecting')
            );
        }
        // insert newOpportunities
        insert newOpportunities;
        
        // Ops to be associated with Contacts
        List<Opportunity> otherOpportunities = new List<Opportunity>();
        for(Integer x=0; x<numberOfOpportunities; x++){
            otherOpportunities.add(
                new Opportunity(CloseDate= Date.Today().addDays(5),
                                Name = 'OtherOppsTest_' + String.valueOf(x),
                                StageName='Prospecting')
            );
        }
        // insert otherOpportunities
        insert otherOpportunities;

        otherOpportunities.addAll(newOpportunities);

       
        List<OpportunityContactRole> ocrList = new List<OpportunityContactRole>();
        Integer contactNumber = 0;
        for(Opportunity op: otherOpportunities){
            for(Integer ocrNumber = 0; ocrNumber < contactRolesPerOp; ocrNumber++){
                ocrList.add(
                    new OpportunityContactRole(OpportunityID=op.id, 
                                               ContactID=cts[contactNumber].id)
                );
                contactNumber++;
                if(contactNumber >=numberOfContacts) contactNumber = 0;
            }
        }
        // insert opportunityContactRoles -> Opportunities associated with contacts
        insert ocrList;

    }

    public static void validateOCRs(List<Opportunity> ops){
        // Get map for IDs
        Map<ID, Opportunity> opMap = new Map<ID, Opportunity>(ops);
        
        //* FIRST APPROACH START - 2 LOOPS
        // Returning the ID and Opportunity ID of the Opportunities
        // that have a primary contact 
        List<OpportunityContactRole> ocrs = [SELECT ID, OpportunityId FROM OpportunityContactRole 
                                             WHERE OpportunityId in: opMap.keySet()
                                             AND IsPrimary=true];

        // Create a set of opportunity IDs with primary contacts
        Set<ID> opportunitiesWithPrimaryContact = new Set<ID>();
        for(OpportunityContactRole ocr: ocrs)
            opportunitiesWithPrimaryContact.add(ocr.OpportunityId);

        // We make sure every opportunity has a primary contact role
        for(Opportunity op: ops)
            // Looping through given opportunities and checking if the opportunity id
            // Is found in our set of opportunites that have a primary contact role
            System.assert(opportunitiesWithPrimaryContact.contains(op.Id));
         //* FIRST APPROACH END

         //* SECOND APPROACH START - SUBQUERY WITH 1 LOOP
        List<Opportunity> opResults = [SELECT ID,
                                        (SELECT ID FROM  OpportunityContactRoles WHERE IsPrimary=true)
                                       FROM Opportunity WHERE ID in: opMap.keyset()];
        for(Opportunity op: opResults)
            System.assert(op.OpportunityContactRoles.size()==1);
        //* SECOND APPROACH END 
    }

    

}
