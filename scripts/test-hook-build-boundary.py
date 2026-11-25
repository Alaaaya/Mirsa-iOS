#!/usr/bin/env python3
"""The macOS /bin/bash 3.2 empty-array edge must not skip the device compiler."""
import pathlib,re,subprocess,unittest
root=pathlib.Path(__file__).resolve().parents[1]
class HookBuildBoundary(unittest.TestCase):
    def test_optional_link_arguments_remain_separate_and_empty_is_absent(self):
        source=(root/'hook-engine/build.sh').read_text()
        expression=re.search(r'-lobjc -framework Foundation (.*?) \\\n',source).group(1)
        code=('set -eu\nLINK=()\nset -- before '+expression+' after\ntest "$#" = 2\n'
              'LINK=("-one flag" "-two")\nset -- before '+expression+' after\n'
              'test "$#" = 4\ntest "$2" = "-one flag"\ntest "$3" = "-two"\n')
        subprocess.run(['/bin/bash','-uc',code],check=True)
    def test_every_ci_device_build_removes_checkout_binary_first(self):
        lines=(root/'.github/workflows/final-bundle25.yml').read_text().splitlines()
        indexes=[i for i,line in enumerate(lines) if line.strip()=='bash hook-engine/build.sh']
        self.assertGreaterEqual(len(indexes),2)
        for i in indexes:
            self.assertEqual(lines[i-1].strip(),'rm -f hook-engine/dist/CydiaSubstrate.framework/CydiaSubstrate')
    def test_nonempty_temporary_compiler_output_required_before_copy(self):
        text=(root/'hook-engine/build.sh').read_text()
        self.assertLess(text.index('[[ -s "$WORK/CydiaSubstrate" ]]'),text.index('cp "$WORK/CydiaSubstrate"'))
if __name__=='__main__': unittest.main()
