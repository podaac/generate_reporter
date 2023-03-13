#!/usr/local/bin/perl

#  Copyright 2016, by the California Institute of Technology.  ALL RIGHTS
#  RESERVED. United States Government Sponsorship acknowledged. Any commercial
#  use must be negotiated with the Office of Technology Transfer at the
#  California Institute of Technology.
#
# $Id$
# DO NOT EDIT THE LINE ABOVE - IT IS AUTOMATICALLY GENERATED BY CM

#
# Subroutine prints a report of the number of MODIS/VIIRS files processed on a particular day.
#
# The subroutine does this by looking through the processing log archive and looks for the
# phrase "SUCCESS_OVERALL_TOTAL_TIME" and the day this report for.
#
# Assumption(s):
#
# 1.  The format of the processing log archive looks like this:
#
#
#        1201508579,Mon Jan 28 00:22:59 2008,20080124-MODIS_T-JPL-L2P-T2008024000500.L2_LAC_GHRSST-v01.nc,SUCCESS_OVERALL_TOTAL_TIME: 143.87
#        1201508579,Mon Jan 28 00:22:59 2008,20080124-MODIS_T-JPL-L2P-T2008024022500.L2_LAC_GHRSST-v01.nc,SUCCESS_OVERALL_TOTAL_TIME: 143.87
#        1201508581,Mon Jan 28 00:23:01 2008,20080124-MODIS_T-JPL-L2P-T2008024040500.L2_LAC_GHRSST-v01.nc,SUCCESS_OVERALL_TOTAL_TIME: 145.87
#        1201509446,Mon Jan 28 00:37:26 2008,20080124-MODIS_T-JPL-L2P-T2008024071000.L2_LAC_GHRSST-v01.nc,SUCCESS_OVERALL_TOTAL_TIME: 175.52
#        1201509449,Mon Jan 28 00:37:29 2008,20080123-MODIS_T-JPL-L2P-T2008023232500.L2_LAC_GHRSST-v01.nc,SUCCESS_OVERALL_TOTAL_TIME: 177.47
#        1201509453,Mon Jan 28 00:37:33 2008,20080124-MODIS_T-JPL-L2P-T2008024121000.L2_LAC_GHRSST-v01.nc,SUCCESS_OVERALL_TOTAL_TIME: 182.62
#        1201516548,Mon Jan 28 02:35:48 2008,20080126-MODIS_T-JPL-L2P-T2008026035500.L2_LAC_GHRSST-v01.nc,SUCCESS_OVERALL_TOTAL_TIME: 85.24
#
#
# where the fields are:
#
#        seconds_since_1950, ascii_text_of_date, file_name_processed, SUCCESS_OVERALL_TOTAL_TIME: num_seconds
#
# 2.  The processing log archive is stored in SCRATCH_AREA/ghrsst_processing_log_archive.txt file.
#
# 3.  The format of the processed file registry looks like this:
#
#        20080304-MODIS_A-JPL-L2P-A2008064004500.L2_LAC_GHRSST-v01.nc.bz2,1204668816,Tue Mar  4 14:13:36 2008
#        20080304-MODIS_A-JPL-L2P-A2008064012000.L2_LAC_GHRSST-v01.nc.bz2,1204672573,Tue Mar  4 15:16:13 2008
#        20080304-MODIS_T-JPL-L2P-T2008064000000.L2_LAC_GHRSST-v01.nc.bz2,1204672628,Tue Mar  4 15:17:08 2008
#        20080304-MODIS_A-JPL-L2P-A2008064012500.L2_LAC_GHRSST-v01.nc.bz2,1204675898,Tue Mar  4 16:11:38 2008
#        20080304-MODIS_A-JPL-L2P-A2008064013000.L2_LAC_GHRSST-v01.nc.bz2,1204675951,Tue Mar  4 16:12:31 2008
#        20080304-MODIS_A-JPL-L2P-A2008064013500.L2_LAC_GHRSST-v01.nc.bz2,1204676008,Tue Mar  4 16:13:28 2008
#        20080304-MODIS_A-JPL-L2P-A2008064014000.L2_LAC_GHRSST-v01.nc.bz2,1204676515,Tue Mar  4 16:21:55 2008
#        20080304-MODIS_A-JPL-L2P-A2008064014500.L2_LAC_GHRSST-v01.nc.bz2,1204677390,Tue Mar  4 16:36:30 2008
#        20080304-MODIS_A-JPL-L2P-A2008064015000.L2_LAC_GHRSST-v01.nc.bz2,1204677446,Tue Mar  4 16:37:26 2008
#        20080304-MODIS_A-JPL-L2P-A2008064015500.L2_LAC_GHRSST-v01.nc.bz2,1204677591,Tue Mar  4 16:39:51 2008
#
# where the fields are:
#
#        file_name_processed,seconds_since_1970,ascii_text_of_date
#
####################################################################################################

$GHRSST_PERL_LIB_DIRECTORY = $ENV{GHRSST_PERL_LIB_DIRECTORY};

do "$GHRSST_PERL_LIB_DIRECTORY/read_configuration_file.pl";

my $g_L2P_registry = "";   # Global variable to hold the name of the registry file.

#--------------------------------------------------------------------------------------------------
sub print_daily_report_from_processed_file_registry
{
    # Function gets the number of entries in the processed file registry.

    # Get input(s):

    my $i_unique_id   = $_[0];
    my $i_instrument  = $_[1];  # "VIIRS"
    my $i_data_type   = $_[2];  # "QUICKLOOK" or "REFINED"
    my $i_report_year = $_[3];
    my $i_date_string_search_token = $_[4];

    # Returned variable(s): 
    my $r_num_files_from_registry = 0;

    # Determine which processed file registry to use.

    my $scratch_area = $ENV{SCRATCH_AREA};
#    my $scratch_area = "/home/ghrsst_ps/scratch"; 

    # Depend on the processing type, use different registry.
    if ($i_data_type eq "QUICKLOOK" || $i_data_type eq "REFINED") {
        $g_L2P_registry = $scratch_area . "/ghrsst_master_" . lc($i_instrument) . "_" . lc($i_data_type) . "_list_processed_files_" . $i_unique_id . ".dat";
    } else {
        print "print_generic_daily_report: Unrecognized processing type.  No need to continue\n";
        print "print_generic_daily_report: i_data_type = [$i_data_type]\n";
        return ($r_num_files_from_registry);
    }

    my $system_command_string = "grep \"$i_date_string_search_token\" $g_L2P_registry | grep $i_report_year | grep $i_instrument";
#print "system_command_string = [$system_command_string]\n";

    # Get the lines from registry.

    my @file_list_in_registry_on_this_day = readpipe($system_command_string);

    $r_num_files_from_registry = @file_list_in_registry_on_this_day;

    # Get the number of lines.  This may not be necessary as the previous line gets all the lines.
    # It is here in case. 

    $system_command_string = $system_command_string . " | wc -l";
    my $wc_command_output = readpipe($system_command_string);
    chomp($wc_command_output);

    return($r_num_files_from_registry);
}


#--------------------------------------------------------------------------------------------------
sub print_generic_daily_report
{
  #
  # Get input parameters.
  #

  my $i_unique_id   = $_[0];
  my $i_instrument  = $_[1];  # "VIIRS"
  my $i_data_type   = $_[2];  # "QUICKLOOK" or "REFINED"
  my $i_report_date = $_[3];  # "Jan 28" or "today"  3 letter month, a space, and the day
  my $i_report_year = $_[4];  # "2008"   4 digits year or empty if $i_report_date is "today"

  # Execution status.  Value of 0 means OK, 1 means bad.

  my $o_status = 0;

  # Check to make sure the environment variables are defined.  Return immediately if not.

  if (length($ENV{SCRATCH_AREA}) == 0) {
      print "ERROR: SCRATCH_AREA is not defined.\n";
      $o_status = 1;
      return ($o_status); 
  }

  # Check to make sure the log archive can be found.
  
  my $archive_filename = $ENV{PROCESSING_LOGS} . "/ghrsst_" . lc($i_instrument) . "_processing_log_archive_" . $i_unique_id . ".txt";   # processing_logs
  # print "ARCHIVE FILE NAME: $archive_filename\n";

  if (!-e($archive_filename)) {
      print "ERROR: File $archive_filename cannot be found.\n";
      $o_status = 1;
      return ($o_status);
  }

  # Create a list of months so we can convert 1 to Jan, and 2 to Feb, etc...

  my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

  # Get today's date and time from the operating system.
  #
  #  0    1    2     3     4    5     6     7     8
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

  # Note: the year variable returned from localtime() function is only two digits.
  # Add 1900 to get the 4 digit year.
  $year += 1900;

#  print "sec = [$sec]\n";
#  print "min = [$min]\n";
#  print "hour = [$hour]\n";
#  print "mday = [$mday]\n";
#  print "mon = [$mon] $months[$mon]\n";
#  print "year = [$year]\n";
#  print "wday = [$wday]\n";
#  print "yday = [$yday]\n";
#  print "isdst = [$isdst]\n";

  # Parse the i_report_date for the month and day.  If it is "today" we convert it to the
  # proper date string.

  my $l_date_string_search_token = "";

  if ($i_report_date eq "today") {
#print "i_report_date is today\n";
#print "i_report_date = [$i_report_date]\n";

      # Build the l_date_string with the month and day.
      # Becareful here, day less than 10 has two spaces in between the month and the day.
      # This is the particular aspect of the "ls" command.

      if ($mday < 10) {
          $l_date_string_search_token = $months[$mon] . "  " . $mday; 
      } else {
          $l_date_string_search_token = $months[$mon] . " " . $mday; 
      }

      $i_report_year = $year; 
  } else {
      $l_date_string_search_token = $i_report_date;
      # Set the year to this year if user did not specify the year.
      if ($i_report_year eq "") {
          $i_report_year = $year; 
      }
  }

  # Build the system command string to look for lines containing the files processed for a
  # particular day.

#print "i_report_year = [$i_report_year]\n";

  my $system_command_string = "grep \"$l_date_string_search_token\" $archive_filename | grep $i_report_year | grep SUCCESS_OVERALL_TOTAL_TIME | grep $i_instrument | grep $i_data_type";
#   print "system_command_string = [$system_command_string]\n";


  # Get the lines from archive log.

  my @file_list_processed_on_this_day = readpipe($system_command_string);

  my $num_files_processed = @file_list_processed_on_this_day;

  # Get the number of lines.

  $system_command_string = $system_command_string . " | wc -l";
  my $wc_command_output = readpipe($system_command_string);

  # Remove the carriage return.

  chomp($wc_command_output);
#print "wc_command_output = [$wc_command_output]\n"; 

  #
  # Get the number of files in the processed file registry as well.
  #
  my $l_num_files_from_registry = print_daily_report_from_processed_file_registry(
                                    $i_unique_id,
                                    $i_instrument,
                                    $i_data_type,
                                    $i_report_year,
                                    $l_date_string_search_token);


  if ($num_files_processed > 0) {
      print "\n";
      print "==========================================================================================\n";
      print "Product: list of $i_data_type $i_instrument L2P files processed on $l_date_string_search_token, $year\n";
      print "Extracted_from: $archive_filename\n";
      print "Software: Perl module print_generic_daily_report.pl\n";
      print "Date_printed: " . localtime(time) . "\n";
      print "Num_files_processed: $num_files_processed, Note: it may be different than from registry.\n"; 
      print "Num_files_from_registry: $l_num_files_from_registry, g_L2P_registry = $g_L2P_registry\n"; 

      # Change to 2 == 2 if wish to print the actual names of files processed.
      if (2 == 3) {
        print "Format: seconds_since_1950, ascii_text_of_date, file_name_processed, SUCCESS_OVERALL_TOTAL_TIME: num_seconds\n";
        print "\n";
        print @file_list_processed_on_this_day; 
        print "\n";
      }
  } else {
      print "There were no $i_data_type $i_instrument L2P files processed on $l_date_string_search_token, $i_report_year\n";
  }

  # ---------- Close up shop ----------
  return ($o_status);
}

#--------------------------------------------------------------------------------------------------
# Describes how to use this program
#
sub usage()
{ 
    print "\n";
    print "perl usage: $0 [-i instrument -d data_type -t date -y year]\n";
    print "\n";
    print " -i instrument : MODIS_A or MODIS_T or VIIRS\n";
    print " -d data_type  : QUICKLOOK or REFINED\n";
    print " -t date       : Date of report as in \"Jan 28\" or \"Feb  2\"\n";
    print " -y year       : The year\n";
    print "\n";
    print "Note: If the date is less than 10, there must be 2 spaces between the month and the day.\n";
    print "\n";
    exit; 
} 

#--------------------------------------------------------------------------------------------------
use Getopt::Std;   # Use to get arguments from command line.
    
#   
# Get the filename of the list of files to be resend.
#    
my %options = ();
my $ok = getopts('hf:u:i:d:t:y:',\%options) or usage();
my $unique_id = "";
my $l_data_type = "";
my $l_report_date = ""; 
my $l_instrument = ""; 
my $l_report_year= ""; 

# 
# Get the file name if the -f option is specified.  Exit if now.
#

if ($ok eq 1) {
    $l_unique_id = $options{u};
    $l_instrument= $options{i};
    $l_data_type = $options{d};
    $l_report_date =$options{t};
    $l_report_year =$options{y};
}

#   
# Print usage if user specified -h option.
#    

usage() if $options{h};

# Call the subroutine defined above.

my $l_monitor_status = print_generic_daily_report($l_unique_id,$l_instrument,$l_data_type,$l_report_date,$l_report_year);

# Check for errors

if ($l_monitor_status == 1){
  system("touch", "/tmp/error.txt");
  print "print_generic_daily_report.pl encountered an error. Exiting.\n";
  exit(1);
}