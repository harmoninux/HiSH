import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import {
  applyVirtualKeyModifiers,
  FunctionKeyOrder,
  FunctionKeySequences,
  getVirtualKeyMetrics,
  NormalKeySequences
} from '../main/ets/lib/terminalVirtualKeys';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
  });

  describe('terminalVirtualKeys', () => {
    it('functionKeySequencesShouldMatchSpec', 0, () => {
      expect(FunctionKeyOrder.length).assertEqual(12);
      expect(FunctionKeySequences.F1).assertEqual('\x1bOP');
      expect(FunctionKeySequences.F2).assertEqual('\x1bOQ');
      expect(FunctionKeySequences.F3).assertEqual('\x1bOR');
      expect(FunctionKeySequences.F4).assertEqual('\x1bOS');
      expect(FunctionKeySequences.F5).assertEqual('\x1b[15~');
      expect(FunctionKeySequences.F6).assertEqual('\x1b[17~');
      expect(FunctionKeySequences.F7).assertEqual('\x1b[18~');
      expect(FunctionKeySequences.F8).assertEqual('\x1b[19~');
      expect(FunctionKeySequences.F9).assertEqual('\x1b[20~');
      expect(FunctionKeySequences.F10).assertEqual('\x1b[21~');
      expect(FunctionKeySequences.F11).assertEqual('\x1b[23~');
      expect(FunctionKeySequences.F12).assertEqual('\x1b[24~');
    });

    it('normalLayoutSequencesShouldNotChange', 0, () => {
      expect(NormalKeySequences.ESC).assertEqual('\x1b');
      expect(NormalKeySequences.TAB).assertEqual('\t');
      expect(NormalKeySequences.PGUP).assertEqual('\x1b[5~');
      expect(NormalKeySequences.HOME).assertEqual('\x1b[H');
      expect(NormalKeySequences.UP).assertEqual('\x1b[A');
      expect(NormalKeySequences.UP_APP).assertEqual('\x1bOA');
      expect(NormalKeySequences.END).assertEqual('\x1b[F');
      expect(NormalKeySequences.PGDN).assertEqual('\x1b[6~');
      expect(NormalKeySequences.LEFT).assertEqual('\x1b[D');
      expect(NormalKeySequences.LEFT_APP).assertEqual('\x1bOD');
      expect(NormalKeySequences.DOWN).assertEqual('\x1b[B');
      expect(NormalKeySequences.DOWN_APP).assertEqual('\x1bOB');
      expect(NormalKeySequences.RIGHT).assertEqual('\x1b[C');
      expect(NormalKeySequences.RIGHT_APP).assertEqual('\x1bOC');
    });

    it('modifierBehaviorShouldKeepExistingSemantics', 0, () => {
      const ctrlOnLower = applyVirtualKeyModifiers('a', true, false);
      expect(ctrlOnLower.data).assertEqual('\u0001');
      expect(ctrlOnLower.ctrlConverted).assertEqual(true);
      expect(ctrlOnLower.shouldResetCtrl).assertEqual(true);

      const ctrlOnUpper = applyVirtualKeyModifiers('A', true, false);
      expect(ctrlOnUpper.data).assertEqual('A');
      expect(ctrlOnUpper.ctrlConverted).assertEqual(false);
      expect(ctrlOnUpper.shouldResetCtrl).assertEqual(true);

      const shiftOnLower = applyVirtualKeyModifiers('b', false, true);
      expect(shiftOnLower.data).assertEqual('B');
      expect(shiftOnLower.shiftConverted).assertEqual(true);
      expect(shiftOnLower.shouldResetCtrl).assertEqual(false);

      const keepFnSequence = applyVirtualKeyModifiers('\x1bOP', true, true);
      expect(keepFnSequence.data).assertEqual('\x1bOP');
      expect(keepFnSequence.shouldResetCtrl).assertEqual(false);
      expect(keepFnSequence.shiftConverted).assertEqual(false);
    });

    it('virtualKeyMetricsShouldSupportPhoneAndNonPhone', 0, () => {
      const phoneMetrics = getVirtualKeyMetrics('phone');
      expect(phoneMetrics.margin).assertEqual(1);
      expect(phoneMetrics.padding).assertEqual(2);
      expect(phoneMetrics.width).assertEqual(48);
      expect(phoneMetrics.fontSize).assertEqual(11);
      expect(phoneMetrics.height).assertEqual(28);
      expect(phoneMetrics.radius).assertEqual(5);

      const nonPhoneMetrics = getVirtualKeyMetrics('tablet');
      expect(nonPhoneMetrics.margin).assertEqual(2);
      expect(nonPhoneMetrics.padding).assertEqual(4);
      expect(nonPhoneMetrics.width).assertEqual(60);
      expect(nonPhoneMetrics.fontSize).assertEqual(14);
      expect(nonPhoneMetrics.height).assertEqual(28);
      expect(nonPhoneMetrics.radius).assertEqual(5);
    });
  });
}
