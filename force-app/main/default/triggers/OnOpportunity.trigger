trigger OnOpportunity on Opportunity (after update) {

    BulkPatternCommon.afterUpdateOpportunityCommon(trigger.new, trigger.newMap, trigger.oldMap);

    // Comment the preceding line and uncomment this one to test the afterUpdateOpportunitySets approach
    // BulkPatternCommon.afterUpdateOpportunitySets(trigger.new, trigger.newMap, trigger.oldMap);
}