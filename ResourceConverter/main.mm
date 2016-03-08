//
//  main.mm
//  ResourceConverter
//
//  Copyright © 2016 vit9696. All rights reserved.
//

//This file is a shameful terribly written copy-paste-like draft with minimal error checking if at all
//TODO: Rewrite this completely

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#include <initializer_list>

#define SYSLOG(str, ...) printf("ResourceConverter: " str "\n", ## __VA_ARGS__)
#define ERROR(str, ...) do { SYSLOG(str, ## __VA_ARGS__); exit(1); } while(0)
NSString *ResourceHeader {@"\
//                                                   \n\
//  kern_resources.cpp                               \n\
//  AppleALC                                         \n\
//                                                   \n\
//  Copyright © 2016 vit9696. All rights reserved.   \n\
//                                                   \n\
//  This is an autogenerated file!                   \n\
//  Please avoid any modifications!                  \n\
//                                                   \n\n\
#include \"kern_resources.hpp\"                      \n\n"
};

static void appendFile(NSString *file, NSString *data) {
	NSFileHandle *handle = [NSFileHandle fileHandleForUpdatingAtPath:file];
	[handle seekToEndOfFile];
	[handle writeData:[data dataUsingEncoding:NSUTF8StringEncoding]];
	[handle closeFile];
}

static NSString *makeStringList(NSString *name, size_t index, NSArray *array, NSString *type=@"char *") {
	auto str = [[NSMutableString alloc] initWithFormat:@"static const %@ %@%zu[] { ", type, name, index];
	
	if ([type isEqualToString:@"char *"]) {
		for (NSString *item in array) {
			[str appendFormat:@"\"%@\", ", item];
		}
	} else {
		for (NSNumber *item in array) {
			[str appendFormat:@"0x%lX, ", [item unsignedLongValue]];
		}
	}
	
	[str appendString:@"};\n"];
	
	return str;
}

static NSDictionary * generateKexts(NSString *file, NSDictionary *kexts) {
	auto kextPathsSection = [[NSMutableString alloc] initWithUTF8String:"\n// Kext section\n\n"];
	auto kextSection = [[NSMutableString alloc] init];
	auto kextNums = [[NSMutableDictionary alloc] init];
	
	[kextSection appendString:@"KernelPatcher::KextInfo kextList[] {\n"];
	
	size_t kextIndex {0};
	size_t kextAppleHDAIndex {0};
	
	for (NSString *kextName in kexts) {
		if ([kextName isEqualToString:@"AppleHDA"]) {
			kextAppleHDAIndex = kextIndex;
		}
		
		NSDictionary *kextInfo = [kexts objectForKey:kextName];
		NSString *kextID = [kextInfo objectForKey:@"Id"];
		NSArray *kextPaths = [kextInfo objectForKey:@"Paths"];
		
		[kextPathsSection appendString:makeStringList(@"kextPath", kextIndex, kextPaths)];
		
		[kextSection appendFormat:@"\t{ \"%@\", kextPath%zu, %lu },\n",
			kextID, kextIndex, [kextPaths count]];
		
		[kextNums setObject:[NSNumber numberWithUnsignedLongLong:kextIndex] forKey:kextName];
		
		kextIndex++;
	}
	
	[kextSection appendString:@"};\n"];

	appendFile(file, kextPathsSection);
	appendFile(file, kextSection);
	appendFile(file, [[NSString alloc] initWithFormat:@"KernelPatcher::KextInfo *kextAppleHDA = &kextList[%zu];\n", kextAppleHDAIndex]);

	return kextNums;
}

static NSString *generateFile(NSString *file, NSString *path, NSString *inFile) {
	static size_t fileIndex {0};
	
	auto fullInPath = [[NSString alloc] initWithFormat:@"%@/%@", path, inFile];
	auto data = [[NSFileManager defaultManager] contentsAtPath:fullInPath];
	auto bytes = static_cast<const uint8_t *>([data bytes]);
	
	if (data) {
		appendFile(file, [[NSString alloc] initWithFormat:@"static const uint8_t file%zu[] {\n", fileIndex]);
		
		size_t i = 0;
		while (i < [data length]) {
			auto outLine = [[NSMutableString alloc] initWithString:@"\t"];
			for (size_t p = 0; p < 24 && i < [data length]; p++, i++) {
				[outLine appendFormat:@"0x%0.2X, ", bytes[i]];
			}
			[outLine appendString:@"\n"];
			appendFile(file, outLine);
		}
		
		appendFile(file, [[NSString alloc] initWithFormat:@"};\n"]);
		fileIndex++;
		return [[NSString alloc] initWithFormat:@"file%zu, %zu", fileIndex-1, [data length]];
	}
	
	return @"nullptr, 0";
}

static NSString *generateRevisions(NSString *file, NSDictionary *codecDict) {
	static size_t revisionIndex {0};
	
	NSArray *revs = [codecDict objectForKey:@"Revisions"];
	
	if (revs) {
		appendFile(file, makeStringList(@"revisions", revisionIndex, revs, @"uint32_t"));
		revisionIndex++;
		return [[NSString alloc] initWithFormat:@"revisions%zu, %lu", revisionIndex-1, [revs count]];
	}
	
	return @"nullptr, 0";
}

static NSString *generatePlatforms(NSString *file, NSDictionary *codecDict, NSString *path) {
	static size_t platformIndex {0};
	
	NSArray *plats = [[codecDict objectForKey:@"Files"] objectForKey:@"Platforms"];
	
	if (plats) {
		auto pStr = [[NSMutableString alloc] initWithFormat:@"static const CodecModInfo::Platform platforms%zu[] {\n", platformIndex];
		for (NSDictionary *p in plats) {
			[pStr appendFormat:@"\t{ %@, %@, %@ },\n", generateFile(file, path, [p objectForKey:@"Path"]),
			 [p objectForKey:@"MinKernel"] ?: @"KernelPatcher::KernelAny",
			 [p objectForKey:@"MaxKernel"] ?: @"KernelPatcher::KernelAny"
			];
		}
		[pStr appendString:@"};\n"];
	
		appendFile(file, pStr);
		platformIndex++;
		return [[NSString alloc] initWithFormat:@"platforms%zu, %lu", platformIndex-1, [plats count]];
	}
	
	return @"nullptr, 0";
}

static NSString *generateLayouts(NSString *file, NSDictionary *codecDict, NSString *path) {
	static size_t layoutIndex {0};
	
	NSArray *lts = [[codecDict objectForKey:@"Files"] objectForKey:@"Layouts"];
	
	if (lts) {
		auto pStr = [[NSMutableString alloc] initWithFormat:@"static const CodecModInfo::Layout layouts%zu[] {\n", layoutIndex];
		for (NSDictionary *p in lts) {
			[pStr appendFormat:@"\t{ %@, %@, %@, %@ },\n", [p objectForKey:@"Id"],
			 generateFile(file, path, [p objectForKey:@"Path"]),
			 [p objectForKey:@"MinKernel"] ?: @"KernelPatcher::KernelAny",
			 [p objectForKey:@"MaxKernel"] ?: @"KernelPatcher::KernelAny"
			 ];
		}
		[pStr appendString:@"};\n"];
		
		appendFile(file, pStr);
		layoutIndex++;
		return [[NSString alloc] initWithFormat:@"layouts%zu, %lu", layoutIndex-1, [lts count]];
	}
	
	return @"nullptr, 0";
}

static NSString *generatePatches(NSString *file, NSDictionary *codecDict, NSDictionary *kextIndexes) {
	static size_t patchIndex {0};
	static size_t patchBufIndex {0};
	
	NSArray *patches = [codecDict objectForKey:@"Patches"];

	if (patches) {
		auto pStr = [[NSMutableString alloc] initWithFormat:@"static const CodecModInfo::KextPatch patches%zu[] {\n", patchIndex];
		auto pbStr = [[NSMutableString alloc] init];
		for (NSDictionary *p in patches) {
			NSData *f = [p objectForKey:@"Find"];
			NSData *r = [p objectForKey:@"Replace"];
			
			if ([f length] != [r length]) {
				[pStr appendString:@"#error not matching patch lengths"];
				continue;
			}
			
			for (auto d : {f, r}) {
				[pbStr appendString:[[NSString alloc] initWithFormat:@"static const uint8_t patchBuf%zu[] { ", patchBufIndex]];
				
				for (size_t b = 0; b < [d length]; b++) {
					[pbStr appendString:[[NSString alloc] initWithFormat:@"0x%0.2X, ", reinterpret_cast<const uint8_t *>([d bytes])[b]]];
				}
				
				[pbStr appendString:@"};\n"];
				
				patchBufIndex++;
			}
			
			[pStr appendFormat:@"\t{ { &kextList[%@], patchBuf%zu, patchBuf%zu, %zu, %@ }, %@, %@ },\n",
			 [kextIndexes objectForKey:[p objectForKey:@"Name"]],
			 patchBufIndex-2,
			 patchBufIndex-1,
			 [f length],
			 [p objectForKey:@"Count"] ?: @"1",
			 [p objectForKey:@"MinKernel"] ?: @"KernelPatcher::KernelAny",
			 [p objectForKey:@"MaxKernel"] ?: @"KernelPatcher::KernelAny"
			];
		}
		[pStr appendString:@"};\n"];
		
		appendFile(file, pbStr);
		appendFile(file, pStr);
		patchIndex++;
		return [[NSString alloc] initWithFormat:@"patches%zu, %lu", patchIndex-1, [patches count]];
	}
	
	return @"nullptr, 0";
}

static size_t generateCodecs(NSString *file, NSString *vendor, NSString *path, NSDictionary *kextIndexes) {
	appendFile(file, [[NSString alloc] initWithFormat:@"\n// %@ CodecMod section\n\n", vendor]);

	auto codecModSection = [[NSMutableString alloc] initWithFormat:@"CodecModInfo codecMod%@[] {\n", vendor];
	auto fm = [NSFileManager defaultManager];
	NSArray *entries = [fm contentsOfDirectoryAtPath:path error:nil];
	
	size_t codecs {0};
	for (NSString *entry in entries) {
		NSString *baseDirStr = [[NSString alloc] initWithFormat:@"%@/%@", path, entry];
		NSString *infoCfgStr = [[NSString alloc] initWithFormat:@"%@/Info.plist", baseDirStr];
		
		// Dir exists and is codec dir
		if ([fm fileExistsAtPath:infoCfgStr]) {
			auto codecDict = [NSDictionary dictionaryWithContentsOfFile:infoCfgStr];
			// Vendor match
			if ([[codecDict objectForKey:@"Vendor"] isEqualToString:vendor]) {
				auto revs = generateRevisions(file, codecDict);
				auto platforms = generatePlatforms(file, codecDict, baseDirStr);
				auto layouts = generateLayouts(file, codecDict, baseDirStr);
				auto patches = generatePatches(file, codecDict, kextIndexes);
			
				[codecModSection appendFormat:@"\t{ \"%@\", 0x%X, %@, %@, %@, %@ },\n",
				 [codecDict objectForKey:@"CodecName"],
				 [[codecDict objectForKey:@"CodecID"] unsignedShortValue],
				 revs, platforms, layouts, patches
				];
				codecs++;
			}
		}
	}
	
	[codecModSection appendString:@"};\n"];
	appendFile(file, codecModSection);
	
	return codecs;
}

static void generateVendors(NSString *file, NSDictionary *vendors, NSString *path, NSDictionary *kextIndexes) {
	auto vendorSection = [[NSMutableString alloc] initWithUTF8String:"\n// Vendor section\n\n"];
	
	[vendorSection appendString:@"VendorModInfo vendorMod[] {\n"];
	
	for (NSString *dictKey in vendors) {
		NSNumber *vendorID = [vendors objectForKey:dictKey];
		size_t num = generateCodecs(file, dictKey, path, kextIndexes);
		[vendorSection appendFormat:@"\t{ \"%@\", 0x%X, codecMod%@, %zu },\n",
			dictKey, [vendorID unsignedShortValue], dictKey, num];
	}
	
	[vendorSection appendString:@"};\n"];
	[vendorSection appendFormat:@"\nconst size_t vendorModSize {%lu};\n", [vendors count]];
	appendFile(file, vendorSection);
}

static void generateLookup(NSString *file, NSDictionary *lookup) {
	appendFile(file, @"\n// Lookup section\n\n");

	auto trees = [[NSMutableString alloc] init];
	auto lookups = [[NSMutableString alloc] init];
	size_t treeIndex {0};
	
	for (NSString *dictKey in lookup) {
		// Build tree
		NSArray *treeArr = [[lookup objectForKey:dictKey] objectForKey:@"Tree"];
		[trees appendString:makeStringList(@"tree", treeIndex, treeArr)];
		
		// Build lookup
		[lookups appendFormat:@"\t{ tree%zu, %lu, %@ },\n",
			treeIndex, [treeArr count], [[lookup objectForKey:dictKey] objectForKey:@"layoutNum"]];
		
		treeIndex++;
	}
	appendFile(file, trees);
	appendFile(file, @"CodecLookupInfo codecLookup[] {\n");
	appendFile(file, lookups);
	appendFile(file, @"};\n");
	appendFile(file, [[NSString alloc] initWithFormat:@"const size_t codecLookupSize {%zu};\n", treeIndex]);
}

int main(int argc, const char * argv[]) {
	if (argc != 3)
		ERROR("Invalid usage");
	
	auto basePath = [[NSString alloc] initWithUTF8String:argv[1]];
	auto lookupCfg = [[NSString alloc] initWithFormat:@"%@/CodecLookup.plist", basePath];
	auto vendorsCfg = [[NSString alloc] initWithFormat:@"%@/Vendors.plist", basePath];
	auto kextsCfg = [[NSString alloc] initWithFormat:@"%@/Kexts.plist",basePath];
	auto outputCpp = [[NSString alloc] initWithUTF8String:argv[2]];
	
	auto lookup = [NSDictionary dictionaryWithContentsOfFile:lookupCfg];
	auto vendors = [NSDictionary dictionaryWithContentsOfFile:vendorsCfg];
	auto kexts = [NSDictionary dictionaryWithContentsOfFile:kextsCfg];
	
	if (!lookup || !vendors || !kexts)
		ERROR("Missing resource data (lookup:%p, vendors:%p, kexts:%p)", lookup, vendors, kexts);
	
	// Create a file
	[[NSFileManager defaultManager] createFileAtPath:outputCpp contents:nil attributes:nil];
	
	appendFile(outputCpp, ResourceHeader);
	generateLookup(outputCpp, lookup);
	auto kextIndexes = generateKexts(outputCpp, kexts);
	generateVendors(outputCpp, vendors, basePath, kextIndexes);
}
