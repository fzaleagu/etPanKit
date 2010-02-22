//
//  LEPMessageHeader.m
//  etPanKit
//
//  Created by DINH Viêt Hoà on 31/01/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "LEPMessageHeader.h"

#import "LEPAddress.h"
#import "LEPAddressPrivate.h"
#import "NSString+LEP.h"
#import "NSString+LEPUUID.h"
#import "LEPUtils.h"
#import <libetpan/libetpan.h>

#pragma mark IMAP mailbox conversion

static NSArray * imap_mailbox_list_to_address_array(clist * imap_mailbox_list)
{
    clistiter * cur;
    NSMutableArray * result;
    
    result = [NSMutableArray array];
    
    for(cur = clist_begin(imap_mailbox_list) ; cur != NULL ;
        cur = clist_next(cur)) {
        struct mailimap_address * imap_addr;
        LEPAddress * address;
        
        imap_addr = clist_content(cur);
        address = [LEPAddress addressWithIMAPAddress:imap_addr];
        [result addObject:address];
    }
    
    return result;
}

#pragma mark Message-ID conversion

static NSArray * msg_id_to_string_array(clist * msgids)
{
	clistiter * cur;
	NSMutableArray * result;
	
	result = [NSMutableArray array];
	
	for(cur = clist_begin(msgids) ; cur != NULL ; cur = clist_next(cur)) {
		char * msgid;
		NSString * str;
		
		msgid = clist_content(cur);
		str = [NSString stringWithUTF8String:msgid];
		[result addObject:str];
	}
	
	return result;
}

static clist * msg_id_from_string_array(NSArray * msgids)
{
	clist * result;
	
	result = clist_new();
	for(NSString * msgid in msgids) {
		clist_append(result, strdup([msgid UTF8String]));
	}
	
	return result;
}

#pragma mark date conversion

#ifndef WRONG
#define WRONG	(-1)
#endif /* !defined WRONG */

static int tmcomp(struct tm * atmp, struct tm * btmp)
{
	register int	result;
	
	if ((result = (atmp->tm_year - btmp->tm_year)) == 0 &&
		(result = (atmp->tm_mon - btmp->tm_mon)) == 0 &&
		(result = (atmp->tm_mday - btmp->tm_mday)) == 0 &&
		(result = (atmp->tm_hour - btmp->tm_hour)) == 0 &&
		(result = (atmp->tm_min - btmp->tm_min)) == 0)
		result = atmp->tm_sec - btmp->tm_sec;
	return result;
}

static time_t mkgmtime(struct tm * tmp)
{
	register int			dir;
	register int			bits;
	register int			saved_seconds;
	time_t				t;
	struct tm			yourtm, mytm;
	
	yourtm = *tmp;
	saved_seconds = yourtm.tm_sec;
	yourtm.tm_sec = 0;
	/*
	 ** Calculate the number of magnitude bits in a time_t
	 ** (this works regardless of whether time_t is
	 ** signed or unsigned, though lint complains if unsigned).
	 */
	for (bits = 0, t = 1; t > 0; ++bits, t <<= 1)
		;
	/*
	 ** If time_t is signed, then 0 is the median value,
	 ** if time_t is unsigned, then 1 << bits is median.
	 */
	if(bits > 40) bits = 40;
	t = (t < 0) ? 0 : ((time_t) 1 << bits);
	for ( ; ; ) {
		gmtime_r(&t, &mytm);
		dir = tmcomp(&mytm, &yourtm);
		if (dir != 0) {
			if (bits-- < 0) {
				return WRONG;
			}
			if (bits < 0)
				--t;
			else if (dir > 0)
				t -= (time_t) 1 << bits;
			else	t += (time_t) 1 << bits;
			continue;
		}
		break;
	}
	t += saved_seconds;
	return t;
}

static time_t timestamp_from_date(struct mailimf_date_time * date_time)
{
	struct tm tmval;
	time_t timeval;
	
	tmval.tm_sec  = date_time->dt_sec;
	tmval.tm_min  = date_time->dt_min;
	tmval.tm_hour = date_time->dt_hour;
	tmval.tm_sec  = date_time->dt_sec;
	tmval.tm_mday = date_time->dt_day;
	tmval.tm_mon  = date_time->dt_month - 1;
	tmval.tm_year = date_time->dt_year - 1900;
	
	timeval = mkgmtime(&tmval);
	
	timeval -= date_time->dt_zone * 36;
	
	return timeval;
}

static struct mailimf_date_time * get_date_from_timestamp(time_t timeval)
{
	struct tm gmt;
	struct tm lt;
	int off;
	struct mailimf_date_time * date_time;
	
	gmtime_r(&timeval, &gmt);
	localtime_r(&timeval, &lt);
	
	off = (mkgmtime(&lt) - mkgmtime(&gmt)) / (60 * 60) * 100;
	
	date_time = mailimf_date_time_new(lt.tm_mday, lt.tm_mon + 1,
									  lt.tm_year + 1900,
									  lt.tm_hour, lt.tm_min, lt.tm_sec,
									  off);
	
	return date_time;
}

#pragma mark RFC 2822 mailbox conversion

static NSArray * lep_address_list_from_lep_mailbox(struct mailimf_mailbox_list * mb_list)
{
	NSMutableArray * result;
	clistiter * cur;
	
	result = [NSMutableArray array];
	for(cur = clist_begin(mb_list->mb_list) ; cur != NULL ; cur = clist_next(cur)) {
		struct mailimf_mailbox * mb;
		LEPAddress * address;
		
		mb = clist_content(cur);
		address = [LEPAddress addressWithIMFMailbox:mb];
		[result addObject:address];
	}
	
	return result;
}

static NSArray * lep_address_list_from_lep_addr(struct mailimf_address_list * addr_list)
{
	NSMutableArray * result;
	clistiter * cur;
	
	result = [NSMutableArray array];
	
	for(cur = clist_begin(addr_list->ad_list) ; cur != NULL ;
		cur = clist_next(cur)) {
		struct mailimf_address * addr;
		
		addr = clist_content(cur);
		switch (addr->ad_type) {
			case MAILIMF_ADDRESS_MAILBOX:
			{
				LEPAddress * address;
				
				address = [LEPAddress addressWithIMFMailbox:addr->ad_data.ad_mailbox];
				[result addObject:address];
				break;
			}
			
			case MAILIMF_ADDRESS_GROUP:
			{
				if (addr->ad_data.ad_group->grp_mb_list != NULL) {
					NSArray * subArray;
					
					subArray = lep_address_list_from_lep_mailbox(addr->ad_data.ad_group->grp_mb_list);
					[result addObjectsFromArray:subArray];
				}
				break;
			}
		}
	}
	
	return result;
}

static struct mailimf_mailbox_list * lep_mailbox_list_from_array(NSArray * addresses)
{
	struct mailimf_mailbox_list * mb_list;
	
	mb_list = mailimf_mailbox_list_new_empty();
	
	for(LEPAddress * address in addresses) {
		struct mailimf_mailbox * mailbox;
		
		mailbox = [address createIMFMailbox];
		mailimf_mailbox_list_add(mb_list, mailbox);
	}
	
	return mb_list;
}

static struct mailimf_address_list * lep_address_list_from_array(NSArray * addresses)
{
	struct mailimf_address_list * addr_list;
	
	addr_list = mailimf_address_list_new_empty();

	for(LEPAddress * address in addresses) {
		struct mailimf_address * addr;
		
		addr = [address createIMFAddress];
		mailimf_address_list_add(addr_list, addr);
	}
	
	return addr_list;
}

#pragma mark extract subject

static inline int skip_subj_blob(char * subj, size_t * begin,
								 size_t length)
{
	/* subj-blob       = "[" *BLOBCHAR "]" *WSP */
	size_t cur_token;
	
	cur_token = * begin;
	
	if (subj[cur_token] != '[')
		return 0;
	
	cur_token ++;
	
	while (1) {
		if (cur_token >= length)
			return 0;
		
		if (subj[cur_token] == '[')
			return 0;
		
		if (subj[cur_token] == ']')
			break;
		
		cur_token ++;
	}
	
	cur_token ++;
	
	while (1) {
		if (cur_token >= length)
			break;
		
		if (subj[cur_token] != ' ')
			break;
		
		cur_token ++;
	}
	
	* begin = cur_token;
	
	return 1;
}

static inline int skip_subj_refwd(char * subj, size_t * begin,
								  size_t length)
{
	/* subj-refwd      = ("re" / ("fw" ["d"])) *WSP [subj-blob] ":" */
	size_t cur_token;
	int prefix;
	
	cur_token = * begin;
	
	prefix = 0;
	if (length >= 3) {
		if (strncasecmp(subj + cur_token, "fwd", 3) == 0) {
			cur_token += 3;
			prefix = 1;
		}
	}
	if (!prefix) {
		if (length >= 2) {
			if (strncasecmp(subj + cur_token, "fw", 2) == 0) {
				cur_token += 2;
				prefix = 1;
			}
			else if (strncasecmp(subj + cur_token, "re", 2) == 0) {
				cur_token += 2;
				prefix = 1;
			}
		}
	}
	
	if (!prefix)
		return 0;
	
	while (1) {
		if (cur_token >= length)
			break;
		
		if (subj[cur_token] != ' ')
			break;
		
		cur_token ++;
	}
	
	skip_subj_blob(subj, &cur_token, length);
	
	if (subj[cur_token] != ':')
		return 0;
	
	cur_token ++;
	
	* begin = cur_token;
	
	return 1;
}

static inline int skip_subj_leader(char * subj, size_t * begin,
								   size_t length)
{
	size_t cur_token;
	
	cur_token = * begin;
	
	/* subj-leader     = (*subj-blob subj-refwd) / WSP */
	
	if (subj[cur_token] == ' ') {
		cur_token ++;
	}
	else {
		while (cur_token < length) {
			if (!skip_subj_blob(subj, &cur_token, length))
				break;
		}
		if (!skip_subj_refwd(subj, &cur_token, length))
			return 0;
	}
	
	* begin = cur_token;
	
	return 1;
}

static char * extract_subject(char * str)
{
	char * subj;
	char * cur;
	char * write_pos;
	size_t len;
	size_t begin;
	int do_repeat_5;
	int do_repeat_6;
	
	/*
	 (1) Convert any RFC 2047 encoded-words in the subject to
	 UTF-8.
	 We work on UTF-8 string -- DVH
	 */
	
	subj = strdup(str);
	if (subj == NULL)
		return NULL;
	
	len = strlen(subj);
	
	/*
	 Convert all tabs and continuations to space.
	 Convert all multiple spaces to a single space.
	 */
	
	cur = subj;
	write_pos = subj;
	while (* cur != '\0') {
		int cont;
		
		switch (* cur) {
			case '\t':
			case '\r':
			case '\n':
				cont = 1;
				
				cur ++;
				while (* cur && cont) {
					switch (* cur) {
						case '\t':
						case '\r':
						case '\n':
							cont = 1;
							break;
						default:
							cont = 0;
							break;
					}
					cur ++;
				}
				
				* write_pos = ' ';
				write_pos ++;
				
				break;
				
			default:
				* write_pos = * cur;
				write_pos ++;
				
				cur ++;
				
				break;
		}
	}
	* write_pos = '\0';
	
	begin = 0;
	
	do {
		do_repeat_6 = 0;
		
		/*
		 (2) Remove all trailing text of the subject that matches
		 the subj-trailer ABNF, repeat until no more matches are
		 possible.
		 */
		
		while (len > 0) {
			int chg;
			
			chg = 0;
			
			/* subj-trailer    = "(fwd)" / WSP */
			if (subj[len - 1] == ' ') {
				subj[len - 1] = '\0';
				len --;
			}
			else {
				if (len < 5)
					break;
				
				if (strncasecmp(subj + len - 5, "(fwd)", 5) != 0)
					break;
				
				subj[len - 5] = '\0';
				len -= 5;
			}
		}
		
		do {
			size_t saved_begin;
			
			do_repeat_5 = 0;
			
			/*
			 (3) Remove all prefix text of the subject that matches the
			 subj-leader ABNF.
			 */
			
			if (skip_subj_leader(subj, &begin, len))
				do_repeat_5 = 1;
			
			/*
			 (4) If there is prefix text of the subject that matches the
			 subj-blob ABNF, and removing that prefix leaves a non-empty
			 subj-base, then remove the prefix text.
			 */
			
			saved_begin = begin;
			if (skip_subj_blob(subj, &begin, len)) {
				if (begin == len) {
					/* this will leave a empty subject base */
					begin = saved_begin;
				}
				else
					do_repeat_5 = 1;
			}
			
			/*
			 (5) Repeat (3) and (4) until no matches remain.
			 Note: it is possible to defer step (2) until step (6),
			 but this requires checking for subj-trailer in step (4).
			 */
			
		}
		while (do_repeat_5);
		
		/*
		 (6) If the resulting text begins with the subj-fwd-hdr ABNF
		 and ends with the subj-fwd-trl ABNF, remove the
		 subj-fwd-hdr and subj-fwd-trl and repeat from step (2).
		 */
		
		if (len >= 5) {
			size_t saved_begin;
			
			saved_begin = begin;
			if (strncasecmp(subj + begin, "[fwd:", 5) == 0) {
				begin += 5;
				
				if (subj[len - 1] != ']')
					saved_begin = begin;
				else {
					subj[len - 1] = '\0';
					len --;
					do_repeat_6 = 1;
				}
			}
		}
		
	}
	while (do_repeat_6);
	
	/*
	 (7) The resulting text is the "base subject" used in
	 threading.
	 */
	
	/* convert to upper case */
	
	cur = subj + begin;
	write_pos = subj;
	
	while (* cur != '\0') {
		* write_pos = * cur;
		cur ++;
		write_pos ++;
	}
	* write_pos = '\0';
	
	return subj;
}

@implementation LEPMessageHeader

@synthesize date = _date;
@synthesize messageID = _messageID;
@synthesize references = _references;
@synthesize inReplyTo = _inReplyTo;
@synthesize from = _from;
@synthesize to = _to;
@synthesize cc = _cc;
@synthesize bcc = _bcc;
@synthesize replyTo = _replyTo;
@synthesize subject = _subject;

- (id) init
{
	char * msgid;
	
	self = [super init];
	
	[self setDate:[NSDate date]];
	msgid = mailimf_get_message_id();
	[self setMessageID:[NSString stringWithUTF8String:msgid]];
	free(msgid);
	
	return self;
} 

- (void) dealloc
{
	[_messageID release];
	[_references release];
	[_inReplyTo release];
	[_from release];
	[_to release];
	[_cc release];
	[_bcc release];
    [_replyTo release];
	[_subject release];
    [_date release];
    
	[super dealloc];
}

- (void) setFromIMFFields:(struct mailimf_fields *)fields
{
	struct mailimf_single_fields single_fields;
	
	mailimf_single_fields_init(&single_fields, fields);
	
	/* date */
	
	if (single_fields.fld_orig_date != NULL) {
		time_t timestamp;
		
		timestamp = timestamp_from_date(single_fields.fld_orig_date->dt_date_time);
		[self setDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
		LEPLog(@"%lu %@", (unsigned long) timestamp, [self date]);
	}
	
	/* subject */
	if (single_fields.fld_subject != NULL) {
		char * subject;
		
		subject = single_fields.fld_subject->sbj_value;
		[self setSubject:[NSString lepStringByDecodingMIMEHeaderValue:subject]];
	}
	
	/* from */
	if (single_fields.fld_from != NULL) {
		struct mailimf_mailbox_list * mb_list;
		NSArray * addresses;
		
		mb_list = single_fields.fld_from->frm_mb_list;
		addresses = lep_address_list_from_lep_mailbox(mb_list);
		if ([addresses count] > 0) {
			[self setFrom:[addresses objectAtIndex:0]];
		}
	}
	
	/* replyto */
	if (single_fields.fld_reply_to != NULL) {
		struct mailimf_address_list * addr_list;
		NSArray * addresses;
		
		addr_list = single_fields.fld_reply_to->rt_addr_list;
		addresses = lep_address_list_from_lep_addr(addr_list);
		[self setReplyTo:addresses];
	}
	
	/* to */
	if (single_fields.fld_to != NULL) {
		struct mailimf_address_list * addr_list;
		NSArray * addresses;
		
		addr_list = single_fields.fld_to->to_addr_list;
		addresses = lep_address_list_from_lep_addr(addr_list);
		[self setTo:addresses];
	}
	
	/* cc */
	if (single_fields.fld_cc != NULL) {
		struct mailimf_address_list * addr_list;
		NSArray * addresses;
		
		addr_list = single_fields.fld_cc->cc_addr_list;
		addresses = lep_address_list_from_lep_addr(addr_list);
		[self setCc:addresses];
	}
	
	/* bcc */
	if (single_fields.fld_bcc != NULL) {
		struct mailimf_address_list * addr_list;
		NSArray * addresses;
		
		addr_list = single_fields.fld_bcc->bcc_addr_list;
		addresses = lep_address_list_from_lep_addr(addr_list);
		[self setBcc:addresses];
	}
	
	/* msgid */
	if (single_fields.fld_message_id != NULL) {
		char * msgid;
		
		msgid = single_fields.fld_message_id->mid_value;
		[self setMessageID:[NSString stringWithUTF8String:msgid]];
	}
	
	/* references */
	if (single_fields.fld_references != NULL) {
		clist * msg_id_list;
		NSArray * msgids;
		
		msg_id_list = single_fields.fld_references->mid_list;
		msgids = msg_id_to_string_array(msg_id_list);
		[self setReferences:msgids];
	}
	
	/* inreplyto */
	if (single_fields.fld_in_reply_to != NULL) {
		clist * msg_id_list;
		NSArray * msgids;
		
		msg_id_list = single_fields.fld_in_reply_to->mid_list;
		msgids = msg_id_to_string_array(msg_id_list);
		[self setInReplyTo:msgids];
	}
}

- (void) setFromIMAPEnvelope:(struct mailimap_envelope *)env
{
	if (env->env_date != NULL) {
		size_t cur_token;
		struct mailimf_date_time * date_time;
		int r;
		
		cur_token = 0;
		r = mailimf_date_time_parse(env->env_date, strlen(env->env_date),
									&cur_token, &date_time);
		if (r == MAILIMF_NO_ERROR) {
			time_t timestamp;
			
			// date
			timestamp = timestamp_from_date(date_time);
			[self setDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
			mailimf_date_time_free(date_time);
		}
	}
	
	if (env->env_subject != NULL) {
		char * subject;
		
		// subject
		subject = env->env_subject;
		[self setSubject:[NSString lepStringByDecodingMIMEHeaderValue:subject]];
	}
	
	if (env->env_from != NULL) {
		if (env->env_from->frm_list != NULL) {
			NSArray * addresses;
			
			addresses = imap_mailbox_list_to_address_array(env->env_from->frm_list);
			if ([addresses count] > 0) {
				[self setFrom:[addresses objectAtIndex:0]];
			}
		}
	}
	
	// skip Sender header
	
	if (env->env_reply_to != NULL) {
		if (env->env_reply_to->rt_list != NULL) {
			NSArray * addresses;
			
			addresses = imap_mailbox_list_to_address_array(env->env_reply_to->rt_list);
			[self setReplyTo:addresses];
		}
	}
	
	if (env->env_to != NULL) {
		if (env->env_to->to_list != NULL) {
			NSArray * addresses;
			
			addresses = imap_mailbox_list_to_address_array(env->env_to->to_list);
			[self setTo:addresses];
		}
	}
	
	if (env->env_cc != NULL) {
		if (env->env_cc->cc_list != NULL) {
			NSArray * addresses;
			
			addresses = imap_mailbox_list_to_address_array(env->env_cc->cc_list);
			[self setCc:addresses];
		}
	}
	
	if (env->env_bcc != NULL) {
		if (env->env_bcc->bcc_list != NULL) {
			NSArray * addresses;
			
			addresses = imap_mailbox_list_to_address_array(env->env_bcc->bcc_list);
			[self setBcc:addresses];
		}
	}
	
	if (env->env_in_reply_to != NULL) {
		size_t cur_token;
		clist * msg_id_list;
		int r;
		
		cur_token = 0;
		r = mailimf_msg_id_list_parse(env->env_in_reply_to,
									  strlen(env->env_in_reply_to), &cur_token, &msg_id_list);
		if (r == MAILIMF_NO_ERROR) {
			NSArray * msgids;
			
			msgids = msg_id_to_string_array(msg_id_list);
			[self setInReplyTo:msgids];
			// in-reply-to
			clist_foreach(msg_id_list, (clist_func) mailimf_msg_id_free, NULL);
			clist_free(msg_id_list);
		}
	}
	
	if (env->env_message_id != NULL) {
		char * msgid;
		size_t cur_token;
		int r;
		
		cur_token = 0;
		r = mailimf_msg_id_parse(env->env_message_id, strlen(env->env_message_id),
								 &cur_token, &msgid);
		if (r == MAILIMF_NO_ERROR) {
			// msg id
			[self setMessageID:[NSString stringWithUTF8String:msgid]];
		}
	}
}

- (void) setFromIMAPReferences:(NSData *)data
{
	size_t cur_token;
	clist * msg_id_list;
	int r;
	
	cur_token = 0;
	r = mailimf_msg_id_list_parse([data bytes], [data length], &cur_token, &msg_id_list);
	if (r == MAILIMF_NO_ERROR) {
		NSArray * msgids;
		
		msgids = msg_id_to_string_array(msg_id_list);
		[self setReferences:msgids];
		clist_foreach(msg_id_list, (clist_func) mailimf_msg_id_free, NULL);
		clist_free(msg_id_list);
	}
}

- (struct mailimf_fields *) createIMFFields
{
	struct mailimf_date_time * date;
	char * msgid;
	char * subject;
	struct mailimf_mailbox_list * from;
	struct mailimf_address_list * reply_to;
	struct mailimf_address_list * to;
	struct mailimf_address_list * cc;
	struct mailimf_address_list * bcc;
	clist * in_reply_to;
	clist * references;
	
	date = NULL;
	if ([self date] != nil) {
		LEPLog(@"%@", [self date]);
		date = get_date_from_timestamp((time_t) [[self date] timeIntervalSince1970]);
	}
	from = NULL;
	if ([self from] != nil) {
		from = lep_mailbox_list_from_array([NSArray arrayWithObject:[self from]]);
	}
	reply_to = NULL;
	if ([[self replyTo] count] > 0) {
		reply_to = lep_address_list_from_array([self replyTo]);
	}
	to = NULL;
	if ([[self to] count] > 0) {
		to = lep_address_list_from_array([self to]);
	}
	cc = NULL;
	if ([[self cc] count] > 0) {
		cc = lep_address_list_from_array([self cc]);
	}
	bcc = NULL;
	if ([[self bcc] count] > 0) {
		bcc = lep_address_list_from_array([self bcc]);
	}
	msgid = NULL;
	if ([self messageID] != nil) {
		msgid = strdup([[self messageID] UTF8String]);
	}
	in_reply_to = NULL;
	if ([self inReplyTo] > 0) {
		in_reply_to = msg_id_from_string_array([self inReplyTo]);
	}
	references = NULL;
	if ([self references] > 0) {
		references = msg_id_from_string_array([self references]);
	}
	subject = NULL;
	if ([self subject] != NULL) {
		subject = strdup([[[self subject] lepEncodedMIMEHeaderValue] bytes]);
	}
	return mailimf_fields_new_with_data_all(date,
											from,
											NULL /* sender */,
											reply_to,
											to,
											cc,
											bcc,
											msgid,
											in_reply_to,
											references,
											subject);
}

- (NSString *) extractedSubject
{
	char * result;
	NSString * str;
	
	if ([self subject] == nil)
		return nil;
	
	result = extract_subject((char *) [[self subject] UTF8String]);
	
	str = [NSString stringWithUTF8String:result];
	free(result);
	
	return str;
}

@end