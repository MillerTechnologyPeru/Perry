#ifndef PERRYSTEAMAPI_H
#define PERRYSTEAMAPI_H

// libPerrysteam_api: Steamworks' libsteam_api.dylib, over the running Linux
// Steam client's steamclient.so.

/// The loader asks for imports this library does not define itself: none
/// are bound, and PERRY_STEAM_TRACE names them.
void *perry_provider_symbol(const char *name);

#endif
