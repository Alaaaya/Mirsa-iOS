import test from 'node:test';
import assert from 'node:assert/strict';
import { generationSystem, repairSystem, examples, validateModernUIKit } from './prompts.mjs';
import { validateLogos } from './contract.mjs';
test('generation and repair enforce scene-based modern UIKit and preserve safety', () => {
 for (const prompt of [generationSystem, repairSystem]) {
  for (const s of ['UIAlertView', 'UIActionSheet', 'UIApplication.keyWindow', 'UIAlertController', 'UIWindowScene', 'UIApplicationDidBecomeActiveNotification', 'compiler']) assert.ok(prompt.includes(s), s);
  assert.match(prompt, /untrusted/i);
 }
});
test('vetted launch alert waits for activation, resolves visible top VC, presents once on main queue', () => {
 const code = examples.launch;
 assert.equal(validateLogos(code), null);
 assert.equal(validateModernUIKit(code), null);
 for (const s of ['UIApplicationDidBecomeActiveNotification', 'dispatch_after', 'dispatch_get_main_queue', 'connectedScenes', 'UISceneActivationStateForegroundActive', 'isKeyWindow', 'presentedViewController', 'visibleViewController', 'selectedViewController', 'UIAlertController', 'UIAlertAction', 'static BOOL shown', 'view.window']) assert.ok(code.includes(s), s);
 assert.match(code, /%@|علاء/);
});
test('all small view-edit recipes are valid Logos and modern UIKit', () => {
 for (const code of Object.values(examples)) { assert.equal(validateLogos(code), null); assert.equal(validateModernUIKit(code), null); }
 assert.match(examples.hide, /setHidden:YES/);
 assert.match(examples.recolor, /setTextColor:/);
 assert.match(examples.font, /setFont:/);
});
test('obsolete classes and application-level window access are rejected but window.isKeyWindow allowed', () => {
 for (const code of ['UIAlertView *a;', 'UIActionSheet *a;', '[UIApplication sharedApplication].keyWindow', 'app.keyWindow', '[app keyWindow]', '[UIApplication sharedApplication].windows']) assert.equal(validateModernUIKit(code), 'deprecated_uikit');
 assert.equal(validateModernUIKit('if (window.isKeyWindow) {}'), null);
});
