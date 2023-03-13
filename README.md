# reporter

The reporter generates daily reports on the number of L2P granules that were processed for MODIS Aqua, MODIS Terra, and VIIRS.

The reporter reads in all processing files found in a specified directory and generates one report for all datasets. It then sends an email of the report contents. The processing files that have been processed are archived and moved from the directory so that they are not processed when the reporter is run again.

Top-level Generate repo: https://github.com/podaac/generate

## pre-requisites to building

None.

## build command

`docker build --tag reporter:0.1 . `

## execute command

Arguemnts:
1.	unique_id
2.	instrument
3.	data_type
4.	report_date
5.	report_year
6.	email_flag

Execution:

`docker run --rm --name reporter -v /processor/data:/mnt/data reporter:0.1`

## aws infrastructure

The reporter includes the following AWS services:
- AWS Lambda function.
- AWS SNS Topic `reporter`.
- AWS SNS Topic `batch-job-failures`.

## terraform 

Deploys AWS infrastructure and stores state in an S3 backend using a DynamoDB table for locking.

To deploy:
1. Edit `terraform.tfvars` for environment to deploy to.
2. Edit `terraform_conf/backed-{prefix}.conf` for environment deploy.
3. Initialize terraform: `terraform init -backend-config=terraform_conf/backend-{prefix}.conf`
4. Plan terraform modifications: `terraform plan -out=tfplan`
5. Apply terraform modifications: `terraform apply tfplan`

`{prefix}` is the account or environment name.