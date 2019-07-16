#!/bin/bash

# Treat unset variables and parameters as an error when performing parameter expansion
set -o nounset

# Exit immediately if command returns a non-zero status
set -o errexit

# Return value of a pipeline is the value of the last command to exit with a non-zero status
set -o pipefail


RUN_ONLY_INTEGRATION_TESTS=no
if [ "${1:-}" = '--only-integration-tests' ]; then
	RUN_ONLY_INTEGRATION_TESTS=yes
fi

# shellcheck source=src/main/scripts/ci/common.sh
. "$(dirname "$0")/common.sh"

CS_STATUS=
PMD_STATUS=
LICENSE_STATUS=
POM_STATUS=
BOOTLINT_STATUS=
RFLINT_STATUS=
SHELLCHECK_STATUS=
JASMINE_STATUS=
HTML_STATUS=
ENFORCER_STATUS=
TEST_STATUS=
CODENARC_STATUS=
SPOTBUGS_STATUS=
VERIFY_STATUS=

DANGER_STATUS=skip
if [ "${SPRING_PROFILES_ACTIVE:-}" = 'travis' ] && [ "${TRAVIS_PULL_REQUEST:-false}" != 'false' ]; then
	DANGER_STATUS=
fi

echo

if [ "$RUN_ONLY_INTEGRATION_TESTS" = 'no' ]; then
	
	# TRAVIS_COMMIT_RANGE: The range of commits that were included in the push or
	# pull request. (Note that this is empty for builds triggered by the initial
	# commit of a new branch.)
	if [ -n "${TRAVIS_COMMIT_RANGE:-}" ]; then
		echo "INFO: Range of the commits to be checked: $TRAVIS_COMMIT_RANGE"
		echo 'INFO: List of the files modified by this commits range:'
		git --no-pager diff --name-only "$TRAVIS_COMMIT_RANGE" -- | sed 's|^|      |' || :
		
		MODIFIED_FILES="$(git --no-pager diff --name-only "$TRAVIS_COMMIT_RANGE" -- 2>/dev/null || :)"
		
		if [ -n "$MODIFIED_FILES" ]; then
			AFFECTS_POM_XML="$(echo "$MODIFIED_FILES"      | grep -Fxq 'pom.xml' || echo 'no')"
			AFFECTS_TRAVIS_CFG="$(echo "$MODIFIED_FILES"   | grep -Fxq '.travis.yml' || echo 'no')"
			AFFECTS_CS_CFG="$(echo "$MODIFIED_FILES"        | grep -Eq '(checkstyle\.xml|checkstyle-suppressions\.xml)$' || echo 'no')"
			AFFECTS_SPOTBUGS_CFG="$(echo "$MODIFIED_FILES"  |  grep -q 'spotbugs-filter\.xml$' || echo 'no')"
			AFFECTS_PMD_XML="$(echo "$MODIFIED_FILES"       |  grep -q 'pmd\.xml$' || echo 'no')"
			AFFECTS_JS_FILES="$(echo "$MODIFIED_FILES"      |  grep -q '\.js$' || echo 'no')"
			AFFECTS_HTML_FILES="$(echo "$MODIFIED_FILES"    |  grep -q '\.html$' || echo 'no')"
			AFFECTS_JAVA_FILES="$(echo "$MODIFIED_FILES"    |  grep -q '\.java$' || echo 'no')"
			AFFECTS_ROBOT_FILES="$(echo "$MODIFIED_FILES"   |  grep -q '\.robot$' || echo 'no')"
			AFFECTS_SHELL_FILES="$(echo "$MODIFIED_FILES"   |  grep -q '\.sh$' || echo 'no')"
			AFFECTS_GROOVY_FILES="$(echo "$MODIFIED_FILES"  |  grep -q '\.groovy$' || echo 'no')"
			AFFECTS_PROPERTIES="$(echo "$MODIFIED_FILES"    |  grep -q '\.properties$' || echo 'no')"
			AFFECTS_LICENSE_HEADER="$(echo "$MODIFIED_FILES" | grep -q 'license_header\.txt$' || echo 'no')"
			
			if [ "$AFFECTS_POM_XML" = 'no' ]; then
				POM_STATUS=skip
				ENFORCER_STATUS=skip
				
				if [ "$AFFECTS_JAVA_FILES" = 'no' ]; then
					[ "$AFFECTS_SPOTBUGS_CFG" != 'no' ] || SPOTBUGS_STATUS=skip
					[ "$AFFECTS_PMD_XML" != 'no' ] || PMD_STATUS=skip
					
					if [ "$AFFECTS_CS_CFG" = 'no' ] && [ "$AFFECTS_PROPERTIES" = 'no' ]; then
						CS_STATUS=skip
					fi
					
					if [ "$AFFECTS_GROOVY_FILES" = 'no' ]; then
						TEST_STATUS=skip
						
						[ "$AFFECTS_LICENSE_HEADER" != 'no' ] || LICENSE_STATUS=skip
					fi
				fi
				
				[ "$AFFECTS_GROOVY_FILES" != 'no' ] || CODENARC_STATUS=skip
				[ "$AFFECTS_JS_FILES" != 'no' ] || JASMINE_STATUS=skip
			fi
			
			if [ "$AFFECTS_TRAVIS_CFG" = 'no' ]; then
				if [ "$AFFECTS_HTML_FILES" = 'no' ]; then
					BOOTLINT_STATUS=skip
					HTML_STATUS=skip
				fi
				[ "$AFFECTS_ROBOT_FILES" != 'no' ] || RFLINT_STATUS=skip
				[ "$AFFECTS_SHELL_FILES" != 'no' ] || SHELLCHECK_STATUS=skip
			fi
			echo 'INFO: Some checks could be skipped'
		else
			echo "INFO: Couldn't determine list of modified files."
			echo 'INFO: All checks will be performed'
		fi
	else
		echo "INFO: Couldn't determine a range of the commits: \$TRAVIS_COMMIT_RANGE is empty."
		echo 'INFO: All checks will be performed'
	fi
	
	echo
	
	if [ "$CS_STATUS" != 'skip' ]; then
		fold_start checkstyle 'CheckStyle'
		mvn --batch-mode checkstyle:check -Dcheckstyle.violationSeverity=warning \
			2>&1 || CS_STATUS=fail
		fold_end checkstyle
	fi
	
	if [ "$PMD_STATUS" != 'skip' ]; then
		fold_start pmd 'PMD'
		mvn --batch-mode pmd:check \
			2>&1 || PMD_STATUS=fail
		fold_end pmd
	fi
	
	if [ "$LICENSE_STATUS" != 'skip' ]; then
		fold_start license 'mvn license'
		mvn --batch-mode license:check \
			2>&1 || LICENSE_STATUS=fail
		fold_end license
	fi
	
	if [ "$POM_STATUS" != 'skip' ]; then
		fold_start sortpom 'mvn sortpom'
		mvn --batch-mode sortpom:verify -Dsort.verifyFail=stop \
			2>&1 || POM_STATUS=fail
		fold_end sortpom
	fi
	
	if [ "$BOOTLINT_STATUS" != 'skip' ]; then
		fold_start bootlint 'bootlint'
		find src/main -type f -name '*.html' -print0 | xargs -0 bootlint --disable W013 \
			2>&1 || BOOTLINT_STATUS=fail
		fold_end bootlint
	fi
	
	if [ "$RFLINT_STATUS" != 'skip' ]; then
		fold_start rflint 'rflint'
		rflint \
			--error=all \
			--ignore TooFewTestSteps \
			--ignore TooManyTestSteps \
			--ignore TooFewKeywordSteps \
			--ignore TooManyTestCases \
			--ignore RequireTestDocumentation \
			--ignore RequireKeywordDocumentation \
			--configure LineTooLong:130 \
			src/test/robotframework \
			2>&1 || RFLINT_STATUS=fail
		fold_end rflint
	fi
	
	if [ "$SHELLCHECK_STATUS" != 'skip' ]; then
		fold_start shellcheck 'shellcheck'
		# Shellcheck doesn't support recursive scanning: https://github.com/koalaman/shellcheck/issues/143
		# Also I don't want to invoke it many times (slower, more code for handling failures), so I prefer this way.
		# shellcheck disable=SC2207
		SHELL_FILES=( $(find src/main/scripts -type f -name '*.sh') )
		shellcheck \
			--shell bash \
			--format gcc \
			"${SHELL_FILES[@]}" \
			2>&1 || SHELLCHECK_STATUS=fail
		fold_end shellcheck
	fi
	
	if [ "$JASMINE_STATUS" != 'skip' ]; then
		fold_start jasmine 'JS: Unit Tests'
		mvn --batch-mode jasmine:test \
			2>&1 || JASMINE_STATUS=fail
		fold_end jasmine
	fi
	
	if [ "$HTML_STATUS" != 'skip' ]; then
		fold_start html5validator 'html5validator'
		# FIXME: remove ignoring of error about alt attribute after resolving #314
		# @todo #109 Check src/main/config/nginx/503.*html by html5validator
		# @todo #695 /series/import/request/{id}: use divs instead of table for elements aligning
		html5validator \
			--root src/main/webapp/WEB-INF/views \
			--no-langdetect \
			--ignore-re 'Attribute “(th|sec|togglz|xmlns):[a-z]+” not allowed' \
				'Attribute “(th|sec|togglz):[a-z]+” is not serializable' \
				'Attribute with the local name “xmlns:[a-z]+” is not serializable' \
				'An "img" element must have an "alt" attribute' \
				'The first child "option" element of a "select" element with a "required" attribute' \
				'Element "option" without attribute "label" must not be empty' \
				'The "width" attribute on the "td" element is obsolete' \
			--show-warnings \
			2>&1 || HTML_STATUS=fail
		fold_end html5validator
	fi
	
	if [ "$ENFORCER_STATUS" != 'skip' ]; then
		fold_start enforcer 'mvn enforcer'
		mvn --batch-mode enforcer:enforce \
			2>&1 || ENFORCER_STATUS=fail
		fold_end enforcer
	fi
	
	if [ "$TEST_STATUS" != 'skip' ]; then
		fold_start unit 'Java: Unit Tests'
		mvn --batch-mode test -Denforcer.skip=true -Dmaven.resources.skip=true -DskipMinify=true -DdisableXmlReport=false -Dskip.npm -Dskip.installnodenpm \
			2>&1 || TEST_STATUS=fail
		fold_end unit
	fi
	
	if [ "$CODENARC_STATUS" != 'skip' ]; then
		fold_start codenarc 'CodeNarc'
		# run after tests for getting compiled sources
		mvn --batch-mode codenarc:codenarc -Dcodenarc.maxPriority1Violations=0 -Dcodenarc.maxPriority2Violations=0 -Dcodenarc.maxPriority3Violations=0 \
			2>&1 || CODENARC_STATUS=fail
		fold_end codenarc
	fi
	
	if [ "$SPOTBUGS_STATUS" != 'skip' ]; then
		fold_start spotbugs 'SpotBugs'
		# run after tests for getting compiled sources
		mvn --batch-mode spotbugs:check \
			2>&1 || SPOTBUGS_STATUS=fail
		fold_end spotbugs
	fi
fi

fold_start verify 'Integration Tests'
mvn --batch-mode --activate-profiles frontend verify -Denforcer.skip=true -DskipUnitTests=true \
	>verify-raw.log 2>&1 || VERIFY_STATUS=fail
# Workaround for #538
"$(dirname "$0")/filter-out-htmlunit-messages.pl" <verify-raw.log
rm -f verify-raw.log
fold_end verify

if [ "$DANGER_STATUS" != 'skip' ]; then
	fold_start danger 'Danger'
	danger 2>&1 || DANGER_STATUS=fail
	fold_end danger
fi

if [ "$RUN_ONLY_INTEGRATION_TESTS" = 'no' ]; then
	print_status "$CS_STATUS"         'Run CheckStyle'
	print_status "$PMD_STATUS"        'Run PMD'
	print_status "$LICENSE_STATUS"    'Check license headers'
	print_status "$POM_STATUS"        'Check sorting of pom.xml'
	print_status "$BOOTLINT_STATUS"   'Run bootlint'
	print_status "$RFLINT_STATUS"     'Run robot framework lint'
	print_status "$SHELLCHECK_STATUS" 'Run shellcheck'
	print_status "$JASMINE_STATUS"    'Run JavaScript unit tests'
	print_status "$HTML_STATUS"       'Run html5validator'
	print_status "$ENFORCER_STATUS"   'Run maven-enforcer-plugin'
	print_status "$TEST_STATUS"       'Run unit tests'
	print_status "$CODENARC_STATUS"   'Run CodeNarc'
	print_status "$SPOTBUGS_STATUS"   'Run SpotBugs'
fi

print_status "$VERIFY_STATUS" 'Run integration tests'
print_status "$DANGER_STATUS" 'Run danger'

if echo "$CS_STATUS$PMD_STATUS$LICENSE_STATUS$POM_STATUS$BOOTLINT_STATUS$RFLINT_STATUS$SHELLCHECK_STATUS$JASMINE_STATUS$HTML_STATUS$ENFORCER_STATUS$TEST_STATUS$CODENARC_STATUS$SPOTBUGS_STATUS$VERIFY_STATUS$DANGER_STATUS" | grep -Fqs 'fail'; then
	exit 1
fi
