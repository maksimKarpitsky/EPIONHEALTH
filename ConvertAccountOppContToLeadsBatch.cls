/**
 * Created by m.karpitsky on 13.04.18.
 */

global class ConvertAccountOppContToLeadsBatch implements Database.Batchable<sObject>, Database.Stateful {


    global Database.QueryLocator start(Database.BatchableContext bc) {


    global void execute(Database.BatchableContext bc, List<Account> scope) {

    global void finish(Database.BatchableContext bc) {

}