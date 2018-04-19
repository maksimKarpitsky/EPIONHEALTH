/**
 * Created by m.karpitsky on 13.04.18.
 */

global class ConvertAccountOppContToLeadsBatch implements Database.Batchable<sObject>, Database.Stateful {


    global Database.QueryLocator start(Database.BatchableContext bc) {
        String test = 'SELECT Id, OwnerId, AccountId, Salutation, FirstName, LastName, Phone, Email FROM Contacts';
        return Database.getQueryLocator(test);
    }
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
    }
    global void finish(Database.BatchableContext bc) {
    }
}