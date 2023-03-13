"""Download List Creator Lambda

This script serves as a wrapper to the original reporter code.
It performs the following:
1. Determines the files to process to generate a daily report.
2. Processes each file to generate a report for that dataset and particular 
   execution of Generate.
3. Collates the report into one email report and publishes the report to an SNS 
   Topic.
4. Compresses the files that were processed into an archive and removes 
   processing files to avoid duplication in following reports.
"""

# Standard imports
import datetime
import glob
import logging
import os
import pathlib
import subprocess
from subprocess import PIPE
import sys

# Third-party imports
import boto3
import botocore

# Local imports
from notify import notify

# Constants
# DATA_DIR = pathlib.Path("/mnt/data")    # Mounted Processor EFS directory
DATA_DIR = pathlib.Path("/data/dev/tebaldi/aws/reporter/processor")    # Mounted Processor EFS directory

def event_handler(event, context):
    """Parse EventBridge schedule input for arguments and generate reports."""
    
    start = datetime.datetime.now()
    
    logger = get_logger()
    
    # Locate unique identifiers
    dataset_dict = { 
        "modis_a": { "refined": [], "quicklook": [] }, 
        "modis_t": { "refined": [], "quicklook": [] }, 
        "viirs":   { "refined": [], "quicklook": [] }
    }
    locate_processing_files(dataset_dict, logger)
    
    # Generate reports for each unique identifier and combine into single report
    dataset_email = { 
        "modis_a": { "refined": "", "quicklook": "" }, 
        "modis_t": { "refined": "", "quicklook": "" }, 
        "viirs":   { "refined": "", "quicklook": "" }
    }
    for dataset, processing_dict in dataset_dict.items():
        for processing_type, dataset_files in processing_dict.items():
            generate_report(dataset, processing_type, dataset_files, logger)
            combine_dataset_reports(dataset, processing_type, dataset_files, dataset_email)
    
    # Publish report        
    print(dataset_email["modis_a"]["refined"])
    print(dataset_email["modis_a"]["quicklook"])
    
    end = datetime.datetime.now()
    logger.info(f"Execution time - {end - start}.")
    
def get_logger():
    """Return a formatted logger object."""
    
    # Remove AWS Lambda logger
    logger = logging.getLogger()
    for handler in logger.handlers:
        logger.removeHandler(handler)
    
    # Create a Logger object and set log level
    logger = logging.getLogger(__name__)
    logger.setLevel(logging.DEBUG)

    # Create a handler to console and set level
    console_handler = logging.StreamHandler()

    # Create a formatter and add it to the handler
    console_format = logging.Formatter("%(asctime)s - %(module)s - %(levelname)s : %(message)s")
    console_handler.setFormatter(console_format)

    # Add handlers to logger
    logger.addHandler(console_handler)

    # Return logger
    return logger

def locate_processing_files(dataset_dict, logger):
    """Locate quicklook and refined processing files for each dataset.
    
    Modifies dataset_dict to set each key with list of appropriate processing
    files.
    
    Parameters
    ----------
    dataset_dict: dict
        dictionary of 'aqua', 'terra' and 'viirs' keys with quicklook and refined.
    """
    
    for dataset in dataset_dict.keys():
        refined_processing_files = glob.glob(f"{str(DATA_DIR.joinpath('scratch'))}/*{dataset}*refined*.dat")
        if len(refined_processing_files) != 0:
            unique_ids = [ processing_file.split('_')[-1].split('.')[0] for processing_file in refined_processing_files ]
            dataset_dict[dataset]["refined"] = unique_ids
            logger.info(f"Found refined processing files for dataset: {dataset.upper()}.")
        quicklook_processing_files = glob.glob(f"{str(DATA_DIR.joinpath('scratch'))}/*{dataset}*quicklook*.dat")
        if len(quicklook_processing_files) != 0:
            unique_ids = [ processing_file.split('_')[-1].split('.')[0] for processing_file in quicklook_processing_files ]
            dataset_dict[dataset]["quicklook"] = unique_ids
            logger.info(f"Found quicklook processing files for dataset: {dataset.upper()}.")
            
def generate_report(dataset, processing_type, file_ids, logger):
    """Generate report for the dataset using associated files.
    
    Parameters
    ----------
    dataset: str
        "modis_a", "modis_t", "viirs"
    processing_type: str
        "quicklook" or "refined"
    file_ids: list
        List of processing file ids to generate a report from.
    logger: Logger 
        Logger object to log status.
    """
    
    for file_id in file_ids:
        lambda_task_root = os.getenv('LAMBDA_TASK_ROOT')
        try:
            if dataset == "modis_a" or dataset == "modis_t":
                subprocess.run([f"{lambda_task_root}/reporter/print_modis_daily_report.csh", \
                    file_id, dataset.upper(), processing_type.upper(), "today"], \
                    cwd=f"{lambda_task_root}/reporter", check=True, stderr=PIPE)
            else:
                subprocess.run([f"{lambda_task_root}/reporter/print_generic_daily_report.csh", \
                    file_id, dataset.upper(), processing_type.upper(), "today"], \
                    cwd=f"{lambda_task_root}/reporter", check=True, stderr=PIPE)        
        except subprocess.CalledProcessError as e:
            error_msg = e.stderr.decode("utf-8").strip()
            sigevent_description = error_msg if len(error_msg) != 0 else "Error encountered in print_generic_daily_report.csh"
            sigevent_data = f"Subprocess Run command: {e.cmd}"
            handle_error(sigevent_description, sigevent_data, logger)
    
def combine_dataset_reports(dataset, processing_type, file_ids, dataset_email):
    """Combine reports produced for a single dataset.
    
    Parameters
    ----------
    dataset: str
        "modis_a", "modis_t", "viirs"
    processing_type: str
        "quicklook" or "refined"
    file_ids: list
        List of processing file ids to generate a report from.
    dataset_email: dict
        Dictionary to store email message alongside dataset.
    """
    
    # Locate refined reports and create email
    report_prefix = DATA_DIR.joinpath("scratch", "reports", f"daily_report_{dataset.upper()}_{processing_type.upper()}_")
    num_files_processed = 0
    num_files_registry = 0
    
    for file_id in file_ids:
        report_name = f"{report_prefix}{file_id}.txt"
        with open(report_name) as fh:
            report_lines = fh.read().splitlines()
            
        if len(report_lines) != 0:
            # Beginning of report
            if dataset_email[dataset][processing_type] == "":
                dataset_email[dataset][processing_type] += report_lines[1] + "\n" + report_lines[2] + "\n" + report_lines[5] + "\n"
            num_files_processed += int(report_lines[6].split(": ")[1].split(',')[0])
            num_files_registry += int(report_lines[7].split(": ")[1].split(',')[0])
        
    dataset_email[dataset][processing_type] += f"Number of files processed: {num_files_processed}, extracted from: ghrsst_{dataset}_processing_log_archive_uniqueid.txt\n"
    dataset_email[dataset][processing_type] += f"Number of files processed: {num_files_registry}, extracted from: ghrsst_master_{dataset}_datatype_list_processed_files_uniqueid.dat\n"
        
def handle_error(sigevent_description, sigevent_data, logger):
    """Handle errors by logging them and sending out a notification."""
    
    sigevent_type = "ERROR"
    logger.error(sigevent_description)
    logger.error(sigevent_data)
    notify(logger, sigevent_type, sigevent_description, sigevent_data)
    logger.error("Program exit.")
    sys.exit(1)
        
if __name__ == "__main__":
    event_handler(None, None)