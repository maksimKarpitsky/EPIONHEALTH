/**
 * Created by m.karpitsky on 13.04.18.
 */

global class ConvertAccountOppContToLeadsBatch implements Database.Batchable<sObject>, Database.Stateful {

    public String queryAcc;
    public Id globalUserId;
    global Integer recordsProcessed = 0;
    List<String> errors = new List<String>();

    public static final Map<String, String> accountToLeadMap = new Map<String, String>{
            'Name' => 'Company',
            'Phone' => 'Phone',
            'OwnerId' => 'OwnerId',
            'AccountSource' => 'LeadSource',
            'BillingAddress' => 'Address',
            'BillingCity' => 'City',
            'BillingCountry' => 'Country',
            'BillingCountryCode' => 'CountryCode',
            'BillingLatitude' => 'Latitude',
            'BillingLongitude' => 'Longitude',
            'BillingPostalCode' => 'PostalCode',
            'BillingState' => 'State',
            'BillingStateCode' => 'StateCode',
            'BillingStreet' => 'Street',
            'Website' => 'Website',
            'EMR_ID__c' => 'EMR_ID__c',
            'EMR_Type__c' => 'EMR_Company__c',
            'Fax' => 'Fax',
            'Industry' => 'Industry',
            'Provider_Potential__c' => 'Provider_Potential__c',
            'Rating' => 'Rating',
            'Specialties__c' => 'Specialty__c'
    };

    global Database.QueryLocator start(Database.BatchableContext bc) {
        globalUserId = [SELECT Id FROM User WHERE Name = 'Max Tyroler' LIMIT 1].Id;
        List<String> fieldsList = new List<String>(accountToLeadMap.keySet());
        String fields = String.join(fieldsList, ', ');

        this.queryAcc = 'SELECT ' + fields + ', Id, (SELECT Id, OwnerId, AccountId, Salutation, FirstName, LastName, Phone, Email FROM Contacts), ';
        this.queryAcc += '(SELECT Id, Name, StageName FROM Opportunities), (SELECT Body, IsDeleted, IsPrivate, OwnerId, Title FROM Notes), ';
        //this.queryAcc += '(SELECT Id, Name, ParentId, Body, Description, IsPrivate FROM Attachments), ';
        this.queryAcc += '(SELECT Id, WhatId, WhoId, Subject, StartDateTime, EndDateTime, Description, OwnerId, Location, Activity_Type__c, DurationInMinutes, ActivityDateTime FROM Events), ';
        this.queryAcc += '(SELECT Id, WhatId, WhoId, Status FROM Tasks) FROM Account WHERE ';
        this.queryAcc += 'Id IN (SELECT AccountId FROM Opportunity WHERE StageName = \'Not Contacted\' OR StageName = \'Attempting Contact\')';
        return Database.getQueryLocator(queryAcc);
    }

    global void execute(Database.BatchableContext bc, List<Account> scope) {
        try {
            Map<Id, Lead> leadMap = new Map<Id, Lead>();
            Set<Id> userIds = new Set<Id>();

            for (Account acc : scope) {
                userIds.add(acc.OwnerId);

                for (Contact cntct : acc.Contacts) {
                    userIds.add(cntct.OwnerId);
                }

                for (Note nt : acc.Notes) {
                    userIds.add(nt.OwnerId);
                }

                for (Event ev : acc.Events) {
                    userIds.add(ev.OwnerId);
                }

                for (Task task : acc.Tasks) {
                    userIds.add(task.OwnerId);
                }
            }

            Map<Id, User> userMap = new Map<Id, User>([
                    SELECT Id, IsActive
                    FROM User
                    WHERE Id IN :userIds
            ]);

            Map<Id, Id> userIdsMap = new Map<Id, Id>();
            for (User usr : userMap.values()) {
                if (usr.IsActive) {
                    userIdsMap.put(usr.Id, usr.Id);
                } else {
                    userIdsMap.put(usr.Id, globalUserId);
                }
            }

            List<Contact> contactDeleteList = new List<Contact>();
            List<Opportunity> opportunityDeleteList = new List<Opportunity>();
            Set<Id> oppIds = new Set<Id>();

            //check the condition for the inverse conversion
            for (Account acc : scope) {
                if (acc.Contacts != null) {
                    if (acc.Opportunities != null) {
                        Boolean isMoveToLead = true;
                        for (Opportunity opp : acc.Opportunities) {
                            if (!(opp.StageName == 'Not Contacted' || opp.StageName == 'Attempting Contact')) {
                                oppIds.add(opp.Id);
                                isMoveToLead = false;
                                break;
                            }
                        }
                        if (isMoveToLead) {
                            Lead newLead = createNewLead(acc);
                            contactDeleteList.add(acc.Contacts.get(0));
                            opportunityDeleteList.add(acc.Opportunities.get(0));
                            leadMap.put(acc.Id, newLead);
                            recordsProcessed++;
                        }
                    }
                } /*else if (acc.Contacts != null && acc.Contacts.size() > 1){
                    contactDeleteList.addAll(acc.Contacts);
            } */

            }
            if (!leadMap.isEmpty()) {
                insert leadMap.values();
            }

            List<Task> tasksUpdateList = new List<Task>();
            List<Note> notesInsertList = new List<Note>();
            List<Note> notesDeleteList = new List<Note>();
            List<Event> eventInsertList = new List<Event>();
            List<Event> eventDeleteList = new List<Event>();
            /*List<Attachment> attachmentInsertList = new List<Attachment>();
            List<Attachment> attachmentDeleteList = new List<Attachment>();*/

            for (Account acc : scope) {
                /* Chose one Contact from Contacts
                for (Contact cntct : contactList) {

                }*/
                if (!acc.Notes.isEmpty()) {
                    for (Note nt : acc.Notes) {
                        Note newNote = new Note(
                                Body = nt.Body,
                                IsPrivate = nt.IsPrivate,
                                Title = nt.Title,
                                ParentId = leadMap.get(acc.Id).Id
                        );
                        if (userMap.containsKey(nt.OwnerId) && userMap.get(nt.OwnerId).IsActive) {
                            newNote.OwnerId = userIdsMap.get(nt.OwnerId);
                        } else {
                            newNote.OwnerId = globalUserId;
                        }
                        notesInsertList.add(newNote);
                        notesDeleteList.add(nt);
                    }
                }

                if (!acc.Events.isEmpty()) {
                    for (Event ev : acc.Events) {
                        if (ev.EndDateTime >= Date.today()) {
                            Event newEvent = new Event(
                                    Subject = ev.Subject,
                                    WhatId = null,
                                    WhoId = leadMap.get(acc.Id).Id,
                                    StartDateTime = ev.StartDateTime,
                                    EndDateTime = ev.EndDateTime,
                                    DurationInMinutes = ev.DurationInMinutes,
                                    ActivityDateTime = ev.ActivityDateTime,
                                    Description = ev.Description,
                                    Location = ev.Location,
                                    Activity_Type__c = ev.Activity_Type__c
                            );
                            if (userMap.containsKey(ev.OwnerId) && userMap.get(ev.OwnerId).IsActive) {
                                newEvent.OwnerId = userIdsMap.get(ev.OwnerId);
                            } else {
                                newEvent.OwnerId = globalUserId;
                            }
                            eventInsertList.add(newEvent);
                            eventDeleteList.add(ev);
                        }
                    }
                }

                if (!acc.Tasks.isEmpty()) {
                    for (Task t : acc.Tasks) {
                        t.WhatId = null;
                        t.WhoId = leadMap.get(acc.Id).Id;
                        t.OwnerId = userIdsMap.get(acc.OwnerId);
                    }
                    tasksUpdateList.addAll(acc.Tasks);
                }

                /*if (!acc.Attachments.isEmpty()) {
                    for (Attachment att : acc.Attachments) {
                        Attachment newAttachment = new Attachment(
                                Name = att.Name,
                                ParentId = leadMap.get(acc.Id).Id,
                                Body = att.Body,
                                Description = att.Description,
                                IsPrivate = att.IsPrivate
                        );
                        if (userMap.containsKey(att.OwnerId) && userMap.get(att.OwnerId).IsActive) {
                            newAttachment.OwnerId = userIdsMap.get(att.OwnerId);
                        } else {
                            newAttachment.OwnerId = globalUserId;
                        }
                        attachmentInsertList.add(newAttachment);
                        attachmentDeleteList.add(att);
                    }
                }*/
            }

            List<Opportunity> opportunities = [
                    SELECT Id, Name, StageName, (SELECT Id, WhatId, WhoId, Status, Subject, Description FROM Tasks)/*, (SELECT Id, Name, ParentId, Body, Description, IsPrivate FROM Attachments)*/
                    FROM Opportunity
                    WHERE (StageName = 'Not Contacted' OR StageName = 'Attempting Contact') AND Id IN :oppIds
            ];

            /*if (!attachmentInsertList.isEmpty()) {
                insert attachmentInsertList;
            }
            if (!attachmentDeleteList.isEmpty()) {
                delete attachmentDeleteList;
            }*/

            if (!opportunityDeleteList.isEmpty()) {
                delete opportunityDeleteList;
            }
            if (!tasksUpdateList.isEmpty()) {
                update tasksUpdateList;
            }
            if (!eventInsertList.isEmpty()) {
                insert eventInsertList;
            }
            if (!eventDeleteList.isEmpty()) {
                delete eventDeleteList;
            }
            if (!notesInsertList.isEmpty()) {
                insert notesInsertList;
            }
            if (!notesDeleteList.isEmpty()) {
                delete notesDeleteList;
            }
            if (!contactDeleteList.isEmpty()) {
                delete contactDeleteList;
            }
            if (!scope.isEmpty()) {
                delete scope;
            }
        } catch (Exception e) {
            errors.add(e.getMessage());
        }
    }

    private Lead createNewLead(Account acc) {
        Lead newLead = new Lead();
        newLead.EMR_ID__c = acc.EMR_ID__c;
        newLead.EMR_Type__c = acc.EMR_Company__c;
        newLead.Status = acc.Opportunities.get(0).StageName;
        //newLead.Address = acc.BillingAddress;
        newLead.Latitude = acc.BillingLatitude;
        newLead.Longitude = acc.BillingLongitude;
        newLead.PostalCode = acc.BillingPostalCode;
        newLead.State = acc.BillingState;
        newLead.StateCode = acc.BillingStateCode;
        newLead.Street = acc.BillingStreet;
        newLead.City = acc.BillingCity;
        newLead.Country = acc.BillingCountry;
        newLead.CountryCode = acc.BillingCountryCode;
        newLead.Phone = acc.Phone;
        newLead.Website = acc.Website;
        newLead.Provider_Potential__c = acc.Provider_Potential__c;
        newLead.Specialty__c = acc.Specialties__c;
        newLead.Company = acc.Name;
        newLead.FirstName = acc.Contacts.get(0).FirstName;
        newLead.LastName = acc.Contacts.get(0).LastName;
        newLead.Email = acc.Contacts.get(0).Email;
        newLead.Salutation = acc.Contacts.get(0).Salutation;
        return newLead;
    }

    global void finish(Database.BatchableContext bc) {
        if (!errors.isEmpty()) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setSubject('Errors occurred during batch process.');
            mail.setTargetObjectId(UserInfo.getUserId());
            mail.setSaveAsActivity(false);
            mail.setPlainTextBody(String.join(errors, ',') + '\n Lead Processed: ' + recordsProcessed);
            Messaging.sendEmail(new Messaging.Email[]{
                    mail
            });
        }
    }
}