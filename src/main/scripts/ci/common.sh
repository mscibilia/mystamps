print_status() {
	# $1 is empty if check has succeeded
	# $1 equals to 'fail' if check has failed
	# $1 equals to 'skip' if check has skipped
	local result="$1"
	local msg="$2"
	
	local status='SUCCESS'
	local color=32
	
	if [ "$result" = 'fail' ]; then
		status='FAIL'
		color=31
	elif [ "$result" = 'skip' ]; then
		status='SKIP'
		color=33
	fi
	printf "* %s... \033[1;%dm%s\033[0m\n" "$msg" "$color" "$status"
}

fold_start() {
	local name="$1"
	local title="$2"
	
	printf "\ntravis_fold:start:%s\033[33;1m%s\033[0m\n" "$name" "$title"
}

fold_end() {
	local name="$1"
	
	printf "\ntravis_fold:end:%s\r" "$name"
}
