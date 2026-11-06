import unittest
from score import align, normalize, tokenize, score
class ScoringTests(unittest.TestCase):
 def test_negation_not_removed(self):
  self.assertEqual(align(tokenize('不要发送','cer'),tokenize('要发送','cer'))['deletions'],1)
 def test_mixed_tokens(self):
  self.assertEqual(tokenize('使用 SwiftUI 和 SQLite','mer'),['使','用','swiftui','和','sqlite'])
 def test_numbers_not_canonicalized(self):
  self.assertNotEqual(normalize('三十'),normalize('30'))
 def test_no_simplified_traditional_rewrite(self):
  self.assertNotEqual(normalize('学习'),normalize('學習'))
 def test_numeric_sign_and_decimal_preserved(self):
  self.assertNotEqual(normalize('-3'),normalize('3'))
  self.assertNotEqual(normalize('0.5'),normalize('05'))
  self.assertEqual(tokenize('-3.5%','mer'),['-3.5%'])
 def test_repeat_penalized(self):
  self.assertEqual(align(['a','b'],['a','a','b'])['insertions'],1)
 def test_omission_and_missing_call_differ(self):
  m=[{'id':'a','reference':'不要','language':'zh','group':'primary'}]
  self.assertEqual(score(m,[])['groups']['primary/zh']['not_run'],1)
  self.assertEqual(score(m,[{'id':'a','text':'','error':'timeout'}])['groups']['primary/zh']['micro_error_rate'],1)
 def test_empty_reference(self):
  self.assertIsNone(align([],['invented'])['error_rate'])
 def test_emoji_unicode(self):
  self.assertEqual(align(list('你😀'),list('你😀'))['errors'],0)
if __name__=='__main__':unittest.main()
