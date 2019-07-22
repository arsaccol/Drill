

// import std.algorithm : canFind, filter, map;
// import std.container : Array, SList;
// import std.array : array, split;

// import std.string : indexOf;
// import std.regex: Regex, regex;
// import std.file : dirEntries, SpanMode, DirEntry, readText, FileException;
// import std.path : buildPath;
// import std.conv: to;

// import Utils : mergeAllTextFilesInDirectory;
// import Logger : Logger;
// import Crawler : Crawler;
// import FileInfo : FileInfo;
// import ApplicationInfo : ApplicationInfo;
import Config : DrillConfig;
import FileInfo : FileInfo;
/**
This struct represents an active Drill search, 
it holds a pool of crawlers and the current state, 
like the searched value
*/
struct DrillContext
{
    import std.container : SList;
    string search_value;
    import Crawler : Crawler;
    SList!Crawler threads;
}


/**
A crawler is active when it's scanning something.
If a crawler cleanly finished its job it's not considered active anymore.
If a crawler crashes (should never happen, generally only for permission problems) it's not considered active.
Minimum: 0
Maximum: length of total number of mountpoints unless the user started the crawlers manually

Returns: number of crawlers active
*/
@nogc @safe immutable(uint) activeCrawlersCount(ref DrillContext context)
{
    int active = 0;
    foreach (thread; context.threads)
        active += thread.isCrawling();
    return active;
}


/*
Notifies the crawlers to stop and clears the crawlers array stored inside DrillContext
This function is non-blocking.
If no crawling is currently underway this function will do nothing.
*/
@nogc @system void stopCrawlingAsync(ref DrillContext context)
{
    import Crawler : Crawler; 
    foreach (Crawler crawler; context.threads)
        crawler.stopAsync();
    context.threads.clear(); // TODO: if nothing has a reference to a thread does the thread get GC-ed?
}


/**
This function will return only when all crawlers finished their jobs or were stopped
This function does not stop the crawlers!!!
*/
@system void waitForCrawlers(ref DrillContext context)
{
    import Crawler : Crawler; 
    import Logger : Logger;
    import std.conv: to;
    Logger.logInfo("Waiting for "~to!string(activeCrawlersCount(context))~" crawlers to stop");
    foreach (Crawler crawler; context.threads)
    {
        Logger.logInfo("Waiting for crawler "~to!string(crawler)~" to stop");
        import core.thread : ThreadException;
        try
        {
            crawler.join();
            Logger.logInfo("Crawler "~to!string(crawler)~" stopped");
        }
        catch(ThreadException e)
        {
            Logger.logError("Thread "~crawler.toString()~" crashed when joining");
            Logger.logError(e.msg);
        }
        
    }
    Logger.logInfo("All crawlers stopped.");
}


/**
This function stops all the crawlers and will return only when all of them are stopped
*/
@system void stopCrawlingSync(ref DrillContext context)
{
    import Crawler : Crawler; 
    foreach (Crawler crawler; context.threads)
        crawler.stopAsync();
    waitForCrawlers(context);
}


/**
Starts the crawling, every crawler will filter on its own.
Use the resultFound callback as an event to know when a crawler finds a new result.
You can call this without stopping the crawling, the old crawlers will get stopped automatically.
If a crawling is already in progress the current one will get stopped asynchronously and a new one will start.

Params:
    search = the search string, case insensitive, every word (split by space) will be searched in the file name
    resultFound = the delegate that will be called when a crawler will find a new result
*/
@system DrillContext startCrawling(const(DrillConfig) config, 
                                   immutable(string) searchValue, 
                                   immutable(void function(immutable(FileInfo) result, void* userObject)) resultCallback, 
                                   void* userObject)
{
    import Utils : getMountpoints;
    import Crawler : Crawler; 
    import Logger : Logger;

    DrillContext c = {searchValue};
    debug Logger.logWarning("user_object is null");
    foreach (immutable(string) mountpoint; getMountpoints())
    {
        Crawler crawler = new Crawler(mountpoint, config.BLOCK_LIST, config.PRIORITY_LIST_REGEX, resultCallback, searchValue,userObject);
        if (config.singlethread)
            crawler.run();
        else
            crawler.start();
        c.threads.insertFront(crawler);
    }
    return c;
}







