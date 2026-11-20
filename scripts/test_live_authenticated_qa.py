import unittest

from live_authenticated_qa import QAError, approved_email, cross_account_assertions, validate_accounts


class AuthenticatedQAUnitTests(unittest.TestCase):
    def test_approved_emails_require_explicit_marker(self):
        self.assertTrue(approved_email("name+pipoqa-a@example.com"))
        self.assertFalse(approved_email("customer@example.com"))
        self.assertFalse(approved_email("name+pipoqa@"))
        self.assertFalse(approved_email(""))

    def test_distinct_disposable_accounts_required(self):
        validate_accounts("name+pipoqa-a@example.com", "name+pipoqa-b@example.com")
        with self.assertRaises(QAError):
            validate_accounts("name+pipoqa-a@example.com", "NAME+PIPOQA-A@example.com")
        with self.assertRaises(QAError):
            validate_accounts("real.user@example.com", "name+pipoqa-b@example.com")

    def test_no_empty_table_false_positive(self):
        with self.assertRaises(QAError):
            cross_account_assertions([], [{"id": "b"}], [], [], "saving_goals")
        with self.assertRaises(QAError):
            cross_account_assertions([{"id": "a"}], [], [], [], "saving_transactions")

    def test_cross_account_reads_are_security_failures(self):
        with self.assertRaises(QAError):
            cross_account_assertions(
                [{"id": "a"}], [{"id": "b"}], [{"id": "a"}], [], "saving_goals")
        with self.assertRaises(QAError):
            cross_account_assertions(
                [{"id": "a"}], [{"id": "b"}], [], [{"id": "b"}], "saving_goals")

    def test_valid_isolation(self):
        cross_account_assertions(
            [{"id": "a"}], [{"id": "b"}], [], [], "saving_goals")


if __name__ == "__main__":
    unittest.main()
