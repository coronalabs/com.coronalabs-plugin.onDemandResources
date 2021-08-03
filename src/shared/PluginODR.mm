//
//  PluginODR.mm
//
//  Copyright (c) 2016 Corona Labs. All rights reserved.
//

#import "PluginODR.h"

#include "CoronaRuntime.h"
#include "CoronaEvent.h"

#import <UIKit/UIKit.h>

// ----------------------------------------------------------------------------

class PluginODR;

@interface BundleRequestWrapper : NSObject

@property (retain) NSBundleResourceRequest* request;
@property (assign) BOOL requestSucceeded;
@property (assign) CoronaLuaRef instanceCallback;
@property (assign) lua_State* L;


-(void)performRequestWithTag:(NSString*)tag download:(BOOL)download andInstanceCallback:(CoronaLuaRef)callback withLibrary:(PluginODR*)library;

@end



@interface LowDiskSpaceWatcher : NSObject {
	PluginODR *library;
}

- (instancetype)initWithLibrary:(PluginODR*)_library;
-(void)lowDiskSpaceWithNote:(NSNotification*)note;

@end


class PluginODR
{
	public:
		typedef PluginODR Self;

	public:
		static const char kName[];
		static const char kEvent[];

	protected:
		PluginODR();
		~PluginODR();

	public:
		CoronaLuaRef GetListener() const { return fListener; }
		lua_State* GetLua() const { return fL; }

	public:
		static int Open( lua_State *L );

	protected:
		static int Finalizer( lua_State *L );

	public:
		static Self *ToLibrary( lua_State *L );

	public:
		static int setEventListener( lua_State *L );
	
		static int request( lua_State *L );
	
		static int progress( lua_State *L );
		static int pause( lua_State *L );
		static int resume( lua_State *L );
		static int cancel( lua_State *L );
	
		static int getDownloadPriority( lua_State *L );
		static int setDownloadPriority( lua_State *L );
	
		static int getPreservationPriority( lua_State *L );
		static int setPreservationPriority( lua_State *L );
	
		static int path( lua_State *L );
	
	public:
		void DispatchLowDiskWarning();
		void DispatchResourceAvailable(NSString *tag, bool available, NSError* error, CoronaLuaRef instanceCallback);
	
	private:
        static void PushResourceAvailableEvent(lua_State *L, NSString *tag, bool available, NSError* error);

	
		lua_State *fL;
		NSMutableDictionary<NSString*, BundleRequestWrapper*> *fRequests;
		CoronaLuaRef fListener;
		LowDiskSpaceWatcher *fLowDiskSpaceWatcher;
};


@implementation LowDiskSpaceWatcher

- (instancetype)initWithLibrary:(PluginODR*)_library
{
	self = [super init];
	if (self) {
		library = _library;
	}
	return self;
}

-(void)lowDiskSpaceWithNote:(NSNotification *)note
{
	[[NSOperationQueue mainQueue] addOperationWithBlock:^{
		library->DispatchLowDiskWarning();
	}];
}

@end


@implementation BundleRequestWrapper

@synthesize request;
@synthesize requestSucceeded;
@synthesize instanceCallback;
@synthesize L;

-(void)dealloc
{
	if (instanceCallback)
	{
		CoronaLuaDeleteRef(self.L, instanceCallback);
		self.instanceCallback = 0;
	}
	[super dealloc];
}

-(void)performRequestWithTag:(NSString *)tag download:(BOOL)download andInstanceCallback:(CoronaLuaRef)callback withLibrary:(PluginODR *)library
{
	
	if(self.instanceCallback)
	{
		CoronaLuaDeleteRef( library->GetLua(), self.instanceCallback );
	}
	if (callback)
	{
		self.L = library->GetLua();
		self.instanceCallback = callback;
	}
	
	if(!request)
	{
		NSBundleResourceRequest *_req = [[NSBundleResourceRequest alloc] initWithTags:[NSSet setWithObject:tag]];
		self.request = _req;
		[_req release];
	}

	// avoid consequtive successfull calls
	if (requestSucceeded)
	{
		[[NSOperationQueue mainQueue] addOperationWithBlock:^{
			library->DispatchResourceAvailable(self.request.tags.anyObject, requestSucceeded, nil, self.instanceCallback);
		}];
		return;
	}
	
	
	if (download)
	{
		[self.request beginAccessingResourcesWithCompletionHandler:^(NSError *error) {
			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				requestSucceeded = (error == nil);
				library->DispatchResourceAvailable(self.request.tags.anyObject, requestSucceeded, error, self.instanceCallback);
			}];
		}];
	}
	else
	{
		[self.request conditionallyBeginAccessingResourcesWithCompletionHandler:^(BOOL resourcesAvailable) {
			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				requestSucceeded = resourcesAvailable;
				library->DispatchResourceAvailable(self.request.tags.anyObject, requestSucceeded, nil, self.instanceCallback);
			}];
		}];
	}
}

@end


// ----------------------------------------------------------------------------

// This corresponds to the name of the library, e.g. [Lua] require "plugin.onDemandResources"
const char PluginODR::kName[] = "plugin.onDemandResources";

// This corresponds to the event name, e.g. [Lua] event.name
const char PluginODR::kEvent[] = "OnDemandResourcesEvent";

PluginODR::PluginODR()
: fListener( NULL )
, fRequests( nil )
, fLowDiskSpaceWatcher( nil )
, fL( NULL )
{
}

PluginODR::~PluginODR()
{
	CoronaLuaDeleteRef( fL, GetListener() );
	[fRequests release];
	if (fLowDiskSpaceWatcher)
	{
		[[NSNotificationCenter defaultCenter] removeObserver:fLowDiskSpaceWatcher];
		[fLowDiskSpaceWatcher release];
	}
	
}

int
PluginODR::Open( lua_State *L )
{
	// Register __gc callback
	const char kMetatableName[] = __FILE__; // Globally unique string to prevent collision
	CoronaLuaInitializeGCMetatable( L, kMetatableName, Finalizer );

	// Functions in library
	const luaL_Reg kVTable[] =
	{
		{"setEventListener", setEventListener},
		{"request", request},
		{"progress", progress},
		{"pause", pause},
		{"resume", resume},
		{"cancel", cancel},
		{"getDownloadPriority", getDownloadPriority},
		{"setDownloadPriority", setDownloadPriority},
		{"getPreservationPriority", getPreservationPriority},
		{"setPreservationPriority", setPreservationPriority},
		
		{"path", path},

		{ NULL, NULL }
	};

	// Set library as upvalue for each library function
	Self *library = new Self;
	library->fL = L;
	CoronaLuaPushUserdata( L, library, kMetatableName );

	luaL_openlib( L, kName, kVTable, 1 ); // leave "library" on top of stack

	return 1;
}

int
PluginODR::Finalizer( lua_State *L )
{
	Self *library = (Self *)CoronaLuaToUserdata( L, 1 );
	
	library->fL = L;
	delete library;

	return 0;
}

PluginODR *
PluginODR::ToLibrary( lua_State *L )
{
	// library is pushed as part of the closure
	Self *library = (Self *)CoronaLuaToUserdata( L, lua_upvalueindex( 1 ) );
	return library;
}

// [Lua] odr.setEventListener( listener )
int
PluginODR::setEventListener( lua_State *L )
{
	int listenerIndex = 1;

	if ( CoronaLuaIsListener( L, listenerIndex, kEvent ) )
	{
		Self *library = ToLibrary( L );
		library->fL = L;
		CoronaLuaRef listener = CoronaLuaNewRef( L, listenerIndex );
		if ( listener )
		{
			if(library->GetListener())
			{
				CoronaLuaDeleteRef( L, library->GetListener());
			}
			library->fListener = listener;
			
			if (!library->fRequests)
			{
				library->fRequests = [[NSMutableDictionary alloc] init];
			}
			
			if (!library->fLowDiskSpaceWatcher)
			{
				library->fLowDiskSpaceWatcher = [[LowDiskSpaceWatcher alloc] initWithLibrary:library];
				[[NSNotificationCenter defaultCenter] addObserver:library->fLowDiskSpaceWatcher
														 selector:@selector(lowDiskSpaceWithNote:)
															 name:NSBundleResourceRequestLowDiskSpaceNotification
														   object:nil];
			}
		}

	}

	return 0;
}


int
PluginODR::request( lua_State *L )
{
	int index = 1;
	int results = 0;
	NSString *tag = nil;
	if ( lua_type( L, index ) == LUA_TSTRING )
	{
		tag = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}
	index ++;
	
	BOOL download = YES;
	if ( lua_type( L, index ) == LUA_TBOOLEAN )
	{
		download = lua_toboolean( L, index );
		index++;
	}
	
	CoronaLuaRef instanceListener = 0;
	if ( [tag length] && CoronaLuaIsListener( L, index, kEvent ))
	{
		instanceListener = CoronaLuaNewRef( L, index);
		index++;
	}
	
	Self *library = ToLibrary( L );
	if ( !library->fListener && !instanceListener )
	{
		CoronaLuaWarning( L, "ERROR: odr.request() - no listener set in odr.init or as last parameter to this call." );
	}
	else if ([tag length])
	{
		if (!library->fRequests)
		{
			library->fRequests = [[NSMutableDictionary alloc] init];
			library->fL = L;
		}

		BundleRequestWrapper* requestWrapper = [library->fRequests valueForKey:tag];
		if (!requestWrapper)
		{
			requestWrapper = [[BundleRequestWrapper alloc] init];
			[library->fRequests setObject:requestWrapper forKey:tag];
			[requestWrapper release]; // dictionary is holding to a reference
		}
		[requestWrapper performRequestWithTag:tag
									 download:download
						  andInstanceCallback:instanceListener
								  withLibrary:library];
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: odr.request() - should receive tag name as first parameter" );
	}
	
	return results;
}

int
PluginODR::progress( lua_State *L )
{
	int results = 0;
	NSString *tag = nil;
	if ( lua_type( L, 1 ) == LUA_TSTRING )
	{
		tag = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}
	
	if ([tag length])
	{
		Self *library = ToLibrary( L );
		
		NSBundleResourceRequest* request = [[library->fRequests valueForKey:tag] request];
		if (request)
		{
			lua_pushnumber( L, request.progress.fractionCompleted );
			lua_pushnumber( L, request.progress.totalUnitCount );
			lua_pushnumber( L, request.progress.completedUnitCount );
			results = 3;
		}
		else
		{
			CoronaLuaWarning( L, "ERROR: odr.progress() - called before requesting a resource" );
			lua_pushnil( L );
			results = 1;
		}
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: odr.progress() - should receive tag name as first parameter" );
	}
	
	return results;
}

int
PluginODR::pause( lua_State *L )
{
	int results = 0;
	NSString *tag = nil;
	if ( lua_type( L, 1 ) == LUA_TSTRING )
	{
		tag = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}
	
	if ([tag length])
	{
		Self *library = ToLibrary( L );
		
		NSBundleResourceRequest* request = [[library->fRequests valueForKey:tag] request];
		if (request)
		{
			[request.progress pause];
		}
		else
		{
			CoronaLuaWarning( L, "ERROR: odr.pause() - called before requesting a resource" );
		}
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: odr.pause() - should receive tag name as first parameter" );
	}
	
	return results;
}

int
PluginODR::resume( lua_State *L )
{
	int results = 0;
	NSString *tag = nil;
	if ( lua_type( L, 1 ) == LUA_TSTRING )
	{
		tag = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}
	
	if ([tag length])
	{
		Self *library = ToLibrary( L );
		
		NSBundleResourceRequest* request = [[library->fRequests valueForKey:tag] request];
		if (request)
		{
			[request.progress resume];
		}
		else
		{
			CoronaLuaWarning( L, "ERROR: odr.resume() - called before requesting a resource" );
		}
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: odr.resume() - should receive tag name as first parameter" );
	}
	
	return results;
}

int
PluginODR::cancel( lua_State *L )
{
	int results = 0;
	NSString *tag = nil;
	if ( lua_type( L, 1 ) == LUA_TSTRING )
	{
		tag = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}
	
	if ([tag length])
	{
		Self *library = ToLibrary( L );
		
		NSBundleResourceRequest* request = [[library->fRequests valueForKey:tag] request];
		if (request)
		{
			[request.progress cancel];
			[library->fRequests removeObjectForKey:tag];
		}
		else
		{
			CoronaLuaWarning( L, "ERROR: odr.cancel() - called before requesting a resource" );
		}
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: odr.cancel() - should receive tag name as first parameter" );
	}
	
	return results;
}

int
PluginODR::getDownloadPriority( lua_State *L )
{
	int results = 0;
	NSString *tag = nil;
	if ( lua_type( L, 1 ) == LUA_TSTRING )
	{
		tag = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}
	
	if ([tag length])
	{
		Self *library = ToLibrary( L );
		
		NSBundleResourceRequest* request = [[library->fRequests valueForKey:tag] request];
		if (request)
		{
			lua_pushnumber( L, request.loadingPriority );
			results = 1;
		}
		else
		{
			CoronaLuaWarning( L, "ERROR: odr.getDownloadPriority() - called before requesting a resource" );
		}
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: odr.getDownloadPriority() - should receive tag name as first parameter" );
	}
	
	return results;
}

int
PluginODR::setDownloadPriority( lua_State *L )
{
	int results = 0;
	NSString *tag = nil;
	if ( lua_type( L, 1 ) == LUA_TSTRING )
	{
		tag = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}
	
	double priority = 0;
	if ( lua_type( L, 2 ) == LUA_TNUMBER )
	{
		priority = lua_tonumber( L, 2 );
	}
	else if (lua_type( L, 2 ) == LUA_TSTRING && strcmp("urgent", lua_tostring(L, 2))==0 )
	{
		priority = NSBundleResourceRequestLoadingPriorityUrgent;
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: odr.setDownloadPriority() - second parameter must be a number between 0 and 1 or 'urgent'" );
	}
	
	if ([tag length])
	{
		Self *library = ToLibrary( L );
		
		NSBundleResourceRequest* request = [[library->fRequests valueForKey:tag] request];
		if (request)
		{
			request.loadingPriority = priority;
		}
		else
		{
			CoronaLuaWarning( L, "ERROR: odr.setDownloadPriority() - called before requesting a resource" );
		}
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: odr.setDownloadPriority() - should receive tag name as first parameter" );
	}
	
	return results;
}

int
PluginODR::getPreservationPriority( lua_State *L )
{
	int results = 0;
	NSString *tag = nil;
	if ( lua_type( L, 1 ) == LUA_TSTRING )
	{
		tag = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}
	
	if ([tag length])
	{
		@try
		{
			lua_pushnumber(L, [[NSBundle mainBundle] preservationPriorityForTag:tag]);
			results = 1;
		}
		@catch (NSException *exception)
		{
			CoronaLuaWarning( L, "ERROR: getPreservationPriority() - error occured while getting preservation priority of the tag '%s'", [tag UTF8String] );
		}
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: getPreservationPriority() - should receive tag name as first parameter" );
	}
	
	return results;
}

int
PluginODR::setPreservationPriority( lua_State *L )
{
	int results = 0;
	NSString *tag = nil;
	if ( lua_type( L, 1 ) == LUA_TSTRING )
	{
		tag = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}
	
	double priority = 0;
	if ( lua_type( L, 2 ) == LUA_TNUMBER )
	{
		priority = lua_tonumber( L, 2 );
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: odr.setPreservationPriority() - second parameter must be a number between 0 and 1" );
	}
	
	if ([tag length])
	{
		@try
		{
			[[NSBundle mainBundle] setPreservationPriority:priority forTags:[NSSet setWithObject:tag]];
		}
		@catch (NSException *exception)
		{
			CoronaLuaWarning( L, "ERROR: setPreservationPriority() - error occured while setting priority to the tag '%s'", [tag UTF8String] );
		}
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: setPreservationPriority() - should receive tag name as first parameter" );
	}
	
	return results;
}

int
PluginODR::path( lua_State *L )
{
	int results = 0;
	NSString *resource = nil;
	if ( lua_type( L, 1 ) == LUA_TSTRING )
	{
		resource = [NSString stringWithUTF8String:lua_tostring( L,  1 )];
	}

	if ([resource length])
	{
		@try
		{
			NSString *path = [[NSBundle mainBundle] pathForResource:resource ofType:nil];
			if (path)
			{
				lua_pushstring( L, [path UTF8String]);
			}
			else
			{
				lua_pushnil( L );
			}
			results = 1;
		}
		@catch (NSException *exception)
		{
			CoronaLuaWarning( L, "ERROR: path() - error occured when fetching path for resource '%s'", [resource UTF8String] );
		}
	}
	else
	{
		CoronaLuaWarning( L, "ERROR: path() - should receive resource name as only parameter" );
	}
	
	return results;
}

void
PluginODR::DispatchLowDiskWarning()
{
	if (!fL || !GetListener())
	{
		return;
	}
	lua_State *L = fL;
	
	CoronaLuaNewEvent( L, kEvent );
	
	lua_pushstring(L, "lowDiskSpace");
	lua_setfield( L, -2, CoronaEventTypeKey());
	
	lua_pushboolean( L, true );
	lua_setfield( L, -2, CoronaEventIsErrorKey());
	
	CoronaLuaDispatchEvent( L, GetListener(), 0 );
}

void
PluginODR::PushResourceAvailableEvent(lua_State *L, NSString *tag, bool available, NSError* error)
{
	CoronaLuaNewEvent( L, kEvent );
	
	lua_pushstring(L, "complete");
	lua_setfield( L, -2, CoronaEventTypeKey());
	
	lua_pushboolean( L, !available );
	lua_setfield( L, -2, CoronaEventIsErrorKey());
	
	if(tag)
	{
		lua_pushstring( L, [tag UTF8String]);
		lua_setfield( L, -2, "tag" );
	}
	
	if (error)
	{
		lua_pushnumber( L, error.code);
		lua_setfield( L, -2, "errorCode" );
		
		lua_pushstring( L, [error.localizedDescription UTF8String]);
		lua_setfield( L, -2, "error" );
	}
	
}

void
PluginODR::DispatchResourceAvailable(NSString *tag, bool available, NSError* error, CoronaLuaRef instanceCallback)
{
	if (!fL)
	{
		return;
	}
	lua_State *L = fL;
	
	if (instanceCallback)
	{
		PushResourceAvailableEvent(L, tag, available, error);
		CoronaLuaDispatchEvent( L, instanceCallback, 0 );
	}
	
	if (GetListener())
	{
		PushResourceAvailableEvent(L, tag, available, error);
		CoronaLuaDispatchEvent( L, GetListener(), 0 );
	}
}

// ----------------------------------------------------------------------------

CORONA_EXPORT int luaopen_plugin_onDemandResources( lua_State *L )
{
	return PluginODR::Open( L );
}
