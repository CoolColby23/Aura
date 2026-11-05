import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('schema', Path(__file__).resolve().parents[2] / 'scripts/verify-cloud-schema.py')
schema = importlib.util.module_from_spec(spec)
spec.loader.exec_module(schema)

def fixture():
    return 'DEFINE SCHEMA\n' + '\n'.join('RECORD TYPE ' + name + ' (' + ',\n'.join(field + ' ' + kind for field, kind in fields.items()) + ');' for name, fields in schema.REQUIRED.items())

class SchemaRequirementsTests(unittest.TestCase):
    def test_complete_export_and_implicit_number(self):
        schema.verify(fixture())
        schema.verify(fixture().replace('generation INT64', 'generation NUMBER PREFERRED AS INT64'))
        with self.assertRaises(ValueError):
            schema.verify(fixture().replace('generation INT64', 'generation NUMBER'))

    def test_missing_wrong_or_comment_only_field_fails(self):
        for replacement in ['listenIDs STRING', '/* listenIDs LIST<STRING> */', 'unrelated LIST<STRING>']:
            with self.assertRaises(ValueError):
                schema.verify(fixture().replace('listenIDs LIST<STRING>', replacement))

    def test_duplicate_record_type_fails(self):
        with self.assertRaises(ValueError):
            schema.verify(fixture() + 'RECORD TYPE Listen (listenIDs LIST<STRING>);')

if __name__ == '__main__':
    unittest.main()
