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
import json
import logging
import os
import pathlib
import subprocess
from subprocess import PIPE
import sys
import zipfile

# Third-party imports
import boto3
import botocore

# Local imports
from notify import notify

# Constants
DATA_DIR = pathlib.Path("/mnt/data")    # Mounted Processor EFS directory
TOPIC_STRING = "reporter"
DATASET_DICT = {
    "aqua": "MODIS_A",
    "terra": "MODIS_T",
    "viirs": "VIIRS"
}

def event_handler(event, context):
    """Parse EventBridge schedule input for arguments and generate reports."""
    
    start = datetime.datetime.now()
    
    prefix = event["prefix"]
    logger = get_logger()
    
    # # Locate unique identifiers
    dataset_dict = { 
        "modis_a": { "quicklook": [], "refined": [] }, 
        "modis_t": { "quicklook": [], "refined": [] }, 
        "viirs":   { "quicklook": [], "refined": [] }
    }
    locate_processing_files(dataset_dict, logger)
    
    # Generate reports for each unique identifier and combine into single report
    dataset_email = { 
        "modis_a": { "quicklook": "", "refined": "" }, 
        "modis_t": { "quicklook": "", "refined": "" }, 
        "viirs":   { "quicklook": "", "refined": "" }
    }
    for dataset, processing_dict in dataset_dict.items():
        for processing_type, dataset_files in processing_dict.items():
            generate_report(dataset, processing_type, dataset_files, logger)
            combine_dataset_reports(dataset, processing_type, dataset_files, dataset_email, logger)
        
    # Publish report
    publish_report(dataset_email, logger)
    
    # Remove logs and registries
    remove_processing_files(dataset_dict, logger)
    
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
                subprocess.run([f"{lambda_task_root}/print_modis_daily_report.csh", \
                    file_id, dataset.upper(), processing_type.upper(), "today"], \
                    cwd=f"{lambda_task_root}", check=True, stderr=PIPE)
            else:
                subprocess.run([f"{lambda_task_root}/print_generic_daily_report.csh", \
                    file_id, dataset.upper(), processing_type.upper(), "today"], \
                    cwd=f"{lambda_task_root}", check=True, stderr=PIPE)        
        except subprocess.CalledProcessError as e:
            error_msg = e.stderr.decode("utf-8").strip()
            sigevent_description = error_msg if len(error_msg) != 0 else "Error encountered in print_generic_daily_report.csh"
            sigevent_data = f"Subprocess Run command: {e.cmd}"
            handle_error(sigevent_description, sigevent_data, logger)
    
def combine_dataset_reports(dataset, processing_type, file_ids, dataset_email, logger):
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
    
    # Create reports directory if it does not exist
    report_dir = DATA_DIR.joinpath("scratch")
    report_dir.mkdir(parents=True, exist_ok=True)
    
    # Locate refined reports and create email
    num_files_processed = 0
    num_files_registry = 0
    
    for file_id in file_ids:
        report_name = report_dir.joinpath("reports", f"daily_report_{dataset.upper()}_{processing_type.upper()}_{file_id}.txt")
        if report_name.exists():
            with open(report_name) as fh:
                report_lines = fh.read().splitlines()
                
            if len(report_lines) != 0:
                # Beginning of report
                if dataset_email[dataset][processing_type] == "":
                    if "There were no" in report_lines[0]: 
                        dataset_email[dataset][processing_type] += report_lines[0] + "\n"
                    else:
                        dataset_email[dataset][processing_type] += report_lines[1] + "\n" + report_lines[2] + "\n" + report_lines[5] + "\n"
                # Locate number of files processed if applicable
                if not "There were no" in report_lines[0]:
                    num_files_processed += int(report_lines[6].split(": ")[1].split(',')[0])
                    num_files_registry += int(report_lines[7].split(": ")[1].split(',')[0])
            logger.info(f"Read and processed report: {report_name}.")
        else:
            logger.error(f"Cannot locate daily report: {report_name}.")
            sigevent_description = f"Cannot locate daily report: {report_name}."
            handle_error(sigevent_description, "", logger)
    
    # Beginning of report when no files are processed
    if num_files_processed == 0 or num_files_registry == 0:
        date_printed = datetime.datetime.now(datetime.timezone.utc).strftime("%a %b %d %H:%M:%S %Y")
        dataset_email[dataset][processing_type] += "==========================================================================================\n"
        dataset_email[dataset][processing_type] += f"Product: list of {processing_type.upper()} {dataset.upper()} L2P files processed\n"
        dataset_email[dataset][processing_type] += f"Date_printed: {date_printed}\n"
    
    # Record the number of files processed both from logs and in registry
    dataset_email[dataset][processing_type] += f"Number of files processed: {num_files_processed}, extracted from processing logs: ghrsst_{dataset}_processing_log_archive_*.txt\n"
    dataset_email[dataset][processing_type] += f"Number of files processed: {num_files_registry}, extracted from registry: ghrsst_master_{dataset}_*_list_processed_files_*.dat\n"

def publish_report(dataset_email, logger):
    """Publish report to SNS Topic."""
    
    sns = boto3.client("sns")
    
    # Get topic ARN
    try:
        topics = sns.list_topics()
    except botocore.exceptions.ClientError as e:
        sigevent_description = "Failed to list SNS Topics."
        sigevent_data = f"Error - {e}"
        handle_error(sigevent_description, sigevent_data, logger)
    for topic in topics["Topics"]:
        if TOPIC_STRING in topic["TopicArn"]:
            topic_arn = topic["TopicArn"]
            
    # Publish to topic
    date = datetime.datetime.now(datetime.timezone.utc).strftime("%a %b %d %H:%M:%S %Y")
    subject = f"Generate Daily Processing Report {date} UTC"
    # Processing report
    message = f"Generate Processing Report for {date} UTC\n\n"
    line = "==========================================================================================\n"
    for processing_type in dataset_email.values():
        for email in processing_type.values():
            message += email
            message += "\n"
    try:
        response = sns.publish(
            TopicArn = topic_arn,
            Message = message,
            Subject = subject
        )
    except botocore.exceptions.ClientError as e:
        sigevent_description = f"Failed to publish to SNS Topic: {topic_arn}."
        sigevent_data = f"Error - {e}"
        handle_error(sigevent_description, sigevent_data, logger)
    
    logger.info(f"Message published to SNS Topic: {topic_arn}.")
    
def remove_processing_files(dataset_dict, logger):
    """Compress and remove logs (txt) and registry (dat) processing files."""
    
    # Generate list of processing files
    processing = DATA_DIR.joinpath("logs", "processing_logs")
    registry = DATA_DIR.joinpath("scratch")
    file_list = []
    for dataset, processing_dict in dataset_dict.items():
        for processing_type, file_ids in processing_dict.items():
            for file_id in file_ids:
                processing_file = processing.joinpath(f"ghrsst_{dataset}_processing_log_archive_{file_id}.txt")
                if processing_file.exists(): file_list.append(processing_file)
                registry_file = registry.joinpath(f"ghrsst_master_{dataset}_{processing_type}_list_processed_files_{file_id}.dat")
                if registry_file.exists(): file_list.append(registry_file)
                
    if len(file_list) > 0:
        # Compress list
        archive_dir = DATA_DIR.joinpath("scratch", "reports", "archive")
        archive_dir.mkdir(parents=True, exist_ok=True)
        today = datetime.datetime.now().strftime("%Y%m%d")
        zip_file = archive_dir.joinpath(f"{today}_process_files.zip")
        with zipfile.ZipFile(zip_file, mode='w') as archive:
            for file in file_list: archive.write(file, arcname=file.name)
        logger.info(f"Archive of processing files written to: {zip_file}")
            
        # Delete all files in list
        for file in file_list: file.unlink()
        logger.info("Processing files deleted from log and scratch directories.")
                
        
def handle_error(sigevent_description, sigevent_data, logger):
    """Handle errors by logging them and sending out a notification."""
    
    sigevent_type = "ERROR"
    logger.error(sigevent_description)
    logger.error(sigevent_data)
    notify(logger, sigevent_type, sigevent_description, sigevent_data)
    logger.error("Program exit.")
    sys.exit(1)
