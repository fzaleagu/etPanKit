//
//  LEPIMAPRequest.m
//  etPanKit
//
//  Created by DINH Viêt Hoà on 03/01/2010.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "LEPIMAPRequest.h"
#import "LEPIMAPSession.h"

@interface LEPIMAPRequest ()

- (void) _finished;

@end

@implementation LEPIMAPRequest

@synthesize delegate = _delegate;
@synthesize error = _error;
@synthesize session = _session;

- (id) init
{
	self = [super init];
	
	return self;
} 

- (void) dealloc
{
	[_error release];
	[_session release];
	[super dealloc];
}

- (void) startRequest
{
	[_session queueOperation:self];
}

- (void) cancel
{
	[super cancel];
}

- (void) main
{
	if ([self isCancelled]) {
		return;
	}
	
	[self mainRequest];
	
	[self performSelectorOnMainThread:@selector(_finished) withObject:nil waitUntilDone:YES];
}

- (void) mainRequest
{
}

- (void) mainFinished
{
}

- (void) _finished
{
	if ([self isCancelled]) {
		return;
	}
	
	[self mainFinished];
	[[self delegate] LEPIMAPRequest_finished:self];
}

@end