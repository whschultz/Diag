#!/usr/bin/env awk -f

############################################################
#                                                          #
#  Written by Hank Schultz for Charlotte Street Computers  #
#                                                          #
############################################################

END {
# the first END clause initiates the beginning of the summaries
	if ( print_all_errors != 0 )
		print "\n    ---------------\n";
	else
		print "";

}

# main BEGIN statement.  Sets up coloring variables and spacing counts
BEGIN {
	"tput setaf 1" | getline RED
	"tput setaf 2" | getline GREEN
	"tput setaf 3" | getline YELLOW
	"tput setaf 4" | getline BLUE
	"tput setaf 5" | getline PURPLE
	"tput smso" | getline BOLD
	"tput rmso" | getline OFFBOLD
	"tput sgr0" | getline RESET
	"tput bold ; tput setaf 1" | getline BOLD_RED
	"tput bold ; tput setaf 5" | getline PINK
		
	# how many lines of spacing on either end?  Default to 10.
	if (spacing==0)
		spacing=10;

	#print "Checking for known error messages..."
	
	lines_since_error=spacing+1;
}
# Main END statement.  Gives a count of the error types encountered
END {
	#print "Done"
	print "Summary of errors encountered\ncount\t: error type";
	for ( error_type in error_counts )
		print error_colors[error_type] error_counts[error_type] "\t: " error_type RESET;
#	RESET()
	print ""
}

####################################################################
#
#   IO and Media
#

BEGIN {
# The purpose of this BEGIN statement is to set up the regular expression used to find IO errors on internal drives

	# Currently, the following has been verified on 10.6.
	# List internal drives that are not ejectable.
	program_for_list_of_drives="system_profiler -listDataTypes | egrep 'ATA|SCSI' | xargs system_profiler | awk '/BSD Name.*disk[0-9]+$/ { print $3 }' | xargs -n 1 diskutil info | awk '/Ejectable/ { if ( $2 == \"No\" ) print identifier; } /Device Identifier/ { identifier=$3; }'"

	# The following lists internal SCSI, ATA, or SATA drives, even if they are ejectable.
	#program_for_list_of_drives="system_profiler -listDataTypes | egrep 'ATA|SCSI' | xargs system_profiler | awk '/BSD Name.*disk[0-9]+$/ { print $3 }'"

	while((program_for_list_of_drives | getline temp_drive) > 0)
	{
		list_of_drives[temp_drive]=temp_drive;
	}
	close(program_for_list_of_drives);
		
	for( drive in list_of_drives )
	{
	# These drives are considered "Main IO".  All others are considered
	# secondary IO or disk images.  In some cases, booting from an external USB device
	# will cause the boot device to snag disk0, but this is rare and likely only happens
	# when the internal drive takes a long time to spin up and be ready.  This is part of why
	# this is being printed.  If disk0 isn't in this list, the interpretations of the log
	# files may be inaccurate.
		print "Found physically connected drive:  " drive
		if ( physically_connected_drives_regexp == 0 )
			physically_connected_drives_regexp=drive;
		else
			physically_connected_drives_regexp=(physically_connected_drives_regexp "|" drive );
	}
	
	disk_IO_error_regexp="(" physically_connected_drives_regexp ")(s[0-9]+)?:.*(I\\/O (error|timeout)|media is not present|\\(UNDEFINED\\)|device is not open|alignment error|close: journal .*, is invalid)";
	#print "disk IO regexp: " disk_IO_error_regexp
}

$0 ~ disk_IO_error_regexp {
	handle_error_row($0,"Main IO",RED);
	next;
}

/disk[1-9][0-9]*.*(media is not present|device\/channel is not attached)|msdosfs_fat_uninit_vol: error 6 from msdosfs_fat_cache_flush|fseventsd.*disk logger.*failed to open output file.*No such file or directory/ {
	last_unplug_error=0;
	if ( ignore_unplug_errors == 0 )
		handle_error_row($0,"Improperly unplugged external device",BLUE);
	else
		handle_ignored_error($0,"Improperly unplugged external device",BLUE);
	next;
}

/(disk[1-9][0-9]*.*(I\/O (error|timeout)|\(UNDEFINED\))|device is not open|fseventsd.*failed to unlink old log file.*\(Input\/output error\)|backupd.*Input\/output error)/ {
	if ( last_multimedia_error < multimedia_limit )
	{
		# This disk error is still a multimedia error, and we need to treat it
		# as such, whether we report it or not.
		last_multimedia_error=0;
		if ( ignore_multimedia_errors == 0 )
			handle_error_row($0,"Multimedia",YELLOW);
		else
		{
			handle_ignored_error($0,"Multimedia",YELLOW);
		}
	}
	else
	{
		if ( ignore_secondary_io_errors == 0 )
			handle_error_row($0,"Secondary IO",PURPLE);
		else
			handle_ignored_error($0,"Secondary IO",PURPLE);
	}
		
	next;
}

/Burn to.*media in.*failed|SerialATAPI device reconfiguration did not complete successfully|SerialATAPI Terminating due to unrecoverable Reset error - drive has stopped responding/ {
	if ( ignore_multimedia_errors == 0 )
		handle_error_row($0,"Multimedia (burn failed)",RED);
	else
		handle_ignored_error($0,"Multimedia (burn failed)",RED);
	next;
}


BEGIN {
	multimedia_limit=1;
	last_multimedia_error=multimedia_limit+spacing+1;
	last_unplug_error=spacing+1;
}

/SAM Multimedia: READ or WRITE failed|disk[1-9][0-9]*.*unsupported mode|disk[1-9][0-9]*.*alignment error/ {
	last_multimedia_error=0;
	if ( ignore_multimedia_errors == 0 )
		handle_error_row($0,"Multimedia",YELLOW);
	else
		handle_ignored_error($0,"Multimedia",YELLOW);
	next;
}

/disk[1-9][0-9]*.*privilege violation/ {
	if ( ignore_multimedia_errors == 0 )
		handle_error_row($0,"Multimedia (region violation)",YELLOW);
	else
		handle_ignored_error($0,"Multimedia (region violation)",YELLOW);
	next;
}

/(timed out waiting for IOKit to quiesce|AppleSMUsendMISC: FAILURE -- TIMEOUT EXCEEDED on GPIO)/ {
	handle_error_row($0,"IOKit",RED);
	next;
}

/InterfaceNamer/ {
	if ( lines_since_error==0 )
	{
		# don't add additional errors to the count for these lines,
		# but we want to make sure they show up when looking at context
		handle_additional_error_row($0,"IOKit",RED);
		next; # keep this inside the "if" statement
	}
}

/FireWire.*(bus resets in last.*minutes|no valid selfIDs.*after bus reset)/ {
	handle_error_row($0,"FireWire",PURPLE);
	next;
}

/(USBF|IOUSBMassStorageClass|USB Notification).*(timing|is having trouble enumerating|was not able to enumerate|The device is still unresponsive|bit not sticking|data length is 0 in enqueueData|Device.*is violating.*the USB Specification|has caused an overcurrent condition|returning error|reported error|could not find the hub device)/ {
	if ( ignore_usb_errors == 0 )
		handle_error_row($0,"USB",YELLOW);
	else
		handle_ignored_error($0,"USB",YELLOW);
	next;
}

/(AppleUSBMultitouchDebug|AppleUSBMultitouchDriver).*(packet checksum is incorrect|returning error|reported error)/ {
	if ( ignore_usb_errors == 0 )
		handle_error_row($0,"Trackpad",PURPLE);
	else
		handle_ignored_error($0,"Trackpad",PURPLE);
	next;
}

/AppleRAID.*(has been marked offline|(read|copy) failed)/ {
	if ( ignore_usb_errors == 0 )
		handle_error_row($0,"RAID",RED);
	else
		handle_ignored_error($0,"RAID",RED);
	next;
}



####################################################################
#
#   File System and Software
#

/jnl.*disk[0-9]+.*(close: journal .*, is invalid|only wrote.*of.*bytes to the journal|error)|kernel.*(ntfs|NTFS|hfs|msdosfs).*(corruption|[Ee]rr|[Ff]ailed|invalid|warning|can.t find (iNode|dir))/ {
	handle_error_row($0,"File system",YELLOW);
	next;
}

BEGIN {
	# Not an official list.  Tweaking this as I come across the errors.  Descriptions are determined
	# by author from context clues in the logs.
	list_of_time_machine_explanations[11]=RED"Copy failed"RESET;
	list_of_time_machine_explanations[18]=RED"Couldn't find backup (e.g. backup found but doesn't match this computer, or couldn't connect to server)"RESET;
	list_of_time_machine_explanations[19]=YELLOW"Error while resolving alias to backup target; mount failed"RESET;
	list_of_time_machine_explanations[20]=YELLOW"Failed to create image"RESET;
	list_of_time_machine_explanations[21]=YELLOW"Failed to attach image"RESET;
	list_of_time_machine_explanations[26]=YELLOW"Disk full; changing Time Machine settings on destination failed; writing to backup destination failed"RESET;
	list_of_time_machine_explanations[27]=YELLOW"Stopped backup because the backup volume was ejected"RESET;
	list_of_time_machine_explanations[29]=YELLOW"Authentication failed"RESET;
	list_of_time_machine_explanations[31]=PURPLE"Failed to mount disk image (e.g. disk image may already be mounted.  restart base station.)"RESET;
}
/backupd.*Backup failed with error: ([0-9]+)/ {
	if ( ignore_time_machine_errors == 0 )
	{
		time_machine_error_count++;
		split($0,reason_row,": ");
		time_machine_failure_reasons[reason_row[3]]++;
		handle_error_row($0,"Time Machine",YELLOW);
	}
	else
		handle_ignored_error($0,"Time Machine",YELLOW);
	next;
}
END {
# this END statement gives the summary from the above Time Machines failure causes
	if ( time_machine_error_count > 0 ) {		
		print "Summary of Time Machine errors encountered\ncode\t: count\t: description";
		for (reason in time_machine_failure_reasons) {
			print reason "\t: " time_machine_failure_reasons[reason] "\t: " list_of_time_machine_explanations[reason];
		}
		
		if ( worst_days_since_backup != 0 )
			print "Worst amount of time between backups:  " worst_days_since_backup " as of " worst_date;
		if ( last_failed_backup != 0 )
			print "Last failed backup:      " last_failed_backup;
	}
	
	if ( last_successful_backup != 0 )
	{
		print GREEN"Last successful backup:  " last_successful_backup RESET
	}
	else
	{
		if ( time_machine_error_count > 0 )
			print RED"No successful Time Machine backups found."RESET
		else
			print YELLOW"No Time Machine backups found."RESET
	}

	print ""
}

/backupd.*days since last backup/ {
	if ( ignore_time_machine_errors == 0 )
	{
		last_failed_backup=$1 " " $2 " " $3;
		split($0,backup_failed_row,": ");
		split(backup_failed_row[2],days_since_backup_row," ");
		days_since_backup=days_since_backup_row[1];
		if ( days_since_backup > worst_days_since_backup )
		{
			worst_days_since_backup=days_since_backup;
			worst_date=last_failed_backup;
		}

		handle_error_row($0,"Time Machine",YELLOW);
	}
	else
		handle_ignored_error($0,"Time Machine",YELLOW);
	next;
}

/backupd.*Backup completed successfully/ {
	if ( ignore_time_machine_errors == 0 )
	{
		last_successful_backup=$1 " " $2 " " $3;
	}
	next;
}

/backupd.*(Backup failed|FSMountServerVolumeSync failed with error|Error writing to backup log.*Input\/output error|Cookie file is not readable or does not exist|Volume at path.*does not appear to be the correct backup volume for this computer)/ {
	if ( ignore_time_machine_errors == 0 )
		handle_error_row($0,"Time Machine",YELLOW);
	else
		handle_ignored_error($0,"Time Machine",YELLOW);
	next;
}


/DirectoryService.*Failed Authentication.*for username/ {
	if ( ignore_login_failures == 0 )
	{
		login_failure_count++;
		split($0,reason_row,": ");
		account_login_failure[reason_row[3]]++;
		handle_error_row($0,"Failed login attempt",PURPLE);
	}
	else
		handle_ignored_error($0,"Failed login attempt",YELLOW);
	next;
}

END {
# this END statement gives the summary from the above Time Machines failure causes
	if ( login_failure_count > 0 ) {		
		print "Failed user logins\ncount\t: name";
		for (name in account_login_failure) {
			print account_login_failure[name] "\t: " name ;
		}

		print ""
	}
}

/Allocator race detected: transaction is not verified for/ {
	if ( ignore_potential_hang == 0 )
		handle_error_row($0,"Potential Hang",PURPLE);
	else
		handle_ignored_error($0,"Potential Hang",PURPLE);
	next;
}

/mDNSResponder.*(Double NAT|Failed to obtain NAT port mapping|Registration of record.*members\.mac\.com\..*failed)/ {
	if ( ignore_back_to_my_mac_errors == 0 )
		handle_error_row($0,"Back to My Mac",YELLOW);
	else
		handle_ignored_error($0,"Back to My Mac",YELLOW);
	next;
}

/fontd.*(problematic|Error|[Ff]ailed)/ {
	if ( ignore_font_errors == 0 )
		handle_error_row($0,"Font",YELLOW);
	else
		handle_ignored_error($0,"Font",YELLOW);
	next;
}

/SystemStarter.*failed security check/ {
	split($0,a,":");
	explanation=a[4]": "a[5];
	security_failure_reasons[explanation]++;
	security_failure_count++;

	if ( ignore_security_errors == 0 )
		handle_error_row($0,"Security",PURPLE);
	else
		handle_ignored_error($0,"Security",PURPLE);
	next;
}
END {
# this END statement gives the summary from the above security failure causes
	if ( security_failure_count > 0 ) {		
		print PURPLE"Summary of Security errors encountered:"RESET;
		for (failure in security_failure_reasons) {
			print failure;
		}
	}

	print ""
}




# Commented out because this does not seem to be indicative of actual problems
#/kernel.*(decmpfs|AppleFSCompression).*err/ {
#	if ( ignore_compression_errors == 0 )
#		handle_error_row($0,"Apple File System Compression",YELLOW);
#	else
#		handle_ignored_error($0,"Apple File System Compression",YELLOW);
#	next;
#}

/kernel.*(default pager.*(System is out of paging space|[Ee]mergency paging segment|Swap File Error)|low swap: (suspending pid|unable to find any eligible processes to take action on))/ {
	if ( ignore_swap_full_errors == 0 )
		handle_error_row($0,"Ran out of swap space.",RED);
	else
		handle_ignored_error($0,"Ran out of swap space.",RED);
	next;
}

/audit space low/ {
	if ( ignore_drive_full_errors == 0 )
		handle_error_row($0,"Running out of HD space.",PURPLE);
	else
		handle_ignored_error($0,"Running out of HD space.",PURPLE);
	next;
}

/ct_loader|cttoolbar|CTLoad|Incompatible applications.*app=.*targetApp=/ {
	# By default, the messages in the logs are not shown for this error.  It's really only relevant
	# that it's installed and should most likey be uninstalled.
	if ( dont_ignore_cttoolbar == 1 )
		handle_error_row($0,"CTToolbar is installed and producing errors",YELLOW);
	else
		handle_ignored_error($0,"CTToolbar is installed and producing errors",YELLOW);
	next;
}


####################################################################
#
#   Internal Hardware
#


/((NVDA|NVChannel)(\((Compute|OpenGL|Display)\).*(exception|timeout)|: Fatal error)|ATIRadeon.*Overflowed|GPU Debug Info|kernel.*Graphics chip error|The graphics driver has detected a corruption in its command stream)/ {
	if ( ignore_graphics_errors == 0 )
		handle_error_row($0,"Graphics",RED);
	else
		handle_ignored_error($0,"Graphics",RED);
	next;
}

/Sound assertion.*failed|WARNING:.*(has detected that a connected.*audio device is sending too much audio data|This.*audio device may not function properly.*Please notify the device manufacturer)/ {
	if ( ignore_sound_errors == 0 )
		handle_error_row($0,"Sound",YELLOW);
	else
		handle_ignored_error($0,"Sound",YELLOW);
	next;
}

/(AppleBluetooth.*(Timeout|getReport returned error|Couldn\'t get battery (percentage|state) from device|Could not send .* command)|Bluetooth Setup Assistant.*Connection failed for pre-paired device|USBBluetoothHCIController.*timed out after)/ {
	handle_error_row($0,"Bluetooth",YELLOW);
	next;
}

/(SystemUIServer|System Preferences).*Error joining|(Apple80211|airportd).*([Ee]rror|failed|bailing)/ {
	handle_error_row($0,"Airport",PURPLE);
	next;
}

/kernel.*bad busy count/ {
	handle_error_row($0,"Bad Busy",PURPLE);
	next;
}

# This appears to be a normal sleep/wake message.  The ethernet/airport is put to sleep as the
# machine goes to sleep.
#/AppleYukon2.*(HardwareNotResponding|hardware is not responding)/ {
#	if ( ignore_ethernet_errors == 0 )
#		handle_error_row($0,"Ethernet Hardware",RED);
#	else
#		handle_ignored_error($0,"Ethernet Hardware",RED);
#	next;
#}



####################################################################
#
#   Shutdown Causes
#

/AppleSMU -- shutdown cause/ {
	# PowerPC
	if ( print_all_errors == 1 || print_all_shutdown_causes == 1 )
	{
		if ( $11 >= 0 && print_all_shutdown_causes == 1 ) 
			print $8 " at " $1 " " $2 " " $3 " : " $11;
		else
		{
			if ( $11 < 0 )
				print "Suspicious shutdown cause at " $1 " " $2 " " $3 " : " $11;
		}
	}

	list_of_causes[$11]++;
	show_summary=1;
	if ( $11 > max )
		max = $11;
	if ( $11 < min )
		min = $11;
}
/Previous (Shutdown|Sleep) Cause/ {
	# Intel
	if ( $9 ~ /^-?[0-9]+$/ )
	{
		if ( ! ( $9 in list_of_explanations ) )
		{
			list_of_explanations[$9]=BOLD RED"(abnormal, not found in documentation)"RESET;
		}
		
		if ( ( print_all_errors == 1 && $9 < 0 && $9 != -5 ) || print_all_shutdown_causes == 1 )
			print $7 "   \tat " $1 " " $2 " " $3 "\t: " $9 "\t" list_of_explanations[$9];
			
		list_of_causes[$9]++;
		show_summary=1;
		if ( $9 > max )
			max = $9;
		if ( $9 < min )
			min = $9;
	}
}
BEGIN {
# this BEGIN statement ties in with the above shutdown codes regex

	show_summary=0;

	if ( MODEL_IDENTIFIER == 0 )
	{
	# Note that the default behavior is to get the Model Indentifier from the machine checking
	# the log files.  If you're checking the log files of a completely different machine, you
	# should find that machine's model identifier and pass it into this script using awk's "-v"
	# argument.  The "if" statement is here such that the model identifier is only looked up
	# if it isn't provided.

		command_to_get_model_id="system_profiler SPHardwareDataType | awk '/Model Identifier|Machine Model/ { print $3 }'"
		command_to_get_model_id | getline MODEL_IDENTIFIER
		#MODEL_IDENTIFIER=$0
		close(command_to_get_model_id)
		print "This machine's model identifier:   " MODEL_IDENTIFIER
	}
	else
	{
		print "Using model identifier:   " MODEL_IDENTIFIER
	}
	
	
	# Many of these descriptions come directly from Apple's service manuals (which have limited 
	# information and are therefore rather ambiguous as to what's really going on.  e.g. -70).
	# Others come from direct observation and are known.  Therefore, don't consider this a master
	# list.  If a specific model is listed, consider the explanation verified.
	
	
	if ( MODEL_IDENTIFIER ~ /iMac7,1/ )
	{
		list_of_explanations[0]="(power disconnected or booted from different device.  Expected normal behavior)";
		list_of_explanations[-2]=RED"(power supply disconnected.  Suspicious behavior)"RESET;
	}
	else if ( MODEL_IDENTIFIER ~ /iMac[0-9]+,[0-9]+/ )
	{
		list_of_explanations[0]="(power disconnected.  Expected normal behavior)";
		list_of_explanations[-2]=RED"(power supply disconnected.)"RESET;
	}
	else
	{
		list_of_explanations[0]="(battery/power disconnected.  Expected normal behavior)";
		list_of_explanations[-2]=YELLOW"(power supply disconnected.  Normal if unplugged with no battery.)"RESET;
	}


	if ( MODEL_IDENTIFIER ~ /MacBookPro5,5/ )
	{
		# This is identical to the below description, but it's been explicitly verified on this model.
		list_of_explanations[3]="(normal restart or power button forced shutdown.  Expected normal behavior)";
	}
	else if ( MODEL_IDENTIFIER ~ /MacBookPro[0-9]+,[0-9]+/ )
	{
		# Suspect the same is true for all MBPs until we have evidence to the contrary.
		list_of_explanations[3]="(normal restart or power button forced shutdown.  Expected normal behavior)";
	}
	else
	{
		list_of_explanations[3]="(power button forced shutdown.  Expected normal behavior)";
	}


	if ( MODEL_IDENTIFIER ~ /MacBookPro[0-9]+,[0-9]+/ )
	{
		# The Apple documentation has completely different descriptions for this code
		# depending on the machine that produces it.
		list_of_explanations[-86]=RED"(Proximity temperature exceeds limits)"RESET;
	}
	else if ( MODEL_IDENTIFIER ~ /MacBook[0-9]+,[0-9]+/ )
	{
		# This code is not in the documentation for the MacBook, but it still comes up.
		# Research seems to indicate it's a temperature issue on the MacBook.
		list_of_explanations[-86]=RED"(Proximity temperature exceeds limits.  Check fan.)"RESET;
	}
	else if ( MODEL_IDENTIFIER ~ /MacBookAir[0-9]+,[0-9]+/ )
	{
		list_of_explanations[-86]=RED"(Charger circuit on logic board.)"RESET;
	}
	else
	{
		list_of_explanations[-86]=RED"(Not in documentation for this model.  Suspect overtemp.)"RESET;
	}


	if ( MODEL_IDENTIFIER ~ /MacBook[0-9]+,[0-9]+/ )
	{
		list_of_explanations[-3]=RED"(multiple sensors overtemp.  Check fan.)"RESET;
		list_of_explanations[-4]=RED"(overtemp.  Check fan.  Reapply thermal paste)"RESET;
	}
	else
	{
		list_of_explanations[-3]=RED"(multiple sensors overtemp.  Run ASD to see which ones)"RESET;
		list_of_explanations[-4]=RED"(overtemp.  Reapply thermal paste)"RESET;
	}
	list_of_explanations[-72]=list_of_explanations[-4];
	list_of_explanations[-84]=list_of_explanations[-4];
	list_of_explanations[-95]=list_of_explanations[-4];
	
	
	list_of_explanations[5]="(normal shutdown or sleep)";
	list_of_explanations[-5]=list_of_explanations[-5];

	list_of_explanations[-128]=YELLOW"(not known.  Did it boot from a different OS?  Potentially normal behavior)"RESET;

	list_of_explanations[-61]=YELLOW"(OS X watchdog shutdown timer.  OS stopped responding)"RESET;
	list_of_explanations[-62]=YELLOW"(OS X watchdog restart timer.  OS stopped responding)"RESET;

	list_of_explanations[2]=YELLOW"(battery died.  Potentially normal behavior)"RESET;
	list_of_explanations[-60]=list_of_explanations[2];
	list_of_explanations[-103]=YELLOW"(battery undervoltage; bad battery)"RESET;
	list_of_explanations[-74]=RED"(battery overtemp)"RESET;

	list_of_explanations[-70]=RED"(replace top case)"RESET;

	list_of_explanations[-75]=YELLOW"(communication issue with power adapter)"RESET;
	list_of_explanations[-78]=YELLOW"(incorrect current value coming from AC adapter.  suspect charging circuitry)"RESET;
	list_of_explanations[-79]=YELLOW"(incorrect current value coming from battery.  suspect charging circuitry)"RESET;

	list_of_explanations[-82]=RED"(check thermal sensors)"RESET;
	list_of_explanations[-100]=RED"(power supply temp exceeds limits.  Check fans and air flow)"RESET;
	list_of_explanations[-101]=RED"(LCD overtemp.  Check LCD panel and environment temperature)"RESET;
	
	
	# This overrides anything written above for the following machines.
	if ( MODEL_IDENTIFIER ~ /PowerMac[0-9]+,[0-9]+/ )
	{
	# Verified on iMac G5 (17-inch).  Need to look up the model ID.
	# On the test machine, there were also -122 codes, and it had a semi-dead power supply,
	# so it's possible the -122 means the power supply stopped putting out correct voltages,
	# but this is not known.  (Trickle voltage was present, but machine failed to power on.)
		list_of_explanations[1]="(normal shutdown.  Expected normal behavior)";
		list_of_explanations[2]="(normal restart.  Expected normal behavior)";
		list_of_explanations[3]="(power button forced shutdown.  Expected normal behavior)";
		list_of_explanations[-110]=YELLOW"(lost power.  Potentially normal behavior)"RESET;
	}
}
END {
# this END statement gives the summary from the above shutdown codes regex
	if ( show_summary ) {		
		print "Summary of shutdowns and sleeps encountered\nshutdown: count\t: description";
		for (cause=max; cause >= min; cause--) {
			if ( cause in list_of_causes )
				print cause "\t: " list_of_causes[cause] "\t: " list_of_explanations[cause];
		}
	}
	print ""
}



####################################################################
#
#   How to handle repeats detected by the OS logging system
#

/last message repeated.*time/ {
	if ( last_multimedia_error == 0 )
	{
		last_multimedia_error=0;
	}
		
	if ( last_unplug_error == 0 )
	{
		last_unplug_error=0;
	}

	if ( lines_since_error == 0 )
	{
		handle_error_row($0,last_error,last_color);	
	}
	else
	{
		handle_normal_line($0);
	}
	
	next;
}


####################################################################
#
#   Default Behavior for non-matching lines
#

// {
# clean line
	last_multimedia_error++;
	last_unplug_error++;

	handle_normal_line($0)
	next;
}

function handle_normal_line(line_text) {
	lines_since_error++;

	for (var=spacing-1;var>=0;var--)
	{
		if ( var in clean_line )
		{
			clean_line[var+1]=clean_line[var];
		}
	}
	clean_line[0]=$0;
	#error_counts["Clean"]++;
	
	if ( print_all_errors != 0 )
	{
		if (lines_since_error<spacing)
		{
			print $0
		}
		if (lines_since_error==spacing && spacing > 0)
		{
			#indicate a gap at this point
			print "\n --\n"
		}
	}
}

####################################################################
#
#   Common behavior for matching lines
#

function handle_ignored_error(row_text,error_type,color) {
# count the errors but don't highlight them when showing logs
	handle_error_counts(error_type,color);
	handle_normal_line(row_text);
}

function handle_error_counts(error_type,color) {
	error_counts[error_type]++;
	error_colors[error_type]=color;
}

function handle_error_row(row_text,error_type,color) {
	last_error=error_type;
	last_color=color;
	
	handle_error_counts(error_type,color);
	handle_additional_error_row( row_text,error_type,color );
}

function handle_additional_error_row( row_text,error_type,color ) {
	lines_since_error=0;
	if ( print_all_errors != 0 )
	{
		for (var=spacing-1;var>=0;var--)
		{
			if ( var in clean_line )
			{
				print clean_line[var];
				delete clean_line[var]
			}
		}

		if ( color != 0 )
		{
			print color row_text RESET;
		}
		else
		{
			print row_text;
		}
	}
}

BEGIN {
# the last BEGIN clause initiates the beginning of the matches
	print "\n    ---------------\n";
}
