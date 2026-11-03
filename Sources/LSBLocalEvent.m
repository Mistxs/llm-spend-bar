#import "LSBLocalEvent.h"

@implementation LSBLocalEvent

- (instancetype)init {
    self = [super init];
    if (self) {
        _eventID = @"";
        _tool = @"";
        _provider = @"";
        _model = @"";
        _sessionID = @"";
        _sessionTitle = @"";
        _project = @"";
        _costSource = @"estimated";
        _sourcePath = @"";
        _rawMeta = @"";
    }
    return self;
}

@end
