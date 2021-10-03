public with sharing class AwfulBulkAntiPattern {

    /**
     * ! Bad implementation just to demostrate what an Apex Beginner who did not receive proper education might do
     * ! To run this test, reduce the number of objects by setting the data initialization in bulkOpportunityTest to
     * ! initTestObjects(ops, 50, 10, 10, 20);
     * ! and the opportunity count in createTaskTest to 50. 
     * 
     * 
     * 
     * In one sample run, the results I saw for bulkOpportunityTest were:
        Number of SOQL queries: 100 out of 100 ******* CLOSE TO LIMIT
        Number of query rows: 16000 out of 50000
        Number of SOSL queries: 0 out of 20
        Number of DML statements: 51 out of 150
        Number of DML rows: 100 out of 10000
        Maximum CPU time: 3565 out of 10000

        And for createTaskTest:
        Number of SOQL queries: 100 out of 100 ******* CLOSE TO LIMIT
        Number of query rows: 0 out of 50000
        Number of SOSL queries: 0 out of 20
        Number of DML statements: 51 out of 150
        Number of DML rows: 100 out of 10000
        Maximum CPU time: 1155 out of 10000
     */


    public static void afterUpdateOpportunityAwful(
        List<Opportunity> newList, 
        Map<Id, Opportunity> oldMap
    ){

        // Pattern 1 - terrible implementation

        // Get OpportunityContactRoles
        for(Opportunity op:  newList){
            if(op.StageName == oldMap.get(op.Id).StageName) continue; // Only process changes to stagename

            //* SOQL inside of a lopp! HORRIFIC
            List<OpportunityContactRole> ocrs = [SELECT ID, ContactID, IsPrimary
                                                 FROM OpportunityContactRole 
                                                 WHERE OpportunityId = :op.id];
            if(ocrs.size() == 0){
                /**
                 * No associated contact at all for an op
                 * - Create a new task for the owner to create said contact for the op
                 * - If task is set continue
                 */
                List<Task> tasks = [SELECT ID, OwnerID, WhatID, Status, Subject, Type
                                   FROM Task
                                   WHERE OwnerId = :op.OwnerId
                                   AND Type = 'Other'
                                   AND WhatId = :op.Id
                                   AND IsClosed = False
                                   AND Subject = 'Assign Primary Contact'];

                if(tasks.size() > 0) continue; // Already set

                Task t = new Task(OwnerId= op.OwnerId, Type='Other',
                                  WhatId=op.Id, Subject='Assign Primary Contact',
                                  ActivityDate = Date.today().addDays(3));
                insert t; //* DML inside of a loop is just BAD
                continue;
            }

            Boolean primaryFound = false;
            for(OpportunityContactRole ocr : ocrs){
                if(ocr.IsPrimary){
                    primaryFound = true;
                    break;
                }
            }
            if(primaryFound) continue;

            // Get a list of the contacts for an ocr
            List<ID> contactIdsForOps = new List<ID>();

            for(OpportunityContactRole ocr : ocrs){
                contactIdsForOps.add(ocr.ContactId);
            }

            // We then query the contact with the OpportunityContactRoles
            Map<ID, Contact> contactsForOps = 
                new Map<ID, Contact>(
                    [SELECT ID, 
                     (SELECT ID, IsPrimary FROM OpportunityContactRoles)
                    FROM Contact WHERE ID in : contactIdsForOps]
                );
            
            // Then figure out which of the OpportunityContactRoles should be set to primary
            OpportunityContactRole bestOcr = null;
            Integer bestContactAllOcrCount = 0;
            Integer bestPrimaryContactOcrCount = 0;


            for(OpportunityContactRole ocr : ocrs){
                Contact currentContact = contactsForOps.get(ocr.ContactId);
                Integer primaryCount = 0;
                for(OpportunityContactRole conOcr: currentContact.OpportunityContactRoles){
                    if(conOcr.IsPrimary) primaryCount++;  
                }
                if(bestOcr == null ||
                   primaryCount > bestPrimaryContactOcrCount ||
                    (primaryCount == bestContactAllOcrCount && 
                     currentContact.OpportunityContactRoles.size() > bestContactAllOcrCount))
                {
                    bestOcr = ocr;
                    bestContactAllOcrCount = currentContact.OpportunityContactRoles.size();
                    bestPrimaryContactOcrCount = primaryCount;
                }
            }

            bestOcr.IsPrimary = true;
            update bestOcr; // Another DML inside a loop🤦‍♂️ 

        }

    }

}
