import Foundation

/// Explicit, local inspector transport. No background capture and no remote I/O.
enum ForgeInspector {
    static func code(tweakID: UUID) -> String {
        let id = tweakID.uuidString.lowercased()
        return """
        %hook UIWindow
        - (void)becomeKeyWindow {
          %orig;
          static char attached;
          if (![NSThread isMainThread]) return;
          if (!objc_getAssociatedObject(self, &attached)) {
            objc_setAssociatedObject(self, &attached, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mirsaInspect:)];
            g.minimumPressDuration = 0.8;
            g.cancelsTouchesInView = NO;
            [self addGestureRecognizer:g];
          }
        }
        %new
        - (void)mirsaInspect:(UILongPressGestureRecognizer *)g {
          if (g.state != UIGestureRecognizerStateBegan || ![NSThread isMainThread]) return;
          if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
          UIWindowScene *scene = self.windowScene;
          if (!scene || scene.activationState != UISceneActivationStateForegroundActive) return;
          UIViewController *top = self.rootViewController;
          while (top.presentedViewController) top = top.presentedViewController;
          if (!top || [top isKindOfClass:[UIAlertController class]]) return;
          static char eventsKey;
          NSMutableArray *events = objc_getAssociatedObject(self, &eventsKey);
          if (!events) {
            events = [NSMutableArray array];
            objc_setAssociatedObject(self, &eventsKey, events, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
          }
          [events addObject:@"inspector: explicit foreground capture requested"];
          while (events.count > 20) [events removeObjectAtIndex:0];
          NSMutableArray *nodes = [NSMutableArray array];
          NSMutableArray *queue = [NSMutableArray array];
          for (UIWindow *w in scene.windows) {
            if (!w.hidden && w.alpha > 0 && queue.count < 400) [queue addObject:@[w, @0, @(-1)]];
          }
          BOOL truncated = scene.windows.count > 400;
          NSUInteger cursor = 0;
          // Breadth-first traversal avoids recursive stack growth and block retain cycles.
          while (cursor < queue.count && nodes.count < 400) {
            NSArray *entry = queue[cursor++];
            UIView *view = entry[0];
            NSUInteger depth = [entry[1] unsignedIntegerValue];
            NSString *className = NSStringFromClass([view class]);
            if (className.length > 128) className = [className substringToIndex:128];
            BOOL secure = [view isKindOfClass:[UITextField class]] && ((UITextField *)view).secureTextEntry;
            CGRect frame = [view convertRect:view.bounds toView:self];
            if (!isfinite(frame.origin.x) || !isfinite(frame.origin.y) || !isfinite(frame.size.width) || !isfinite(frame.size.height)) frame = CGRectZero;
            // Freeform text, accessibility labels and identifiers may contain credentials.
            // Only fixed UI vocabulary is exportable; all other content is redacted.
            NSSet *safeWords = [NSSet setWithArray:@[@"OK", @"Cancel", @"Back", @"Done", @"Settings", @"Home", @"Search", @"إلغاء", @"رجوع", @"تم", @"الإعدادات"]];
            NSString *label = @"[redacted]";
            NSString *text = @"[redacted]";
            if (!secure && [view isKindOfClass:[UIButton class]]) {
              NSString *candidate = [(UIButton *)view titleForState:UIControlStateNormal];
              if ([safeWords containsObject:candidate ?: @""]) text = candidate;
            }
            if (!secure && [view isKindOfClass:[UILabel class]]) {
              NSString *candidate = [(UILabel *)view text];
              if ([safeWords containsObject:candidate ?: @""]) text = candidate;
            }
            // Do not read editable field contents, even when secureTextEntry is false.
            NSDictionary *node = @{@"class":className, @"depth":@(depth), @"parent":entry[2], @"frame":@[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)], @"identifier":@"[redacted]", @"label":label, @"text":text, @"secure":@(secure)};
            [nodes addObject:node];
            if (depth >= 32) { if (view.subviews.count) truncated = YES; continue; }
            for (UIView *child in view.subviews) {
              if (child.hidden || child.alpha <= 0) continue;
              if (queue.count >= 400) { truncated = YES; break; }
              [queue addObject:@[child, @(depth + 1), @(nodes.count - 1)]];
            }
          }
          if (cursor < queue.count) truncated = YES;
          NSString *bundle = [NSBundle mainBundle].bundleIdentifier ?: @"unknown";
          if (bundle.length > 155) bundle = @"unknown";
          NSMutableDictionary *report = [@{@"schema":@"mirsa.inspector.v1", @"bundleID":bundle, @"tweakID":@"\(id)", @"nodes":nodes, @"truncated":@(truncated), @"limitations":@"Current foreground scene UIKit windows only. SwiftUI/WebView internals may be unavailable. Text uses a fixed safe vocabulary; labels, identifiers and editable contents are redacted. Logs are only this inspector's own recent events, not other tweaks or system logs.", @"logs":[events copy]} mutableCopy];
          // Read only this injected app's own cache. Unknown guard state stays absent.
          NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"] stringByAppendingPathComponent:@"mirsa_guard_\(id).plist"];
          NSDictionary *guard = [NSDictionary dictionaryWithContentsOfFile:path];
          if ([guard[@"disabled"] isKindOfClass:[NSNumber class]]) report[@"guardDisabled"] = @([guard[@"disabled"] boolValue]);
          else if ([guard[@"launched"] boolValue] && [guard[@"crashes"] isKindOfClass:[NSNumber class]] && [guard[@"crashes"] intValue] >= 0 && [guard[@"crashes"] intValue] < 2) report[@"guardDisabled"] = @NO;
          NSData *data = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
          while (data.length > 24000 && nodes.count) {
            [nodes removeLastObject];
            report[@"truncated"] = @YES;
            data = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
          }
          if (!data || data.length > 24000) return;
          NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
          UIAlertController *preview = [UIAlertController alertControllerWithTitle:@"المفتش" message:json preferredStyle:UIAlertControllerStyleAlert];
          [preview addAction:[UIAlertAction actionWithTitle:@"Cancel / إلغاء" style:UIAlertActionStyleCancel handler:nil]];
          [preview addAction:[UIAlertAction actionWithTitle:@"Copy / نسخ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            // Copy happens only after the user reviews the complete redacted JSON.
            [[UIPasteboard generalPasteboard] setItems:@[@{@"public.utf8-plain-text":json}] options:@{UIPasteboardOptionLocalOnly:@YES, UIPasteboardOptionExpirationDate:[NSDate dateWithTimeIntervalSinceNow:120]}];
            [events addObject:@"inspector: user copied redacted preview locally"];
            while (events.count > 20) [events removeObjectAtIndex:0];
          }]];
          [top presentViewController:preview animated:YES completion:nil];
        }
        %end
        """
    }
}
