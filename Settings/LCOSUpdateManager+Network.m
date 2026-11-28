#import "LCOSUpdateManager+Private.h"
#import "LCOSLogManager.h"

@implementation LCOSUpdateManager (Network)

- (NSArray<NSURL *> *)candidateURLsForOfficialURL:(NSURL *)url {
    if (![url.scheme isEqualToString:@"https"]) return @[];
    BOOL official = [url.host isEqualToString:@"api.github.com"] || [url.host isEqualToString:@"github.com"] || [url.host isEqualToString:@"raw.githubusercontent.com"];
    if (!official) return @[];
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithObject:url];
    // Only verified GitHub URLs are wrapped. No third-party URL is forwarded.
    for (NSString *prefix in @[@"https://ghfast.top/", @"https://gh-proxy.com/", @"https://ghproxy.net/"]) {
        NSURL *candidate = [NSURL URLWithString:[prefix stringByAppendingString:url.absoluteString]];
        if (candidate) [urls addObject:candidate];
    }
    return urls;
}

- (void)performCandidates:(NSArray<NSURL *> *)urls index:(NSUInteger)index completion:(void (^)(NSData *, NSURLResponse *, NSError *, NSUInteger))completion {
    if (index >= urls.count) {
        completion(nil, nil, [self error:10 description:@"所有更新线路均无响应，请稍后重新点击"], index);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:urls[index]];
    request.timeoutInterval = 5;
    [request setValue:@"LCOS-Updater" forHTTPHeaderField:@"User-Agent"];
    [[LCOSLogManager sharedManager] forceLog:[NSString stringWithFormat:@"LCOS Update: trying route %lu/%lu %@", (unsigned long)(index + 1), (unsigned long)urls.count, urls[index].host]];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        // Timeouts and transport/HTTP failures try the next mirror. A 200
        // response belongs to the caller, even when its JSON says "latest".
        if (error || status != 200) {
            if (index + 1 < urls.count) {
                [self performCandidates:urls index:index + 1 completion:completion];
                return;
            }
            if (!error && status) error = [self error:status description:[NSString stringWithFormat:@"所有更新线路均失败（HTTP %ld），请重新点击", (long)status]];
            completion(data, response, error, index);
            return;
        }
        completion(data, response, nil, index);
    }] resume];
}

@end
