public with sharing class BulkPatternCommon {
    public BulkPatternCommon() {

    }
    
    /* 
        Sample results (TestBulkPatterns.initTestObjects(ops, 100, 15, 15, 40)):
		bulkOpportunityTest - 
		Number of SOQL queries: 2 out of 100
		Number of query rows: 3265 out of 50000
		Number of SOSL queries: 0 out of 20
		Number of DML statements: 2 out of 150
		Number of DML rows: 200 out of 10000
		Maximum CPU time: 3434 out of 10000

		createTaskTest
		Number of SOQL queries: 2 out of 100
		Number of query rows: 0 out of 50000
		Number of SOSL queries: 0 out of 20
		Number of DML statements: 2 out of 150
		Number of DML rows: 200 out of 10000
		Maximum CPU time: 2 out of 10000
    */

    public static void afterUpdateOpportunityCommon(
        List<Opportunity> newOps, 
        Map<ID, Opportunity> newMap,
        Map<ID, Opportunity> oldMap
    ){
        // Pattern 1 - Straight forward common implementation
        Set<Id> opportunityIDsWithStagenameChanges = new Set<ID>();

        //Get OpportunityContactRoles
        for(Opportunity op: newOps){
            if(op.StageName != oldMap.get(op.id).StageName)
                opportunityIDsWithStagenameChanges.add(op.Id);
        }

        //Quick exit if no processing required
        if(opportunityIDsWithStagenameChanges.size()==0) return;

        //Query for all related OpportunityContactRole
        List<OpportunityContactRole> ocrs = [SELECT ID, ContactID, IsPrimary, OpportunityID  
                                             FROM OpportunityContactrole
                                             WHERE OpportunityId in: opportunityIDsWithStagenameChanges];
        // Look for primary, or for no ocr on opportunities
        Set<Id> primaryFound = new Set<ID>();
        Set<Id> anyFound = new Set<ID>();

        for(OpportunityContactRole ocr : ocrs){
            if(ocr.IsPrimary) primaryFound.add(ocr.OpportunityId);
            anyFound.add(ocr.OpportunityId);
        }

        /**
         * We build a list of opportunities with no contact role (no ocr)
         * another list with contact role but not primary contact role.
         * We'll use maps to make it easier to get the keyset for later queries
         */
        Map<ID, Opportunity> opsWithNoContactRoles = new Map<ID, Opportunity>();
        Map<ID, Opportunity> opsWithNoPrimary = new Map<ID, Opportunity>();

        for(ID opId: opportunityIDsWithStagenameChanges){
            if(!primaryFound.contains(opId)){
                if(anyFound.contains(opId))
                    // Ops with an ocrs but with no primary
                    opsWithNoPrimary.put(opId, newMap.get(opId));
                else
                    opsWithNoContactRoles.put(opId, newMap.get(opId));
            }
        }

        // First deal with any opportunities without contact roles
        if(opsWithNoContactRoles.size() > 0){
            //Find out which ones have existing tasks
            List<Task> tasks = [SELECT ID, OwnerID, WhatID, Status, Subject, Type 
                                FROM Task
                                WHERE Type='Other'
                                AND WhatID in :opsWithNoContactRoles.keySet()
                                AND IsClosed = False
                                AND Subject = 'Assign Primary Contact'];

            /**
             * Looping through opportunities is a waste of time
             * Loop through Tasks instead of to build a set of Op IDs
             * with tasks.
             */

             Set<Id> opsWithTasks = new Set<ID>();
             for(Task t: tasks){
                 // Get ops with tasks
                 Opportunity op = opsWithNoContactRoles.get(t.WhatId);
                 // Make sure it's assigned to the right person 
                 if(t.OwnerId == op.OwnerId) opsWithTasks.add(op.Id);
             }
             // Creating tasks for ops that have no ocr
             List<Task> newOcrTasks = new List<Task>();
             for(Opportunity op : opsWithNoContactRoles.values()){
                 if(!opsWithTasks.contains(op.Id)){
                     newOcrTasks.add(
                         new Task(
                            OwnerID = op.OwnerID, Type='Other', 
                            WhatID = op.ID,
                            Subject = 'Assign Primary Contact',
                            ActivityDate = Date.Today().addDays(3) 
                         )
                     );
                 }
             }
             // Insert new tasks
             if(newOcrTasks.size()>0) insert newOcrTasks;
        }

        if(opsWithNoPrimary.size()>0){
            // Get a list of all the contacts
            List<Id> contactIdsForOps = new List<Id>();
            for(OpportunityContactRole ocr:ocrs){
                if(opsWithNoPrimary.containsKey(ocr.OpportunityId)){
                    contactIdsForOps.add(ocr.ContactId);
                }
            }

            // Querying contacts with their OpportunityContactRoles
            Map<ID, Contact> contactsForOps = 
                new Map<ID, Contact>(
                    [SELECT ID, 
                        (SELECT ID, IsPrimary, OpportunityID FROM OpportunityContactRoles)
                    FROM Contact WHERE ID in :contactIdsForOps]);

            /**
             * Below we want to figure out which OCR should be set to primary
             * We choose to iterate over OpportunityContactRoles instead of Opportunities
             * as this is the more effecient approach.
             * We'll sotre the ranking of each one in maps that are indexed by Opportunity.
             */
            // Map of the opId to the best ocr for the ID
            Map<ID, OpportunityContactRole> bestOcr = new Map<ID, OpportunityContactRole>();

            //Map of opportunity to Total # of OCR on the current best opportunity contact
            Map<ID, Integer> bestContactAlloOcrCount = new Map<ID, Integer>();

            //Map of opportunity to Total # primary OCRs on the current best op contact
            Map<ID, Integer> bestContactPrimaryOcrCount = new Map<ID, Integer>();

            for(OpportunityContactRole ocr : ocrs){
                if(!opsWithNoPrimary.containsKey(ocr.OpportunityId)) continue;
                Contact currentContact = contactsForOps.get(ocr.ContactId);
                Integer primaryCount = 0;

                for(OpportunityContactRole conOcr : currentContact.OpportunityContactRoles){
                    if(conOcr.IsPrimary) primaryCount ++;
                }

                if(!bestOcr.containsKey(ocr.OpportunityId) || 
                    primaryCount > bestContactPrimaryOcrCount.get(ocr.OpportunityId) ||
                        (primaryCount == bestContactAlloOcrCount.get(ocr.OpportunityId) && 
                         currentContact.OpportunityContactRoles.size() > bestContactAlloOcrCount.get(ocr.OpportunityId))
                  ){
                      bestOcr.put(ocr.OpportunityId, ocr);
                      bestContactAlloOcrCount.put(ocr.OpportunityId, currentContact.OpportunityContactRoles.size());
                      bestContactPrimaryOcrCount.put(ocr.OpportunityId, primaryCount);
                  }
            }

            for(OpportunityContactRole best: bestOcr.values()) best.IsPrimary = true;
            update bestOcr.values();

             

        }


    }


    public static void afterUpdateOpportunitySets(
        List<Opportunity> newList, 
        Map<ID, Opportunity> newMap,
        Map<ID, Opportunity> oldMap
    ){
        // Pattern 3 - Straightforward common implementatoion with sets

        Set<Id> opportunityIDsWithStagenameChanges = new Set<ID>();

        for(Opportunity op : newList){
            if(op.StageName != oldMap.get(op.Id).StageName)
                opportunityIDsWithStagenameChanges.add(op.id);
        }

        // Quick exit if no processing required
        if(opportunityIDsWithStagenameChanges.size() == 0) return;

        // Query for all related OpportunityContactRole
        List<OpportunityContactRole> ocrs = [SELECT ID, ContactID, IsPrimary, OpportunityID
                                             FROM OpportunityContactRole
                                             WHERE OpportunityId in :opportunityIDsWithStagenameChanges];

        // Look for primary, or for no OCR on opportunities
        Set<Id> opsWithNoPrimary = opportunityIDsWithStagenameChanges.Clone();
        Set<Id> opsWithNoContactRoles = opportunityIDsWithStagenameChanges.Clone();

        for(OpportunityContactRole ocr : ocrs){
            // Remove ocr with primaries from the opsWithNoPrimary clone ids
            if(ocr.IsPrimary) opsWithNoPrimary.remove(ocr.OpportunityId);
            opsWithNoContactRoles.remove(ocr.OpportunityId);
        }

        // First deal with any opportunities without contact roles
        if(opsWithNoContactRoles.size() > 0){

            // Find out which ones have existing tasks
            List<Task> tasks = [SELECT ID, OwnerID, WhatID, Status, Subject, Type
                                FROM Task WHERE Type = 'Other'
                                AND WhatId in : opsWithNoContactRoles
                                AND IsClosed = false
                                AND Subject = 'Assign Primary Contact'];

            // We loop through tasks instead of opportunities and build a set
            // of ops without ocr tasks
            Set<ID> opsWithoutTasks = opsWithNoContactRoles.clone();

            for(Task t : tasks){
                Opportunity op = newMap.get(t.WhatId); // Get the op
                /**
                 * Make sure it has an open task by checking whether the task & op have the same
                 * Owner
                 */
                if(t.OwnerId == op.OwnerId) opsWithoutTasks.remove(op.Id); 
            }

            // Create new tasks for ops without ocrs
            List<Task> newTasks = new List<Task>();
            for(Id opId : opsWithoutTasks){
                Opportunity op = newMap.get(opId);
                newTasks.add(
                    new Task(OwnerID = op.OwnerId, Type='Other', 
                             WhatId = op.Id,
                             Subject = 'Assign Primary Contact',
                             ActivityDate = Date.today().addDays(3))
                );
            }
            if(newTasks.size()>0) insert newTasks;
        }

        if(opsWithNoPrimary.size() > 0){

            List<Id> contactIdsForOps = new List<Id>();
            // Get list of the contacts from the ocr
            for(OpportunityContactRole ocr : ocrs){
                if(opsWithNoPrimary.contains(ocr.OpportunityId))
                    contactIdsForOps.add(ocr.ContactId);
            }

            // Now query the contact with their OpportuntiyContactRoles
            Map<ID, Contact> contactsForOps = 
                new Map<ID, Contact>(
                    [SELECT ID,
                        (SELECT ID, IsPrimary, OpportunityId FROM OpportunityContactRoles)
                    FROM Contact where ID in : contactIdsForOps]
                );
        
           /** 
            * Below we figure out which OCR should be set as primary 
            */
            Map<ID, OpportunityContactRole> bestOcrs = new Map<ID, OpportunityContactRole>();
            Map<ID, Integer> bestContactAllOcrCount = new Map<ID, Integer>();
            Map<ID, Integer> bestContactPrimaryOcrCount = new Map<ID, Integer>();

            for(OpportunityContactRole ocr : ocrs){
                if(!opsWithNoPrimary.contains(ocr.OpportunityId)) continue;
                Contact currentContact = contactsForOps.get(ocr.ContactId);
                Integer primaryCount = 0;

                for(OpportunityContactRole conOcr : currentContact.OpportunityContactRoles){
                    if(conOcr.IsPrimary) primaryCount++;
                }
                if(!bestOcrs.containsKey(ocr.OpportunityId) || 
                    primaryCount > bestContactPrimaryOcrCount.get(ocr.OpportunityId) ||
                        (primaryCount == bestContactAllOcrCount.get(ocr.OpportunityId) && 
                         currentContact.OpportunityContactRoles.size() > bestContactAllOcrCount.get(ocr.OpportunityId))
                    ){
                        bestOcrs.put(ocr.OpportunityId, ocr);
                        bestContactAllOcrCount.put(ocr.OpportunityId, currentContact.OpportunityContactRoles.size());
                        bestContactPrimaryOcrCount.put(ocr.OpportunityId, primaryCount);
                    }
            }

            for(OpportunityContactRole best : bestOcrs.values()) best.IsPrimary = true;
            update bestOcrs.values();
        
        }

    }

}
