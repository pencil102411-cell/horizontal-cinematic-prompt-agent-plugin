import unittest

from audit_fingerprint import DEFAULT_RULE_FILES, build_fingerprint
from check_prompt import DURATION_MAX, DURATION_MIN, LIMITS, RULE_FINGERPRINT


class AuditFingerprintTests(unittest.TestCase):
    def test_rule_bundle_is_complete_and_stable(self):
        first = build_fingerprint()
        second = build_fingerprint()
        self.assertEqual(first, second)
        self.assertEqual(first["fingerprint"], RULE_FINGERPRINT)
        self.assertEqual(len(first["files"]), len(DEFAULT_RULE_FILES))
        self.assertTrue(all(len(item["sha256"]) == 64 for item in first["files"]))

    def test_limits_are_loaded_from_config(self):
        self.assertEqual(LIMITS, {"simple": 2000, "complex": 3000, "maximal": 4000})
        self.assertEqual(DURATION_MIN, 4)
        self.assertEqual(DURATION_MAX, 15)


if __name__ == "__main__":
    unittest.main()
