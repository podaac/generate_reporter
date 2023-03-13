#!/bin/csh

#  Copyright 2008, by the California Institute of Technology.  ALL RIGHTS
#  RESERVED. United States Government Sponsorship acknowledged. Any commercial
#  use must be negotiated with the Office of Technology Transfer at the
#  California Institute of Technology.
#
# $Id$
# DO NOT EDIT THE LINE ABOVE - IT IS AUTOMATICALLY GENERATED BY CM

#
# C-shell to create a report of the number of MODIS/VIIRS files processed on a particular day
# and email it to users defined in environment variable OPS_MODIS_MONITOR_EMAIL_LIST.
#
# The shell script calls the Perl subroutine with the same name.
#

source $LAMBDA_TASK_ROOT/reporter_config

set i_first_arg = $argv[1]

# Start with empty string for the system command.

set perl_script_command = ""
set report_created_flag = ""
set i_instrument  = "" 
set i_data_type   = "" 
set i_email_flag  = "" 

if $i_first_arg == "-h" then
    # Print the -h options from Perl script and exit.
    echo "Help argument request"
    set perl_script_command = "perl $GHRSST_PERL_LIB_DIRECTORY/print_generic_daily_report.pl -h" 
    $perl_script_command
else
    set unique_id     = $argv[1]
    set i_instrument  = $argv[2]
    set i_data_type   = $argv[3]
    # The i_report_date must be enclosed in quotes since it has spaces.
#echo "[$argv[3]]"

    # Check to see if the $argv[3] is today.
    # If true, set the year to blank (equivalent to this year).
#echo "MARKER1 [$argv[3]]"
    if ("$argv[4]" == "today") then
        set i_report_date = "$argv[4]"
        set i_report_year = 9999
        if ($#argv > 4) then
            set i_email_flag  = $argv[5]
            echo "[$i_email_flag]"
        endif
    else
#echo "THERE [$argv[3]]"
#echo "THERE [$argv[4]]"
        set i_report_date = "$argv[4]"
        set i_report_year = $argv[5]
    endif


    # Only get the -m flag if we have the correct number of arguments of 5

#echo "[$#argv]"
    if ($#argv == 6) then
       set i_email_flag  = $argv[6]
       echo "[$i_email_flag]"
    endif

#echo "HERE [$i_instrument]"
#echo "HERE [$i_data_type]"
#echo "HERE [$i_report_date]"
#echo "HERE [$i_report_year]"
#echo "HERE [$i_email_flag]"
    set PERL_SCRIPT_LOCATION = $GHRSST_PERL_LIB_DIRECTORY
    set perl_script_command = "perl $GHRSST_PERL_LIB_DIRECTORY/print_generic_daily_report.pl "

#echo "[$perl_script_command]"

  # Create an empty report file.
  if (! -d $SCRATCH_AREA/reports ) then
    mkdir -p $SCRATCH_AREA/reports
  endif
  set REPORT_FILENAME = $SCRATCH_AREA/reports/daily_report_${i_instrument}_${i_data_type}_${unique_id}.txt
  rm -f $REPORT_FILENAME
  touch $REPORT_FILENAME

  # Log script data
  echo "UNIQUE ID:      $unique_id"
  echo "INSTRUMENT:     $i_instrument"
  echo "DATA TYPE:      $i_data_type"
  echo "REPORT DATE:    $i_report_date"
  echo "REPORT YEAR:    $i_report_year"
  echo "EMAIL FLAG:     $i_email_flag"
  echo "REPORT NAME:    $REPORT_FILENAME"

  # Execute the Perl script and send output to report file.
  # The i_report_date must be enclosed in quotes since it has spaces.
  $perl_script_command -u $unique_id -i $i_instrument -d $i_data_type -t "$i_report_date" -y $i_report_year | tee $REPORT_FILENAME
  echo "PERL SCRIPT COMMAND: $perl_script_command -u $unique_id -i $i_instrument -d $i_data_type -t '$i_report_date' -y $i_report_year"

  # Sent the report name to terminal.
  echo "Output has been saved to $REPORT_FILENAME" 
  echo "Can be viewed with:  cat $REPORT_FILENAME" 

  # Set flag that the report has been created so it can be emailed if asked.
  set report_created_flag = "yes"
endif

#
# Send the email if the report was created and the user asks for it.
# Must add the extra 'x' in front of $i_emal_flag and "-m" to avoid the "if: Missing file name"
# error.
#

if ((x$i_email_flag == x"-m") && ($report_created_flag == "yes")) then
  # Send the email of the output content.

  set EMAIL_RECIPIENT_LIST = $OPS_MODIS_MONITOR_EMAIL_LIST

  echo "Email has been sent to $EMAIL_RECIPIENT_LIST" 
  echo "   set in environment variable OPS_MODIS_MONITOR_EMAIL_LIST" 

  set today_is = `date`
  set the_subject = "Processing Report for $i_data_type $i_instrument on $today_is"

  echo "the_subject = [$the_subject]"

  #
  #  Send the report to intended recipients.
  #
  mail -s "$the_subject" $EMAIL_RECIPIENT_LIST < $REPORT_FILENAME 

else
   if ($report_created_flag != "yes") then
       echo "A reported was not created." 
   endif
#    if (x$i_email_flag != x"-m") then
#        echo "User did not request an email." 
#    endif
endif

# Get contents of error file indicator see if any errors were encountered in python script
set error_file="/tmp/error.txt"
if ( -f "$error_file" ) then
    rm -rf $error_file    # Remove error file indicator
    echo "print_modis_daily_report.csh exiting with status of 1"
    exit(1)
endif