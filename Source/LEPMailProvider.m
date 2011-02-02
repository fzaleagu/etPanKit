//
//  LEPMailProvider.m
//  etPanKit
//
//  Created by DINH Viêt Hoà on 1/30/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "LEPMailProvider.h"
#import "LEPNetService.h"

#include <regex.h>

@implementation LEPMailProvider

@synthesize identifier = _identifier;

- (id) init
{
    self = [super init];
    
    _imapServices = [[NSMutableArray alloc] init];
    _smtpServices = [[NSMutableArray alloc] init];
    _popServices = [[NSMutableArray alloc] init];
    
    return self;
}

- (void) dealloc
{
    [_domainMatch release];
    [_imapServices release];
    [_smtpServices release];
    [_popServices release];
    [_mailboxPaths release];
    [_identifier release];
    [super dealloc];
}

- (id) initWithInfo:(NSDictionary *)info
{
    NSArray * imapInfos;
    NSArray * smtpInfos;
    NSArray * popInfos;
    NSDictionary * serverInfo;
    
    self = [self init];
    
    _domainMatch = [[info objectForKey:@"domain-match"] retain];
    _mailboxPaths = [[info objectForKey:@"mailboxes"] retain];
    
    serverInfo = [info objectForKey:@"servers"];
    imapInfos = [serverInfo objectForKey:@"imap"];
    smtpInfos = [serverInfo objectForKey:@"smtp"];
    popInfos = [serverInfo objectForKey:@"pop"];
    
    for(NSDictionary * info in imapInfos) {
        LEPNetService * service;
        
        service = [[LEPNetService alloc] initWithInfo:info];
        [_imapServices addObject:service];
        [service release];
    }
    for(NSDictionary * info in smtpInfos) {
        LEPNetService * service;
        
        service = [[LEPNetService alloc] initWithInfo:info];
        [_smtpServices addObject:service];
        [service release];
    }
    for(NSDictionary * info in popInfos) {
        LEPNetService * service;
        
        service = [[LEPNetService alloc] initWithInfo:info];
        [_popServices addObject:service];
        [service release];
    }
    
    return self;
}

- (NSArray * /* LEPNetService */) imapServices
{
    return _imapServices;
}

- (NSArray * /* LEPNetService */) smtpServices
{
    return _smtpServices;
}

- (NSArray * /* LEPNetService */) popServices
{
    return _popServices;
}

- (BOOL) matchEmail:(NSString *)email
{
    NSArray * components;
    NSString * domain;
    const char * cDomain;
    
    components = [email componentsSeparatedByString:@"@"];
    if ([components count] < 2)
        return NO;
    
    domain = [components lastObject];
    cDomain = [domain UTF8String];
    for(NSString * match in _domainMatch) {
        regex_t r;
        BOOL matched;
        
        if (regcomp(&r, [match UTF8String], REG_EXTENDED | REG_ICASE | REG_NOSUB) != 0)
            continue;
        
        matched = NO;
        if (regexec(&r, cDomain, 0, NULL, 0) == 0) {
            matched = YES;
        }
        
        regfree(&r);
        
        if (matched)
            return YES;
    }
    
    return NO;
}

- (NSString *) sentMailFolderPath
{
    return [_mailboxPaths objectForKey:@"sentmail"];
}

- (NSString *) starredFolderPath
{
    return [_mailboxPaths objectForKey:@"starred"];
}

- (NSString *) allMailFolderPath
{
    return [_mailboxPaths objectForKey:@"allmail"];
}

- (NSString *) trashFolderPath
{
    return [_mailboxPaths objectForKey:@"trash"];
}

- (NSString *) draftsFolderPath
{
    return [_mailboxPaths objectForKey:@"drafts"];
}

- (NSString *) spamFolderPath
{
    return [_mailboxPaths objectForKey:@"spam"];
}

- (NSString *) importantFolderPath
{
    return [_mailboxPaths objectForKey:@"important"];
}

- (BOOL) isMainFolder:(NSString *)folderPath
{
    return [[_mailboxPaths allValues] containsObject:folderPath];
}

@end